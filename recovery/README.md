# OrangeFox recovery for the Galaxy Tab S9 Wi-Fi (gts9wifi)

Work in progress. Goal: a recovery that mounts what the existing TWRP V2
does not, keeps the Samsung route into fastboot (userspace fastbootd in
recovery; Samsung's bootloader has none), and is safe with an Ubuntu card.

## Recipe

`build-orangefox.sh` (x86_64 host, ~60 GB) or the *OrangeFox recovery*
workflow in GitHub Actions:

1. OrangeFox **fox_12.1** sources via OrangeFox's sync script (pinned).
2. Device tree **rainbowdashh/android_device_samsung_gts9wifi** at
   `fe92d0f`: the tree of TWRP V2, the recovery known to boot on this
   tablet. Its prebuilt kernel, dtb, dtbo and modules are kept as they are.
3. Our patches, `patches/` (applied with `git am`, each with its reason):

| Patch | What |
|---|---|
| 0001 | fstab: drop *USB-OTG* on `/dev/block/sda1` (here sda is the **internal UFS**: wiping it would format an internal partition); no *Wipe* for the microSD (on an Ubuntu card it holds `GTS9W_BACK`, the switch zips); drop `/sdcard` on the nonexistent `mmcblk0p1`; `/data` with LineageOS 22's real flags (FBE v2, wrapped keys, metadata encryption) instead of the old full-disk `encryptable=footer` |
| 0002 | BoardConfig: fastbootd stated explicitly, lptools/lpdump, repacktools, resetprop; OrangeFox screen geometry for the rotated 2560×1600 panel |
| 0003 | microSD not wipeable from the Wipe list: TWRP enables that for `/external_sd` in code, so `twrp.flags` says `wipeingui=0` |
| 0004 | `/data` decryption: KeyMint, qseecomd, gatekeeper and their libraries from **this tablet's own vendor** (X710XXU4BXHB, so they match its TrustZone apps), the tablet's vintf manifest, an init file that starts KeyMint, TWRP FBE + metadata decryption with Qualcomm wrapped keys, `device/qcom/twrp-common` |

The vendor binaries in 0004 are Samsung/Qualcomm files, carried as other
TWRP trees for this tablet carry them (rainbowdashh, dmXq-twrp-development).

## Status

| | |
|---|---|
| Boots, touch, display | ✅ (first build, 0001–0002); drawing is slow: the panel is rotated in software. Default theme: Black (build script) |
| system, vendor, product, odm, system_ext, microSD | ✅ mounted; 0 errors in `recovery.log` |
| fastbootd (*Reboot → Fastboot*) | to be tested |
| `/data` | V2 and the first build: not decrypted (`Invalid argument`); 0004 adds decryption — to be tested |

## Flashing (test)

Never with Odin (it rejects images it cannot verify). From Android with
root, after saving the current recovery:

```sh
su -c 'dd if=/dev/block/by-name/recovery of=/sdcard/recovery-backup.img'
su -c 'dd if=/sdcard/OrangeFox.img of=/dev/block/by-name/recovery'
```

A recovery that does not start never affects Android: write the backup
back the same way.
