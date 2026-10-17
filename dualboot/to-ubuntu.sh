#!/system/bin/sh
# Android -> Ubuntu on the Galaxy Tab S9 Wi-Fi (gts9wifi, SM-X710).
#
# Adapted from the Fedora gts9wifi port's to-fedora.sh.  Writes the four Linux
# boot images to boot, init_boot, vendor_boot and dtbo, then reboots.  vbmeta
# is never touched.  Run from a root shell (Magisk su).
#
# Images:  /data/media/0/Ubuntu/images/{boot,init_boot,vendor_boot,dtbo}.img
#          plus SHA256SUMS produced by build-gts9wifi-bundle.sh
set -eu

BASE="/data/media/0/Ubuntu/images"
BB="/dev/block/by-name"

[ "$(id -u)" = 0 ] || { echo "HATA: root gerekli (su)"; exit 1; }
[ "$(getprop ro.product.device)" = "gts9wifi" ] || { echo "HATA: Cihaz gts9wifi değil!"; exit 1; }
[ -f "$BASE/SHA256SUMS" ] || { echo "HATA: $BASE/SHA256SUMS yok"; exit 1; }

for name in boot init_boot vendor_boot dtbo; do
    case "$name" in
        boot|vendor_boot) expected=100663296 ;;
        init_boot) expected=8388608 ;;
        dtbo) expected=16777216 ;;
    esac
    img="$BASE/$name.img"
    part="$BB/$name"
    [ -f "$img" ] || { echo "HATA: İmaj yok: $img"; exit 1; }
    [ -e "$part" ] || { echo "HATA: Bölüm yok: $part"; exit 1; }
    case "$(readlink -f "$part")" in
        /dev/block/sd[a-f][0-9]*) ;;
        *) echo "HATA: $part beklenmeyen hedef: $(readlink -f "$part")"; exit 1 ;;
    esac
    actual=$(stat -c %s "$img")
    psize=$(blockdev --getsize64 "$part")
    [ "$actual" = "$expected" ] || { echo "HATA: $name imaj boyutu yanlış: $actual"; exit 1; }
    [ "$psize" = "$expected" ] || { echo "HATA: $name bölüm boyutu yanlış: $psize"; exit 1; }
    want=$(grep " $name.img\$" "$BASE/SHA256SUMS" | cut -d' ' -f1)
    have=$(sha256sum "$img" | cut -d' ' -f1)
    [ -n "$want" ] && [ "$want" = "$have" ] || { echo "HATA: $name sha256 uyuşmuyor"; exit 1; }
    echo "OK: $name ($actual bayt, sha256 doğru)"
done

echo
echo "DİKKAT: Dört önyükleme bölümü (boot, init_boot, vendor_boot, dtbo) değiştirilecek."
echo "Android'e dönüş: Ubuntu'da 'Android'e Geç' ya da recovery'den yedek geri yükleme."
echo "Devam etmek için UBUNTU yaz:"
read answer
[ "$answer" = "UBUNTU" ] || { echo "İptal edildi."; exit 0; }

for name in boot init_boot vendor_boot dtbo; do
    echo "Yazılıyor: $name"
    dd if="$BASE/$name.img" of="$BB/$name" bs=4M
done
sync
for name in boot init_boot vendor_boot dtbo; do
    size=$(stat -c %s "$BASE/$name.img")
    want=$(grep " $name.img\$" "$BASE/SHA256SUMS" | cut -d' ' -f1)
    have=$(head -c "$size" "$BB/$name" | sha256sum | cut -d' ' -f1)
    [ "$want" = "$have" ] || { echo "HATA: $name yazma doğrulaması başarısız — yeniden başlatılmıyor"; exit 1; }
done
echo "Yazma doğrulandı; yeniden başlatılıyor."
reboot
