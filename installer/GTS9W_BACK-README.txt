GTS9W_BACK - Galaxy Tab S9 Wi-Fi (SM-X710) Ubuntu microSD

Two recovery zips switch the tablet between Android and Ubuntu. Flash one in
recovery (TWRP or LineageOS recovery, "Install" or "adb sideload"); each asks
Volume Up = yes / Volume Down = no, then writes only the four boot partitions
(boot, init_boot, vendor_boot, dtbo) and verifies them. No root needed.

  android-restore.zip   -> Android: THIS tablet's own Android boot images,
                        saved by the Ubuntu installer zip before it wrote
                        Ubuntu (whatever Android version it runs); the
                        Magisk module keeps it current after Android updates
  ubuntu-boot.zip       -> Ubuntu: the Ubuntu boot images of this card
  fingerprint/          the fingerprint sensor's calibration for Ubuntu,
                        copied from Android (installer zip from the Magisk
                        app, or the Magisk module)

The same files are used by "Switch to Android" in Ubuntu and by the Magisk
module's "Switch to Ubuntu" in Android.

Do not delete them: they are the way back without a PC. Android's data is
never touched by any of these zips.
