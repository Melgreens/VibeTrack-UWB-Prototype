# Troubleshooting

## BLE connects but Nearby Interaction does not start

Check the debug log in the app. If it says `Accessory configuration missing`,
the iPhone has not received real Apple/Qorvo accessory configuration bytes. The
current ESP32 Arduino firmware intentionally does not invent those bytes.

## Accessory configuration data is missing

This is expected with the transport-only ESP32 firmware. Real config data must
come from Qorvo's Apple NI-compatible accessory firmware/API.

## NISession invalidates

Common causes:

- Nearby Interaction permission was denied.
- The accessory configuration bytes are invalid.
- The accessory configuration lacks a discovery token.
- The accessory disconnected.
- The accessory-side NI UWB protocol is not running.

The app shows the invalidation error in the debug log.

## Distance updates but direction is nil

The app displays distance-only tracking. Move the iPhone around, improve line of
sight, and keep the accessory nearby. Direction may be unavailable even when
distance is present.

## DWM3000 device ID fails

If Serial shows `0x00000000`, `0xFFFFFFFF`, or another invalid value:

- Verify 3.3V power and ground.
- Verify `SCK=GPIO18`, `MOSI=GPIO23`, `MISO=GPIO19`, `CS=GPIO4`.
- Verify `RST=GPIO27`.
- Confirm the DWM3000EVB shield/header pin labels match your wiring.
- Shorten SPI jumper wires.

## SPI wiring is wrong

Wrong CS, swapped MISO/MOSI, missing ground, or a reset line held low will stop
the device ID read. Fix SPI before debugging Nearby Interaction.

## ESP32 cannot run Qorvo NI firmware

The source tree does not include a Qorvo Apple NI accessory SDK/API for ESP32
Arduino. If Qorvo's NI stack is only available for another supported platform,
such as a Qorvo or Nordic development setup, use that platform for real NI.

## iPhone 16 Pro Max gives distance-only behavior

Distance-only mode means `NINearbyObject.distance` is present but
`NINearbyObject.direction` is nil. The app does not synthesize direction.
Improve line of sight and move the iPhone until the NI framework provides a
direction vector.

## Comparing with the official Qorvo app

Use Qorvo's official Nearby Interaction app with a supported Qorvo NI firmware
image as a baseline. If the official app cannot get distance/direction from the
accessory, this app will not be able to either.
