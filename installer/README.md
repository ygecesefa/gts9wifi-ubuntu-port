# Installer zip, Magisk module and switch zips

`scripts/build-gts9wifi-installer-zip.sh VERSION` builds
`ubuntu-gts9wifi-VERSION-installer.zip`. The same zip is:

- a **recovery zip** (LineageOS recovery or TWRP), preferably sent with
  `adb sideload` from a PC: a zip stored on the microSD itself would be erased
  while it is being installed;
- a **Magisk module** (*Modules → Install from storage*), which installs from
  the running Android and leaves the Android-side switch behind.

On the tablet it makes the two **switch zips** and puts them on the card:
`android-restore.zip` (this tablet's own Android boot images) and
`ubuntu-boot.zip` (the Ubuntu boot images of this card). Neither is ever
published: the Android images must be those of the user's own Android build.

## Layout (AnyKernel3-style, plus a Magisk module)

```
META-INF/com/google/android/update-binary   update-binary.sh + gts9w-tool + 16-byte length
META-INF/com/google/android/updater-script  "#MAGISK" (checked by the Magisk app; no Edify)
module.prop, customize.sh                   Magisk module (magisk/)
module/                                     the module's files (magisk/module/, to-ubuntu.sh)
gts9wifi/install.sh                         the installer
gts9wifi/restore.sh                         goes into both switch zips
gts9wifi/sd.img.zst, boot.img, init_boot.img, vendor_boot.img, dtbo.img
gts9wifi/SHA256SUMS, version.txt
```

`update-binary.sh` is only a loader. In recovery it cuts the static arm64
`gts9w-tool` (`gts9w-tool.c`: volume keys, stored-entry extract, zstd, zip
writer) out of itself into `/tmp`, because a recovery is not guaranteed to
have `unzip`, then runs the script next to it in the zip: `gts9wifi/install.sh`
here, `android/restore.sh` or `ubuntu/restore.sh` in a switch zip. Started by
the Magisk app (Android running), it hands over to Magisk's `install_module`,
which sources `customize.sh`; KernelSU and APatch source `customize.sh`
directly.

## What install.sh does

1. Checks the device (`gts9wifi`), the microSD (`/dev/block/mmcblk1`, type SD,
   large enough, not adopted as internal storage), and the four boot
   partitions (by-name, `sd[a-f]N`, sizes). Stages the payload (`/tmp` in
   recovery, `/data/local/tmp` in Android) and verifies every sha256.
2. Reads this tablet's own `boot`, `init_boot`, `vendor_boot`, `dtbo` and builds
   `android-restore.zip` from them, then reads it back. If the partitions already
   hold an Ubuntu set, it looks for an earlier backup on the card instead (and
   asks before going on without one).
3. Asks: the microSD will be erased. Recovery: Volume Up = yes, Volume Down
   or 60 s = no. Android: a volume key twice = yes, once or 60 s = no
   (`gts9w-tool presses`), because Android swaps the keys with the screen
   rotation: in landscape the key that turns the volume down sends
   `KEY_VOLUMEUP` (measured on the tablet with `getevent`).
4. Writes the Ubuntu image to the card and reads it back.
5. Builds `ubuntu-boot.zip` from its own copy of the Ubuntu boot images and
   puts both switch zips on `GTS9W_BACK`, the card's FAT partition. In Android
   it also copies the fingerprint calibration to `GTS9W_BACK/fingerprint/`.
6. Only then writes the four Ubuntu boot images and reads them back.

A failure before step 6 leaves the boot partitions untouched. Nothing writes
Ubuntu's root filesystem, Android's `userdata`, `super` or `vbmeta`.

In Android, Android's vold has the card's FAT mounted: the installer asks it
to unmount the card (`sm unmount`) before erasing, and after writing waits
until vold has checked and mounted the new FAT before writing to it.

From Magisk, on a card that already holds Ubuntu, the first question is
*keep it?* — yes keeps the card and its Ubuntu and only refreshes
`android-restore.zip`, copies the calibration and installs the module (for
users who installed from recovery first).

## The Magisk module (`magisk/module/`)

Installed as `/data/adb/modules/gts9wifi-ubuntu`:

| File | Does |
|---|---|
| `gts9w.sh` | `status`, `backup`, `fingerprint`, `ubuntu` — all work on `GTS9W_BACK` |
| `action.sh` | Magisk's action button (Magisk 28+): `gts9w.sh ubuntu` |
| `webroot/index.html` | WebUI (KernelSU, APatch, WebUI X): status, Switch to Ubuntu, refresh backup |
| `service.sh` | at every Android boot: `backup` and `fingerprint` (log: `service.log`) |
| `to-ubuntu.sh` | `dualboot/to-ubuntu.sh`, run with `--yes`: writes `ubuntu-boot.zip`'s images, verifies, reboots |
| `bin/gts9w-tool`, `update-binary`, `restore.sh` | to read and build the switch zips |

`gts9w.sh backup` reads the four boot partitions of the running Android and,
when they differ from `android-restore.zip` (after an Android or Magisk
update), rebuilds the zip, checks it and replaces the one on the card. It
refuses when Android has not finished booting or the partitions hold Ubuntu.
`gts9w.sh ubuntu` runs `backup` first, so the zip is current right before
Android's boot images are overwritten.

## Ubuntu side

- *Switch to Android* (`dualboot/ubuntu-to-android`) mounts `GTS9W_BACK`
  read-only and takes the images from `android-restore.zip`.
- `gts9wifi-import-backup` installs `GTS9W_BACK/fingerprint/{calib,egoptbds}.dat`
  into the fingerprint firmware directory; its unit runs at each boot only
  while one of the two is still missing.

## Testing without a tablet

`test/setup.sh` and `test/inner.sh` emulate the tablet on any arm64 Linux host:
loop devices with the real partition sizes appear as `/dev/block/by-name/*` and
`/dev/block/mmcblk1` inside a private mount namespace, `/sys/block/mmcblk1`
says `SD`, `getprop` is faked, and a FIFO at `/dev/input/event0` delivers real
`input_event` key releases. `TEST_MODE=magisk` emulates a running Android
instead: `./data` as `/data` with a stand-in for Magisk's `install_module`
(`test/magisk-util_functions.sh`), a fake calibration, and fake `sm`, `blkid`
and `reboot`. Copy the three files to a scratch directory and run there:

```sh
sudo bash setup.sh                       # fake Android partitions + 9 GiB card
unzip -p ZIP META-INF/com/google/android/update-binary > ub
sudo unshare -m bash inner.sh $PWD/ub ZIP y            # answers: y / n per question
sudo TEST_SH=mksh unshare -m bash inner.sh ...          # LineageOS recovery's shell
sudo TEST_SH="busybox sh" unshare -m bash inner.sh ...  # TWRP's shell
sudo TEST_MODE=magisk TEST_SH="busybox sh" unshare -m bash inner.sh $PWD/ub ZIP y
sudo TEST_MODE=magisk TEST_AFTER=$PWD/after.sh unshare -m bash inner.sh ...  # then run after.sh
```
