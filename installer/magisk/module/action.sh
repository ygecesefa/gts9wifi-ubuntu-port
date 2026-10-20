#!/system/bin/sh
# Magisk's action button (Magisk 28+): one tap to Ubuntu.  Checks first,
# refreshes the Android backup on the card, writes and verifies the Ubuntu
# boot images, then reboots; on any failure nothing is rebooted.
MODDIR=${0%/*}
sh $MODDIR/gts9w.sh ubuntu
