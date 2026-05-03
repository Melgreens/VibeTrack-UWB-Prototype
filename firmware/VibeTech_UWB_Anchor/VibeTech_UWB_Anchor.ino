/*
  VibeTech UWB Anchor

  Flash this sketch to the fixed/anchor ESP32 + Qorvo DWM3000 board.
  It responds to real double-sided two-way ranging (DS-TWR) requests from the
  tag sketch. This board does not run BLE.

  Required Arduino library:
    Fhilb/DW3000_Arduino
    https://github.com/Fhilb/DW3000_Arduino

  Wiring:
    DWM3000 VCC  -> ESP32 3.3V
    DWM3000 GND  -> ESP32 GND
    DWM3000 SCK  -> ESP32 GPIO18
    DWM3000 MOSI -> ESP32 GPIO23
    DWM3000 MISO -> ESP32 GPIO19
    DWM3000 CS   -> ESP32 GPIO4
    DWM3000 RST  -> ESP32 GPIO27
    DWM3000 IRQ  -> ESP32 GPIO34 (configured as input; this library polls status)
*/

#include <Arduino.h>
#include <SPI.h>

#if !__has_include("DW3000.h")
#error "Missing DW3000.h. Install Fhilb/DW3000_Arduino for ESP32/DW3000 support; DW1000-only libraries will not work with this sketch."
#endif
#include "DW3000.h"

// ---------------- Hardware constants ----------------
static constexpr uint8_t PIN_SPI_SCK = 18;
static constexpr uint8_t PIN_SPI_MISO = 19;
static constexpr uint8_t PIN_SPI_MOSI = 23;
static constexpr uint8_t PIN_DW_CS = 4;
static constexpr uint8_t PIN_DW_RST = 27;
static constexpr uint8_t PIN_DW_IRQ = 34;

// ---------------- Ranging constants ----------------
static constexpr uint32_t SERIAL_BAUD = 115200;
static constexpr uint32_t RANGE_STAGE_TIMEOUT_MS = 250;
static constexpr uint8_t TAG_ID = 1;
static constexpr uint8_t ANCHOR_ID = 2;

enum AnchorStage {
  STAGE_WAIT_RANGE = 0,
  STAGE_SEND_RESPONSE = 1,
  STAGE_WAIT_SECOND_RANGE = 2,
  STAGE_SEND_TIMING_INFO = 3
};

AnchorStage anchorStage = STAGE_WAIT_RANGE;
uint32_t lastStageMs = 0;
int rxStatus = 0;
int tRoundB = 0;
int tReplyB = 0;
unsigned long long rxTimestamp = 0;
unsigned long long txTimestamp = 0;
String deviceIdString = "0x00000000";

String hex32(uint32_t value) {
  char buffer[11];
  snprintf(buffer, sizeof(buffer), "0x%08lX", static_cast<unsigned long>(value));
  return String(buffer);
}

void resetAnchorState(const String& reason) {
  if (reason.length() > 0) {
    Serial.println("[UWB] " + reason);
  }

  anchorStage = STAGE_WAIT_RANGE;
  tRoundB = 0;
  tReplyB = 0;
  rxTimestamp = 0;
  txTimestamp = 0;
  DW3000.clearSystemStatus();
  DW3000.standardRX();
}

bool initializeDwm3000() {
  Serial.println();
  Serial.println("=== VibeTech UWB Anchor ===");
  Serial.println("[INFO] Role: anchor / DS-TWR responder");
  Serial.println("[SPI] Starting SPI.begin(18, 19, 23, 4)...");

  pinMode(PIN_DW_CS, OUTPUT);
  digitalWrite(PIN_DW_CS, HIGH);
  pinMode(PIN_DW_RST, OUTPUT);
  digitalWrite(PIN_DW_RST, HIGH);
  pinMode(PIN_DW_IRQ, INPUT);

  SPI.begin(PIN_SPI_SCK, PIN_SPI_MISO, PIN_SPI_MOSI, PIN_DW_CS);
  Serial.println("[SPI] SPI started.");

  DW3000.begin();

  Serial.println("[DWM3000] Resetting with GPIO27...");
  DW3000.hardReset();
  delay(200);
  Serial.println("[DWM3000] Reset complete.");

  const uint32_t devId = DW3000.read(0x00, 0x00);
  deviceIdString = hex32(devId);
  Serial.println("[DWM3000] DEV_ID read result: " + deviceIdString);

  if (!DW3000.checkSPI()) {
    Serial.println("[DWM3000] Init failed: SPI/DEV_ID check failed. Expected 0xDECA0302 or 0xDECA0312.");
    return false;
  }

  uint32_t idleStart = millis();
  while (!DW3000.checkForIDLE()) {
    if (millis() - idleStart > 2000) {
      Serial.println("[DWM3000] Init failed: chip did not enter IDLE before soft reset.");
      return false;
    }
    delay(20);
  }

  DW3000.softReset();
  delay(200);

  idleStart = millis();
  while (!DW3000.checkForIDLE()) {
    if (millis() - idleStart > 2000) {
      Serial.println("[DWM3000] Init failed: chip did not enter IDLE after soft reset.");
      return false;
    }
    delay(20);
  }

  DW3000.setChannel(CHANNEL_5);
  DW3000.setPreambleLength(PREAMBLE_128);
  DW3000.setPreambleCode(9);
  DW3000.setPACSize(PAC8);
  DW3000.setDatarate(DATARATE_6_8MB);
  DW3000.setPHRMode(PHR_MODE_STANDARD);
  DW3000.setPHRRate(PHR_RATE_850KB);
  DW3000.setSenderID(ANCHOR_ID);
  DW3000.setDestinationID(TAG_ID);

  Serial.println("[DWM3000] UWB config: channel 5, preamble 128, preamble code 9, PAC8, 6.8 Mbps, PHR standard/850k.");

  DW3000.init();
  if (!DW3000.checkSPI()) {
    Serial.println("[DWM3000] Init failed after configuration.");
    return false;
  }

  DW3000.setupGPIO();
  DW3000.configureAsTX();
  DW3000.clearSystemStatus();
  DW3000.standardRX();

  Serial.println("[DWM3000] DWM3000 init success.");
  Serial.println("[UWB] Ranging responder started.");
  return true;
}

void processAnchorRanging() {
  if (anchorStage != STAGE_WAIT_RANGE && millis() - lastStageMs > RANGE_STAGE_TIMEOUT_MS) {
    resetAnchorState("Anchor ranging exchange timeout; returning to RX.");
    return;
  }

  switch (anchorStage) {
    case STAGE_WAIT_RANGE:
      tRoundB = 0;
      tReplyB = 0;
      rxStatus = DW3000.receivedFrameSucc();
      if (!rxStatus) {
        return;
      }

      DW3000.clearSystemStatus();
      if (rxStatus != 1) {
        resetAnchorState("Receiver error while waiting for tag range request.");
        return;
      }

      if (DW3000.ds_isErrorFrame()) {
        resetAnchorState("Tag sent DS-TWR error frame.");
        return;
      }

      if (DW3000.ds_getStage() != 1) {
        DW3000.ds_sendErrorFrame();
        resetAnchorState("Unexpected DS-TWR stage while waiting for stage 1.");
        return;
      }

      anchorStage = STAGE_SEND_RESPONSE;
      lastStageMs = millis();
      break;

    case STAGE_SEND_RESPONSE:
      // Message 2: anchor answers the tag and records its RX/TX timestamps.
      DW3000.ds_sendFrame(2);
      rxTimestamp = DW3000.readRXTimestamp();
      txTimestamp = DW3000.readTXTimestamp();
      tReplyB = txTimestamp - rxTimestamp;
      anchorStage = STAGE_WAIT_SECOND_RANGE;
      lastStageMs = millis();
      break;

    case STAGE_WAIT_SECOND_RANGE:
      rxStatus = DW3000.receivedFrameSucc();
      if (!rxStatus) {
        return;
      }

      DW3000.clearSystemStatus();
      if (rxStatus != 1) {
        resetAnchorState("Receiver error while waiting for second tag range.");
        return;
      }

      if (DW3000.ds_isErrorFrame()) {
        resetAnchorState("Tag sent second-stage DS-TWR error frame.");
        return;
      }

      if (DW3000.ds_getStage() != 3) {
        DW3000.ds_sendErrorFrame();
        resetAnchorState("Unexpected DS-TWR stage while waiting for stage 3.");
        return;
      }

      anchorStage = STAGE_SEND_TIMING_INFO;
      lastStageMs = millis();
      break;

    case STAGE_SEND_TIMING_INFO:
      // Message 4: anchor sends timing information back to the tag so the tag
      // can calculate the final double-sided time-of-flight.
      rxTimestamp = DW3000.readRXTimestamp();
      tRoundB = rxTimestamp - txTimestamp;
      DW3000.ds_sendRTInfo(tRoundB, tReplyB);
      Serial.println("[UWB] Responded to valid DS-TWR exchange.");
      resetAnchorState("");
      break;
  }
}

void setup() {
  Serial.begin(SERIAL_BAUD);
  delay(1000);

  if (!initializeDwm3000()) {
    Serial.println("[FATAL] Anchor cannot start without a working DWM3000.");
    while (true) {
      delay(1000);
    }
  }
}

void loop() {
  processAnchorRanging();
}
