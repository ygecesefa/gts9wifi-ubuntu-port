# Recovery installer zip

`scripts/build-gts9wifi-installer-zip.sh VERSION` builds
`ubuntu-gts9wifi-VERSION-installer.zip`. Flash it in recovery (LineageOS
recovery or TWRP), preferably with `adb sideload` from a PC: a zip stored on the
microSD itself would be erased while it is being installed.

## Layout (AnyKernel3-style)

```
META-INF/com/google/android/update-binary   update-binary.sh + gts9w-tool + 16-byte length
META-INF/com/google/android/updater-script  placeholder (no Edify)
gts9wifi/install.sh                         the installer
gts9wifi/restore.sh                         goes into android-restore.zip
gts9wifi/sd.img.zst, boot.img, init_boot.img, vendor_boot.img, dtbo.img
gts9wifi/SHA256SUMS, version.txt
```

`update-binary.sh` is only a loader. It cuts the static arm64 `gts9w-tool`
(`gts9w-tool.c`: volume keys, stored-entry extract, zstd, zip writer) out of
itself into `/tmp`, because a recovery is not guaranteed to have `unzip`, then
runs the script next to it in the zip. The same loader is reused for the
`android-restore.zip` the installer builds on the tablet.

## What install.sh does

1. Checks the device (`gts9wifi`), the microSD (`/dev/block/mmcblk1`, type SD,
   large enough), and the four boot partitions (by-name, `sd[a-f]N`, sizes).
   Stages the payload in `/tmp` and verifies every sha256.
2. Reads this tablet's own `boot`, `init_boot`, `vendor_boot`, `dtbo` and builds
   `android-restore.zip` from them, then reads it back. If the partitions already
   hold an Ubuntu set, it looks for an earlier backup on the card instead (and
   asks before going on without one).
3. Asks: the microSD will be erased (Volume Up = yes, Volume Down or 60 s = no).
4. Writes the Ubuntu image to the card and reads it back.
5. Puts `android-restore.zip` and the unpacked images on `GTS9W_BACK`, the
   card's FAT partition.
6. Only then writes the four Ubuntu boot images and reads them back.

A failure before step 6 leaves the boot partitions untouched. Recovery never
writes Ubuntu's root filesystem, Android's `userdata`, `super` or `vbmeta`.

Ubuntu takes the backup itself: `gts9wifi-import-backup` (every boot, read-only
mount of `GTS9W_BACK`) copies the Android images into the "Switch to Android"
set and, once present, `GTS9W_BACK/fingerprint/{calib,egoptbds}.dat` into the
fingerprint firmware directory.

## Testing without a tablet

`test/setup.sh` and `test/inner.sh` emulate a recovery on any arm64 Linux host:
loop devices with the real partition sizes appear as `/dev/block/by-name/*` and
`/dev/block/mmcblk1` inside a private mount namespace, `/sys/block/mmcblk1`
says `SD`, `getprop` is faked, and a FIFO at `/dev/input/event0` delivers real
`input_event` key releases. Copy both to a scratch directory and run there:

```sh
sudo bash setup.sh                       # fake Android partitions + 9 GiB card
unzip -p ZIP META-INF/com/google/android/update-binary > ub
sudo unshare -m bash inner.sh $PWD/ub ZIP y            # answers: y / n per question
sudo TEST_SH="busybox sh" unshare -m bash inner.sh ...  # TWRP's shell
```

Tested this way (2026-10-20): install over Android, android-restore.zip back to
Android, reinstall over an Ubuntu set (backup rescued from the card), "no"
writes nothing, import of the backup and calibration into Ubuntu.
