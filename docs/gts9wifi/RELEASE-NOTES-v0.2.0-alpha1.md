# v0.2.0-alpha1 — first gts9wifi baseline (draft)

> **Draft.** Not released yet. This file is completed after the first boot
> test on the tablet; until then nothing below is confirmed on hardware.

Supersedes `v0.1.0-alpha1`, which never booted (see
[PORTING-LOG.md](PORTING-LOG.md)).

## What is in it

- Linux **7.2** (`8d3ae5928`) + the Fedora gts9wifi port's patches, X710
  drivers and device tree + Ubuntu userspace kernel options
- Ubuntu **24.04 LTS** GNOME desktop on microSD, Turkish locale/keyboard by
  default
- X710 device firmware staged from the owner's tablet
- X710 device services from the Fedora port (USB network, panel cold-boot
  recovery, rootfs growth, Wi-Fi recovery, DSP/firmware mounts, ALSA UCM)
- Android ↔ Ubuntu switch scripts with sha256 verification; `vbmeta` never written

## Assets

| File | Purpose |
|---|---|
| `ubuntu-gts9wifi-v0.2.0-alpha1-sd.img.zst` | microSD image |
| `boot.img`, `init_boot.img`, `vendor_boot.img`, `dtbo.img` | Ubuntu boot set |
| `to-ubuntu.sh` | Android → Ubuntu switch |
| `SHA256SUMS` | checksums of everything above |

## Install

[INSTALL.md](INSTALL.md) and [DUALBOOT.md](DUALBOOT.md).

## Hardware status

To be filled from the first boot test.

## Known issues

[KNOWN-ISSUES.md](KNOWN-ISSUES.md).
