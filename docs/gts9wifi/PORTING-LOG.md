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
