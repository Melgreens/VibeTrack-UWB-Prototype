/*
  VibeTrack NI Accessory ESP32 firmware

  Hardware:
    ESP32-WROOM-32 development board
    Qorvo DWM3000EVB / DW3110 UWB accessory board

  This sketch provides the BLE transport and DWM3000EVB bring-up layer for an
  Apple Nearby Interaction accessory experiment. It does not implement the
  Apple/Qorvo NI accessory UWB protocol and it never sends placeholder distance,
  bearing, or accessory configuration data.

  Wiring:
    DWM3000EVB VCC  -> ESP32 3.3V
    DWM3000EVB GND  -> ESP32 GND
    DWM3000EVB SCK  -> ESP32 GPIO18
    DWM3000EVB MOSI -> ESP32 GPIO23
    DWM3000EVB MISO -> ESP32 GPIO19
    DWM3000EVB CS   -> ESP32 GPIO4
    DWM3000EVB RST  -> ESP32 GPIO27
    DWM3000EVB IRQ  -> ESP32 GPIO34
*/

#include <Arduino.h>
#include <SPI.h>
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
static constexpr uint32_t SERIAL_BAUD = 115200;
static constexpr uint32_t STATUS_INTERVAL_MS = 1000;

// ---------------- BLE constants ----------------
static const char* BLE_DEVICE_NAME = "VibeTrack-UWB";
static const char* SERVICE_UUID = "7E400001-B5A3-F393-E0A9-E50E24DCCA9E";
static const char* ACCESSORY_CONFIG_UUID = "7E400011-B5A3-F393-E0A9-E50E24DCCA9E";
static const char* IPHONE_CONFIG_UUID = "7E400012-B5A3-F393-E0A9-E50E24DCCA9E";
static const char* STATUS_DEBUG_UUID = "7E400013-B5A3-F393-E0A9-E50E24DCCA9E";

static const char* NI_MISSING_MESSAGE =
  "NI accessory firmware not implemented because Qorvo Apple NI accessory API is missing.";

BLEServer* bleServer = nullptr;
BLECharacteristic* accessoryConfigCharacteristic = nullptr;
BLECharacteristic* iPhoneConfigCharacteristic = nullptr;
BLECharacteristic* statusDebugCharacteristic = nullptr;

bool bleClientConnected = false;
bool oldBleClientConnected = false;
bool uwbDetected = false;
uint32_t dwmDeviceId = 0;
String deviceIdString = "0x00000000";
String lastStatus = "Booting";
uint32_t lastStatusMs = 0;

String hex32(uint32_t value) {
  char buffer[11];
  snprintf(buffer, sizeof(buffer), "0x%08lX", static_cast<unsigned long>(value));
  return String(buffer);
}

String jsonEscape(const String& value) {
  String escaped;
  escaped.reserve(value.length() + 8);

  for (size_t index = 0; index < value.length(); index++) {
    const char c = value[index];
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

void selectDwm() {
  digitalWrite(PIN_DW_CS, LOW);
}

void deselectDwm() {
  digitalWrite(PIN_DW_CS, HIGH);
}

uint32_t readDwmDevId() {
  // DW3000 register 0x00 is DEV_ID. A basic read uses the register byte followed
  // by four dummy bytes. This is enough to verify SPI wiring and chip presence.
  SPI.beginTransaction(SPISettings(2000000, MSBFIRST, SPI_MODE0));
  selectDwm();
  SPI.transfer(0x00);
  const uint8_t b0 = SPI.transfer(0x00);
  const uint8_t b1 = SPI.transfer(0x00);
  const uint8_t b2 = SPI.transfer(0x00);
  const uint8_t b3 = SPI.transfer(0x00);
  deselectDwm();
  SPI.endTransaction();

  const uint32_t devId = (static_cast<uint32_t>(b3) << 24) |
                         (static_cast<uint32_t>(b2) << 16) |
                         (static_cast<uint32_t>(b1) << 8) |
                         static_cast<uint32_t>(b0);
  return devId;
}

void hardwareResetDwm() {
  Serial.println("[DWM3000] Resetting DWM3000EVB with GPIO27...");
  digitalWrite(PIN_DW_RST, LOW);
  delay(10);
  digitalWrite(PIN_DW_RST, HIGH);
  delay(200);
  Serial.println("[DWM3000] DWM3000 reset complete.");
}

bool validDwmDeviceId(uint32_t devId) {
  // Common DW3000/DW3110 DEV_ID values seen in DW3000 examples include
  // 0xDECA0302 and 0xDECA0312. Reject all-zero/all-one reads as wiring faults.
  return devId == 0xDECA0302UL ||
         devId == 0xDECA0312UL ||
         ((devId & 0xFFFF0000UL) == 0xDECA0000UL && devId != 0xDECA0000UL);
}

bool initializeDwm3000Transport() {
  Serial.println();
  Serial.println("=== VibeTrack NI Accessory ESP32 ===");
  Serial.println("[INFO] Role: BLE data channel for Apple Nearby Interaction accessory flow");
  Serial.println("[INFO] This is not DWM3000-to-DWM3000 ranging firmware.");

  pinMode(PIN_DW_CS, OUTPUT);
  digitalWrite(PIN_DW_CS, HIGH);
  pinMode(PIN_DW_RST, OUTPUT);
  digitalWrite(PIN_DW_RST, HIGH);
  pinMode(PIN_DW_IRQ, INPUT);

  Serial.println("[SPI] Starting SPI.begin(18, 19, 23, 4)...");
  SPI.begin(PIN_SPI_SCK, PIN_SPI_MISO, PIN_SPI_MOSI, PIN_DW_CS);
  Serial.println("[SPI] SPI started.");

  hardwareResetDwm();

  dwmDeviceId = readDwmDevId();
  deviceIdString = hex32(dwmDeviceId);
  Serial.println("[DWM3000] DEV_ID read result: " + deviceIdString);

  if (!validDwmDeviceId(dwmDeviceId)) {
    uwbDetected = false;
    lastStatus = "DWM3000 device ID failed. Check power, SPI wiring, CS=GPIO4, RST=GPIO27, and the DWM3000EVB pinout.";
    Serial.println("[DWM3000] Init failed: " + lastStatus);
    return false;
  }

  uwbDetected = true;
  lastStatus = String(NI_MISSING_MESSAGE);
  Serial.println("[DWM3000] DWM3000 init success for SPI transport bring-up.");
  Serial.println("[DWM3000] Apple NI accessory protocol is not running in this Arduino sketch.");
  Serial.println("[NI] " + lastStatus);
  return true;
}

bool getQorvoAccessoryConfigurationData(uint8_t* buffer, size_t bufferSize, size_t* length) {
  (void)buffer;
  (void)bufferSize;
  if (length != nullptr) {
    *length = 0;
  }

  // TODO: Replace this stub only with Qorvo's real Apple Nearby Interaction
  // accessory firmware/API. The bytes returned here must be generated by the
  // compliant accessory stack. Do not hard-code or invent config data.
  return false;
}

String buildStatusJson() {
  String json;
  json.reserve(320);
  json += "{";
  json += "\"deviceName\":\"VibeTrack-UWB\",";
  json += "\"uwbDetected\":";
  json += uwbDetected ? "true" : "false";
  json += ",";
  json += "\"deviceId\":\"";
  json += deviceIdString;
  json += "\",";
  json += "\"niAccessoryFirmware\":false,";
  json += "\"accessoryConfigurationAvailable\":false,";
  json += "\"lastUpdateMs\":";
  json += String(millis());
  json += ",";
  json += "\"message\":\"";
  json += jsonEscape(lastStatus);
  json += "\"";
  json += "}";
  return json;
}

void notifyStatus(const String& status) {
  Serial.println("[STATUS] " + status);
  if (statusDebugCharacteristic == nullptr) {
    return;
  }

  statusDebugCharacteristic->setValue(status.c_str());
  if (bleClientConnected) {
    statusDebugCharacteristic->notify();
  }
}

void sendStatusJson() {
  notifyStatus(buildStatusJson());
}

void sendAccessoryConfigurationIfAvailable() {
  uint8_t configBuffer[256];
  size_t configLength = 0;

  if (getQorvoAccessoryConfigurationData(configBuffer, sizeof(configBuffer), &configLength) && configLength > 0) {
    accessoryConfigCharacteristic->setValue(configBuffer, configLength);
    if (bleClientConnected) {
      accessoryConfigCharacteristic->notify();
    }
    Serial.print("[NI] Sent real accessory configuration bytes: ");
    Serial.println(configLength);
    return;
  }

  accessoryConfigCharacteristic->setValue("");
  lastStatus = String(NI_MISSING_MESSAGE);
  notifyStatus(lastStatus);
}

class VibeTrackServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) override {
    (void)server;
    bleClientConnected = true;
    Serial.println("[BLE] iPhone connected.");
    sendStatusJson();
  }

  void onDisconnect(BLEServer* server) override {
    (void)server;
    bleClientConnected = false;
    Serial.println("[BLE] iPhone disconnected.");
  }
};

class AccessoryConfigCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    String command = String(characteristic->getValue().c_str());
    command.trim();
    Serial.println("[BLE] Accessory config characteristic write: " + command);
    sendAccessoryConfigurationIfAvailable();
  }
};

class IPhoneConfigCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    const String value = String(characteristic->getValue().c_str());
    Serial.print("[BLE] Received iPhone NI shareable configuration bytes: ");
    Serial.println(value.length());
    lastStatus = "Received iPhone shareable config, but no Qorvo NI accessory API is linked to consume it.";
    notifyStatus(lastStatus);
  }
};

class StatusDebugCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    String command = String(characteristic->getValue().c_str());
    command.trim();
    Serial.println("[BLE] Status/debug command: " + command);

    if (command == "STATUS") {
      sendStatusJson();
      return;
    }

    if (command == "REQUEST_ACCESSORY_CONFIG") {
      sendAccessoryConfigurationIfAvailable();
      return;
    }

    if (command == "RESET_UWB") {
      initializeDwm3000Transport();
      sendStatusJson();
      return;
    }

    lastStatus = "Unknown command: " + command;
    notifyStatus(lastStatus);
  }
};

void initializeBle() {
  Serial.println("[BLE] Starting BLE...");
  BLEDevice::init(BLE_DEVICE_NAME);
  BLEDevice::setMTU(185);

  bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new VibeTrackServerCallbacks());

  BLEService* service = bleServer->createService(SERVICE_UUID);

  accessoryConfigCharacteristic = service->createCharacteristic(
    ACCESSORY_CONFIG_UUID,
    BLECharacteristic::PROPERTY_READ |
      BLECharacteristic::PROPERTY_WRITE |
      BLECharacteristic::PROPERTY_NOTIFY
  );
  accessoryConfigCharacteristic->addDescriptor(new BLE2902());
  accessoryConfigCharacteristic->setCallbacks(new AccessoryConfigCallbacks());
  accessoryConfigCharacteristic->setValue("");

  iPhoneConfigCharacteristic = service->createCharacteristic(
    IPHONE_CONFIG_UUID,
    BLECharacteristic::PROPERTY_WRITE |
      BLECharacteristic::PROPERTY_WRITE_NR
  );
  iPhoneConfigCharacteristic->setCallbacks(new IPhoneConfigCallbacks());

  statusDebugCharacteristic = service->createCharacteristic(
    STATUS_DEBUG_UUID,
    BLECharacteristic::PROPERTY_READ |
      BLECharacteristic::PROPERTY_WRITE |
      BLECharacteristic::PROPERTY_NOTIFY
  );
  statusDebugCharacteristic->addDescriptor(new BLE2902());
  statusDebugCharacteristic->setCallbacks(new StatusDebugCallbacks());
  statusDebugCharacteristic->setValue(buildStatusJson().c_str());

  service->start();

  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->setMinPreferred(0x06);
  advertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("[BLE] BLE started. Advertising as VibeTrack-UWB.");
}

void setup() {
  Serial.begin(SERIAL_BAUD);
  delay(1000);

  initializeDwm3000Transport();
  initializeBle();
  sendStatusJson();
}

void loop() {
  if (!bleClientConnected && oldBleClientConnected) {
    delay(200);
    BLEDevice::startAdvertising();
    Serial.println("[BLE] Restarted advertising.");
    oldBleClientConnected = bleClientConnected;
  }

  if (bleClientConnected && !oldBleClientConnected) {
    oldBleClientConnected = bleClientConnected;
    sendStatusJson();
  }

  if (millis() - lastStatusMs >= STATUS_INTERVAL_MS) {
    lastStatusMs = millis();
    if (bleClientConnected) {
      sendStatusJson();
    }
  }
}
