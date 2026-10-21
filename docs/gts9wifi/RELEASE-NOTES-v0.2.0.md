# v0.2.0 — Ubuntu 24.04 for the Galaxy Tab S9 Wi-Fi (SM-X710)

First public release. Ubuntu 24.04 LTS (GNOME 46 on Wayland, Linux 7.2.0)
on a microSD card, next to Android. Android and its data stay untouched.

## The one file you need

`ubuntu-gts9wifi-v0.2.0-installer.zip` (check it with the `.sha256` next to
it). It is both:

- a **Magisk module**: *Modules → Install from storage* (recommended), and
- a **recovery zip**: TWRP / LineageOS recovery, best with `adb sideload`
  (for tablets without root).

On the tablet it writes Ubuntu to the card, backs up **your own** Android
boot images (any Android version) into `android-restore.zip`, builds
`ubuntu-boot.zip`, puts both on the card's `GTS9W_BACK` partition, and only
then writes the Ubuntu boot images. Critical questions are answered YES by
pressing a volume key **twice** in Android (once = no), or Volume Up in
recovery. Steps: [INSTALL.md](INSTALL.md).

## Switching

- **Android → Ubuntu:** Magisk → *Modules* → *Ubuntu for Galaxy Tab S9 Wi-Fi*
  → **RUN** (▶ action) button. KernelSU / APatch: the module's WebUI.
- **Ubuntu → Android:** *Switch to Android* in the dock.
- **Emergencies, or no root:** flash `android-restore.zip` /
  `ubuntu-boot.zip` from `GTS9W_BACK` in recovery (TWRP).

The module refreshes `android-restore.zip` after Android or Magisk updates,
and copies the fingerprint calibration to the card; Ubuntu installs it at
the next boot.

## What works

Display, touch (double tap to wake), S Pen with tilt, GPU (Vulkan 1.4), Wi-Fi
2.4/5 GHz, Bluetooth, audio (speakers, microphone), battery with 80 % limit
and charge bypass, both cameras with rear autofocus, hardware video in
GStreamer apps, sensors (rotation, light, compass), instant suspend/wake,
under-display fingerprint (unlock, sudo), on-screen keyboard. Full table and
known issues: [README](../../README.md),
[KNOWN-ISSUES.md](KNOWN-ISSUES.md).

## Changes since the pre-releases

- One zip for recovery and Magisk; the switch zips are made on the tablet
  and never published (they must hold the user's own Android images).
- Magisk module: RUN button / WebUI to Ubuntu, Android backup kept current.
- Fingerprint calibration comes over by itself (Magisk install or module).
- In Android, YES = two presses: Android swaps the volume keys with rotation.
- A fresh card now has working DNS (and so time sync): the image no longer
  carries the build host's `resolv.conf`.

Default login: `ubuntu` / `ubuntu` (you are asked to change it).
