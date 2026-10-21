#!/sbin/sh
# Ubuntu installer zip for the Galaxy Tab S9 Wi-Fi (SM-X710, gts9wifi).
# One zip, two ways in:
#   recovery (LineageOS recovery, TWRP: adb sideload): started by the zip's
#       update-binary loader (installer/update-binary.sh)
#   Android (Magisk app, as a module): started by the zip's customize.sh
#       (installer/magisk/customize.sh), GTS9W_MODE=android
#   install.sh <api> <OUTFD> <ZIPFILE>
# The caller provides GTS9W_TOOL (gts9w-tool) and GTS9W_LOADER (the loader
# with the tool appended, reused for the two switch zips).
#
# Order, chosen so that a failure at any step leaves a bootable Android:
#   1. checks: device, microSD (/dev/block/mmcblk1 only, not adopted as
#      internal storage), boot partitions, free space; stage the payload and
#      verify every sha256
#   2. Android backup: read this tablet's own boot, init_boot, vendor_boot and
#      dtbo, whatever Android version it runs, and build android-restore.zip
#      from them (an Ubuntu set already in the partitions is detected and
#      never "backed up")
#   3. ask: the microSD will be erased (Volume Up = yes, Volume Down = no)
#   4. write the Ubuntu microSD image, read it back
#   5. build ubuntu-boot.zip from this zip's Ubuntu boot images and put both
#      switch zips on the card's FAT partition GTS9W_BACK; in Android also the
#      fingerprint sensor's calibration (only readable there), which Ubuntu
#      installs at boot (gts9wifi-import-backup).  Ubuntu's root filesystem
#      is never written.
#   6. only now write the four Ubuntu boot images, read them back
# Android's userdata, super, vbmeta and everything else are never written.
#
# In Android, a card that already holds Ubuntu is kept unless the user says
# YES to erasing it: then only the
# Android backup and the calibration are refreshed (and the Magisk module is
# installed); boot partitions and the card's Ubuntu stay as they are.
set -u

OUTFD=$2
ZIPFILE=$3
MODE=${GTS9W_MODE:-recovery}
TOOL=${GTS9W_TOOL:?started by update-binary or customize.sh}
LOADER=${GTS9W_LOADER:?started by update-binary or customize.sh}
BB=/dev/block/by-name
SD=/dev/block/mmcblk1
P=gts9wifi
FP_SRC=/data/vendor/biometrics/meta
if [ $MODE = android ]; then
	W=/data/local/tmp/gts9w
	ui() { echo "$*"; }
else
	W=/tmp/gts9w
	ui() { printf 'ui_print %s\nui_print\n' "$*" >> /proc/self/fd/$OUTFD; }
fi

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
# YES -> 0; NO or 60 s without an answer -> 1.  Recovery: Volume Up / Down.
# Android swaps the two keys with the screen rotation (the key that turns
# the volume down in landscape sends Volume Up), so there it counts presses
# of either key instead: two = YES, one = NO.
ask() {
	ui ""
	for line in "$@"; do ui "$line"; done
	if [ $MODE = android ]; then
		ui "  YES: press a volume key TWICE"
		ui "  NO:  press it once   (no answer in 60 s: NO)"
		$TOOL presses 60
	else
		ui "  Volume Up   = YES"
		ui "  Volume Down = NO   (no answer in 60 s: NO)"
		$TOOL keys 60
	fi
	[ $? = 0 ]
}
# Before the card is erased.  Android's vold mounts the card's FAT itself
# (shown as /dev/block/vold/public:179,N): ask it to let go.
release_sd() {
	if [ $MODE = android ]; then
		for v in $(sm list-volumes public 2>/dev/null | grep -o 'public:179,[0-9]*'); do
			sm unmount $v
		done
		i=0
		while grep -q '^/dev/block/vold/public:179,' /proc/mounts && [ $i -lt 20 ]; do
			sleep 0.5; i=$((i + 1))
		done
		grep -q '^/dev/block/vold/public:179,' /proc/mounts && fail "Android did not release the SD card"
	fi
	for m in $(grep "^$SD" /proc/mounts | cut -d' ' -f2); do
		umount "$m" || fail "Could not unmount the SD card: $m"
	done
}
# GTS9W_BACK at $W/back.  After the card was written, Android's vold finds
# the new FAT partition, checks it (fsck) and mounts it: wait for that, so
# nothing writes during its fsck.  Mounting the same partition again shares
# the filesystem with vold's mount.
mount_back() {
	if [ $MODE = android ]; then
		i=0
		while ! grep -q '^/dev/block/vold/public:179,' /proc/mounts && [ $i -lt 30 ]; do
			sleep 0.5; i=$((i + 1))
		done
	fi
	mkdir -p $W/back
	mount -t vfat ${SD}p1 $W/back || fail "Could not mount GTS9W_BACK"
}
card_has_ubuntu() {
	[ -b ${SD}p3 ] && head -c 1160 ${SD}p3 | tail -c 16 | grep -a -q GTS9W_ROOT
}
# Copy one file onto GTS9W_BACK and check it there.
put() {
	rm -f "$2.new"
	cp "$1" "$2.new" && sync && [ "$(sha "$2.new")" = "$(sha "$1")" ] && mv "$2.new" "$2" || {
		rm -f "$2.new"; fail "Could not write $(basename "$2") to the SD card"; }
}
# Older cards (512 MiB GTS9W_BACK) also kept the Android images unpacked in
# android/.  Remove only those files: on FAT that folder is the same as
# Android's own "Android/" (data, media of apps on the card).
drop_legacy() {
	for f in boot.img init_boot.img vendor_boot.img dtbo.img SHA256SUMS info.txt; do
		rm -f $W/back/android/$f
	done
	rmdir $W/back/android 2>/dev/null
	return 0
}
# The calibration lives only in Android's /data/vendor (encrypted for a
# recovery); Ubuntu's gts9wifi-import-backup installs it from the card.
copy_fingerprint() {
	[ $MODE = android ] || return 0
	[ -f $FP_SRC/calib.dat ] && [ -f $FP_SRC/egoptbds.dat ] || {
		ui "No fingerprint calibration in Android ($FP_SRC); skipped."; return 0; }
	mkdir -p $W/back/fingerprint
	for f in calib.dat egoptbds.dat; do put $FP_SRC/$f $W/back/fingerprint/$f; done
	(cd $FP_SRC && sha256sum calib.dat egoptbds.dat) > $W/fp.sums
	put $W/fp.sums $W/back/fingerprint/SHA256SUMS
	ui "Fingerprint calibration copied to the SD card."
}

rm -rf $W
mkdir -p $W/pay $W/android
ui "=============================================="
ui " Ubuntu 24.04 - Galaxy Tab S9 Wi-Fi (SM-X710)"
if [ $MODE = android ]; then ui " microSD installer (Magisk)"; else ui " microSD installer"; fi
ui "=============================================="

# ---- 1. checks ----------------------------------------------------------
dev=$(getprop ro.product.device)
case "$dev $(getprop ro.build.product) $(getprop ro.boot.hardware.sku 2>/dev/null)" in
	*gts9wifi*) ;;
	*) fail "This zip is only for the SM-X710 (gts9wifi) (device: $dev)" ;;
esac

[ -b $SD ] || fail "No microSD card found ($SD)"
[ "$(cat /sys/block/mmcblk1/device/type 2>/dev/null)" = SD ] || fail "$SD is not an SD card"
# A card adopted as internal storage holds Android apps and data.
grep -qs 'PARTNAME=android_expand' /sys/block/mmcblk1/mmcblk1p*/uevent &&
	fail "This SD card is used as Android internal storage; nothing was written"
for name in boot init_boot vendor_boot dtbo; do
	part=$BB/$name
	[ -e $part ] || fail "Missing partition: $part"
	case "$(readlink -f $part)" in
		/dev/block/sd[a-f][0-9]*) ;;
		*) fail "$part points to an unexpected device: $(readlink -f $part)" ;;
	esac
	[ "$(blockdev --getsize64 $part)" = "$(size_of $name)" ] || fail "Unexpected size of the $name partition"
done

# Every question that goes on with something is asked so that going on is
# YES (in Android: two presses); NO and no answer are always the safe way.
keep=0
erase_ok=0
if [ $MODE = android ] && card_has_ubuntu; then
	if ask "Ubuntu is already on this SD card." \
		"ERASE the card and install Ubuntu again?" \
		"(NO: keep the card; only install the Magisk module" \
		" and refresh the Android backup on the card.)"; then
		erase_ok=1
	else
		keep=1
	fi
fi

if [ $keep = 0 ]; then
	ui "Copying the package to $(dirname $W) and verifying it..."
	free_kb=$(df -k $(dirname $W) | tail -1 | tr -s ' ' | cut -d' ' -f4)
	[ "${free_kb:-0}" -gt 2500000 ] || fail "Not enough space in $(dirname $W) (${free_kb} KB)"
	files="sd.img.zst boot.img init_boot.img vendor_boot.img dtbo.img restore.sh"
else
	files="restore.sh"
fi
for f in SHA256SUMS version.txt $files; do
	$TOOL extract "$ZIPFILE" $P/$f $W/pay/$f || fail "Could not extract from the zip: $f"
done
for f in $files; do
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
	[ $keep = 0 ] &&
	[ "$(head -c 100663296 $BB/boot | sha256sum | cut -d' ' -f1)" = "$(want boot.img $W/pay/SHA256SUMS)" ]
}

# Take a verified set from directory $1 (four images + SHA256SUMS).
take_set() {
	[ -f $1/SHA256SUMS ] || return 1
	for name in boot init_boot vendor_boot dtbo; do
		[ -f $1/$name.img ] && [ "$(sha $1/$name.img)" = "$(want $name.img $1/SHA256SUMS)" ] || return 1
	done
	for name in boot init_boot vendor_boot dtbo; do cp $1/$name.img $W/android/; done
}

# An Ubuntu set is already installed: the Android images can only come from
# an earlier backup on this card (GTS9W_BACK/android-restore.zip, or older
# layouts: GTS9W_BACK/android/, Ubuntu's own restore set).
rescue_backup() {
	mkdir -p $W/old $W/rescue/android
	for p in $SD"p"*; do
		[ -b "$p" ] || continue
		for fs in vfat ext4; do
			mount -t $fs -o ro "$p" $W/old 2>/dev/null || continue
			if [ -f $W/old/android-restore.zip ]; then
				for f in SHA256SUMS boot.img init_boot.img vendor_boot.img dtbo.img; do
					$TOOL extract $W/old/android-restore.zip android/$f $W/rescue/android/$f 2>/dev/null
				done
				if take_set $W/rescue/android; then
					umount $W/old; rm -rf $W/rescue
					ui "Found an earlier Android backup: $p android-restore.zip"
					return 0
				fi
			fi
			for d in $W/old/android $W/old/usr/share/gts9wifi-dualboot/android; do
				if take_set $d; then
					umount $W/old; rm -rf $W/rescue
					ui "Found an earlier Android backup: $p"
					return 0
				fi
			done
			umount $W/old
		done
	done
	rm -rf $W/rescue
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
		[ "$(stat -c %s $W/android/$name.img)" = "$(size_of $name)" ] || fail "Could not read $name"
	done
	backup=partitions
fi

# Build a switch zip: $1 output, $2 set (android|ubuntu), $3 directory with
# the four images, SHA256SUMS and info.txt.  Same loader as this zip (with
# gts9w-tool); restore.sh does the work.
make_switch_zip() {
	printf '# gts9wifi %s boot set: see %s/restore.sh (run by update-binary)\n' $2 $2 > $W/updater-script
	$TOOL zip -0 $1 \
		META-INF/com/google/android/update-binary=$LOADER \
		META-INF/com/google/android/updater-script=$W/updater-script \
		$2/restore.sh=$W/pay/restore.sh \
		$2/boot.img=$3/boot.img \
		$2/init_boot.img=$3/init_boot.img \
		$2/vendor_boot.img=$3/vendor_boot.img \
		$2/dtbo.img=$3/dtbo.img \
		$2/SHA256SUMS=$3/SHA256SUMS \
		$2/info.txt=$3/info.txt || fail "Could not create $(basename $1)"
	# Read the images back out of the new zip.
	for name in boot init_boot vendor_boot dtbo; do
		$TOOL extract $1 $2/$name.img $W/check.img &&
		[ "$(sha $W/check.img)" = "$(want $name.img $3/SHA256SUMS)" ] ||
			fail "$(basename $1) did not verify ($name)"
	done
	rm -f $W/check.img
}

if [ $backup != none ]; then
	(cd $W/android && sha256sum boot.img init_boot.img vendor_boot.img dtbo.img > SHA256SUMS)
	for name in boot init_boot vendor_boot dtbo; do
		ui "  $name  $(want $name.img $W/android/SHA256SUMS | cut -c1-16)"
	done
	{
		echo "Android boot images of this tablet, saved $(date -u +%Y-%m-%dT%H:%MZ)"
		echo "by the gts9wifi Ubuntu installer ($(cat $W/pay/version.txt))."
		echo "source: $backup"
		echo "device: $dev  build: $(getprop ro.build.fingerprint)"
	} > $W/android/info.txt
	make_switch_zip $W/android-restore.zip android $W/android
	ui "android-restore.zip created and verified."
fi

if [ $keep = 1 ]; then
	mount_back
	drop_legacy
	[ $backup != none ] && put $W/android-restore.zip $W/back/android-restore.zip
	copy_fingerprint
	no_boot_zip=0
	[ -f $W/back/ubuntu-boot.zip ] || no_boot_zip=1
	umount $W/back
	ui ""
	ui "=============================================="
	ui " DONE. Ubuntu on the SD card was kept."
	if [ $no_boot_zip = 1 ]; then
		ui " WARNING: this card has no ubuntu-boot.zip"
		ui " (older install), so the module cannot switch"
		ui " to Ubuntu. Install again and answer YES to"
		ui " the first question to rebuild the card."
	fi
	ui " Switch to Ubuntu with the Magisk module"
	ui " (action button or WebUI), after a reboot."
	ui "=============================================="
	cleanup
	exit 0
fi

# ---- 3. confirm ------------------------------------------------------------
# (Already answered when the card held Ubuntu.)
[ $erase_ok = 1 ] ||
ask "WARNING: EVERYTHING on the microSD card" \
	"($((card / 1953125)) GB) will be ERASED and Ubuntu installed." \
	"Android and the internal storage are not changed." \
	"Continue?" || fail "Cancelled; nothing was written"

# ---- 4. microSD ------------------------------------------------------------
release_sd
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
# New partition table.  In Android, ueventd (re)creates the partition nodes
# only after vold has looked at the new disk, which took longer than 10 s on
# the tablet: wait up to 60 s, then make missing nodes from sysfs.
blockdev --rereadpt $SD
i=0
while [ ! -b ${SD}p3 ] && [ $i -lt 120 ]; do sleep 0.5; i=$((i + 1)); done
for n in 1 2 3; do
	[ -b ${SD}p$n ] && continue
	d=$(cat /sys/block/mmcblk1/mmcblk1p$n/dev 2>/dev/null) || continue
	mknod ${SD}p$n b ${d%%:*} ${d##*:}
done
[ -b ${SD}p1 ] && [ -b ${SD}p3 ] || fail "SD partitions did not appear; boot partitions NOT changed"
ui "SD card OK."

# ---- 5. switch zips onto the card -----------------------------------------
mkdir -p $W/ubuntu
for name in boot init_boot vendor_boot dtbo; do
	ln -s $W/pay/$name.img $W/ubuntu/$name.img
done
grep -E ' (boot|init_boot|vendor_boot|dtbo)\.img$' $W/pay/SHA256SUMS > $W/ubuntu/SHA256SUMS
{
	echo "Ubuntu boot images, gts9wifi port $(cat $W/pay/version.txt)."
	echo "They boot the Ubuntu microSD this zip was made with (root=LABEL=GTS9W_ROOT)."
} > $W/ubuntu/info.txt
make_switch_zip $W/ubuntu-boot.zip ubuntu $W/ubuntu
ui "ubuntu-boot.zip created and verified."

mount_back
put $W/ubuntu-boot.zip $W/back/ubuntu-boot.zip
rm -f $W/ubuntu-boot.zip
[ $backup != none ] && put $W/android-restore.zip $W/back/android-restore.zip
copy_fingerprint
umount $W/back
ui "Switch zips written to the SD card (GTS9W_BACK)."

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
ui " Switch zips on the SD card (GTS9W_BACK),"
ui " flash in recovery, no root needed:"
[ $backup != none ] && ui "   android-restore.zip  -> Android"
ui "   ubuntu-boot.zip      -> Ubuntu"
[ $backup = none ] && ui " WARNING: no Android backup was taken."
ui " In Ubuntu: 'Switch to Android' in the dock."
if [ $MODE = android ]; then
	ui " In Android: Magisk module Action button (KernelSU: WebUI)."
else
	ui ""
	ui " Fingerprint reader: in Android, install this"
	ui " zip once from the Magisk app and keep the card"
	ui " (the calibration can only be read there)."
fi
ui "=============================================="
cleanup
exit 0
