# Porting log

Newest last. Mistakes are kept on purpose: this log is the recipe.

## 2026-10-14 — Fedora on microSD works

The owner booted the Fedora gts9wifi port from microSD with two-way switch
scripts (`to-fedora.sh`, `astroid-to-android`). Known Fedora issues: S Pen
tilt, rear autofocus, charging-bypass UI, SELinux permissive, `/vendor` not
mounted, software video decode in browsers/VLC, Wi-Fi broken on 7.2.1–7.2.6.

## 2026-10-15 … 2026-10-17 — v0.1.0-alpha1 (Hermes agent), superseded

An AI agent produced a first set of images and a release. Reviewed on
2026-10-17; none of it was booted. Findings:

- **Kernel incomplete.** Only 4 patches were applied; none of the Fedora port's
  out-of-tree X710 drivers (panel, touch, S Pen, charging) were built in. The
  image would have had no display.
- **No device firmware** in the rootfs (ADSP, GPU zap, Wi-Fi IOE/BDF, VPU,
  speaker protection), and no desktop at all (console-only rootfs).
- **Wrong disk, near miss.** `fastboot getvar partition-size:sda` reported
  `0x3B64000000` (≈238 GiB, internal UFS LUN 0). It was misread as "a 15 GB SD
  card", and the image was piped into `dd of=/dev/block/sda`. The command
  failed instantly only because Android's toybox `dd` rejects
  `status=progress`. GPT verified intact afterwards. On this tablet the
  microSD card is `/dev/block/mmcblk1`.
- **vbmeta written unnecessarily** in its install notes; the Fedora scripts
  never write `vbmeta`.
- **TWRP**: a series of repacked images (v3–v7) were broken (unaligned
  ramdisk, changes silently not applied, duplicated signature block); even an
  unmodified control image failed with
  `partition hyp … vbmeta no sign info`, so the cause is the flashing
  procedure, not the fstab flags. TWRP work is paused.

## 2026-10-17 — handover, v0.2.0-alpha1 baseline

- Verified on the tablet (read-only): GPT intact, `sda` = UFS, SD = `mmcblk1`,
  LineageOS 22 with Magisk, A-only partitions.
- Android boot set + `efs`/`sec_efs`/`modem`/`metadata`/`misc`/`vbmeta*`
  backed up (478 MB), sha256-verified at three hops. The Android set is
  identical to the copy the Fedora card kept from 2026-10-14.
- Device firmware (279 entries, 40 MB) staged from the Fedora card before it
  is replaced.
- The Fedora port's `dtbo.img`/`init_boot.img` and the ones built by this
  pipeline's layout are byte-identical, confirming the boot layout.
- Decision: fork the S9 Ultra Ubuntu port as the base; take the X710 kernel
  recipe and device services from the Fedora port; pin Linux 7.2.0.
- Found that the Fedora port's 19 kernel patches are the S9 Ultra port's
  patches (11 of them adapted for the X710) — both ports share an origin.

## 2026-10-18 — first boot: v0.2.0-pre1

- Kernel 7.2.0-gts9wifi (v7.2 + Fedora recipe + Ubuntu fragment) built on the
  Pi in ~2.5 h. Rootfs stage A: Ubuntu 24.04 GNOME, 3.4 GB. Boot bundle:
  `init_boot.img`/`dtbo.img` byte-identical to the Fedora port's.
- Release assets uploaded to GitHub (private pre-release) and pulled to the
  test PC from there: 4 min 40 s instead of hours over Tailscale.
- Writing the card through `adb exec-in … dd` inside Android ran at ~4 MB/s and
  vold kept remounting the card mid-write. Writing it in the PC's microSD reader
  took 7 min and was verified by reading back the sha256. **Write the card in a
  card reader**, not through Android.
- `to-ubuntu.sh` wrote and read back the four boot partitions; the tablet booted
  straight into GDM. Root grew to 14 GB on first boot.
- Working: display, touch, S Pen (with tilt), GPU firmware, Wi-Fi 2.4 GHz,
  audio, battery, ADSP, USB network (172.16.42.1). AppArmor active.
- 5 GHz RX weak → root-caused to the board-data entry (see KNOWN-ISSUES) and
  fixed live on the tablet; fix moved into the rootfs build.
- `gts9wifi-mem-reclaim` found to rewrite the boot partitions every boot;
  disabled. `rmtfs` disabled (no modem).
- Ubuntu → Android verified: the one-tap "Android'e Geç" launcher (no terminal,
  no password, no prompt) restored the four Android images; Android booted and
  its boot partitions read back identical to the backup. Dual boot works in
  both directions.

## 2026-10-18 — live fixes on the running tablet (towards v0.2.0-pre2)

Everything below was done over SSH on the booted Ubuntu, verified on the
tablet, and folded into the build (`device/`, `scripts/build-gts9wifi-rootfs.sh`)
so the next image carries it.

**Access.** Tailscale on the tablet; the build host reaches it directly
(`ssh gts9wifi`), the USB network of the test PC is only needed for Android.

**Dual boot, both directions.** One-tap "Android'e Geç" in the dock (no
terminal, no password, no prompt) and a Termux:Widget `Ubuntu.sh` on Android.
Leftover Fedora switch scripts and images removed from Android (their
`Fedora.sh` would have booted a Fedora that no longer exists).

**Wi-Fi 5 GHz.** RX ~40 dB weak. This unit's WCN6855 reports
`qmi-chip-id=2`; the Fedora fix had put the tuned NTM_TW220 board data only in
the `qmi-chip-id=18` entry. Tuned payload copied into the chip-id=2 entry: a
phone hotspot at 1 m went from −83 dBm to −41…−50 dBm.

**Bluetooth.** The controller came up unconfigured (`DOWN RAW`). The address is
read from `efs:/bluetooth/bt_addr` (mounted `ro,noload`) and set over the mgmt
socket by `gts9wifi-bt-mgmt`, triggered by udev on `hci0`. `btmgmt` was tried
first and dropped: from a service it sometimes ignored its own `--timeout` and
hung. Nothing is written to the boot partitions (the Fedora port patched the
DTB inside `boot`/`vendor_boot` every boot).

**Clock.** No NTP client was installed; `systemd-timesyncd` added. The PMIC RTC
reads 1970 and is not written; timesyncd's saved clock keeps boots sane.

**Android partitions.** ~90 UFS partitions (incl. `efs`, `persist`, encrypted
`userdata`) were offered in the dock; hidden with `UDISKS_IGNORE`.
`/vendor` is now mounted: `gts9wifi-android-parts` parses the liblp metadata
of `super` (system, vendor, product, odm, system_ext, vendor_dlkm,
system_dlkm) and maps `vendor` read-only with dm-linear (ext4 here). The
Fedora units mounted `dsp` and `persist` read-only but without `noload`, which
lets ext4 replay a dirty journal onto the Android partition; all three now use
`noload`. `userdata` decryption was assessed and not pursued: FBE keys are
hardware-wrapped and need Samsung's keymaster/gatekeeper in TrustZone.

**Video.** The iris VPU decodes H.264, HEVC and VP9 (1080p, 300/300 frames,
~0.24 s CPU vs 2.2–3.7 s in software) and encodes H.264/HEVC at ~170–300 fps.
The V4L2 decoders rank primary+1, so GStreamer/Totem use them automatically.
Browsers still decode in software (no VA-API for the VPU). Vulkan works
(Turnip, Mesa 25.2.8); Turnip implements no Vulkan Video.

**Sensors.** Rotation, ambient light and compass work. Packages from the S9
Ultra port (`libssc`, `hexagonrpcd` 0.4.0 with Samsung registry patches,
patched `iio-sensor-proxy`), plus `sscregistrygen`. The HexagonFS tree is
generated on the tablet from its own vendor sensor JSONs and dsp skels. The
sensor PD is started once per boot after the ADSP, pd-mapper and the panel
cold-boot recovery (starting inside that suspend cycle hung the Fedora port);
iio-sensor-proxy waits for the SSC QMI service and is D-Bus activatable.
Verified across cold boots: the screen rotates, no hang, audio unaffected.

**Disabled as unsafe.** `gts9wifi-mem-reclaim` (rewrote the DTB in the boot
partitions every boot), `gts9wifi-bt-provision` (same), `rmtfs` (no modem).

**Still open (live):** cameras in apps + rear autofocus, double-tap wake and
the device-control extension, fingerprint. **Kernel/image:** charging bypass
and limit, DTB carveout reclaim, S9 Ultra SoC patches, image v0.2.0-pre2,
boot-time key choice, TWRP + installer ZIP.

## 2026-10-18 — v0.1.0-alpha1 removed

The superseded v0.1.0-alpha1 (never booted) and its artifacts were removed:
its GitHub release and tag, the `legacy/hermes-v0.1` branch, and the local
build outputs. Its lessons stay in this log. The agent's own session records
were kept untouched.

## 2026-10-18 (night) — cameras

- Built the S9 Ultra port's camera packages unchanged (`build-camera-packages.sh`):
  libcamera 0.7.2 + 7 patches (soft ISP, software autofocus) and the PipeWire
  libcamera SPA. The tuning is selected by sensor name and the X710 sensors bind
  as `hi1337-gts9u`, so `hi1337-gts9u.yaml` applies as is.
- `cam -l` lists the front (`cci@ac16000`) and rear (`cci@ac15000`) cameras.
  The soft ISP first failed with "Could not open any dma-buf provider":
  `/dev/udmabuf` is root:kvm. `70-gts9wifi-camera.rules` hands it to `video`
  (+uaccess). Then both stream at 30 fps (front 3400×2556, rear 4120×3096);
  the rear AF moved the DW9808 from 384 to 288.
- WirePlumber offered 16 raw CAMSS nodes and the VPU next to the two cameras;
  `51-gts9wifi-cameras.lua` disables them and names the cameras
  "Front Camera" / "Rear Camera". GNOME Snapshot showed both.
- Snapshot then hung on the rear camera: it restarts the stream within a
  second, and the X710 HI1337 driver still carried bring-up debugging in
  `start_streaming` (register reads + `msleep(500)`). The overlapping start
  ended in a CCI timeout (`-110` writing 0x0790) and a failed STREAMON.
  `kernel/patches-gts9wifi/0001-…drop-stream-start-debug.patch` removes it
  (the S9 Ultra driver has no such block); the build script applies this
  directory after the Fedora recipe.
- **Mistake:** the fix was deployed as an incremental kernel rebuild (new
  `boot.img`, sha `896d3a97…`) without rebuilding the modules. With
  `CONFIG_DEBUG_INFO_BTF_MODULES=y` and no `MODULE_ALLOW_BTF_MISMATCH`, every
  module built against the old vmlinux is rejected, so `ath11k` (Wi-Fi) did not
  load. Rule from now on: **a new kernel image always ships with the modules
  rebuilt from the same tree**, installed in the rootfs and the initramfs.
  Modules rebuilt; to be installed on the tablet over the USB network.
