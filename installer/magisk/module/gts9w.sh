#!/system/bin/sh
# gts9wifi Magisk module: Android side of the Android <-> Ubuntu switch.
#
#   gts9w.sh status       key=value lines (the WebUI reads them)
#   gts9w.sh backup       keep GTS9W_BACK/android-restore.zip equal to the boot
#                         images this Android runs on (any Android version,
#                         Magisk's own patches included)
#   gts9w.sh fingerprint  copy the sensor calibration to GTS9W_BACK/fingerprint
#   gts9w.sh ubuntu       backup, then to-ubuntu.sh: write the Ubuntu boot
#                         images from GTS9W_BACK/ubuntu-boot.zip, reboot
#
# Everything lives on the microSD's FAT partition GTS9W_BACK, the same
# switch zips a recovery flashes.  Only boot, init_boot, vendor_boot and
# dtbo are ever written (by to-ubuntu.sh); here they are only read.
MODDIR=${0%/*}
TOOL=$MODDIR/bin/gts9w-tool
BB=/dev/block/by-name
W=/data/local/tmp/gts9w-module
BACK=$W/back
FP_SRC=/data/vendor/biometrics/meta

die() { echo "ERROR: $*"; close_back; rm -rf $W/set; exit 1; }
sha() { sha256sum "$1" | cut -d' ' -f1; }
want() { grep " $1\$" "$2" | cut -d' ' -f1; }
size_of() {
	case $1 in
		boot|vendor_boot) echo 100663296 ;;
		init_boot) echo 8388608 ;;
		dtbo) echo 16777216 ;;
	esac
}

# vold usually has the FAT mounted already; a second mount of the same
# partition shares that filesystem.
open_back() {
	grep -q " $BACK " /proc/mounts && return 0
	dev=$(blkid 2>/dev/null | grep 'LABEL="GTS9W_BACK"' | cut -d: -f1)
	case "$dev" in
		/dev/block/mmcblk1p[0-9]*) ;;
		*) return 1 ;;
	esac
	mkdir -p $BACK
	mount -t vfat $dev $BACK
}
close_back() {
	grep -q " $BACK " /proc/mounts && umount $BACK
	rmdir $BACK $W 2>/dev/null
}
# The Ubuntu boot set carries root=LABEL=GTS9W_ROOT in vendor_boot.
parts_are_ubuntu() { head -c 4096 $BB/vendor_boot | grep -a -q GTS9W_ROOT; }
zip_info() { $TOOL extract "$1" "$2/info.txt" $W/info.txt 2>/dev/null && head -n "${3:-1}" $W/info.txt | tail -n 1; }

status() {
	mkdir -p $W
	if [ "$(cat /sys/block/mmcblk1/device/type 2>/dev/null)" != SD ]; then echo card=none; return; fi
	if ! open_back; then echo card=other; return; fi
	echo card=gts9wifi
	parts_are_ubuntu && echo partitions=ubuntu || echo partitions=android
	[ -f $BACK/ubuntu-boot.zip ] && echo "ubuntu=$(zip_info $BACK/ubuntu-boot.zip ubuntu)"
	if [ -f $BACK/android-restore.zip ]; then
		echo "android=$(zip_info $BACK/android-restore.zip android)"
		echo "android_build=$(zip_info $BACK/android-restore.zip android 4 | sed 's/.*build: //')"
	fi
	[ -f $BACK/fingerprint/calib.dat ] && echo fingerprint=card || echo fingerprint=none
	[ -f $MODDIR/service.log ] && echo "last_check=$(tail -n 1 $MODDIR/service.log)"
	close_back
	rm -rf $W
}

backup() {
	[ "$(getprop sys.boot_completed)" = 1 ] || die "Android has not finished booting"
	parts_are_ubuntu && die "the boot partitions hold Ubuntu, not Android"
	open_back || die "no gts9wifi microSD (GTS9W_BACK)"
	rm -rf $W/set
	mkdir -p $W/set
	for n in boot init_boot vendor_boot dtbo; do
		head -c $(size_of $n) $BB/$n > $W/set/$n.img
		[ "$(stat -c %s $W/set/$n.img)" = "$(size_of $n)" ] || die "could not read $n"
	done
	(cd $W/set && sha256sum boot.img init_boot.img vendor_boot.img dtbo.img > SHA256SUMS)
	if [ -f $BACK/android-restore.zip ] &&
		$TOOL extract $BACK/android-restore.zip android/SHA256SUMS $W/old.sums 2>/dev/null &&
		cmp -s $W/old.sums $W/set/SHA256SUMS; then
		echo "OK: android-restore.zip is up to date"
		rm -rf $W/set $W/old.sums; close_back; return 0
	fi
	{
		echo "Android boot images of this tablet, saved $(date -u +%Y-%m-%dT%H:%MZ)"
		echo "by the gts9wifi Magisk module ($(cat $MODDIR/version.txt))."
		echo "source: running Android"
		echo "device: $(getprop ro.product.device)  build: $(getprop ro.build.fingerprint)"
	} > $W/set/info.txt
	printf '# gts9wifi android boot set: see android/restore.sh (run by update-binary)\n' > $W/set/updater-script
	$TOOL zip -0 $W/set/android-restore.zip \
		META-INF/com/google/android/update-binary=$MODDIR/update-binary \
		META-INF/com/google/android/updater-script=$W/set/updater-script \
		android/restore.sh=$MODDIR/restore.sh \
		android/boot.img=$W/set/boot.img \
		android/init_boot.img=$W/set/init_boot.img \
		android/vendor_boot.img=$W/set/vendor_boot.img \
		android/dtbo.img=$W/set/dtbo.img \
		android/SHA256SUMS=$W/set/SHA256SUMS \
		android/info.txt=$W/set/info.txt || die "could not build android-restore.zip"
	for n in boot init_boot vendor_boot dtbo; do
		$TOOL extract $W/set/android-restore.zip android/$n.img $W/check.img &&
		[ "$(sha $W/check.img)" = "$(want $n.img $W/set/SHA256SUMS)" ] || die "new zip did not verify ($n)"
	done
	rm -f $W/check.img
	cp $W/set/android-restore.zip $BACK/android-restore.zip.new && sync &&
	[ "$(sha $BACK/android-restore.zip.new)" = "$(sha $W/set/android-restore.zip)" ] &&
	mv $BACK/android-restore.zip.new $BACK/android-restore.zip ||
		{ rm -f $BACK/android-restore.zip.new; die "could not write android-restore.zip to the card"; }
	sync
	# Older layouts kept the images unpacked as well; that copy is now stale.
	rm -rf $BACK/android
	echo "OK: android-restore.zip updated ($(getprop ro.build.fingerprint))"
	rm -rf $W/set $W/old.sums
	close_back
}

fingerprint() {
	[ -f $FP_SRC/calib.dat ] && [ -f $FP_SRC/egoptbds.dat ] || { echo "no calibration in $FP_SRC"; return 0; }
	open_back || die "no gts9wifi microSD (GTS9W_BACK)"
	mkdir -p $W
	(cd $FP_SRC && sha256sum calib.dat egoptbds.dat) > $W/fp.sums
	if cmp -s $W/fp.sums $BACK/fingerprint/SHA256SUMS; then
		echo "OK: fingerprint calibration already on the card"
	else
		mkdir -p $BACK/fingerprint
		for f in calib.dat egoptbds.dat; do
			cp $FP_SRC/$f $BACK/fingerprint/.$f.new && mv $BACK/fingerprint/.$f.new $BACK/fingerprint/$f ||
				die "could not copy $f"
		done
		cp $W/fp.sums $BACK/fingerprint/SHA256SUMS
		sync
		(cd $BACK/fingerprint && sha256sum calib.dat egoptbds.dat) | cmp -s - $W/fp.sums ||
			die "fingerprint calibration did not verify on the card"
		echo "OK: fingerprint calibration copied to the card"
	fi
	rm -f $W/fp.sums
	close_back
}

case "${1:-}" in
	status) status ;;
	backup) backup ;;
	fingerprint) fingerprint ;;
	ubuntu)
		backup || exit 1
		GTS9W_TOOL=$TOOL sh $MODDIR/to-ubuntu.sh --yes
		;;
	*) echo "usage: $0 status|backup|fingerprint|ubuntu"; exit 2 ;;
esac
