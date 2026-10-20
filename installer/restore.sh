#!/sbin/sh
# android-restore.zip for the Galaxy Tab S9 Wi-Fi (SM-X710, gts9wifi).
# Built ON THE TABLET by the Ubuntu installer zip from this tablet's own
# Android boot images, before Ubuntu was written; stored on the microSD as
# GTS9W_BACK/android-restore.zip.  Flashing it in recovery writes those
# images back to boot, init_boot, vendor_boot and dtbo (nothing else) and
# verifies them.  The Ubuntu microSD itself is left as it is.
#
# Started by the zip's update-binary loader (installer/update-binary.sh),
# which provides GTS9W_TOOL:  restore.sh <api> <OUTFD> <ZIPFILE>
set -u

OUTFD=$2
ZIPFILE=$3
W=/tmp/gts9w-restore
TOOL=${GTS9W_TOOL:?started by update-binary}
BB=/dev/block/by-name

ui() { printf 'ui_print %s\nui_print\n' "$*" >> /proc/self/fd/$OUTFD; }
fail() {
	ui ""
	ui "HATA: $*"
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

rm -rf $W
mkdir -p $W
ui "=============================================="
ui " Android'e donus - Galaxy Tab S9 Wi-Fi (SM-X710)"
ui "=============================================="
dev=$(getprop ro.product.device)
case "$dev $(getprop ro.build.product)" in
	*gts9wifi*) ;;
	*) fail "Bu zip yalnizca SM-X710 (gts9wifi) icin (cihaz: $dev)" ;;
esac

for f in SHA256SUMS info.txt boot.img init_boot.img vendor_boot.img dtbo.img; do
	$TOOL extract "$ZIPFILE" android/$f $W/$f || fail "Zip'ten cikarilamadi: $f"
done
while read -r line; do ui "$line"; done < $W/info.txt
for name in boot init_boot vendor_boot dtbo; do
	part=$BB/$name
	[ -e $part ] || fail "Bolum yok: $part"
	case "$(readlink -f $part)" in
		/dev/block/sd[a-f][0-9]*) ;;
		*) fail "$part beklenmeyen hedef" ;;
	esac
	[ "$(blockdev --getsize64 $part)" = "$(size_of $name)" ] || fail "$name bolum boyutu beklenmeyen"
	[ "$(stat -c %s $W/$name.img)" = "$(size_of $name)" ] || fail "$name imaj boyutu beklenmeyen"
	[ "$(sha $W/$name.img)" = "$(want $name.img)" ] || fail "sha256 uyusmuyor: $name"
done
ui "Yedek OK."

ui ""
ui "Android acilis imajlari geri yuklenecek"
ui "(boot, init_boot, vendor_boot, dtbo)."
ui "Ubuntu SD kartta kalir. Devam edilsin mi?"
ui "  Ses Ac  = EVET"
ui "  Ses Kis = HAYIR   (60 sn cevap yoksa: HAYIR)"
$TOOL keys 60 || fail "Iptal edildi; hicbir sey yazilmadi"

for name in boot init_boot vendor_boot dtbo; do
	ui "Yaziliyor: $name"
	dd if=$W/$name.img of=$BB/$name bs=4194304 2>/dev/null || fail "$name yazilamadi"
done
sync
for name in boot init_boot vendor_boot dtbo; do
	[ "$(head -c $(size_of $name) $BB/$name | sha256sum | cut -d' ' -f1)" = "$(want $name.img)" ] ||
		fail "$name yazma dogrulamasi basarisiz; yeniden baslatmayin, zip'i tekrar flashlayin"
done
rm -rf $W
ui ""
ui "TAMAM: Android acilis imajlari geri yuklendi ve dogrulandi."
ui "Yeniden baslatin: Android acilir."
exit 0
