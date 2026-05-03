# VibeTrack UWB Prototype

Focused local UWB tracking prototype for ESP32 + Qorvo DWM3000 + SwiftUI iPhone app.

This version removes simulated/test telemetry from the firmware path. The tag ESP32 performs real DWM3000 two-way ranging with a second ESP32/DWM3000 anchor, then sends newline-terminated JSON telemetry to the iPhone over BLE.

## Architecture

1. Real local ranging layer
   - Anchor ESP32 + DWM3000 listens for double-sided two-way ranging messages.
   - Tag ESP32 + DWM3000 initiates ranging, calculates distance, and advertises BLE as `VibeTrack-UWB`.
   - iPhone app connects with CoreBluetooth, subscribes to telemetry JSON, and displays distance/status/debug data.
   - `bearingDegrees` is `null` because this BLE telemetry path does not provide real iPhone UWB direction.

2. Future Nearby Interaction layer
   - `ios/VibeTrackUWB/NearbyInteractionPlaceholder.swift` marks where `NISession` setup could go later.
   - The current firmware and app do not implement Apple Nearby Interaction accessory protocol support.
   - A generic DWM3000 module does not automatically work with the iPhone UWB chip.

## Which Sketch Goes Where

| Board | Sketch | Role |
| --- | --- | --- |
| Mobile/tracked board | `firmware/VibeTech_UWB_Tag_BLE/VibeTech_UWB_Tag_BLE.ino` | Starts DWM3000 ranging and sends BLE JSON to the iPhone |
| Fixed board | `firmware/VibeTech_UWB_Anchor/VibeTech_UWB_Anchor.ino` | Responds to DWM3000 ranging messages |

## Wiring

Use the same wiring on both ESP32/DWM3000 boards.

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

## Required Arduino Libraries

Install these before compiling the sketches:

- ESP32 Arduino core
- ESP32 BLE Arduino library included with the ESP32 Arduino core
- `Fhilb/DW3000_Arduino`: https://github.com/Fhilb/DW3000_Arduino

The two sketches use the real `DW3000.h` API names from the library's double-sided ranging examples. The library was not installed in this local workspace during editing, so compile after installing it in your Arduino libraries folder.

## BLE Contract

- Device name: `VibeTrack-UWB`
- Service UUID: `7E400001-B5A3-F393-E0A9-E50E24DCCA9E`
- Telemetry characteristic UUID: `7E400002-B5A3-F393-E0A9-E50E24DCCA9E`
- Command characteristic UUID: `7E400003-B5A3-F393-E0A9-E50E24DCCA9E`

Commands:

- `RESET_UWB`
- `STATUS`

Successful telemetry:

```json
{
  "deviceName": "VibeTech 3 UWB",
  "uwbDetected": true,
  "deviceId": "0xDECA0302",
  "mode": "uwb_ranging",
  "distanceMeters": 1.23,
  "distanceFeet": 4.04,
  "bearingDegrees": null,
  "signalQuality": "real",
  "lastUpdateMs": 123456,
  "error": null
}
```

Error telemetry:

```json
{
  "deviceName": "VibeTech 3 UWB",
  "uwbDetected": false,
  "deviceId": "0x00000000",
  "mode": "uwb_error",
  "distanceMeters": null,
  "distanceFeet": null,
  "bearingDegrees": null,
  "signalQuality": "none",
  "lastUpdateMs": 123456,
  "error": "No valid UWB range received for more than 2 seconds."
}
```

## ESP32 Real Distance Test

1. Install `Fhilb/DW3000_Arduino`.
2. Wire both ESP32/DWM3000 boards using the table above.
3. Flash `VibeTech_UWB_Anchor.ino` to the fixed anchor board.
4. Open the anchor Serial Monitor at `115200`.
5. Confirm SPI starts, reset completes, `DEV_ID` is read, and the anchor reports ranging responder started.
6. Flash `VibeTech_UWB_Tag_BLE.ino` to the mobile/tag board.
7. Open the tag Serial Monitor at `115200`.
8. Confirm SPI starts, reset completes, `DEV_ID` is read, BLE starts, and ranging starts.
9. Move the boards closer/farther apart and confirm valid distance logs in meters and feet.
10. If no range appears within 2 seconds, check that the anchor is powered, flashed, and using the same channel/config.

## iPhone App Test

1. Build on a physical iPhone. The iOS simulator cannot fully test BLE hardware.
2. Allow Bluetooth permissions.
3. Scan for `VibeTrack-UWB`.
4. Connect to the tag board.
5. Verify telemetry updates.
6. Confirm the distance changes as the boards move.
7. Confirm the arrow shows no real iPhone UWB bearing instead of a fake bearing.
8. Open Debug and confirm raw JSON appears.
9. Confirm `mode` is `uwb_ranging` and `signalQuality` is `real` during valid ranging.
10. Power off the anchor and confirm the app shows `uwb_error` with null distance fields.

## How To Tell Simulation Is Fully Removed

- Firmware no longer accepts `START_SIM` or `STOP_SIM`.
- Firmware does not output `mode: "simulated_tracking"`.
- Firmware does not output `signalQuality: "simulated"`.
- Firmware sends `bearingDegrees: null`.
- Valid distance comes only from the DWM3000 ranging exchange.

## Real Now vs Later

Real now:

- ESP32 SPI setup with `SPI.begin(18, 19, 23, 4)`.
- DWM3000 reset, `DEV_ID` read, and double-sided two-way ranging using `Fhilb/DW3000_Arduino`.
- Anchor/tag UWB ranging structure with clear Serial debug logs.
- BLE GATT telemetry and command path.
- SwiftUI CoreBluetooth scanning, connection, JSON decoding, nullable distance/bearing handling, controls, and debug view.

Requires later work:

- Antenna-delay calibration for accurate distance on your exact boards/enclosures.
- Apple-compatible Nearby Interaction accessory protocol support.
- Real iPhone UWB direction/distance sourced from the iPhone UWB chip.
