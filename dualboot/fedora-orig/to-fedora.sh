#!/system/bin/sh
set -eu

BASE="/data/media/0/Fedora/images"
BB="/dev/block/by-name"

[ "$(getprop ro.product.device)" = "gts9wifi" ] || {
    echo "HATA: Cihaz gts9wifi değil!"
    exit 1
}

for name in boot init_boot vendor_boot dtbo; do
    case "$name" in
        boot|vendor_boot) expected=100663296 ;;
        init_boot) expected=8388608 ;;
        dtbo) expected=16777216 ;;
    esac

    img="$BASE/$name.img"
    part="$BB/$name"

    [ -f "$img" ] || {
        echo "HATA: İmaj bulunamadı: $img"
        exit 1
    }

    [ -e "$part" ] || {
        echo "HATA: Bölüm bulunamadı: $part"
        exit 1
    }

    actual=$(stat -c %s "$img")
    psize=$(blockdev --getsize64 "$part")

    [ "$actual" = "$expected" ] || {
        echo "HATA: $name imaj boyutu yanlış: $actual"
        exit 1
    }

    [ "$psize" = "$expected" ] || {
        echo "HATA: $name bölüm boyutu yanlış: $psize"
        exit 1
    }

    echo "OK: $name ($actual bayt)"
done

echo
echo "DİKKAT: Dört önyükleme bölümü değiştirilecek."
echo "Devam etmek için FEDORA yaz:"
read answer
[ "$answer" = "FEDORA" ] || {
    echo "İptal edildi."
    exit 0
}

for name in boot init_boot vendor_boot dtbo; do
    echo "Yazılıyor: $name"
    dd if="$BASE/$name.img" of="$BB/$name" bs=4M
done

sync
echo "Yazma tamamlandı; yeniden başlatılıyor."
reboot
