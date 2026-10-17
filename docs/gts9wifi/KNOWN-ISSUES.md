# Known issues and targets

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
| S Pen tilt missing | port the tilt handling of the S9 Ultra Wacom driver to WEZ01 |
| Rear camera autofocus missing | the S9 Ultra port's libcamera software autofocus (DW9808 is the same actuator) |
| No charging-bypass UI | expose SM5714/SM5440 bypass, add a toggle |
| SELinux permissive | not applicable: Ubuntu uses AppArmor, enabled |
| `/vendor` not mounted | map `super`'s vendor with dm-linear, read-only |
| Browsers / VLC decode video in software | iris VPU via GStreamer/ffmpeg V4L2 for players; Vulkan Video is not implemented by Mesa Turnip on any Linux |
| Linux 7.2.1–7.2.6 break Wi-Fi | kernel pinned to 7.2.0 |

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
