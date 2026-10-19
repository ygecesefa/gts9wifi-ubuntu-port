# v0.2.0-pre2

Second test build for the Galaxy Tab S9 Wi-Fi (SM-X710, `gts9wifi`): Ubuntu
24.04 GNOME from microSD, Android stays on the internal storage. Everything
below was first fixed live on the reference tablet, then built into this image.
Every patch and script carries its reason and provenance; see
[KNOWN-ISSUES.md](KNOWN-ISSUES.md) for the per-item history.

## Changes since v0.2.0-pre1

### Kernel (7.2.0, patches `kernel/patches-gts9wifi/0005`–`0017`)
- Suspend/wake: ath11k Wake-on-WLAN policy (0005) and a quieter console cut
  resume from 3–4 s to ~0.13 s; double tap to wake reads the gesture after
  resume (0006)
- Charging: 80 % charge limit and charge bypass on the SM5714 (0007), switches
  in Tab9 Extras
- Memory: 30 unused Android carveouts released, ~812 MiB more RAM (0008)
- S9 Ultra SoC fixes (0009–0015): q6v5 handover/ready IRQ storms, fastrpc
  ordering, GMU fault wait, DPU resource reassignment, DRM bridge hotplug,
  GENI I2C cancel
- Fingerprint: QTEE large objects (0016), touchscreen tracks the sensor area
  (0017); the touchscreen driver is now a module
- The eight fingerprint/SPU modules are built at all (a `\t` in the Fedora
  recipe had silently dropped them)

### Device
- **Fingerprint reader works**: enrol in Settings → Users, then unlock, sudo
  and polkit accept it (password still works). Secure start (SPU, Keymaster,
  HwVault) runs once per boot. Needs the tablet's own calibration, which
  `to-ubuntu.sh` copies from Android on the first switch
- Cameras: libcamera + PipeWire, rear autofocus, photo capture without freezes
- Sensors: rotation, ambient light, compass (ADSP / SSC)
- Video: iris hardware decode (H.264/HEVC/VP9) and encode, Totem included
- Wi-Fi 5 GHz RX (correct WCN6855 board data); Bluetooth address from EFS
- Power key: press to lock and suspend, hold for the power menu
- On-screen keyboard opens in GTK apps, Chromium and Firefox (IBus,
  text-input-v3); optional floating keyboard button
- Tab9 Extras settings app (double tap to wake, charging, keyboard)
- Clock: RTC + saved offset before journald (correct time and full boot logs
  without network), NTP afterwards
- `/vendor` mounted read-only from `super`; Android partitions hidden

### Dual boot
- "Switch to Android" from the app grid, no terminal or password
- `to-ubuntu.sh` also copies the fingerprint calibration to the microSD

### Removed or disabled
- `gts9wifi-mem-reclaim` and `gts9wifi-bt-provision` (they wrote to boot
  partitions), `rmtfs`

## Known limitations
- The screen brightens softly while a finger is on the sensor (the panel's
  fingerprint mode is global); GNOME Settings does not animate enrolment
  progress, enrolment completes anyway
- XWayland (X11) apps do not open the on-screen keyboard; swipe up from the
  bottom edge
- Rare GPU fault (GMU OOB) under load
- Browsers decode video in software

## Updating the Android side
After installing this release, replace `/sdcard/Ubuntu/images/` with the four
images and `SHA256SUMS` from the boot set, and `/data/local/tmp/to-ubuntu.sh`
with the new script. An old image set would boot an old kernel against the
new modules (no Wi-Fi, no fingerprint).

## Hardware status
See the table in the [README](../../README.md); every row is measured on the
tablet.
