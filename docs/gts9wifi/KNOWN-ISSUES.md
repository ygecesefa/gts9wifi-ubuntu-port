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

## Roadmap

1. **v0.2.0-alpha1** — first boot from microSD (stage A rootfs).
2. **Stage B userspace** — the S9 Ultra port's rebuilt packages adapted to the
   gts9wifi: libcamera with autofocus, `hexagonrpcd`/`libssc`/`iio-sensor-proxy`
   (rotation), mutter, gnome-settings-daemon.
3. **Ultra SoC improvements** — device-independent SM8550 patches, one at a time.
4. **S Pen tilt, charging bypass, `/vendor`**.
5. **TWRP** — a working recovery for the gts9wifi (rainbowdashh V2 and the
   correct flashing procedure), then a **TWRP installer ZIP** that asks where to
   install, based on the S9 Ultra port's `make-twrp-zip.py`,
   `build-ufs-image.sh` and `make-repartition-zip.py`:
   - **microSD** — as today, Android untouched
   - **internal storage, beside Android** — a `linuxroot` partition carved from `userdata`
   - **whole tablet** — Ubuntu on the internal storage only

## Lessons from v0.1.0-alpha1

`v0.1.0-alpha1` (an earlier, AI-driven attempt, never booted) is superseded.
Its problems are documented in [PORTING-LOG.md](PORTING-LOG.md) so they are not
repeated: the X710 drivers were not in its kernel, the device firmware was not
in its rootfs, and its install notes wrote `vbmeta` unnecessarily.
