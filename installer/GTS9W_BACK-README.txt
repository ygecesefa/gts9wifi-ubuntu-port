GTS9W_BACK - Galaxy Tab S9 Wi-Fi (SM-X710) Ubuntu microSD

Two recovery zips switch the tablet between Android and Ubuntu. Flash one in
recovery (TWRP or LineageOS recovery, "Install" or "adb sideload"); each asks
Volume Up = yes / Volume Down = no, then writes only the four boot partitions
(boot, init_boot, vendor_boot, dtbo) and verifies them. No root needed.

  android-restore.zip   back to Android: THIS tablet's own Android boot
                        images, saved by the Ubuntu installer zip before it
                        wrote Ubuntu
  ubuntu-boot.zip       back to Ubuntu: the Ubuntu boot images of this card
  android/              the Android images and SHA256SUMS, unpacked
  fingerprint/          (after one switch with to-ubuntu.sh from Android)
                        the fingerprint sensor's calibration for Ubuntu

Do not delete them: they are the way back without a PC. Android's data is
never touched by any of these zips.
