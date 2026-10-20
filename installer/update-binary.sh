#!/sbin/sh
# update-binary for the gts9wifi recovery zips (the Ubuntu installer and the
# android-restore.zip it builds on the tablet).  Like AnyKernel3's, it is only
# a loader: the work is done by the readable script next to it in the zip.
#   update-binary <api> <OUTFD> <ZIPFILE>
#
# gts9w-tool (static arm64: keys, extract, unzstd, zip; installer/gts9w-tool.c)
# is appended to this file, and the last 16 bytes are this script's length.
# The tool is carried inside the loader because a recovery is not guaranteed
# to have unzip.  It is cut out to /tmp, then used to extract the script:
#   gts9wifi/install.sh   in the installer zip
#   android/restore.sh    in android-restore.zip
OUTFD=$2
ZIPFILE=$3
W=/tmp/gts9w-loader

ui() { printf 'ui_print %s\nui_print\n' "$*" >> /proc/self/fd/$OUTFD; }

rm -rf $W
mkdir -p $W
total=$(stat -c %s "$0")
off=$(tail -c 16 "$0" | sed 's/^0*//')
off=${off:-0}
tail -c +$((off + 1)) "$0" | head -c $((total - 16 - off)) > $W/gts9w-tool
chmod 0755 $W/gts9w-tool
$W/gts9w-tool >/dev/null 2>&1
[ $? = 2 ] || { ui "HATA: gts9w-tool bu recovery'de calismiyor"; exit 1; }
cp "$0" $W/update-binary
SH=/sbin/sh
[ -x $SH ] || SH=sh

for s in gts9wifi/install.sh android/restore.sh; do
	if $W/gts9w-tool extract "$ZIPFILE" $s $W/script.sh 2>/dev/null; then
		GTS9W_TOOL=$W/gts9w-tool GTS9W_LOADER=$W/update-binary \
			$SH $W/script.sh "$@"
		rc=$?
		rm -rf $W
		exit $rc
	fi
done
ui "HATA: zip'te gts9wifi/install.sh ya da android/restore.sh yok"
rm -rf $W
exit 1
