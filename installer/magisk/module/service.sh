#!/system/bin/sh
# Late in every Android boot: keep the card's Android backup equal to what
# this Android boots from (after an Android or Magisk update the boot images
# change, and an old android-restore.zip would bring the old ones back), and
# put the fingerprint calibration on the card.  See gts9w.sh.
MODDIR=${0%/*}
until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 5; done
sleep 60
{
	date
	sh $MODDIR/gts9w.sh backup
	sh $MODDIR/gts9w.sh fingerprint
} > $MODDIR/service.log 2>&1
