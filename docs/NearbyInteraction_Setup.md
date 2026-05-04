# Nearby Interaction Setup

## Goal

Use an iPhone 16 Pro Max and a Qorvo DWM3000EVB-based accessory with Apple's
Nearby Interaction framework.

This is not DWM3000-to-DWM3000 ranging. Real distance and direction must come
from `NINearbyObject` updates in the iPhone app.

## iPhone flow

1. Scan for BLE device name `VibeTrack-UWB`.
2. Connect with CoreBluetooth.
3. Discover the VibeTrack NI BLE service.
4. Receive real accessory configuration data from the accessory configuration characteristic.
5. Create `NINearbyAccessoryConfiguration(data:)`.
6. Run an `NISession`.
7. Send `session(_:didGenerateShareableConfigurationData:for:)` bytes back to the accessory.
8. Display `NINearbyObject.distance`.
9. Display `NINearbyObject.direction` when it is non-nil.
10. Show distance-only status when direction is nil.

## Accessory flow

1. Advertise BLE as `VibeTrack-UWB`.
2. Expose the documented service and characteristics.
3. Initialize the DWM3000EVB and verify `DEV_ID`.
4. Use Qorvo's Apple NI-compatible accessory firmware to generate accessory configuration data.
5. Send that accessory configuration data to the iPhone over BLE.
6. Receive the iPhone shareable configuration data over BLE.
7. Start the compliant accessory-side NI UWB exchange.

## Current limitation

The ESP32 Arduino firmware in this repo does steps 1 through 3 and keeps BLE
working. It cannot do steps 4 through 7 because Qorvo's Apple NI accessory API
is not available in this source tree for ESP32 Arduino.

The firmware prints and notifies:

```text
NI accessory firmware not implemented because Qorvo Apple NI accessory API is missing.
```

That message is expected until real Qorvo NI accessory firmware is integrated.

## Official references

- Apple `NINearbyAccessoryConfiguration`: https://developer.apple.com/documentation/nearbyinteraction/ninearbyaccessoryconfiguration
- Apple Nearby Interaction with UWB: https://developer.apple.com/nearby-interaction/
- Qorvo DWM3000EVB: https://www.qorvo.com/products/p/DWM3000EVB
- Qorvo Apple-compatible UWB solutions: https://www.qorvo.com/innovation/ultra-wideband/products/uwb-solutions-compatible-with-apple-u1
