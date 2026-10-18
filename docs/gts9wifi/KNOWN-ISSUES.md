# Known issues and targets

## Found on the first boot (v0.2.0-pre1, 2026-10-18)

- **5 GHz Wi-Fi RX ~40 dB weak — fixed.** This tablet's WCN6855 reports
  `qmi-chip-id=2`, so ath11k loads the `…subsystem-device=0108,qmi-chip-id=2,qmi-board-id=255`
  entry of `board-2.bin`, a generic payload. The Fedora port's 5 GHz fix put the
  device-tuned `NTM_TW220` payload only into the `qmi-chip-id=18` entry, which
  this unit never selects. Copying the tuned payload into the chip-id=2 entry
  took a phone hotspot 1 m away from −83 dBm to −41…−50 dBm and made seven
  5 GHz networks visible. Done at build time by `build-gts9wifi-rootfs.sh`.
- **`gts9wifi-mem-reclaim` disabled.** It rewrites the DTB inside the `boot` and
  `vendor_boot` partitions on every boot to free ~812 MiB of unused carveouts.
  That breaks the sha256-verified switch scripts and risks an unbootable boot
  image. The same reclaim should be done at build time in the DTB instead.
- `rmtfs` disabled: this Wi-Fi tablet has no modem.
- Cameras: both HI1337 sensors and the DW9808 lens probe; apps see no camera
  until the stage B libcamera.

## Open in v0.2.0-alpha1

- Not yet booted on the tablet. Every hardware row is 🧪 until the first boot test.
- Bluetooth BD address provisioning (`gts9wifi-bt-provision`) is disabled: it
  rewrites the DTB inside `boot`/`vendor_boot` on every boot, which conflicts
  with the sha256-verified switch scripts. To be redesigned.
- `persist` is mounted read-only; sensor-registry writes are therefore off.
- The ADSP sensor chain (rotation) needs `hexagonrpcd`/`libssc`, which Ubuntu
  does not ship (stage B).
- Stock Ubuntu libcamera: no autofocus yet (stage B).
- Test account with a known password; change it on first login.

## Issues of the Fedora gts9wifi port, and the plan here

| Fedora issue | Plan in this port |
|---|---|
| S Pen tilt missing | **works here**: WEZ01 reports TILT_X/Y, measured −29…+35 on the tablet |
| Rear camera autofocus missing | the S9 Ultra port's libcamera software autofocus (DW9808 is the same actuator) |
| No charging-bypass UI | expose SM5714/SM5440 bypass, add a toggle |
| SELinux permissive | not applicable: Ubuntu uses AppArmor, enabled |
| `/vendor` not mounted | map `super`'s vendor with dm-linear, read-only |
| Browsers / VLC decode video in software | iris VPU via GStreamer/ffmpeg V4L2 for players; Vulkan Video is not implemented by Mesa Turnip on any Linux |
| Linux 7.2.1–7.2.6 break Wi-Fi | kernel pinned to 7.2.0; Wi-Fi works |
| Weak 5 GHz (Fedora issue 7, marked fixed there) | the Fedora fix targets the wrong board-data entry for this unit; fixed here |

## Work queue (ordered)

Live items are installed on the running tablet over SSH and need no new image;
items that need a new kernel or image come last, because each image cycle
(build ~3 h on the Pi, write, boot) is long. Everything live is folded into the
next image afterwards.

| # | Item | Origin | Needs |
|---|---|---|---|
| 1 | ~~Bluetooth public address from `efs` at boot~~ — **done** (`gts9wifi-bt-address` + `gts9wifi-bt-mgmt`), plus NTP (`systemd-timesyncd`) | this port | live |
| 2 | ~~Hardware video decode~~ — **done**: iris decodes H.264/HEVC/VP9 and encodes H.264/HEVC; GStreamer ranks it first so Totem uses it with no setup. Open: browsers (no VA-API for the VPU), mpv/VLC configuration | Fedora 16 | live |
| 3 | ~~Rotation sensor~~ — **done**: accelerometer, ambient light and compass; sensor PD started once per boot after the ADSP and the panel cold-boot recovery (the race that hung Fedora), iio-sensor-proxy waits for SSC | Fedora 5 | live (packages) |
| 4 | Cameras in apps + **rear autofocus** — **preview done**: both cameras stream through libcamera/PipeWire (GPU soft ISP, full field of view), rear continuous AF works. **Open: taking a picture in GNOME Snapshot freezes the app** — the quick stream restarts leave both CCI I2C controllers timing out (no IRQ; sensor and VCM rails do power-cycle, rebinding the CCI driver recovers); a reboot brings the rear camera back. Kernel patches 0002/0003 (sensor off time + retry, VCM no longer holds the rail) are kept but do not fix it. Rare separate issue: GPU fault (GMU OOB timeout) in the soft ISP when switching cameras | Fedora 4/4b/11 | live (packages) + kernel fix |
| 5 | Double-tap to wake + device-control GNOME extension (port to GNOME 46) | Fedora 14 | live |
| 6 | ~~`/vendor`~~ — **done**: `gts9wifi-android-parts` parses super's liblp metadata, maps `vendor` read-only with dm-linear; mounted `ro,noload`. Also fixed: `dsp` and `persist` were mounted without `noload`, so a dirty journal would have been replayed onto the Android partitions | Fedora open | live |
| 7 | Check file capabilities, early-boot clock, ADSP late-start safety | Fedora open | live |
| 7b | **Waydroid** (Android apps in Ubuntu): binder/netfilter already in the kernel; install Waydroid 1.6 + LineageOS 20 GAPPS image as the S9 Ultra port does (`docs/waydroid.md`) | owner | live |
| 8 | Under-display fingerprint (EL721) — blocked on Fedora at `KEYMASTER_NOT_CONFIGURED` | Fedora 15 | live, large |
| 9 | **Charging bypass**: `charge_types` (Standard/Bypass) in the SM5714 driver (stock `ovp_bypass_mode` + two register writes) and a toggle | Fedora 13 | **kernel** + live UI |
| 10 | Reclaim ~812 MiB of dead carveouts in the DTB at build time (replaces `gts9wifi-mem-reclaim`) | this port | **kernel/bundle** |
| 11 | Device-independent S9 Ultra SoC patches, one at a time | S9 Ultra | **kernel** |
| 12 | Image `v0.2.0-pre2`: everything above + 5 GHz fix + one-tap switches | — | **image** |
| 13 | **Boot-time choice with the keys**: Ubuntu in the `recovery` partition, so a normal boot starts Android and *Volume Up + Power* starts Ubuntu (no image swapping). Open questions: ABL's use of the shared `dtbo` on a recovery boot, and losing the custom recovery as rescue path. Alternative: hold *Volume Down* during Ubuntu's initramfs to switch to Android | owner | **image**, experiment |
| 13b | **A working TWRP first**: rainbowdashh V2 cannot mount `/data`, `system` etc.; the fstab/flags edits of v0.1 did not help. Root-cause and build a fixed TWRP (and settle the Odin/vbmeta flashing) before any installer ZIP | owner | **image** |
| 14 | TWRP, then the TWRP installer ZIP (microSD / beside Android / whole tablet) | owner | **image**, last |

Not applicable on Ubuntu: SELinux permissive (AppArmor is used and enabled).
Already resolved here: S Pen tilt, weak 5 GHz, 7.2.1–7.2.6 Wi-Fi, two-way dual boot.

## Lessons from v0.1.0-alpha1

`v0.1.0-alpha1` (an earlier, AI-driven attempt, never booted) is superseded.
Its problems are documented in [PORTING-LOG.md](PORTING-LOG.md) so they are not
repeated: the X710 drivers were not in its kernel, the device firmware was not
in its rootfs, and its install notes wrote `vbmeta` unnecessarily.
