#!/sbin/sh
# Ubuntu installer zip for the Galaxy Tab S9 Wi-Fi (SM-X710, gts9wifi).
# Runs in any recovery (LineageOS recovery, TWRP), started by the zip's
# update-binary loader (installer/update-binary.sh) with the same arguments:
#   install.sh <api> <OUTFD> <ZIPFILE>
# The loader provides GTS9W_TOOL (gts9w-tool) and GTS9W_LOADER (itself).
#
# Order, chosen so that a failure at any step leaves a bootable Android:
#   1. checks: device, microSD (/dev/block/mmcblk1 only), boot partitions,
#      space in /tmp; stage the payload in /tmp and verify every sha256
#   2. Android backup: read this tablet's own boot, init_boot, vendor_boot and
#      dtbo, and build android-restore.zip from them (an Ubuntu set already
#      in the partitions is detected and never "backed up")
#   3. ask: the microSD will be erased (Volume Up = yes, Volume Down = no)
#   4. write the Ubuntu microSD image, read it back
#   5. put android-restore.zip and the unpacked images on the card's FAT
#      partition GTS9W_BACK, next to ubuntu-boot.zip (already in the image); Ubuntu itself takes them into its "Switch to
#      Android" set at boot (gts9wifi-import-backup).  Recovery never writes
#      Ubuntu's root filesystem.
#   6. only now write the four Ubuntu boot images, read them back
# Android's userdata, super, vbmeta and everything else are never written.
#
set -u

OUTFD=$2
ZIPFILE=$3
W=/tmp/gts9w
TOOL=${GTS9W_TOOL:?started by update-binary}
LOADER=${GTS9W_LOADER:?started by update-binary}
BB=/dev/block/by-name
SD=/dev/block/mmcblk1
P=gts9wifi

ui() { printf 'ui_print %s\nui_print\n' "$*" >> /proc/self/fd/$OUTFD; }
fail() {
	ui ""
	ui "ERROR: $*"
	ui "Boot partitions were not changed; the tablet boots as before."
	cleanup
	exit 1
}
cleanup() {
	for m in $W/back $W/old; do
		grep -q " $m " /proc/mounts && umount $m
	done
	rm -rf $W
}
sha() { sha256sum "$1" | cut -d' ' -f1; }
want() { grep " $1\$" "$2" | cut -d' ' -f1; }
size_of() {
	case $1 in
		boot|vendor_boot) echo 100663296 ;;
		init_boot) echo 8388608 ;;
		dtbo) echo 16777216 ;;
	esac
}
# Volume Up -> 0, Volume Down or 60 s without an answer -> 1.
ask() {
	ui ""
	for line in "$@"; do ui "$line"; done
	ui "  Volume Up   = YES"
	ui "  Volume Down = NO   (no answer in 60 s: NO)"
	$TOOL keys 60
	[ $? = 0 ]
}

rm -rf $W
mkdir -p $W/pay $W/android
ui "=============================================="
ui " Ubuntu 24.04 - Galaxy Tab S9 Wi-Fi (SM-X710)"
ui " microSD installer"
ui "=============================================="

# ---- 1. checks ----------------------------------------------------------
dev=$(getprop ro.product.device)
case "$dev $(getprop ro.build.product) $(getprop ro.boot.hardware.sku 2>/dev/null)" in
	*gts9wifi*) ;;
	*) fail "This zip is only for the SM-X710 (gts9wifi) (device: $dev)" ;;
esac

[ -b $SD ] || fail "No microSD card found ($SD)"
[ "$(cat /sys/block/mmcblk1/device/type 2>/dev/null)" = SD ] || fail "$SD is not an SD card"
for name in boot init_boot vendor_boot dtbo; do
	part=$BB/$name
	[ -e $part ] || fail "Missing partition: $part"
	case "$(readlink -f $part)" in
		/dev/block/sd[a-f][0-9]*) ;;
		*) fail "$part points to an unexpected device: $(readlink -f $part)" ;;
	esac
	[ "$(blockdev --getsize64 $part)" = "$(size_of $name)" ] || fail "Unexpected size of the $name partition"
done

ui "Copying the package to /tmp and verifying it..."
free_kb=$(df -k /tmp | tail -1 | tr -s ' ' | cut -d' ' -f4)
[ "${free_kb:-0}" -gt 2500000 ] || fail "Not enough space in /tmp (${free_kb} KB)"
for f in SHA256SUMS sd.img.zst boot.img init_boot.img vendor_boot.img dtbo.img \
	restore.sh version.txt; do
	$TOOL extract "$ZIPFILE" $P/$f $W/pay/$f || fail "Could not extract from the zip: $f"
done
for f in sd.img.zst boot.img init_boot.img vendor_boot.img dtbo.img restore.sh; do
	[ "$(sha $W/pay/$f)" = "$(want $f $W/pay/SHA256SUMS)" ] || fail "sha256 mismatch: $f"
done
raw_size=$(grep '^raw_size ' $W/pay/SHA256SUMS | cut -d' ' -f2)
raw_sectors=$(grep '^raw_sectors ' $W/pay/SHA256SUMS | cut -d' ' -f2)
raw_sha=$(want sd.img $W/pay/SHA256SUMS)
# Sizes are compared in 512-byte sectors: Android's mksh does 32-bit
# arithmetic, so byte counts above 2 GiB overflow in [ -ge ] and $(( )).
card=$(blockdev --getsz $SD)
[ "$card" -ge "$raw_sectors" ] || fail "SD card too small: $card sectors, at least $raw_sectors needed"
ui "Package OK: $(cat $W/pay/version.txt)"

# ---- 2. Android backup ----------------------------------------------------
is_ubuntu_set() {
	head -c 4096 $BB/vendor_boot | grep -a -q GTS9W_ROOT && return 0
	[ "$(head -c 100663296 $BB/boot | sha256sum | cut -d' ' -f1)" = "$(want boot.img $W/pay/SHA256SUMS)" ]
}

# An Ubuntu set is already installed: the Android images can only come from
# an earlier backup on this card (GTS9W_BACK, or Ubuntu's own restore set).
rescue_backup() {
	mkdir -p $W/old
	for p in $SD"p"*; do
		[ -b "$p" ] || continue
		for fs in vfat ext4; do
			mount -t $fs -o ro "$p" $W/old 2>/dev/null || continue
			for d in $W/old/android $W/old/usr/share/gts9wifi-dualboot/android; do
				[ -f $d/SHA256SUMS ] || continue
				ok=1
				for name in boot init_boot vendor_boot dtbo; do
					[ -f $d/$name.img ] &&
					[ "$(sha $d/$name.img)" = "$(want $name.img $d/SHA256SUMS)" ] || ok=0
				done
				if [ $ok = 1 ]; then
					for name in boot init_boot vendor_boot dtbo; do
						cp $d/$name.img $W/android/
					done
					umount $W/old
					ui "Found an earlier Android backup: $p"
					return 0
				fi
			done
			umount $W/old
		done
	done
	return 1
}

ui ""
ui "Backing up the Android boot images..."
backup=none
if is_ubuntu_set; then
	ui "The partitions already hold an Ubuntu boot set; looking for an Android backup on the card."
	if rescue_backup; then
		backup=card
	elif ask "NO Android backup found. If you continue, going back to" \
		"Android needs your own backup or fastboot from a PC." "Continue anyway?"; then
		backup=none
	else
		fail "Cancelled (no Android backup)"
	fi
else
	for name in boot init_boot vendor_boot dtbo; do
		head -c $(size_of $name) $BB/$name > $W/android/$name.img
		[ "$(stat -c %s $W/android/$name.img)" = "$(size_of $name)" ] || fail "$name okunamadi"
	done
	backup=partitions
fi

if [ $backup != none ]; then
	(cd $W/android && sha256sum boot.img init_boot.img vendor_boot.img dtbo.img > SHA256SUMS)
	for name in boot init_boot vendor_boot dtbo; do
		ui "  $name  $(want $name.img $W/android/SHA256SUMS | cut -c1-16)"
	done
	# Same loader as this zip (with gts9w-tool); restore.sh does the work.
	printf '# gts9wifi Android boot-set restore: see android/restore.sh\n' > $W/updater-script
	{
		echo "Android boot images of this tablet, saved $(date -u +%Y-%m-%dT%H:%MZ)"
		echo "by the gts9wifi Ubuntu installer ($(cat $W/pay/version.txt))."
		echo "source: $backup"
		echo "device: $dev  build: $(getprop ro.build.fingerprint)"
	} > $W/android/info.txt
	$TOOL zip -0 $W/android-restore.zip \
		META-INF/com/google/android/update-binary=$LOADER \
		META-INF/com/google/android/updater-script=$W/updater-script \
		android/restore.sh=$W/pay/restore.sh \
		android/boot.img=$W/android/boot.img \
		android/init_boot.img=$W/android/init_boot.img \
		android/vendor_boot.img=$W/android/vendor_boot.img \
		android/dtbo.img=$W/android/dtbo.img \
		android/SHA256SUMS=$W/android/SHA256SUMS \
		android/info.txt=$W/android/info.txt || fail "Could not create android-restore.zip"
	# Read the images back out of the new zip before anything is erased.
	for name in boot init_boot vendor_boot dtbo; do
		$TOOL extract $W/android-restore.zip android/$name.img $W/check.img &&
		[ "$(sha $W/check.img)" = "$(want $name.img $W/android/SHA256SUMS)" ] ||
			fail "android-restore.zip did not verify ($name)"
	done
	rm -f $W/check.img
	ui "android-restore.zip created and verified."
fi

# ---- 3. confirm ------------------------------------------------------------
ask "WARNING: EVERYTHING on the microSD card" \
	"($((card / 1953125)) GB) will be ERASED and Ubuntu installed." \
	"Android and the internal storage are not changed." \
	"Continue?" || fail "Cancelled; nothing was written"

# ---- 4. microSD ------------------------------------------------------------
for m in $(grep "^$SD" /proc/mounts | cut -d' ' -f2); do
	umount "$m" || fail "Could not unmount the SD card: $m"
done
ui ""
ui "Writing Ubuntu to the SD card (a few minutes)..."
{ $TOOL unzstd $W/pay/sd.img.zst $SD; echo "rc $?"; } | while read pct rc; do
	if [ "$pct" = rc ]; then echo $rc > $W/unzstd.rc; else ui "  %$pct"; fi
done
[ "$(cat $W/unzstd.rc 2>/dev/null)" = 0 ] || fail "Writing the SD card failed; boot partitions NOT changed"
rm -f $W/pay/sd.img.zst
sync
ui "Reading back to verify..."
[ "$(head -c $raw_size $SD | sha256sum | cut -d' ' -f1)" = "$raw_sha" ] ||
	fail "SD card read-back failed; boot partitions NOT changed"
blockdev --rereadpt $SD
i=0
while [ ! -b ${SD}p3 ] && [ $i -lt 20 ]; do sleep 0.5; i=$((i + 1)); done
[ -b ${SD}p1 ] && [ -b ${SD}p3 ] || fail "SD partitions did not appear; boot partitions NOT changed"
ui "SD card OK."

# ---- 5. backups onto the card ----------------------------------------------
if [ $backup != none ]; then
	mkdir -p $W/back
	mount -t vfat ${SD}p1 $W/back || fail "Could not mount GTS9W_BACK"
	mkdir -p $W/back/android
	cp $W/android-restore.zip $W/back/ &&
	cp $W/android/*.img $W/android/SHA256SUMS $W/android/info.txt $W/back/android/ ||
		fail "Could not write the backup to the SD card"
	sync
	[ "$(sha $W/back/android-restore.zip)" = "$(sha $W/android-restore.zip)" ] ||
		fail "android-restore.zip on the SD card did not verify"
	for name in boot init_boot vendor_boot dtbo; do
		[ "$(sha $W/back/android/$name.img)" = "$(want $name.img $W/android/SHA256SUMS)" ] ||
			fail "android/$name.img on the SD card did not verify"
	done
	umount $W/back
	ui "Android backup written to the SD card (GTS9W_BACK)."
	ui "Ubuntu takes it for 'Switch to Android' at first boot."
fi

# ---- 6. Ubuntu boot images ---------------------------------------------------
ui ""
ui "Writing the Ubuntu boot images..."
for name in boot init_boot vendor_boot dtbo; do
	dd if=$W/pay/$name.img of=$BB/$name bs=4194304 2>/dev/null || fail "Could not write $name"
done
sync
for name in boot init_boot vendor_boot dtbo; do
	[ "$(head -c $(size_of $name) $BB/$name | sha256sum | cut -d' ' -f1)" = \
		"$(want $name.img $W/pay/SHA256SUMS)" ] || {
		ui "ERROR: $name did not verify after writing."
		ui "Flash GTS9W_BACK/android-restore.zip before rebooting."
		cleanup
		exit 1
	}
done

ui ""
ui "=============================================="
ui " DONE. Reboot: Ubuntu will start."
ui " User: ubuntu   Password: ubuntu"
ui ""
if [ $backup != none ]; then
	ui " Two switch zips are on the SD card (GTS9W_BACK):"
	ui "   android-restore.zip  -> back to Android"
	ui "   ubuntu-boot.zip      -> back to Ubuntu"
	ui " Flash either one in recovery; no root needed."
	ui " (In Ubuntu: 'Switch to Android' in the dock.)"
else
	ui " WARNING: no Android backup was taken."
fi
ui ""
ui " For the fingerprint reader, switch once from"
ui " Android with to-ubuntu.sh (calibration is in Android)."
ui "=============================================="
cleanup
exit 0
