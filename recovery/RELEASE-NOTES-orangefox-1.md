# OrangeFox R12.0 for the Galaxy Tab S9 Wi-Fi (SM-X710) — build 1

A custom recovery for **SM-X710 / gts9wifi** that **decrypts `/data`**
on LineageOS 22 (Android 15), keeps the way into fastboot (userspace
fastbootd) and is safe with an Ubuntu microSD card. Built in GitHub Actions
from `recovery/build-orangefox.sh` (commit `cab0240`); every change is a
documented patch in `recovery/` ([README](README.md)).

## File

`OrangeFox-R12.0-gts9wifi-1.img` (109,576,192 bytes)
sha256 `ebb5d65d9d57281e713ae0875e85fed938c903ce75740703266ae08a6cef0385`

## What works

| | |
|---|---|
| Display, touch, Black theme by default | ✅ drawing ~6× faster than a plain build (the panel is rotated in software) |
| `/data` decryption | ✅ automatic at boot, no password asked (FBE v2 + wrapped keys + metadata encryption, Samsung KeyMint, Samsung Weaver through the K250A secure element and the SPU). `/sdcard` readable |
| system, vendor, product, odm, system_ext, microSD | ✅ mounted |
| fastbootd (*Reboot → Fastboot*) | ✅ `fastboot devices` works (Samsung's bootloader has no fastboot of its own) |
| ADB, sideload, installing zips | ✅ (the Ubuntu port's `android-restore.zip` tested) |

## Limits

- **Decryption is tied to the Android it was built for:** LineageOS 22 with
  the 2025-02 security patch (recovery header 15.0.0 / 2025-02). After an
  Android update that raises the patch level, KeyMint may refuse the keys
  until the recovery is rebuilt with the new values (patch 0007). The rest of
  the recovery keeps working.
- Stock One UI: not tested.
- Lock screen PIN / pattern / password: not tested (tested without one).
- The microSD cannot be wiped from *Wipe* on purpose (on an Ubuntu card it
  holds the switch zips). USB-OTG is not listed (the old TWRP pointed it at
  `sda1`, which on this tablet is the internal UFS).
- The secure element's firmware is never updated from recovery (its update
  images are not in the ramdisk), and `persist` is mounted read-only.

## Installing

Needs an unlocked bootloader. **Not with Odin.** Save the current recovery
first. With root in Android (Magisk):

```sh
su -c 'dd if=/dev/block/by-name/recovery of=/sdcard/recovery-backup.img'
su -c 'dd if=/sdcard/Download/OrangeFox-R12.0-gts9wifi-1.img of=/dev/block/by-name/recovery'
```

or from another TWRP: *Install → Install Image → Recovery*. Then boot to
recovery with *Volume Up + Power*. To go back, write the backup the same way;
a recovery never affects Android.

## Credits

OrangeFox Recovery Project and TeamWin (TWRP); rainbowdashh (gts9wifi device
tree and prebuilt kernel); dmXq-twrp-development (SM8550 Samsung tree used as
reference). Vendor binaries come from this tablet's own firmware
(X710XXU4BXHB).
