#!/sbin/sh
# Boot-set switch zips for the Galaxy Tab S9 Wi-Fi (SM-X710, gts9wifi).  Both
# live on the microSD's FAT partition GTS9W_BACK and are flashed in recovery:
#
#   android-restore.zip  (GTS9W_SET=android)  this tablet's own Android boot
#       images, read from its partitions and zipped ON THE TABLET by the
#       Ubuntu installer just before Ubuntu was written
#   ubuntu-boot.zip      (GTS9W_SET=ubuntu)   the Ubuntu boot images of the
#       image on this card, zipped on the tablet by the installer from its own
#       copy of the boot set
#
# Either one writes its four images to boot, init_boot, vendor_boot and dtbo
# (nothing else) and reads them back.  No root and no Android version
# dependence: this is the safe way to switch without the in-system shortcuts
# (Android: to-ubuntu.sh, Ubuntu: "Switch to Android").
#
# Started by the zip's update-binary loader (installer/update-binary.sh),
# which provides GTS9W_TOOL and GTS9W_SET:  restore.sh <api> <OUTFD> <ZIPFILE>
set -u

OUTFD=$2
ZIPFILE=$3
W=/tmp/gts9w-restore
TOOL=${GTS9W_TOOL:?started by update-binary}
SET=${GTS9W_SET:-android}
BB=/dev/block/by-name
SD=/dev/block/mmcblk1

ui() { printf 'ui_print %s\nui_print\n' "$*" >> /proc/self/fd/$OUTFD; }
fail() {
	ui ""
	ui "ERROR: $*"
	rm -rf $W
	exit 1
}
sha() { sha256sum "$1" | cut -d' ' -f1; }
want() { grep " $1\$" $W/SHA256SUMS | cut -d' ' -f1; }
size_of() {
	case $1 in
		boot|vendor_boot) echo 100663296 ;;
		init_boot) echo 8388608 ;;
		dtbo) echo 16777216 ;;
	esac
}

case $SET in
	android) title="Back to Android"; os=Android ;;
	ubuntu) title="Switch to Ubuntu"; os=Ubuntu ;;
	*) fail "Unknown boot set: $SET" ;;
esac

rm -rf $W
mkdir -p $W
ui "=============================================="
ui " $title - Galaxy Tab S9 Wi-Fi (SM-X710)"
ui "=============================================="
dev=$(getprop ro.product.device)
case "$dev $(getprop ro.build.product)" in
	*gts9wifi*) ;;
	*) fail "This zip is only for the SM-X710 (gts9wifi) (device: $dev)" ;;
esac

# The Ubuntu boot images mount their root by label from the microSD: without
# that card in the slot the tablet would not boot (and the way back,
# android-restore.zip, is on the same card).  The ext4 label sits at byte
# 1144 of the filesystem (superblock at 1024, s_volume_name at +120).
if [ $SET = ubuntu ]; then
	[ -b ${SD}p3 ] && head -c 1160 ${SD}p3 | tail -c 16 | grep -a -q GTS9W_ROOT ||
		fail "No Ubuntu microSD (GTS9W_ROOT) in the slot; nothing was written"
fi

for f in SHA256SUMS info.txt boot.img init_boot.img vendor_boot.img dtbo.img; do
	$TOOL extract "$ZIPFILE" $SET/$f $W/$f || fail "Could not extract from the zip: $f"
done
while read -r line; do ui "$line"; done < $W/info.txt
for name in boot init_boot vendor_boot dtbo; do
	part=$BB/$name
	[ -e $part ] || fail "Missing partition: $part"
	case "$(readlink -f $part)" in
		/dev/block/sd[a-f][0-9]*) ;;
		*) fail "$part points to an unexpected device" ;;
	esac
	[ "$(blockdev --getsize64 $part)" = "$(size_of $name)" ] || fail "Unexpected size of the $name partition"
	[ "$(stat -c %s $W/$name.img)" = "$(size_of $name)" ] || fail "Unexpected size of $name.img"
	[ "$(sha $W/$name.img)" = "$(want $name.img)" ] || fail "sha256 mismatch: $name"
done
ui "Images OK."

ui ""
ui "The $os boot images will be written"
ui "(boot, init_boot, vendor_boot, dtbo)."
ui "Android data and the microSD are not changed. Continue?"
ui "  Volume Up   = YES"
ui "  Volume Down = NO   (no answer in 60 s: NO)"
$TOOL keys 60 || fail "Cancelled; nothing was written"

for name in boot init_boot vendor_boot dtbo; do
	ui "Writing: $name"
	dd if=$W/$name.img of=$BB/$name bs=4194304 2>/dev/null || fail "Could not write $name"
done
sync
for name in boot init_boot vendor_boot dtbo; do
	[ "$(head -c $(size_of $name) $BB/$name | sha256sum | cut -d' ' -f1)" = "$(want $name.img)" ] ||
		fail "$name did not verify after writing; do not reboot, flash the zip again"
done
rm -rf $W
ui ""
ui "DONE: $os boot images written and verified."
ui "Reboot: $os will start."
exit 0
