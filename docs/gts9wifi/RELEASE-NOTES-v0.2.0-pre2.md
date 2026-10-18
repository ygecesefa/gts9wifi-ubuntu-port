# v0.2.0-pre2 — draft

> **Draft.** Collects what was fixed live on the tablet after v0.2.0-pre1
> booted. Not built or released yet.

## Changes since v0.2.0-pre1

- Wi-Fi: 5 GHz RX fixed (correct WCN6855 board-data entry for this unit)
- Bluetooth: unit address from EFS at every boot, no boot-partition writes
- Sensors: screen rotation, ambient light, compass (ADSP / SSC)
- `/vendor` mounted read-only from `super`; `dsp`, `persist`, `vendor` all `noload`
- Video: iris hardware decode (H.264/HEVC/VP9) and encode, Totem included
- Clock: NTP (systemd-timesyncd)
- Dual boot: one-tap "Switch to Android" (no terminal/password/prompt)
- Android partitions hidden from the dock and Files
- Disabled: `gts9wifi-mem-reclaim`, `gts9wifi-bt-provision` (wrote to boot partitions), `rmtfs`
- Packages added: `iw`, `dmsetup`, `systemd-timesyncd`, `totem`, sensor packages

## Hardware status

See the table in the README; every row is measured on the tablet.
