# VibeTrack UWB Prototype

Focused local UWB tracking prototype for ESP32 + Qorvo DWM3000 + SwiftUI iPhone app.

## Architecture

The project has two layers:

1. Practical prototype layer
   - ESP32 owns SPI and DWM3000 reset/IRQ wiring.
   - ESP32 attempts to read the DWM3000 `DEV_ID`.
   - ESP32 advertises `VibeTrack-UWB` over BLE.
   - iPhone connects with CoreBluetooth, subscribes to JSON telemetry, displays distance/status/debug data, and sends commands.
   - Simulation mode animates distance and bearing before true two-node UWB ranging is implemented.

2. Future Nearby Interaction layer
   - `NearbyInteractionPlaceholder.swift` marks where `NISession` setup could go later.
   - The current firmware and app do not implement Apple Nearby Interaction accessory protocol support.
   - A generic DWM3000 module does not automatically work with the iPhone UWB chip.

## Wiring

| DWM3000 | ESP32 |
| --- | --- |
| VCC | 3.3V |
| GND | GND |
| SCK | GPIO18 |
| MOSI | GPIO23 |
| MISO | GPIO19 |
| CS | GPIO4 |
| RST | GPIO27 |
| IRQ | GPIO34 |

## BLE Contract

- Device name: `VibeTrack-UWB`
- Service UUID: `7E400001-B5A3-F393-E0A9-E50E24DCCA9E`
- Telemetry characteristic UUID: `7E400002-B5A3-F393-E0A9-E50E24DCCA9E`
- Command characteristic UUID: `7E400003-B5A3-F393-E0A9-E50E24DCCA9E`

Commands:

- `START_SIM`
- `STOP_SIM`
- `RESET_UWB`
- `STATUS`

Telemetry packets are newline-terminated JSON and may be sent in BLE chunks.

## Files

- Arduino firmware: `firmware/VibeTrackUWB_ESP32_DWM3000/VibeTrackUWB_ESP32_DWM3000.ino`
- SwiftUI app source: `ios/VibeTrackUWB/`
- Bluetooth permission entries: `ios/VibeTrackUWB/Info.plist`

## ESP32 Firmware Test

1. Verify wiring.
2. Open Serial Monitor at `115200`.
3. Confirm SPI starts.
4. Confirm DWM3000 device ID is read.
5. Confirm BLE advertising starts.
6. Confirm telemetry JSON prints.
7. Confirm `START_SIM` changes distance and bearing.

## iPhone App Test

1. Build on a physical iPhone.
2. Allow Bluetooth permissions.
3. Scan for `VibeTrack-UWB`.
4. Connect.
5. Verify telemetry updates.
6. Press Start Simulation.
7. Confirm arrow rotates.
8. Confirm distance changes.
9. Open Debug screen.
10. Confirm raw JSON appears.

## Real Now vs Later

Real now:

- ESP32 SPI setup and reset/IRQ pin handling.
- DWM3000 `DEV_ID` read attempt.
- Clear serial errors for SPI/wiring/CS/reset/library mismatch cases.
- BLE GATT telemetry and command path.
- SwiftUI CoreBluetooth scanning, connection, JSON decoding, controls, and debug view.
- Simulated local tracking UI.

Requires later work:

- True two-way UWB ranging with a second UWB node.
- Board/library-specific DW3000 ranging API integration.
- Apple-compatible Nearby Interaction accessory protocol support.
- Any real iPhone UWB direction/distance sourced from the iPhone UWB chip.
