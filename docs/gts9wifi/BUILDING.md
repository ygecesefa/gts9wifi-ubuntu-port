# Building the gts9wifi images

Everything is built natively on an **arm64 Linux host** (developed on a
Raspberry Pi running Debian; no emulation). The steps below produce the
exact assets published in Releases.

## Host packages

```sh
sudo apt install git make clang lld llvm bc flex bison libssl-dev libelf-dev \
    python3 cpio lz4 zstd mmdebstrap rsync e2fsprogs fdisk dosfstools
```

## Sources

Place the inputs next to this repository (the scripts default to its parent
directory; override with `GTS9WIFI_ROOT`):

```sh
git clone https://github.com/nacht20-de/gts9wifi-fedora-linux fedora-ref
git clone --depth 1 --branch v7.2 \
    https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git build/linux-mainline
```

The kernel build checks that `v7.2` resolves to
`8d3ae59288f1e7d58d76558a6ee96d533bc5019f`.

## Device firmware

Proprietary firmware is not in Git. Stage it from your own tablet as
`backups/firmware/firmware-gts9wifi-from-fedora-sd.tar.gz` (a tarball rooted at
`/usr/lib/firmware`) containing:

```
qcom/sm8550/        ADSP, audio topology (Samsung-Galaxy-Tab-S9-tplg.bin), sensor JSON
qcom/vpu/           iris VPU firmware (vpu30_4v.mbn)
qcom/a740_sqe.fw  qcom/gmu_gen70200.bin  qcom/a740_zap.{mdt,b00,b01,b02}
ath11k/WCN6855/     IOE amss.bin / m3.bin and board-2.bin
qca/                Samsung WCN6855 Bluetooth NVM / rampatch
cirrus/  cs35l45-dsp1-spk-prot-calib.bin   CS35L45 speaker protection
regulatory.db  regulatory.db.p7s
```

alpha1 was built from tarball sha256
`05a60fa7d0686a6a982a5471765434468cd24f92cfcd00aafaaba2eaac86462d`.

You also need your own Android boot-set backup in `backups/android-<date>/`
(see [DUALBOOT.md](DUALBOOT.md)); it is embedded in the rootfs for the
Ubuntu → Android switch.

## Build

```sh
# 1. kernel: v7.2 + Fedora gts9wifi recipe + Ubuntu fragment   (hours on a Pi)
bash scripts/build-gts9wifi-kernel.sh

# 2. Ubuntu 24.04 GNOME rootfs (stage A), modules, firmware, initramfs
sudo GTS9WIFI_PW='<test password>' bash scripts/build-gts9wifi-rootfs.sh

# 3. Android boot header v4 images: boot, init_boot, vendor_boot, dtbo
bash scripts/build-gts9wifi-bundle.sh

# 4. microSD image (+ .zst and SHA256SUMS)
sudo bash scripts/build-gts9wifi-sd-image.sh
```

Outputs:

| Step | Output |
|---|---|
| kernel | `build/gts9wifi-kernel/out/{Image.gz,sm8550-samsung-gts9wifi.dtb,config,kernel.release,modules-root/}` |
| rootfs | `build/gts9wifi-rootfs/` |
| bundle | `build/gts9wifi-bundle/{boot,init_boot,vendor_boot,dtbo}.img`, `SHA256SUMS` |
| SD image | `build/gts9wifi-sd.img`, `.zst`, `.SHA256SUMS` |

None of these scripts write to a tablet or to any real block device.

## What each step does

**Kernel.** Exports a pristine tree from the `v7.2` tag, runs the Fedora
port's `kernel/prepare.sh` (its 19 patches, the out-of-tree X710 drivers —
ANA38407 panel, FTS1BA90A touch, WEZ01 S Pen, SM5714/SM5440 charging, PS5169,
HI1337/DW9808 camera, EL721, K250A, SPU — and the board DTS), merges
`kernel/config/config-gts9wifi-ubuntu.fragment` (AppArmor, squashfs/snap,
overlayfs, netfilter), builds, and refuses to finish if any X710 driver is
missing from the result.

**Rootfs.** `mmdebstrap` of noble with the S9 Ultra port's GNOME package set
(Turkish locale and keyboard by default, `GTS9WIFI_LOCALE`/`GTS9WIFI_KEYMAP`
to change), then: kernel modules, device firmware, an initramfs-tools hook
that puts the GPU firmware into the initramfs, the Fedora port's X710 services
(USB network, panel cold-boot recovery, rootfs growth, Wi-Fi recovery, DSP and
firmware mounts, ALSA UCM), the Ubuntu → Android switch, and a test user.
`persist` is mounted read-only in alpha builds.

**Bundle.** The layout the Fedora port validated: kernel with appended DTB in
`boot`, empty `init_boot`, full LZ4-legacy initramfs + DTB + cmdline in
`vendor_boot`, zero-page `dtbo`. `vbmeta` is not produced.

**SD image.** MBR, 512-byte sectors, `GTS9W_BOOT` (512 MiB ext4) and
`GTS9W_ROOT` (ext4, sized to the content + 3 GiB; grown on first boot).
