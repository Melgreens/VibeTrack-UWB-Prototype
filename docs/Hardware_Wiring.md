# Hardware Wiring

Use this wiring for the ESP32-WROOM-32 development board and Qorvo DWM3000EVB
unless your DWM3000EVB shield/header adapter requires a different mapping.

| DWM3000EVB | ESP32 |
| --- | --- |
| VCC | 3.3V |
| GND | GND |
| SCK | GPIO18 |
| MOSI | GPIO23 |
| MISO | GPIO19 |
| CS | GPIO4 |
| RST | GPIO27 |
| IRQ | GPIO34 |

## Power notes

- Use 3.3V logic only.
- Confirm the DWM3000EVB power jumper is set for the supply path you are using.
- Keep SPI wires short while debugging.
- If `DEV_ID` reads `0x00000000` or `0xFFFFFFFF`, check power, ground, CS, MISO,
  MOSI, SCK, and reset wiring first.

## Expected Serial logs

At `115200`, successful bring-up should include:

```text
[SPI] Starting SPI.begin(18, 19, 23, 4)...
[SPI] SPI started.
[DWM3000] DWM3000 reset complete.
[DWM3000] DEV_ID read result: 0xDECA0302
[DWM3000] DWM3000 init success for SPI transport bring-up.
[BLE] BLE started. Advertising as VibeTrack-UWB.
```

Your exact `DEV_ID` may differ for a DW3000-family part, but it should not be
all zeroes or all ones.
