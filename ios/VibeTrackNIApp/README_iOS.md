# VibeTrack NI iOS App

This folder contains source-only SwiftUI files for the iPhone app. No Xcode
project metadata is included in this repo.

## How to create the Xcode app

1. In Xcode, create a new iOS App project named `VibeTrackNIApp`.
2. Choose SwiftUI and Swift.
3. Copy the Swift files from this folder into the app target.
4. Replace the generated `Info.plist` values with the entries in `Info.plist`.
5. Add the `NearbyInteraction.framework` and `CoreBluetooth.framework` imports by building the target normally.
6. Build and run on a physical iPhone 16 Pro Max.

The iOS simulator cannot fully test this project because it does not provide
real Bluetooth LE peripheral scanning/connection or UWB Nearby Interaction
hardware updates.

## BLE protocol

The app scans for the accessory name `VibeTrack-UWB` and discovers this custom
service:

| Purpose | UUID |
| --- | --- |
| NI BLE service | `7E400001-B5A3-F393-E0A9-E50E24DCCA9E` |
| Accessory NI configuration notify/read/write | `7E400011-B5A3-F393-E0A9-E50E24DCCA9E` |
| iPhone NI configuration write | `7E400012-B5A3-F393-E0A9-E50E24DCCA9E` |
| Status/debug notify/read/write | `7E400013-B5A3-F393-E0A9-E50E24DCCA9E` |

The accessory configuration characteristic must contain real
Apple/Qorvo-compatible Nearby Interaction accessory configuration bytes. The
app passes those bytes into `NINearbyAccessoryConfiguration`. It does not accept
or display BLE distance values as if they were Nearby Interaction results.

## Expected behavior

- If accessory configuration is missing, the app shows `Accessory configuration missing`.
- If `NISession` receives real `NINearbyObject.distance`, the app displays meters and feet.
- If `NINearbyObject.direction` is nil, the arrow is gray and the app shows distance-only status.
- If the session invalidates, the debug log shows the `NISession` error.
