# Ubuntu 24.04 for the Samsung Galaxy Tab S9 Wi-Fi (SM-X710, `gts9wifi`)

> **Alpha.** This is an open, step-by-step port. Everything here is a
> reproducible recipe: every image published in Releases can be rebuilt from
> this repository with the commands in [BUILDING.md](docs/gts9wifi/BUILDING.md).

Ubuntu 24.04 LTS (GNOME, Wayland) booting from a **microSD card** next to
Android, on the Galaxy Tab S9 Wi-Fi (Snapdragon 8 Gen 2 / SM8550).
Android stays on the internal storage untouched; switching between the two
systems only rewrites four boot partitions, which are backed up first.

| | |
|---|---|
| Device | Samsung Galaxy Tab S9 Wi-Fi, SM-X710, codename `gts9wifi` |
| SoC | Qualcomm SM8550 (Snapdragon 8 Gen 2), Adreno 740 |
| Kernel | mainline Linux 7.2 + gts9wifi patches and drivers |
| Userspace | Ubuntu 24.04 LTS (noble), GNOME on Wayland |
| Root filesystem | microSD (`GTS9W_ROOT`), Android untouched on UFS |
| Status | `v0.2.0-pre1` boots — see [hardware status](#hardware-status) |

## Where this comes from

This port stands on two existing projects and would not exist without them:

- **[agcarbajo/ubuntu-galaxy-tab-s9-ultra](https://github.com/agcarbajo/ubuntu-galaxy-tab-s9-ultra)**
  (MIT) — Ubuntu port for the S9 Ultra (SM-X910). This repository is a fork of
  it: the Ubuntu build tooling, the SM8550 SoC work and the patched userspace
  (libcamera autofocus, sensors, mutter) come from there.
- **[nacht20-de/gts9wifi-fedora-linux](https://github.com/nacht20-de/gts9wifi-fedora-linux)**
  (MIT) — Fedora port for *this* tablet. The kernel recipe (patches, X710
  drivers, device tree) and the X710 device services come from there.

Also used: [rainbowdashh/android_device_samsung_gts9wifi](https://github.com/rainbowdashh/android_device_samsung_gts9wifi)
(TWRP device tree, partition map).

The S9 Ultra and the S9 share the SoC but not the board. What this port changes:

| S9 Ultra (SM-X910) | S9 Wi-Fi (SM-X710), this port |
|---|---|
| board-id `0x10008 0x03`, `gts9uwifi` DTS | board-id `0x10008 0x04`, `gts9wifi` DTS |
| WCN7850 Wi-Fi 7 / `ath12k` | WCN6855 Wi-Fi 6E / `ath11k` |
| Goodix touchscreen | ST FTS1BA90A touchscreen |
| Wacom W90xx S Pen | Wacom WEZ01 S Pen |
| ANA38407 AMSA46AS02 panel (2960×1848) | ANA38407 AMSA10FA01 panel (2560×1600) |
| four cameras | two cameras (HI1337 rear + DW9808 lens, HI1337 front) |

## Hardware status

Legend: ✅ confirmed on the tablet · 🧪 built, not yet tested on the tablet ·
🟡 partial · ❌ not working · — not started

| Area | v0.2.0-alpha1 | Notes |
|---|---|---|
| Boot from microSD | ✅ | first boot 2026-10-18; root grown to the whole card |
| Dual boot Android ↔ Ubuntu | ✅ | both directions verified on the tablet; one-tap "Switch to Android" in the dock |
| Display (ANA38407) | ✅ | DSI-1 2560×1600, backlight, GNOME on Wayland |
| Touch (FTS1BA90A) | ✅ | |
| Wi-Fi (WCN6855) | ✅ | 2.4 and 5 GHz; 5 GHz RX fixed via the correct board-data slot (see KNOWN-ISSUES) — fix built into the next image |
| Bluetooth | ✅ | unit address read from EFS (read-only) and set over mgmt at every boot; no boot-partition writes |
| GPU (Adreno 740, Freedreno/Turnip) | ✅ | SQE/GMU firmware loaded from the initramfs |
| Audio (CS35L45) | ✅ | speakers play (owner confirmed) |
| Battery / charging (SM5714) | ✅ | |
| S Pen (WEZ01) | ✅ | position, pressure 0–4095, hover distance, **tilt X/Y** (measured −29…+35) |
| Cameras (2× HI1337, DW9808 lens) | ✅ | front and rear in apps (libcamera + PipeWire, GPU soft ISP, full field of view); GNOME Snapshot takes pictures. Live on the tablet, in the next image |
| Rear camera autofocus | ✅ | continuous AF (S9 Ultra libcamera software AF on the DW9808) |
| Hardware video decode | ✅ | iris VPU: H.264, HEVC, VP9 1080p, 300/300 frames, ~10–15× less CPU than software; GStreamer picks it automatically (GNOME Videos/Totem). Browsers still decode in software (no VA-API for the VPU) |
| Hardware video encode | ✅ | iris VPU: H.264 and HEVC 1080p at ~170–300 fps (`v4l2h264enc`/`v4l2h265enc`) |
| Charging bypass UI | — | the SM5714 driver exposes no charge behaviour yet |
| Rotation, ambient light, compass | ✅ | ADSP sensors through hexagonrpcd + libssc + patched iio-sensor-proxy (from the S9 Ultra port); HexagonFS tree generated from the tablet's own vendor/dsp. Screen rotates in GNOME |
| Vulkan | ✅ | Turnip Adreno 740, Mesa 25.2.8, Vulkan 1.4. No Vulkan Video (Turnip implements none) |
| Fingerprint | — | |
| Suspend / wake | ✅ | s2idle; power key wakes instantly, double tap to wake in under 1 s. Live on the tablet, in the next image (the double-tap driver fix needs the next kernel) |
| Power key | ✅ | press and release: suspend · hold: Restart / Power Off menu |
| On-screen keyboard | ✅ | opens on tapping a text field in GTK apps, Chromium and Firefox; not in XWayland (X11) apps — see below |

This table is only updated from tests on the real tablet.

## Using the tablet

- **On-screen keyboard by gesture:** swipe up from the bottom edge of the
  screen, starting near the bottom-left corner. This opens GNOME's keyboard
  anywhere, including in apps where tapping a text field does not bring it up
  (XWayland/X11 apps, Wine).
- **Power key:** press and release to suspend, press again to wake; hold it
  for about a second for the Restart / Power Off menu.
- **Double tap to wake:** on by default; toggle it in the *gnome-gts9wifi*
  extension's settings (Extensions app).
- Electron apps (VS Code, Discord, …) open the keyboard only when started on
  Wayland with `--ozone-platform=wayland --enable-wayland-ime`.

## Documentation

- [INSTALL.md](docs/gts9wifi/INSTALL.md) — installing on microSD and first boot
- [DUALBOOT.md](docs/gts9wifi/DUALBOOT.md) — how Android ↔ Ubuntu switching works, and how to recover
- [BUILDING.md](docs/gts9wifi/BUILDING.md) — building every image from source
- [KNOWN-ISSUES.md](docs/gts9wifi/KNOWN-ISSUES.md) — open issues and the Fedora port's issues this port targets
- [PORTING-LOG.md](docs/gts9wifi/PORTING-LOG.md) — what was done, in order, including mistakes
- Release notes: [RELEASE-NOTES-v0.2.0-alpha1.md](docs/gts9wifi/RELEASE-NOTES-v0.2.0-alpha1.md)

## Safety

This writes to the boot partitions of your tablet. Read [DUALBOOT.md](docs/gts9wifi/DUALBOOT.md)
before installing. In particular:

- never write anything to `/dev/block/sda` or any other whole UFS disk — on this
  tablet `sda` is the internal storage, **the microSD card is `/dev/block/mmcblk1`**
- the install never writes `vbmeta`, the bootloader, `efs`, `modem` or `persist`
- back up `boot`, `init_boot`, `vendor_boot`, `dtbo` (and `efs`, `sec_efs`,
  `modem`) before the first switch

No warranty. You can lose data or need to reflash your tablet.

## Layout of the gts9wifi port

The gts9wifi-specific parts live next to the inherited S9 Ultra tooling:

| Path | Contents |
|---|---|
| `scripts/build-gts9wifi-*.sh` | kernel, rootfs, boot bundle and microSD image builders |
| `kernel/config/config-gts9wifi-ubuntu.fragment` | Ubuntu userspace kernel options |
| `configs/gts9wifi/` | vendor_boot cmdline and bootconfig |
| `dualboot/` | `to-ubuntu.sh` (Android side), `ubuntu-to-android` (Ubuntu side) |
| `docs/gts9wifi/` | this documentation |

Everything else is the S9 Ultra port as forked (its original README: [docs/upstream-s9-ultra-README.md](docs/upstream-s9-ultra-README.md)); it is reused or adapted step by step.

## License

MIT by default, like both upstream projects ([LICENSE](LICENSE)); per-file
SPDX headers take precedence. Kernel code and patches are GPL-2.0-only, the
device tree is BSD-3-Clause.

Proprietary Samsung/Qualcomm firmware is **not** stored in Git. The build stages
it from the owner's tablet and checks its sha256 (see [BUILDING.md](docs/gts9wifi/BUILDING.md)).

This port is developed with the help of AI agents (Hermes, Claude Code). Every
component is marked working only after it has been tested on the tablet.
