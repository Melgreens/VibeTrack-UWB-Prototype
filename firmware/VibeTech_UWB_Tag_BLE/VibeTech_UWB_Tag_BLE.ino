/*
  VibeTech UWB Tag + BLE telemetry

  Flash this sketch to the mobile/tag ESP32 + Qorvo DWM3000 board.
  It initiates real double-sided two-way ranging (DS-TWR) with the anchor sketch
  and sends JSON telemetry to the iPhone over BLE.

  Required Arduino library:
    Fhilb/DW3000_Arduino
    https://github.com/Fhilb/DW3000_Arduino

  This code uses the actual Fhilb/DW3000_Arduino API names from the library's
  dw3000_doublesided_ranging_ping and dw3000_doublesided_ranging_pong examples.

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
#include <math.h>

#if !__has_include("DW3000.h")
#error "Missing DW3000.h. Install Fhilb/DW3000_Arduino for ESP32/DW3000 support; DW1000-only libraries will not work with this sketch."
#endif
#include "DW3000.h"

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ---------------- Hardware constants ----------------
static constexpr uint8_t PIN_SPI_SCK = 18;
static constexpr uint8_t PIN_SPI_MISO = 19;
static constexpr uint8_t PIN_SPI_MOSI = 23;
static constexpr uint8_t PIN_DW_CS = 4;
static constexpr uint8_t PIN_DW_RST = 27;
static constexpr uint8_t PIN_DW_IRQ = 34;

// ---------------- BLE constants ----------------
static const char* BLE_DEVICE_NAME = "VibeTrack-UWB";
static const char* TELEMETRY_DEVICE_NAME = "VibeTech 3 UWB";
static const char* SERVICE_UUID = "7E400001-B5A3-F393-E0A9-E50E24DCCA9E";
static const char* TELEMETRY_UUID = "7E400002-B5A3-F393-E0A9-E50E24DCCA9E";
static const char* COMMAND_UUID = "7E400003-B5A3-F393-E0A9-E50E24DCCA9E";

// ---------------- Ranging constants ----------------
static constexpr uint32_t SERIAL_BAUD = 115200;
static constexpr uint16_t BLE_NOTIFY_CHUNK_SIZE = 160;
static constexpr uint32_t TELEMETRY_INTERVAL_MS = 125;     // 8 Hz BLE telemetry.
static constexpr uint32_t RANGE_INTERVAL_MS = 100;         // 10 Hz ranging attempts.
static constexpr uint32_t RANGE_STAGE_TIMEOUT_MS = 180;
static constexpr uint32_t RANGE_STALE_TIMEOUT_MS = 2000;
static constexpr uint8_t TAG_ID = 1;
static constexpr uint8_t ANCHOR_ID = 2;

enum RangingStage {
  STAGE_START_RANGE = 0,
  STAGE_WAIT_FIRST_RESPONSE = 1,
  STAGE_SEND_SECOND_RANGE = 2,
  STAGE_WAIT_FINAL_RESPONSE = 3,
  STAGE_PROCESS_RESULT = 4
};

BLEServer* bleServer = nullptr;
BLECharacteristic* telemetryCharacteristic = nullptr;
BLECharacteristic* commandCharacteristic = nullptr;
bool bleClientConnected = false;
bool oldBleClientConnected = false;

bool uwbDetected = false;
String deviceIdString = "0x00000000";
String lastError = "DWM3000 not initialized yet.";

uint32_t lastTelemetryMs = 0;
uint32_t lastRangeAttemptMs = 0;
uint32_t lastRangeStageMs = 0;
uint32_t lastValidRangeMs = 0;

RangingStage rangingStage = STAGE_START_RANGE;
int rxStatus = 0;
int tRoundA = 0;
int tReplyA = 0;
unsigned long long rxTimestamp = 0;
unsigned long long txTimestamp = 0;
int clockOffset = 0;
double lastDistanceMeters = NAN;

String jsonEscape(const String& value) {
  String escaped;
  escaped.reserve(value.length() + 8);

  for (size_t i = 0; i < value.length(); i++) {
    const char c = value[i];
    switch (c) {
      case '"': escaped += "\\\""; break;
      case '\\': escaped += "\\\\"; break;
      case '\n': escaped += "\\n"; break;
      case '\r': escaped += "\\r"; break;
      case '\t': escaped += "\\t"; break;
      default: escaped += c; break;
    }
  }

  return escaped;
}

String hex32(uint32_t value) {
  char buffer[11];
  snprintf(buffer, sizeof(buffer), "0x%08lX", static_cast<unsigned long>(value));
  return String(buffer);
}

void resetRangingState(const String& reason) {
  if (reason.length() > 0) {
    lastError = reason;
    Serial.println("[UWB] " + reason);
  }

  rangingStage = STAGE_START_RANGE;
  tRoundA = 0;
  tReplyA = 0;
  rxTimestamp = 0;
  txTimestamp = 0;
  clockOffset = 0;
  DW3000.clearSystemStatus();
}

bool initializeDwm3000() {
  Serial.println();
  Serial.println("=== VibeTech UWB Tag BLE ===");
  Serial.println("[INFO] Role: tag / BLE telemetry sender");
  Serial.println("[SPI] Starting SPI.begin(18, 19, 23, 4)...");

  lastRangeAttemptMs = 0;
  lastRangeStageMs = 0;
  lastValidRangeMs = 0;
  rangingStage = STAGE_START_RANGE;
  tRoundA = 0;
  tReplyA = 0;
  rxTimestamp = 0;
  txTimestamp = 0;
  clockOffset = 0;
  lastDistanceMeters = NAN;
  uwbDetected = false;
  lastError = "DWM3000 initialization in progress.";

  pinMode(PIN_DW_CS, OUTPUT);
  digitalWrite(PIN_DW_CS, HIGH);
  pinMode(PIN_DW_RST, OUTPUT);
  digitalWrite(PIN_DW_RST, HIGH);
  pinMode(PIN_DW_IRQ, INPUT);

  // The selected Fhilb library uses ESP32 default VSPI pins and CS=GPIO4.
  // The explicit call below satisfies this project's wiring requirement before
  // DW3000.begin() prepares the library's SPI access.
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
    lastError = "DWM3000 init failed: SPI/DEV_ID check failed. Expected 0xDECA0302 or 0xDECA0312. Check wiring, power, CS=GPIO4, and library install.";
    Serial.println("[DWM3000] " + lastError);
    return false;
  }

  uint32_t idleStart = millis();
  while (!DW3000.checkForIDLE()) {
    if (millis() - idleStart > 2000) {
      lastError = "DWM3000 init failed: chip did not enter IDLE before soft reset.";
      Serial.println("[DWM3000] " + lastError);
      return false;
    }
    delay(20);
  }

  DW3000.softReset();
  delay(200);

  idleStart = millis();
  while (!DW3000.checkForIDLE()) {
    if (millis() - idleStart > 2000) {
      lastError = "DWM3000 init failed: chip did not enter IDLE after soft reset.";
      Serial.println("[DWM3000] " + lastError);
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
  DW3000.setSenderID(TAG_ID);
  DW3000.setDestinationID(ANCHOR_ID);

  Serial.println("[DWM3000] UWB config: channel 5, preamble 128, preamble code 9, PAC8, 6.8 Mbps, PHR standard/850k.");

  DW3000.init();
  if (!DW3000.checkSPI()) {
    lastError = "DWM3000 init failed after configuration.";
    Serial.println("[DWM3000] " + lastError);
    return false;
  }

  DW3000.setupGPIO();
  DW3000.configureAsTX();
  DW3000.clearSystemStatus();

  uwbDetected = true;
  lastError = "Waiting for first real UWB range.";
  Serial.println("[DWM3000] DWM3000 init success.");
  Serial.println("[UWB] Ranging started.");
  return true;
}

void processRanging() {
  if (!uwbDetected) {
    return;
  }

  if (rangingStage != STAGE_START_RANGE && millis() - lastRangeStageMs > RANGE_STAGE_TIMEOUT_MS) {
    resetRangingState("Ranging exchange timeout; restarting DS-TWR.");
    return;
  }

  switch (rangingStage) {
    case STAGE_START_RANGE:
      if (millis() - lastRangeAttemptMs < RANGE_INTERVAL_MS) {
        return;
      }

      lastRangeAttemptMs = millis();
      lastRangeStageMs = millis();
      tRoundA = 0;
      tReplyA = 0;

      // Message 1: tag sends DS-TWR poll/stage 1, then switches to RX.
      DW3000.ds_sendFrame(1);
      txTimestamp = DW3000.readTXTimestamp();
      rangingStage = STAGE_WAIT_FIRST_RESPONSE;
      break;

    case STAGE_WAIT_FIRST_RESPONSE:
      rxStatus = DW3000.receivedFrameSucc();
      if (!rxStatus) {
        return;
      }

      DW3000.clearSystemStatus();
      if (rxStatus != 1) {
        resetRangingState("Receiver error while waiting for anchor response.");
        return;
      }

      if (DW3000.ds_isErrorFrame()) {
        resetRangingState("Anchor sent DS-TWR error frame.");
        return;
      }

      if (DW3000.ds_getStage() != 2) {
        DW3000.ds_sendErrorFrame();
        resetRangingState("Unexpected DS-TWR stage while waiting for stage 2.");
        return;
      }

      rangingStage = STAGE_SEND_SECOND_RANGE;
      lastRangeStageMs = millis();
      break;

    case STAGE_SEND_SECOND_RANGE:
      // Message 3: tag sends second range packet. The tag saves t_roundA and
      // t_replyA, then waits for the anchor's timing-information frame.
      rxTimestamp = DW3000.readRXTimestamp();
      DW3000.ds_sendFrame(3);
      tRoundA = rxTimestamp - txTimestamp;
      txTimestamp = DW3000.readTXTimestamp();
      tReplyA = txTimestamp - rxTimestamp;
      rangingStage = STAGE_WAIT_FINAL_RESPONSE;
      lastRangeStageMs = millis();
      break;

    case STAGE_WAIT_FINAL_RESPONSE:
      rxStatus = DW3000.receivedFrameSucc();
      if (!rxStatus) {
        return;
      }

      DW3000.clearSystemStatus();
      if (rxStatus != 1) {
        resetRangingState("Receiver error while waiting for final timing frame.");
        return;
      }

      if (DW3000.ds_isErrorFrame()) {
        resetRangingState("Anchor sent final DS-TWR error frame.");
        return;
      }

      clockOffset = DW3000.getRawClockOffset();
      rangingStage = STAGE_PROCESS_RESULT;
      lastRangeStageMs = millis();
      break;

    case STAGE_PROCESS_RESULT: {
      // The final anchor frame includes t_roundB and t_replyB in RX buffer
      // offsets 0x04 and 0x08, matching Fhilb's doublesided example.
      const int tRoundB = DW3000.read(0x12, 0x04);
      const int tReplyB = DW3000.read(0x12, 0x08);
      const int rangingTime = DW3000.ds_processRTInfo(tRoundA, tReplyA, tRoundB, tReplyB, clockOffset);
      const double distanceCm = DW3000.convertToCM(rangingTime);
      const double distanceMeters = distanceCm / 100.0;

      if (!isnan(distanceMeters) && distanceMeters >= 0.0 && distanceMeters < 200.0) {
        lastDistanceMeters = distanceMeters;
        lastValidRangeMs = millis();
        lastError = "";
        Serial.print("[UWB] Valid distance: ");
        Serial.print(distanceMeters, 2);
        Serial.print(" m / ");
        Serial.print(distanceMeters * 3.28084, 2);
        Serial.println(" ft");
      } else {
        lastError = "Invalid UWB distance result; check antenna delay calibration and line of sight.";
        Serial.println("[UWB] " + lastError);
      }

      rangingStage = STAGE_START_RANGE;
      break;
    }
  }
}

bool hasFreshRange() {
  return uwbDetected && !isnan(lastDistanceMeters) && (millis() - lastValidRangeMs <= RANGE_STALE_TIMEOUT_MS);
}

String nullableDouble(double value, uint8_t precision) {
  if (isnan(value)) {
    return "null";
  }

  return String(value, precision);
}

String buildTelemetryJson() {
  const bool fresh = hasFreshRange();
  const String mode = fresh ? "uwb_ranging" : "uwb_error";
  const String signalQuality = fresh ? "real" : "none";
  const String detectedText = fresh ? "true" : "false";

  String errorText = "null";
  if (!fresh) {
    String error = lastError;
    if (uwbDetected && millis() - lastValidRangeMs > RANGE_STALE_TIMEOUT_MS) {
      error = "No valid UWB range received for more than 2 seconds. Verify the anchor is powered, flashed with VibeTech_UWB_Anchor, and within range.";
    }
    errorText = "\"" + jsonEscape(error) + "\"";
  }

  const double distanceMeters = fresh ? lastDistanceMeters : NAN;
  const double distanceFeet = fresh ? lastDistanceMeters * 3.28084 : NAN;

  String json;
  json.reserve(320);
  json += "{";
  json += "\"deviceName\":\"";
  json += TELEMETRY_DEVICE_NAME;
  json += "\",";
  json += "\"uwbDetected\":";
  json += detectedText;
  json += ",";
  json += "\"deviceId\":\"";
  json += deviceIdString;
  json += "\",";
  json += "\"mode\":\"";
  json += mode;
  json += "\",";
  json += "\"distanceMeters\":";
  json += nullableDouble(distanceMeters, 2);
  json += ",";
  json += "\"distanceFeet\":";
  json += nullableDouble(distanceFeet, 2);
  json += ",";
  json += "\"bearingDegrees\":null,";
  json += "\"signalQuality\":\"";
  json += signalQuality;
  json += "\",";
  json += "\"lastUpdateMs\":";
  json += String(millis());
  json += ",";
  json += "\"error\":";
  json += errorText;
  json += "}\n";
  return json;
}

void notifyInChunks(const String& payload) {
  if (telemetryCharacteristic == nullptr) {
    return;
  }

  telemetryCharacteristic->setValue(payload.c_str());

  if (!bleClientConnected) {
    return;
  }

  for (uint16_t offset = 0; offset < payload.length(); offset += BLE_NOTIFY_CHUNK_SIZE) {
    uint16_t end = offset + BLE_NOTIFY_CHUNK_SIZE;
    if (end > payload.length()) {
      end = payload.length();
    }
    const String chunk = payload.substring(offset, end);
    telemetryCharacteristic->setValue(chunk.c_str());
    telemetryCharacteristic->notify();
    delay(4);
  }
}

void sendTelemetryNow() {
  const String json = buildTelemetryJson();
  Serial.print("[TELEMETRY] ");
  Serial.print(json);
  notifyInChunks(json);
}

bool initializeBle();

class VibeTechServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) override {
    bleClientConnected = true;
    Serial.println("[BLE] iPhone connected.");
  }

  void onDisconnect(BLEServer* server) override {
    bleClientConnected = false;
    Serial.println("[BLE] iPhone disconnected.");
  }
};

class VibeTechCommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    String command = characteristic->getValue().c_str();
    command.trim();
    Serial.println("[BLE] Command received: " + command);

    if (command == "STATUS") {
      sendTelemetryNow();
      return;
    }

    if (command == "RESET_UWB") {
      uwbDetected = initializeDwm3000();
      sendTelemetryNow();
      return;
    }

    lastError = "Unsupported command in real UWB firmware: " + command + ". Use STATUS or RESET_UWB.";
    sendTelemetryNow();
  }
};

bool initializeBle() {
  Serial.println("[BLE] Starting BLE...");
  BLEDevice::init(BLE_DEVICE_NAME);
  BLEDevice::setMTU(185);

  bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new VibeTechServerCallbacks());

  BLEService* service = bleServer->createService(SERVICE_UUID);
  telemetryCharacteristic = service->createCharacteristic(
    TELEMETRY_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  telemetryCharacteristic->addDescriptor(new BLE2902());

  commandCharacteristic = service->createCharacteristic(
    COMMAND_UUID,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
  );
  commandCharacteristic->setCallbacks(new VibeTechCommandCallbacks());

  service->start();

  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->setMinPreferred(0x06);
  advertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("[BLE] BLE started. Advertising as VibeTrack-UWB.");
  return true;
}

void setup() {
  Serial.begin(SERIAL_BAUD);
  delay(1000);

  uwbDetected = initializeDwm3000();
  initializeBle();
  sendTelemetryNow();
}

void loop() {
  processRanging();

  if (!bleClientConnected && oldBleClientConnected) {
    delay(200);
    BLEDevice::startAdvertising();
    Serial.println("[BLE] Restarted advertising.");
    oldBleClientConnected = bleClientConnected;
  }

  if (bleClientConnected && !oldBleClientConnected) {
    oldBleClientConnected = bleClientConnected;
    sendTelemetryNow();
  }

  if (millis() - lastTelemetryMs >= TELEMETRY_INTERVAL_MS) {
    lastTelemetryMs = millis();
    sendTelemetryNow();
  }
}
