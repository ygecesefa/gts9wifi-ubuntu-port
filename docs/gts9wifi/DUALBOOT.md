# Dual boot: Android ↔ Ubuntu on the gts9wifi

## How it works

Samsung's bootloader (ABL) always boots whatever is in four partitions on the
internal UFS storage. There is no boot menu. Switching systems therefore means
**writing a different set of images to those four partitions and rebooting**:

| Partition | Size | Android set | Ubuntu set |
|---|---|---|---|
| `boot` | 96 MiB | Android kernel | Linux 7.2 kernel + appended gts9wifi DTB |
| `init_boot` | 8 MiB | Android generic ramdisk (Magisk-patched if rooted) | empty ramdisk |
| `vendor_boot` | 96 MiB | Android vendor ramdisk | Ubuntu initramfs + DTB + kernel cmdline |
| `dtbo` | 16 MiB | Android DT overlays | zero page (forces ABL's appended-DTB path) |

Nothing else is written: not `vbmeta`, not the bootloader, not `super`, not
`userdata`. Android's data stays exactly as it is. Ubuntu lives entirely on the
microSD card (`GTS9W_BOOT` + `GTS9W_ROOT`).

The Ubuntu kernel finds its root filesystem by label (`root=LABEL=GTS9W_ROOT`),
so the card must be inserted whenever the Ubuntu set is installed.

This is the same mechanism the Fedora gts9wifi port validated on this tablet;
the scripts here are adapted from its `to-fedora.sh` and `astroid-to-android`.

## Block devices on this tablet — read this first

| Device | What it is |
|---|---|
| `/dev/block/sda` … `sdf` | **internal UFS storage** (LUNs). `sda` holds `boot`, `efs`, `userdata`… |
| `/dev/block/mmcblk1` | **the microSD card** |
| `/dev/block/by-name/<name>` | the only correct way to address a boot partition |

Never `dd` to `/dev/block/sda` or any `sdX` disk. A 15 GB card and a 238 GB
UFS LUN are easy to tell apart: check `cat /proc/partitions` before writing.

## Android → Ubuntu

From a root shell on Android (Magisk `su`), with the Ubuntu boot images in
`/sdcard/Ubuntu/images/` (i.e. `/data/media/0/Ubuntu/images/`):

```sh
su -c sh /data/local/tmp/to-ubuntu.sh
```

The script checks that the device is a `gts9wifi`, that every image and every
partition has the expected size, that every image matches `SHA256SUMS`, asks
you to type `UBUNTU`, writes the four images, reads them back to verify, and
reboots.

## Ubuntu → Android

In Ubuntu, open **Android'e Geç** (Switch to Android) from the app grid, or:

```sh
sudo ubuntu-to-android
```

It restores the four Android images saved in
`/usr/share/gts9wifi-dualboot/android/` (taken from your own tablet before the
first install), verifies them against `SHA256SUMS`, and reboots.

## If Ubuntu does not boot

The kernel reboots 10 s after a panic, and ABL will keep booting the Ubuntu set.
Your Android data is safe; you only need to put the Android boot set back.

1. **Recovery (preferred).** Hold *Volume Up + Power* to enter the recovery
   partition (it is never touched by this port). If the recovery offers an
   `adb` root shell, restore from the backup you pushed earlier:
   ```sh
   adb push boot.img init_boot.img vendor_boot.img dtbo.img /tmp/
   adb shell 'for p in boot init_boot vendor_boot dtbo; do dd if=/tmp/$p.img of=/dev/block/by-name/$p bs=4M; done; sync'
   adb reboot
   ```
2. **Download mode + Odin.** Hold *Volume Down + Power* (with USB connected)
   to enter Download mode and flash your backed-up Android boot set as an AP
   tar (`boot.img`, `init_boot.img`, `vendor_boot.img`, `dtbo.img`).

Test path 1 **before** the first Ubuntu install, while Android still works.

## Backups to take before the first install

| Partition | Why |
|---|---|
| `boot`, `init_boot`, `vendor_boot`, `dtbo` | needed to switch back to Android |
| `vbmeta`, `vbmeta_system` | not written by this port; kept in case |
| `efs`, `sec_efs`, `modem`, `metadata`, `misc` | device-unique data; irreplaceable |

```sh
su -c 'mkdir -p /data/local/tmp/backup && for p in boot init_boot vendor_boot dtbo vbmeta vbmeta_system efs sec_efs metadata misc modem; do dd if=/dev/block/by-name/$p of=/data/local/tmp/backup/$p.img; done; cd /data/local/tmp/backup && sha256sum *.img > SHA256SUMS'
adb pull /data/local/tmp/backup .
sha256sum -c backup/SHA256SUMS
```

Keep these off the tablet. `efs` contains your device's unique identifiers:
never publish it.
