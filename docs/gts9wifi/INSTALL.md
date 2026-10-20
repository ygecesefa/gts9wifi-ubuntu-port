# Installing Ubuntu on the gts9wifi (microSD)

> Alpha. Read [DUALBOOT.md](DUALBOOT.md) before starting.

Everything is done by one zip, `ubuntu-gts9wifi-<version>-installer.zip`
(the only release asset you need), from recovery or from the Magisk app. The
steps are in the [README](../../README.md#install); this page adds the
details.

## You need

- Galaxy Tab S9 Wi-Fi **SM-X710** (`gts9wifi`) with an **unlocked bootloader**
- a microSD card, 16 GB or larger (it is erased). Not a card adopted as
  internal storage: the installer refuses those.
- one of:
  - a custom recovery (TWRP or LineageOS recovery) and a PC with `adb`, or
  - Magisk on Android (28+ for the action button) and about 5 GB free
    internal storage (the Magisk app copies the 1.7 GB zip, and the installer
    stages the image next to it)

Check the download: `sha256sum -c ubuntu-gts9wifi-<version>-installer.zip.sha256`

## Before the first install

Optional but recommended: a full copy of the device-unique partitions on your
PC (*Backups to take before the first install* in [DUALBOOT.md](DUALBOOT.md)).
The installer itself backs up the four boot partitions it overwrites, to the
card (`android-restore.zip`).

Test the way back once while Android still works: recovery → *Advanced →
Enter fastboot*, `fastboot devices` on the PC, `fastboot reboot`.

## From recovery

1. Insert the card. *Volume Up + Power* → recovery.
2. LineageOS recovery: *Apply update → Apply from ADB*. TWRP: *Advanced → ADB
   Sideload*.
3. PC: `adb sideload ubuntu-gts9wifi-<version>-installer.zip`
4. Answer the erase question with **Volume Up**; reboot when it says DONE.

Do not install the zip from the microSD itself: the card is erased during
the install. TWRP's sideload screen may show no log; the zip still runs (adb
on the PC shows the progress).

For the fingerprint reader, afterwards in Android: install the same zip from
the Magisk app once and answer **keep** (see below).

## From the Magisk app

1. Insert the card. Magisk → *Modules* → *Install from storage* → the zip.
2. Answer the questions with the volume keys: **twice = yes, once = no**
   (either key: Android swaps Volume Up and Down when the tablet is rotated).
3. Reboot: Ubuntu starts.

The installer then also copies the fingerprint calibration to the card and
leaves the Magisk module, the Android → Ubuntu switch, installed.

If the card already holds Ubuntu, the first question is whether to **keep**
it: yes keeps the card as it is and only refreshes the Android backup,
copies the calibration and installs the module (nothing is erased and the
boot partitions are not written). No goes on to the full install.

## First login

User `ubuntu`, password `ubuntu`; change it with `passwd`. The first boot
grows the root partition to the whole card and can take a few minutes.

With USB connected, the tablet also offers a USB network (`usb0`,
`172.16.42.1`). From the PC:

```sh
sudo ip addr add 172.16.42.2/24 dev <usb-interface>
ssh ubuntu@172.16.42.1
```

## Switching, and the way back

See [DUALBOOT.md](DUALBOOT.md): *Switch to Android* in Ubuntu, the Magisk
module in Android, and the two switch zips on the card for recovery.
