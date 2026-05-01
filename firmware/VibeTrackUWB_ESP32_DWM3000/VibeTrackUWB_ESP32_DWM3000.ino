/*
  VibeTrack UWB - ESP32 + Qorvo DWM3000 practical prototype

  Wiring:
    DWM3000 VCC  -> ESP32 3.3V
    DWM3000 GND  -> ESP32 GND
    DWM3000 SCK  -> ESP32 GPIO18
    DWM3000 MOSI -> ESP32 GPIO23
    DWM3000 MISO -> ESP32 GPIO19
    DWM3000 CS   -> ESP32 GPIO4
    DWM3000 RST  -> ESP32 GPIO27
    DWM3000 IRQ  -> ESP32 GPIO34

  Practical layer:
    - ESP32 initializes SPI and attempts to read the DW3000/DWM3000 device ID.
    - ESP32 advertises BLE as "VibeTrack-UWB".
    - iPhone reads local telemetry over a custom BLE GATT service.
    - Simulation mode provides moving distance/bearing values before true UWB ranging.

  Future Nearby Interaction layer:
    iPhone apps cannot directly consume arbitrary DWM3000 UWB frames. Real iPhone UWB
    distance/direction requires an Apple-compatible Nearby Interaction accessory
    implementation and compatible accessory protocol support. This firmware only sends
    BLE telemetry and does not claim Apple Nearby Interaction interoperability.

  Arduino IDE dependencies:
    - ESP32 board support package
    - Built-in ESP32 BLE Arduino library
    - SPI library

  DWM3000 library note:
    Qorvo DW3000/DWM3000 Arduino APIs differ by board package and version. The direct
    SPI DEV_ID read below is kept inside DWM3000Manager. If your installed library
    exposes dwt_initialise(), dwt_readdevid(), or similar functions, adapt only that
    class and leave the BLE telemetry/application layer unchanged.
*/

#include <Arduino.h>
#include <SPI.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <math.h>

// ---------------- Pin constants ----------------
static constexpr uint8_t PIN_SPI_SCK = 18;
static constexpr uint8_t PIN_SPI_MISO = 19;
static constexpr uint8_t PIN_SPI_MOSI = 23;
static constexpr uint8_t PIN_DWM3000_CS = 4;
static constexpr uint8_t PIN_DWM3000_RST = 27;
static constexpr uint8_t PIN_DWM3000_IRQ = 34;  // GPIO34 is input-only.

// ---------------- BLE constants ----------------
static const char* BLE_DEVICE_NAME = "VibeTrack-UWB";
static const char* TELEMETRY_DEVICE_NAME = "VibeTech 3 UWB";
static const char* SERVICE_UUID = "7E400001-B5A3-F393-E0A9-E50E24DCCA9E";
static const char* TELEMETRY_UUID = "7E400002-B5A3-F393-E0A9-E50E24DCCA9E";
static const char* COMMAND_UUID = "7E400003-B5A3-F393-E0A9-E50E24DCCA9E";

static constexpr uint32_t SERIAL_BAUD = 115200;
static constexpr uint32_t TELEMETRY_INTERVAL_MS = 500;
static constexpr uint16_t BLE_NOTIFY_CHUNK_SIZE = 160;

volatile bool gDwmIrqSeen = false;

void IRAM_ATTR onDwmIrq() {
  gDwmIrqSeen = true;
}

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

class DWM3000Manager {
 public:
  bool begin() {
    _lastError = "";
    _detected = false;
    _deviceId = 0;

    pinMode(PIN_DWM3000_CS, OUTPUT);
    digitalWrite(PIN_DWM3000_CS, HIGH);

    pinMode(PIN_DWM3000_IRQ, INPUT);
    attachInterrupt(digitalPinToInterrupt(PIN_DWM3000_IRQ), onDwmIrq, RISING);

    Serial.println("[DWM3000] Starting SPI bus...");
    SPI.begin(PIN_SPI_SCK, PIN_SPI_MISO, PIN_SPI_MOSI, PIN_DWM3000_CS);
    _spiStarted = true;

    if (!_spiStarted) {
      _lastError = "SPI failure: SPI.begin() did not complete.";
      Serial.println("[DWM3000] ERROR: " + _lastError);
      return false;
    }

    if (!hardwareReset()) {
      _lastError = "reset failure: DWM3000 RST pin did not complete expected reset pulse.";
      Serial.println("[DWM3000] ERROR: " + _lastError);
      return false;
    }

    _deviceId = readDeviceIdRaw();
    Serial.print("[DWM3000] DEV_ID read: ");
    Serial.println(hex32(_deviceId));

    _detected = looksLikeDwm3000(_deviceId);
    if (!_detected) {
      if (_deviceId == 0x00000000UL || _deviceId == 0xFFFFFFFFUL) {
        _lastError =
          "DWM3000 not detected: DEV_ID is all zeros/all ones. Possible wrong CS pin, SPI wiring, power, or reset failure.";
      } else {
        _lastError =
          "DWM3000 not detected: unexpected DEV_ID. Check SPI mode/header for your DWM3000 library or board revision.";
      }
      Serial.println("[DWM3000] ERROR: " + _lastError);
      Serial.println("[DWM3000] Hint: CS must be GPIO4 for this sketch. Wrong CS pin commonly reads 0x00000000 or 0xFFFFFFFF.");
      Serial.println("[DWM3000] Hint: If your library requires Qorvo DW3000 APIs, adapt DWM3000Manager::readDeviceIdRaw().");
      return false;
    }

    Serial.println("[DWM3000] DWM3000/DW3000-family device detected.");
    Serial.println("[DWM3000] Missing library support note: true TWR is not implemented until you add DW3000 ranging APIs.");
    return true;
  }

  bool hardwareReset() {
    Serial.println("[DWM3000] Pulsing RST on GPIO27...");
    pinMode(PIN_DWM3000_RST, OUTPUT);
    digitalWrite(PIN_DWM3000_RST, LOW);
    delay(10);
    digitalWrite(PIN_DWM3000_RST, HIGH);
    delay(30);

    // Some DWM3000 carrier boards prefer the host to release reset after the pulse.
    // If your board has a weak pullup on RST, INPUT here is also acceptable.
    pinMode(PIN_DWM3000_RST, OUTPUT);
    digitalWrite(PIN_DWM3000_RST, HIGH);
    return digitalRead(PIN_DWM3000_RST) == HIGH;
  }

  bool resetAndReinitialize() {
    Serial.println("[DWM3000] RESET_UWB requested.");
    return begin();
  }

  void pollRangingStructure() {
    // Future two-way ranging extension point:
    // 1. Configure channel, preamble, SFD, STS, antenna delays, TX power.
    // 2. Send poll frame to a second UWB node.
    // 3. Receive response/final frames.
    // 4. Compute time-of-flight distance from DW3000 timestamps.
    // 5. Publish real distanceMeters and signalQuality over BLE.
    //
    // This prototype intentionally does not fake real UWB TWR. With one DWM3000
    // board connected, use simulation or single_device_test telemetry.
  }

  bool detected() const {
    return _detected;
  }

  uint32_t deviceId() const {
    return _deviceId;
  }

  String deviceIdString() const {
    return hex32(_deviceId);
  }

  String lastError() const {
    return _lastError;
  }

 private:
  bool _spiStarted = false;
  bool _detected = false;
  uint32_t _deviceId = 0;
  String _lastError;

  uint32_t readDeviceIdRaw() {
    // DW1000/DW3000-family parts expose DEV_ID at register 0x00. The exact
    // low-level SPI header can vary with library/device configuration. This
    // simple read works on many Decawave/Qorvo examples, but if your board
    // package provides dwt_readdevid(), prefer using it here.
    static constexpr uint8_t DEV_ID_REGISTER = 0x00;

    uint8_t bytes[4] = {0, 0, 0, 0};

    SPI.beginTransaction(SPISettings(4000000, MSBFIRST, SPI_MODE0));
    digitalWrite(PIN_DWM3000_CS, LOW);
    delayMicroseconds(2);
    SPI.transfer(DEV_ID_REGISTER & 0x7F);  // Read, no sub-address.
    bytes[0] = SPI.transfer(0x00);
    bytes[1] = SPI.transfer(0x00);
    bytes[2] = SPI.transfer(0x00);
    bytes[3] = SPI.transfer(0x00);
    digitalWrite(PIN_DWM3000_CS, HIGH);
    SPI.endTransaction();

    Serial.print("[DWM3000] DEV_ID bytes: ");
    for (uint8_t i = 0; i < 4; i++) {
      if (bytes[i] < 0x10) Serial.print("0");
      Serial.print(bytes[i], HEX);
      if (i < 3) Serial.print(" ");
    }
    Serial.println();

    const uint32_t littleEndian = static_cast<uint32_t>(bytes[0]) |
                                  (static_cast<uint32_t>(bytes[1]) << 8) |
                                  (static_cast<uint32_t>(bytes[2]) << 16) |
                                  (static_cast<uint32_t>(bytes[3]) << 24);
    const uint32_t bigEndian = static_cast<uint32_t>(bytes[3]) |
                               (static_cast<uint32_t>(bytes[2]) << 8) |
                               (static_cast<uint32_t>(bytes[1]) << 16) |
                               (static_cast<uint32_t>(bytes[0]) << 24);

    if ((littleEndian & 0xFFFF0000UL) == 0xDECA0000UL) {
      return littleEndian;
    }

    if ((bigEndian & 0xFFFF0000UL) == 0xDECA0000UL) {
      return bigEndian;
    }

    return littleEndian;
  }

  bool looksLikeDwm3000(uint32_t id) const {
    // DW1000 commonly reports 0xDECA0130. DW3000-family modules are commonly
    // reported with the 0xDECAxxxx manufacturer/device prefix. Keep this broad
    // so the prototype detects DWM3000 board/package variants without blocking
    // the BLE test layer.
    if ((id & 0xFFFF0000UL) == 0xDECA0000UL) {
      return true;
    }

    return false;
  }
};

DWM3000Manager uwb;

BLEServer* bleServer = nullptr;
BLECharacteristic* telemetryCharacteristic = nullptr;
BLECharacteristic* commandCharacteristic = nullptr;
bool bleClientConnected = false;
bool oldBleClientConnected = false;

bool simulationEnabled = true;
float distanceMeters = 2.35f;
float bearingDegrees = 42.0f;
String activeMode = "single_device_test";
String signalQuality = "simulated";
String runtimeError = "";
uint32_t lastTelemetryMs = 0;

void sendTelemetryNow();
void handleCommand(const String& command);

class VibeTrackServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) override {
    bleClientConnected = true;
    Serial.println("[BLE] iPhone connected.");
  }

  void onDisconnect(BLEServer* server) override {
    bleClientConnected = false;
    Serial.println("[BLE] iPhone disconnected.");
  }
};

class VibeTrackCommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    String command = characteristic->getValue().c_str();
    command.trim();
    handleCommand(command);
  }
};

void setupBle() {
  Serial.println("[BLE] Initializing BLE...");
  BLEDevice::init(BLE_DEVICE_NAME);
  BLEDevice::setMTU(185);

  bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new VibeTrackServerCallbacks());

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
  commandCharacteristic->setCallbacks(new VibeTrackCommandCallbacks());

  service->start();

  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->setMinPreferred(0x06);
  advertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("[BLE] Advertising as VibeTrack-UWB.");
}

void updateSimulation() {
  if (!simulationEnabled) {
    activeMode = "single_device_test";
    signalQuality = uwb.detected() ? "idle" : "no_uwb";
    return;
  }

  const float t = millis() / 1000.0f;
  distanceMeters = 2.2f + 1.45f * sinf(t * 0.75f);
  if (distanceMeters < 0.35f) {
    distanceMeters = 0.35f;
  }

  bearingDegrees = fmodf(42.0f + (t * 34.0f), 360.0f);
  if (bearingDegrees < 0.0f) {
    bearingDegrees += 360.0f;
  }

  activeMode = "simulated_tracking";
  signalQuality = "simulated";
}

String buildTelemetryJson() {
  const float distanceFeet = distanceMeters * 3.28084f;
  const String detectedText = uwb.detected() ? "true" : "false";
  const String errorText = runtimeError.length() > 0 ? ("\"" + jsonEscape(runtimeError) + "\"") : "null";

  String json;
  json.reserve(360);
  json += "{";
  json += "\"deviceName\":\"";
  json += TELEMETRY_DEVICE_NAME;
  json += "\",";
  json += "\"uwbDetected\":";
  json += detectedText;
  json += ",";
  json += "\"deviceId\":\"";
  json += uwb.deviceIdString();
  json += "\",";
  json += "\"mode\":\"";
  json += activeMode;
  json += "\",";
  json += "\"distanceMeters\":";
  json += String(distanceMeters, 2);
  json += ",";
  json += "\"distanceFeet\":";
  json += String(distanceFeet, 2);
  json += ",";
  json += "\"bearingDegrees\":";
  json += String(bearingDegrees, 1);
  json += ",";
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

  for (uint16_t offset = 0; offset < payload.length(); offset += BLE_NOTIFY_CHUNK_SIZE) {
    uint16_t end = offset + BLE_NOTIFY_CHUNK_SIZE;
    if (end > payload.length()) {
      end = payload.length();
    }
    const String chunk = payload.substring(offset, end);
    telemetryCharacteristic->setValue(chunk.c_str());
    telemetryCharacteristic->notify();
    delay(8);
  }
}

void sendTelemetryNow() {
  updateSimulation();

  if (!uwb.detected() && runtimeError.length() == 0) {
    runtimeError = uwb.lastError();
  }

  const String json = buildTelemetryJson();
  Serial.print("[TELEMETRY] ");
  Serial.print(json);

  telemetryCharacteristic->setValue(json.c_str());
  if (bleClientConnected) {
    notifyInChunks(json);
  }
}

void handleCommand(const String& command) {
  Serial.println("[BLE] Command received: " + command);

  if (command == "START_SIM") {
    simulationEnabled = true;
    runtimeError = uwb.detected() ? "" : uwb.lastError();
    sendTelemetryNow();
    return;
  }

  if (command == "STOP_SIM") {
    simulationEnabled = false;
    runtimeError = uwb.detected()
      ? "missing library support: true DWM3000 two-way ranging is not implemented yet. Add a second UWB node and DW3000 ranging APIs, or use START_SIM."
      : uwb.lastError();
    sendTelemetryNow();
    return;
  }

  if (command == "RESET_UWB") {
    const bool ok = uwb.resetAndReinitialize();
    runtimeError = ok ? "" : uwb.lastError();
    signalQuality = ok ? "idle" : "no_uwb";
    sendTelemetryNow();
    return;
  }

  if (command == "STATUS") {
    sendTelemetryNow();
    return;
  }

  runtimeError = "Unknown BLE command: " + command + ". Supported: START_SIM, STOP_SIM, RESET_UWB, STATUS.";
  sendTelemetryNow();
}

void setup() {
  Serial.begin(SERIAL_BAUD);
  delay(1000);

  Serial.println();
  Serial.println("=== VibeTrack UWB ESP32/DWM3000 Prototype ===");
  Serial.println("[INFO] This prototype sends local BLE telemetry. It does not implement Apple Nearby Interaction.");
  Serial.println("[INFO] True UWB ranging requires a second UWB node and a completed two-way ranging implementation.");

  const bool detected = uwb.begin();
  runtimeError = detected ? "" : uwb.lastError();

  setupBle();
  sendTelemetryNow();
}

void loop() {
  if (gDwmIrqSeen) {
    gDwmIrqSeen = false;
    Serial.println("[DWM3000] IRQ observed on GPIO34.");
  }

  if (!bleClientConnected && oldBleClientConnected) {
    delay(500);
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
    uwb.pollRangingStructure();
    sendTelemetryNow();
  }
}
