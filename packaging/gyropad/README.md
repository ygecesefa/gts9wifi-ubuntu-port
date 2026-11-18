# gyropad: a controller + the tablet's motion sensors = one DualSense

Clip-on controllers such as the Razer Kishi Ultra have no gyroscope, but
they hold the tablet: tilting the tablet is tilting the controller.
`gts9wifi-gyropad` joins the two into one virtual **DualSense**, so PS5 games
streamed with chiaki-ng, Steam games and emulators get motion controls.

| File | What |
|---|---|
| `gts9wifi-imu.c` | streams the tablet's gyroscope and accelerometer (Qualcomm Sensor Core, through libssc) at ~200 Hz |
| `build-gyropad.sh` | builds it with its own copy of libssc 0.4.4 (+ `packaging/sensors/fix-ssc-sync-wait-busy-loop.patch`) in which `SSC_SAMPLE_RATE` picks a higher rate: libssc always asked for the lowest rate the sensor offers, 26 Hz here. The system's libssc (screen rotation, 26 Hz) is not touched. Output: `/usr/lib/gts9wifi-gyropad/{bin/gts9wifi-imu,lib/libssc.so.2}` |
| `gts9wifi-gyropad` | the bridge (Python, root): grabs the controller (evdev), reads `gts9wifi-imu`, and creates a USB DualSense through `/dev/uhid`. The kernel's `hid-playstation` driver and SDL's HIDAPI driver (Steam, chiaki-ng) then see a DualSense with motion sensors. Game rumble goes to the controller if it has force feedback |
| `gts9wifi-gyropad.service` | runs it; waits for a controller, restarts when it is unplugged. Not enabled: started by the session when the Game Manager switch is on |
| `50-gts9wifi-gyropad.rules` | polkit: the user at the screen may start/stop this one service without a password (the Game Manager switch) |

Measured on the tablet (2026-11-19): `gts9wifi-imu 200` gives ~210 gyroscope
and accelerometer samples per second (`400` → ~415), the kernel registers
"Sony Interactive Entertainment DualSense Wireless Controller" with Motion
Sensors and Touchpad devices, `/dev/hidrawN` gets the user ACL from
`steam-devices`, and a PS5 game's gyro section was played through chiaki-ng
with a Kishi Ultra.

Details:

- Report layout, report IDs and sizes, and the calibration format are those
  of `drivers/hid/hid-playstation.c`. The report descriptor is a minimal one
  with the same report IDs and sizes (vendor usages), not Sony's.
- Calibration report: ±8847 raw = ±540 °/s (raw = °/s × 16.384, a real
  DualSense's scale), accelerometer ±8192 = ±1 g.
- Axes: `--axes x,z,-y` by default (tablet X → DualSense X, tablet Z → Y,
  −tablet Y → Z): the screen is the controller's face, held landscape facing
  the player. `GTS9WIFI_GYROPAD_AXES` in the unit changes it.
- Button mapping is for Android-style controllers (BTN_A south, BTN_B east,
  BTN_X west, BTN_Y north; sticks ABS_X/Y and ABS_Z/RZ; triggers ABS_BRAKE /
  ABS_GAS). Checked with the Kishi Ultra by playing.
