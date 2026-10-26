# WalkPad Bar

macOS menu bar app showing live stats from a Bluetooth walking pad (built for the Dreaver Elevate One,
should work with any FTMS treadmill).

- Menu bar: icon (`figure.stand` off · `figure.walk` on/stopped · `figure.walk.motion` walking) plus the
  stats you pick — speed, steps, distance, incline, time.
- Panel: status, speed, incline, distance, steps, time, kcal; menu-bar field toggles; launch at login.
- Controls: start / pause / stop, speed ±0.1 km/h, incline ±1 % via the FTMS Control Point (`2AD9`),
  clamped to the pad's advertised ranges (`2AD4`/`2AD5`: 1–6 km/h, 0–9 %).

## Build

```sh
swift test              # parser tests (Swift Testing; works with Command Line Tools only)
./build.sh install      # builds WalkPadBar.app, copies to ~/Applications, launches
```

First launch asks for Bluetooth access. Debug log:
`log stream --level debug --predicate 'subsystem == "com.github.gureevleonid.walkpadbar"'`

## Protocol notes (Dreaver Elevate One, FitShow FS-BT-T4, fw V2.6.3)

Advertises FTMS `1826` + vendor `FFF0`. Stats come from Treadmill Data `2ACD` at 1 Hz, as two frames:

| Frame | Example | Meaning |
|---|---|---|
| main | `8c 05 fa00 220b00 1400 0000 00 c800 ffff ff 00 4a10` | speed 2.50 km/h, distance 2850 m, incline 2.0 %, *pad byte*, 200 kcal, HR 0, 4170 s |
| steps | `01 20 731400` | flag bit 13 (reserved in spec) → uint24 steps = 5235 |

The firmware inserts one extra byte after Inclination/Ramp Angle, so the parser reads trailing fields
from the end of the frame. Only one central can connect at a time — the phone app and this app will
compete for the pad.
