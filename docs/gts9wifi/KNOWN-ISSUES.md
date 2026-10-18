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
| 4 | Cameras in apps + **rear autofocus** — **done**: both cameras stream through libcamera/PipeWire (GPU soft ISP, full field of view), rear continuous AF works, GNOME Snapshot takes pictures. The photo freeze was the CCI I2C controller locking up when a quick stop/start kept it (and the camera GDSC) powered while the sensor rail dropped; fixed by `71-gts9wifi-cci-autosuspend.rules` (immediate runtime suspend). Kernel patches 0002–0004 add retries and diagnostics. Rare separate issue: GPU fault (GMU OOB timeout) in the soft ISP when switching cameras. Stress test: `scripts/diagnostics/camstress.cpp` | Fedora 4/4b/11 | live (packages) + kernel fix + udev |
| 5 | Double-tap to wake + device-control GNOME extension (port to GNOME 46) — **in progress**. Done: extension enabled on GNOME 46 (`gnome-gts9wifi@tabs9linux`), short power press suspends. Wake was 3–4 s: ath11k powered the WCN6855 down and rebooted its firmware on every resume (1.55 s; patch 0005 uses the WoW path, live as a module), and the double-tap IRQ ran before i2c resumed, ~130 i2c errors per wake were flushed to the 115200-baud `ttyMSM0` console before tasks thawed (0.9 s; `60-gts9wifi-console.conf` keeps them off the console, patch 0006 fixes the driver — built-in, applied with item 11). Kernel resume is now ~0.13 s. Power key like Android: `gts9wifi-power-key` (user service) suspends on a short press (on release) and opens GNOME's power-off dialog (Restart / Power Off) when held 0.7 s; the press that woke the tablet is dropped (BOOTTIME−MONOTONIC grew and the wake IRQ is the power key's). GNOME's own handling is off: `power-button-action='nothing'`, and `/etc/machine-info` sets `CHASSIS=convertible`, since on a "tablet" chassis gsd-media-keys suspends on key-down regardless. While GNOME handled the key it blanked the screen on key-down, the lock-screen animation then never finished and gnome-shell's sleep delay lock ran into logind's 5 s timeout on every suspend; the stall came back after a reboot whenever the screen went dark first; `gts9wifi-power-key` now locks the screen itself, waits for the lock (≤ 2 s, ~0.9 s measured) and only then suspends, so gnome-shell holds no delay lock. The floating keyboard button's extension also stays enabled on the lock screen (session-modes) and just hides the button, since destroying it during the lock kept the lock from completing. The Extensions app (`gnome-shell-extension-prefs`) is now in the image | Fedora 14 | live (+ kernel 0006) |
| 5b | ~~On-screen keyboard in apps~~ — **done**: `ibus` was missing (only a Recommends of ubuntu-desktop-minimal), so the keyboard opened in the shell search only. Chromium also needs text-input-v3 (`/etc/skel/.chromium-browser.init`), and mutter 46 shows the keyboard only on a second `enable` while focused, which GTK sends on every tap and Chromium never does; the extension's `oskFocus.js` requests it on a touch focus-in. XWayland/Wine apps never ask for it on tap: the extension's floating, draggable keyboard button (on by default, settings switch) or the bottom-edge swipe opens it, and it types into them; Electron apps need `--ozone-platform=wayland --enable-wayland-ime` | owner | live |
| 6 | ~~`/vendor`~~ — **done**: `gts9wifi-android-parts` parses super's liblp metadata, maps `vendor` read-only with dm-linear; mounted `ro,noload`. Also fixed: `dsp` and `persist` were mounted without `noload`, so a dirty journal would have been replayed onto the Android partitions | Fedora open | live |
| 7 | ~~File capabilities, early-boot clock, ADSP late-start safety~~ — **done**. Capabilities: intact (ping, snap-confine, gst-ptp-helper as their postinsts set them; the SD image is written with `rsync -aHAX`). Clock: the PMIC RTC cannot be set and reads 1970, so the clock started from the last shutdown until NTP; `gts9wifi-rtc-offset` saves wall clock − RTC after every NTP sync (`gts9wifi-rtc-save.path`) and sets RTC + offset first thing at boot (`gts9wifi-rtc-restore.service`, before journald), as Android's time_daemon does. This also fixed the boot log: with a 1970 clock journald's flush saw time jump backwards, rotated, and the 64 MB cap vacuumed the 1970-dated file first, so the first ~50 s of every boot were lost. Verified on reboot: clock correct at 9 s without network, journal from 0 s. ADSP: started late by `gts9wifi-adsp-boot` (firmware is on the rootfs) on every boot, ordered after the panel recovery; a drop-in now blocks suspend from the start request until `/dev/fastrpc-adsp` exists, since a suspend overlapping the start froze the SoC (Fedora) | Fedora open | live |
| 7b | **Waydroid** (Android apps in Ubuntu): binder/netfilter already in the kernel; install Waydroid 1.6 + LineageOS 20 GAPPS image as the S9 Ultra port does (`docs/waydroid.md`) | owner | live |
| 8 | Under-display fingerprint (EL721) — **in progress; secure start works (`SECURE_READY`, 2026-10-19)**, past the Fedora port's `KEYMASTER_NOT_CONFIGURED`: SPU up and "SP Apps were loaded successfully", Keymaster negotiated/bound/configured, HwVault credentials restored from the K250A. Stack from the S9 Ultra port (`fingerprint/`, PROVENANCE.md) plus X710 fixes: the eight fingerprint/SPU modules were never built (literal `\t` in prepare.sh); this vendor's spdaemon waits for a binder context manager (`gts9wifi-binder-ctxmgr`; vndservicemanager aborts without SELinux); libspcom shares its NVM buffers through mem_buf, which mainline lacks (`libvmmem_shim`: the sp-hlos heap already does the SCM assignment); sec_nvm needs `secnvm/` to exist; Samsung's daemons run in a private mount namespace so their NVM is Ubuntu-local, never Android's persist. Runtime and TAs are copied from the tablet's own partitions (`gts9wifi-fingerprint-runtime`). Boot units now enabled (`gts9wifi-fingerprint-runtime`, `-secure`, fprintd drop-in with exactly /dev/tee0, /dev/k250a, /dev/esfp0); fprintd lists "EgisTec EL721 UDFPS" through the adapted libfprint; PAM fingerprint step kept disabled until enrolment works. To do: calib.dat/egoptbds.dat from Android, enrolment test, FTS1BA90A FOD events, overlay for the 11" panel | Fedora 15 | live + kernel (FOD) |
| 9 | ~~Charging bypass + 80 % limit~~ — **done**, on the tablet since 2026-10-19 (verified: limit at 87 % → Not charging, 0 mA; bypass → Not charging; both resume): patch 0007 adds the standard `charge_control_{start,end}_threshold` and `charge_behaviour` (auto / inhibit-charge) to the SM5714 driver, pausing through Q4 as the thermal stop does and handing the pack back from the SM5440; two switches in the extension's settings (`charge-limit` 80/75 %, `charge-bypass`) | Fedora 13 | **kernel** + live UI |
| 10 | ~~Reclaim dead carveouts~~ — **done** (MemTotal 10.32 → 11.11 GiB on the tablet): patch 0008 deletes 30 reserved-memory nodes (811.8 MiB; 62 → 32, the set Fedora's runtime tool removed and verified on hardware) and the two disabled remoteprocs' memory-region properties; spu-tz-shared (fingerprint), video and GPU micro-code regions stay | this port | **kernel** |
| 11 | Ultra SoC patches — 63 tested against the tree: 13 already present, 28 apply, 20 conflict. Taken (0009–0014, provenance in each): q6v5 handover IRQ mask (measured storm, ~5 IRQ/s), fastrpc publish after session init, a6xx GMU fault wait bound, DPU resource reassignment, DRM bridge OOB hotplug, GENI I2C cancel-before-abort. Left out: CPU boost (no boost here), UFS PHY (no UFS errors), PCIe0 mux (X910 boot chain only), Goodix/Gunyah/HI847/sec-log (hardware not on the X710); qcomtee/glink ones wait for #8. The four `*-gts9wifi` patches in the Ultra clone are untracked Hermes additions and were not used. On the tablet: handover IRQ 1 (was ~5/s); the ready IRQ storms the same way, fixed by pending patch 0015 (next kernel) | S9 Ultra / this port | **kernel** |
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
