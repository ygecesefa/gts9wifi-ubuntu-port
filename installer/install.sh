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
#      partition GTS9W_BACK; Ubuntu itself takes them into its "Switch to
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
	ui "HATA: $*"
	ui "Acilis bolumleri degistirilmedi; tablet onceki sistemiyle acilir."
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
	ui "  Ses Ac  = EVET"
	ui "  Ses Kis = HAYIR   (60 sn cevap yoksa: HAYIR)"
	$TOOL keys 60
	[ $? = 0 ]
}

rm -rf $W
mkdir -p $W/pay $W/android
ui "=============================================="
ui " Ubuntu 24.04 - Galaxy Tab S9 Wi-Fi (SM-X710)"
ui " microSD kurulumu"
ui "=============================================="

# ---- 1. checks ----------------------------------------------------------
dev=$(getprop ro.product.device)
case "$dev $(getprop ro.build.product) $(getprop ro.boot.hardware.sku 2>/dev/null)" in
	*gts9wifi*) ;;
	*) fail "Bu zip yalnizca SM-X710 (gts9wifi) icin (cihaz: $dev)" ;;
esac

[ -b $SD ] || fail "microSD kart bulunamadi ($SD)"
[ "$(cat /sys/block/mmcblk1/device/type 2>/dev/null)" = SD ] || fail "$SD bir SD kart degil"
for name in boot init_boot vendor_boot dtbo; do
	part=$BB/$name
	[ -e $part ] || fail "Bolum yok: $part"
	case "$(readlink -f $part)" in
		/dev/block/sd[a-f][0-9]*) ;;
		*) fail "$part beklenmeyen hedef: $(readlink -f $part)" ;;
	esac
	[ "$(blockdev --getsize64 $part)" = "$(size_of $name)" ] || fail "$name bolum boyutu beklenmeyen"
done

ui "Paket /tmp'ye aliniyor ve dogrulaniyor..."
free_kb=$(df -k /tmp | tail -1 | tr -s ' ' | cut -d' ' -f4)
[ "${free_kb:-0}" -gt 2500000 ] || fail "/tmp'de yer yok (${free_kb} KB)"
for f in SHA256SUMS sd.img.zst boot.img init_boot.img vendor_boot.img dtbo.img \
	restore.sh version.txt; do
	$TOOL extract "$ZIPFILE" $P/$f $W/pay/$f || fail "Zip'ten cikarilamadi: $f"
done
for f in sd.img.zst boot.img init_boot.img vendor_boot.img dtbo.img restore.sh; do
	[ "$(sha $W/pay/$f)" = "$(want $f $W/pay/SHA256SUMS)" ] || fail "sha256 uyusmuyor: $f"
done
raw_size=$(grep '^raw_size ' $W/pay/SHA256SUMS | cut -d' ' -f2)
raw_sha=$(want sd.img $W/pay/SHA256SUMS)
card=$(blockdev --getsize64 $SD)
[ "$card" -ge "$raw_size" ] || fail "SD kart kucuk: $card bayt, en az $raw_size gerekli"
ui "Paket OK: $(cat $W/pay/version.txt)"

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
					ui "Eski Android yedegi bulundu: $p"
					return 0
				fi
			done
			umount $W/old
		done
	done
	return 1
}

ui ""
ui "Android acilis imajlari yedekleniyor..."
backup=none
if is_ubuntu_set; then
	ui "Bolumlerde zaten Ubuntu acilis seti var; Android yedegi kartta araniyor."
	if rescue_backup; then
		backup=card
	elif ask "Android yedegi BULUNAMADI. Devam edilirse Android'e donmek" \
		"icin kendi yedeginiz ya da PC'den fastboot gerekir." "Yine de devam edilsin mi?"; then
		backup=none
	else
		fail "Iptal edildi (Android yedegi yok)"
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
		android/info.txt=$W/android/info.txt || fail "android-restore.zip olusturulamadi"
	# Read the images back out of the new zip before anything is erased.
	for name in boot init_boot vendor_boot dtbo; do
		$TOOL extract $W/android-restore.zip android/$name.img $W/check.img &&
		[ "$(sha $W/check.img)" = "$(want $name.img $W/android/SHA256SUMS)" ] ||
			fail "android-restore.zip dogrulanamadi ($name)"
	done
	rm -f $W/check.img
	ui "android-restore.zip hazir ve dogrulandi."
fi

# ---- 3. confirm ------------------------------------------------------------
ask "DIKKAT: microSD karttaki HER SEY SILINECEK" \
	"($((card / 1000000000)) GB) ve Ubuntu kurulacak." \
	"Android ve dahili depolama degismez." \
	"Devam edilsin mi?" || fail "Iptal edildi; hicbir sey yazilmadi"

# ---- 4. microSD ------------------------------------------------------------
for m in $(grep "^$SD" /proc/mounts | cut -d' ' -f2); do
	umount "$m" || fail "SD kart ayrilamadi: $m"
done
ui ""
ui "Ubuntu SD karta yaziliyor (birkac dakika)..."
{ $TOOL unzstd $W/pay/sd.img.zst $SD; echo "rc $?"; } | while read pct rc; do
	if [ "$pct" = rc ]; then echo $rc > $W/unzstd.rc; else ui "  %$pct"; fi
done
[ "$(cat $W/unzstd.rc 2>/dev/null)" = 0 ] || fail "SD karta yazilamadi; acilis bolumleri DEGISMEDI"
rm -f $W/pay/sd.img.zst
sync
ui "Okunarak dogrulaniyor..."
[ "$(head -c $raw_size $SD | sha256sum | cut -d' ' -f1)" = "$raw_sha" ] ||
	fail "SD kart yazma dogrulamasi basarisiz; acilis bolumleri DEGISMEDI"
blockdev --rereadpt $SD
i=0
while [ ! -b ${SD}p3 ] && [ $i -lt 20 ]; do sleep 0.5; i=$((i + 1)); done
[ -b ${SD}p1 ] && [ -b ${SD}p3 ] || fail "SD bolumleri gorunmedi; acilis bolumleri DEGISMEDI"
ui "SD kart OK."

# ---- 5. backups onto the card ----------------------------------------------
if [ $backup != none ]; then
	mkdir -p $W/back
	mount -t vfat ${SD}p1 $W/back || fail "GTS9W_BACK baglanamadi"
	mkdir -p $W/back/android
	cp $W/android-restore.zip $W/back/ &&
	cp $W/android/*.img $W/android/SHA256SUMS $W/android/info.txt $W/back/android/ ||
		fail "Yedek SD karta yazilamadi"
	sync
	[ "$(sha $W/back/android-restore.zip)" = "$(sha $W/android-restore.zip)" ] ||
		fail "SD karttaki android-restore.zip dogrulanamadi"
	for name in boot init_boot vendor_boot dtbo; do
		[ "$(sha $W/back/android/$name.img)" = "$(want $name.img $W/android/SHA256SUMS)" ] ||
			fail "SD karttaki android/$name.img dogrulanamadi"
	done
	umount $W/back
	ui "Android yedegi SD karta yazildi (GTS9W_BACK)."
	ui "Ubuntu ilk acilista onu 'Android'e Gec' icin alir."
fi

# ---- 6. Ubuntu boot images ---------------------------------------------------
ui ""
ui "Ubuntu acilis imajlari yaziliyor..."
for name in boot init_boot vendor_boot dtbo; do
	dd if=$W/pay/$name.img of=$BB/$name bs=4194304 2>/dev/null || fail "$name yazilamadi"
done
sync
for name in boot init_boot vendor_boot dtbo; do
	[ "$(head -c $(size_of $name) $BB/$name | sha256sum | cut -d' ' -f1)" = \
		"$(want $name.img $W/pay/SHA256SUMS)" ] || {
		ui "HATA: $name yazma dogrulamasi basarisiz."
		ui "Yeniden baslatmadan once GTS9W_BACK/android-restore.zip'i flashlayin."
		cleanup
		exit 1
	}
done

ui ""
ui "=============================================="
ui " KURULUM TAMAM. Yeniden baslatin: Ubuntu acilir."
ui " Kullanici: ubuntu   Parola: ubuntu"
ui ""
if [ $backup != none ]; then
	ui " Android yedegi SD kartta:"
	ui "   GTS9W_BACK/android-restore.zip"
	ui " Android'e donmek icin recovery'de bu zip'i"
	ui " flashlayin (ya da Ubuntu'da 'Android'e Gec')."
else
	ui " UYARI: Android yedegi alinmadi."
fi
ui ""
ui " Parmak izi icin bir kez Android'den to-ubuntu.sh"
ui " ile gecin (kalibrasyon yalnizca Android'de)."
ui "=============================================="
cleanup
exit 0
