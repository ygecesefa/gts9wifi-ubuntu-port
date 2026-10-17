# Installing Ubuntu on the gts9wifi (microSD)

> Alpha. Read [DUALBOOT.md](DUALBOOT.md) completely before starting.

## You need

- Galaxy Tab S9 Wi-Fi **SM-X710** (`gts9wifi`) with an **unlocked bootloader**
  and **root** (Magisk) on Android
- a microSD card, 16 GB or larger (its contents will be erased)
- a Linux PC with `adb`, `zstd` and `sha256sum`
- the release assets: `ubuntu-gts9wifi-<version>-sd.img.zst`,
  `boot.img`, `init_boot.img`, `vendor_boot.img`, `dtbo.img`, `SHA256SUMS`,
  `to-ubuntu.sh`

Check the downloads:

```sh
sha256sum -c SHA256SUMS
```

## 1. Back up the Android boot set

Follow *Backups to take before the first install* in [DUALBOOT.md](DUALBOOT.md).
Do not continue without a verified copy of `boot`, `init_boot`,
`vendor_boot` and `dtbo` on your PC.

## 2. Write the microSD card

### From the PC (card in a card reader)

```sh
lsblk -o NAME,SIZE,MODEL,TRAN      # identify the card — e.g. /dev/sdX, ~15 GB, usb
zstd -dc ubuntu-gts9wifi-<version>-sd.img.zst | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
```

### Or with the card inside the tablet (Android, root)

First unmount it in Android (*Settings → Storage → SD card → Unmount*), then
confirm it is `mmcblk1` and roughly the size of your card:

```sh
adb shell su -c 'cat /proc/partitions' | grep -E 'mmcblk1$|sda$'
zstd -dc ubuntu-gts9wifi-<version>-sd.img.zst | adb exec-in su -c 'dd of=/dev/block/mmcblk1 bs=4M'
adb shell su -c 'sync; blkid /dev/block/mmcblk1p1 /dev/block/mmcblk1p2'
```

You must see the labels `GTS9W_BOOT` and `GTS9W_ROOT`. **Never** use `sda` here:
it is the internal storage.

## 3. Copy the Ubuntu boot images to Android

```sh
adb shell mkdir -p /sdcard/Ubuntu/images
adb push boot.img init_boot.img vendor_boot.img dtbo.img SHA256SUMS /sdcard/Ubuntu/images/
adb push to-ubuntu.sh /data/local/tmp/
```

## 4. Switch to Ubuntu

```sh
adb shell
su
sh /data/local/tmp/to-ubuntu.sh       # type UBUNTU when asked
```

The tablet reboots into Ubuntu. The first boot expands the root partition to
the whole card and can take a few minutes.

## 5. First login

Alpha images ship a test account: user `ubuntu`, password given in the release
notes. You are asked to change it on first login.

With USB connected, the tablet also offers a USB network (`usb0`,
`172.16.42.1`). From the PC:

```sh
sudo ip addr add 172.16.42.2/24 dev <usb-interface>
ssh ubuntu@172.16.42.1
```

## 6. Back to Android

Run **Android'e Geç** from the app grid, or `sudo ubuntu-to-android`.
See [DUALBOOT.md](DUALBOOT.md) for the recovery paths if Ubuntu does not boot.
