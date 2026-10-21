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

## The switch zips (GTS9W_BACK)

Everything a switch needs is on the microSD's FAT partition `GTS9W_BACK`
(Android shows it as the SD card's top folder; Ubuntu hides it):

| File | What |
|---|---|
| `android-restore.zip` | this tablet's own Android boot set, read from its partitions by the installer zip (any Android version, Magisk patches included) |
| `ubuntu-boot.zip` | the Ubuntu boot set of the image on this card, zipped on the tablet by the installer |
| `fingerprint/` | `calib.dat`, `egoptbds.dat`, `SHA256SUMS`: the sensor calibration, copied from Android |

Both zips are recovery zips (same loader as the installer): flash one in TWRP
or LineageOS recovery, answer Volume Up, and it writes and verifies the four
partitions. No root, no Android version dependence: this is the safe way to
switch whatever state either system is in. They are made on the tablet and
never published, since the Android images must be the user's own.

## Android → Ubuntu

**Magisk module** (installed by the installer zip from the Magisk app, or by
installing it again from Magisk and keeping the card):

- **Magisk** (28+): *Modules* → the Ubuntu module's **Action** (run)
  button. Magisk has no WebUI of its own.
- **KernelSU / APatch:** open the module's **WebUI** → *Switch to Ubuntu*
  (also shows the card and backup status).
- Both run `gts9w.sh ubuntu`: first `backup` (rebuild `android-restore.zip`
  if this Android's boot images changed since it was made), then
  `to-ubuntu.sh --yes`, which checks every image of `ubuntu-boot.zip`, copies
  the fingerprint calibration to the card, writes, reads back and reboots.
- At every Android boot `service.sh` runs the same `backup` and copies the
  calibration, so the card always holds the Android set this Android boots
  with (log: `/data/adb/modules/gts9wifi-ubuntu/service.log`).

**Without the module**, from a root shell: `su -c sh /data/local/tmp/to-ubuntu.sh`
(asks you to type `UBUNTU`). On a card with `GTS9W_BACK` it only uses that
card's `ubuntu-boot.zip`; older cards fall back to `/sdcard/Ubuntu/images/`.

**Without root:** flash `GTS9W_BACK/ubuntu-boot.zip` in recovery.

The fingerprint calibration (`calib.dat`, `egoptbds.dat` from Android's
`/data/vendor/biometrics/meta`) is unique to each tablet and exists only in
Android's encrypted `/data`, so it is never part of the image and no recovery
can read it. Ubuntu's `gts9wifi-import-backup` installs it from
`GTS9W_BACK/fingerprint/` (sha256 checked, 0600 root) at boot, and stops
running once both files are in place. Android mounts `GTS9W_BACK` as SD-card
storage, so apps with storage access can read the calibration (it holds no
fingerprints).

## Recovery installer

`ubuntu-gts9wifi-<version>-installer.zip` installs everything from recovery
(LineageOS recovery or TWRP, best via `adb sideload`) or from the Magisk app.
Details: [installer/README.md](../../installer/README.md).

## Ubuntu → Android

In Ubuntu, open **Switch to Android** from the dock or app grid, or:

```sh
sudo ubuntu-to-android
```

It mounts `GTS9W_BACK` read-only, takes the four images from
`android-restore.zip` (older cards: `GTS9W_BACK/android/`, or the set in
`/usr/share/gts9wifi-dualboot/android/`), verifies them against `SHA256SUMS`,
writes, reads back, and reboots. Without Ubuntu: flash
`GTS9W_BACK/android-restore.zip` in recovery.

## If Ubuntu does not boot

The kernel reboots 10 s after a panic, and ABL will keep booting the Ubuntu set.
Your Android data is safe; you only need to put the Android boot set back.

1. **Recovery → fastbootd (preferred).** Hold *Volume Up + Power* to enter the
   recovery partition (never touched by this port; LineageOS recovery on the
   reference tablet), choose *Advanced → Enter fastboot*, then from the PC:
   ```sh
   fastboot devices                     # must show the tablet in fastbootd
   for p in boot init_boot vendor_boot dtbo; do fastboot flash $p $p.img; done
   fastboot reboot
   ```
2. **Recovery → adb shell.** If the recovery offers a root `adb` shell
   (*Advanced → Enable ADB*):
   ```sh
   adb push boot.img init_boot.img vendor_boot.img dtbo.img /tmp/
   adb shell 'for p in boot init_boot vendor_boot dtbo; do dd if=/tmp/$p.img of=/dev/block/by-name/$p bs=4M; done; sync'
   adb reboot
   ```
3. **Download mode + Odin (last resort).** Hold *Volume Down + Power* with USB
   connected and flash the Android boot set as an AP `.tar.md5`. Samsung's
   bootloader may reject images that are not Samsung-signed (custom ROM, Magisk),
   so do not rely on this path alone.

Test path 1 **before** the first Ubuntu install, while Android still works:
boot into recovery, enter fastbootd, check `fastboot devices`, then
`fastboot reboot` without flashing anything.

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
