# VibeTrack NI Accessory ESP32 Firmware

Flash `VibeTrack_NI_Accessory_ESP32.ino` to the ESP32 connected to the
Qorvo DWM3000EVB.

## What this firmware does

- Starts Serial at `115200`.
- Initializes SPI using `SPI.begin(18, 19, 23, 4)`.
- Resets the DWM3000EVB using `GPIO27`.
- Reads the DWM3000/DW3110 `DEV_ID`.
- Starts BLE advertising as `VibeTrack-UWB`.
- Exposes the Nearby Interaction BLE transport characteristics.
- Reports that the Qorvo Apple NI accessory API is missing.

## What this firmware does not do

- It does not perform DWM3000-to-DWM3000 ranging.
- It does not output placeholder distance.
- It does not output made-up bearing values.
- It does not invent Apple Nearby Interaction accessory configuration bytes.
- It does not implement the Apple/Qorvo NI accessory UWB protocol.

## Required Arduino support

- ESP32 Arduino core.
- ESP32 BLE Arduino library bundled with the ESP32 core.

The sketch uses direct SPI only for the DWM3000 device ID check. It does not
require a DW3000 ranging library because generic ranging libraries do not
implement Apple's Nearby Interaction accessory protocol.

## Required future integration

To make real iPhone Nearby Interaction work, replace the
`getQorvoAccessoryConfigurationData()` stub with calls into Qorvo's real Apple
NI-compatible accessory firmware/API. Those calls must:

- Generate valid accessory configuration bytes for the iPhone app.
- Consume the iPhone shareable configuration bytes written back over BLE.
- Run the accessory-side UWB protocol required by Apple Nearby Interaction.

Do not hard-code or invent accessory configuration data.
