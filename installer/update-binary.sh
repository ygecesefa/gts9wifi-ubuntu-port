#!/sbin/sh
# update-binary for the gts9wifi zips: the Ubuntu installer, and the two
# switch zips it builds on the tablet (android-restore.zip, ubuntu-boot.zip).
# Like AnyKernel3's, it is only a loader: the work is done by the readable
# script next to it in the zip.
#   update-binary <api> <OUTFD> <ZIPFILE>
#
# Started inside a running Android (the Magisk app installing the installer
# zip as a module), it hands over to Magisk's own module installer, which runs
# the zip's customize.sh (installer/magisk/customize.sh).  KernelSU and APatch
# run customize.sh themselves.
#
# gts9w-tool (static arm64: keys, extract, unzstd, zip; installer/gts9w-tool.c)
# is appended to this file, and the last 16 bytes are this script's length.
# The tool is carried inside the loader because a recovery is not guaranteed
# to have unzip.  It is cut out to /tmp, then used to extract the script:
#   gts9wifi/install.sh   in the installer zip
#   android/restore.sh    in android-restore.zip  (writes the Android boot set)
#   ubuntu/restore.sh     in ubuntu-boot.zip      (writes the Ubuntu boot set)
# GTS9W_SET tells restore.sh which set it is (the directory it came from).
OUTFD=$2
ZIPFILE=$3
W=/tmp/gts9w-loader

ui() { printf 'ui_print %s\nui_print\n' "$*" >> /proc/self/fd/$OUTFD; }

# Android is running (zygote): Magisk app.  The same test as Magisk's
# util_functions.sh.
if [ "${BOOTMODE:-}" = true ] || { ps -A 2>/dev/null || ps; } | grep zygote | grep -qv grep; then
	# Only the installer zip says #MAGISK in its updater-script, which the
	# Magisk app checks before it runs this.
	if [ -f /data/adb/magisk/util_functions.sh ]; then
		umask 022
		ui_print() { echo "$1"; }
		. /data/adb/magisk/util_functions.sh
		install_module
		exit 0
	fi
	echo "! Install this zip from the Magisk app, or flash it in recovery."
	echo "! (android-restore.zip and ubuntu-boot.zip: recovery only.)"
	exit 1
fi

rm -rf $W
mkdir -p $W
total=$(stat -c %s "$0")
off=$(tail -c 16 "$0" | sed 's/^0*//')
off=${off:-0}
tail -c +$((off + 1)) "$0" | head -c $((total - 16 - off)) > $W/gts9w-tool
chmod 0755 $W/gts9w-tool
$W/gts9w-tool >/dev/null 2>&1
[ $? = 2 ] || { ui "ERROR: gts9w-tool does not run in this recovery"; exit 1; }
cp "$0" $W/update-binary
SH=/sbin/sh
[ -x $SH ] || SH=sh

for s in gts9wifi/install.sh android/restore.sh ubuntu/restore.sh; do
	if $W/gts9w-tool extract "$ZIPFILE" $s $W/script.sh 2>/dev/null; then
		GTS9W_TOOL=$W/gts9w-tool GTS9W_LOADER=$W/update-binary GTS9W_SET=${s%%/*} \
			$SH $W/script.sh "$@"
		rc=$?
		rm -rf $W
		exit $rc
	fi
done
ui "ERROR: no gts9wifi/install.sh, android/restore.sh or ubuntu/restore.sh in the zip"
rm -rf $W
exit 1
