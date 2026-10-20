#!/system/bin/sh
# Android -> Ubuntu on the Galaxy Tab S9 Wi-Fi (gts9wifi, SM-X710).
#
# Adapted from the Fedora gts9wifi port's to-fedora.sh.  Writes the four Linux
# boot images to boot, init_boot, vendor_boot and dtbo, then reboots.  vbmeta
# is never touched.  Run from a root shell (Magisk su).  On the way it copies
# the fingerprint sensor's calibration to the Ubuntu root on the microSD.
#
# Images:  /data/media/0/Ubuntu/images/{boot,init_boot,vendor_boot,dtbo}.img
#          plus SHA256SUMS produced by build-gts9wifi-bundle.sh
set -eu

BASE="/data/media/0/Ubuntu/images"
BB="/dev/block/by-name"
# Factory calibration of this tablet's fingerprint sensor.  It only exists in
# Android's encrypted /data, is unique to each unit and is never shipped in the
# image; Ubuntu's EL721 driver reads it from FP_DEST on the microSD root.
FP_SRC="/data/vendor/biometrics/meta"
FP_DEST="var/lib/gts9wifi/fingerprint/firmware"
FP_MNT="/data/local/tmp/gts9w-root"

# Hand calib.dat and egoptbds.dat to Ubuntu.  Cards with the FAT partition
# GTS9W_BACK (v0.2.0-pre3 layout): into GTS9W_BACK/fingerprint/, which Ubuntu's
# gts9wifi-import-backup installs at boot.  Older cards: straight into the
# Ubuntu root, when missing there or different.  Best effort: any problem is
# reported and the switch to Ubuntu goes on (only the fingerprint needs them).
copy_fp_to_back() {
    back=$(blkid 2>/dev/null | grep 'LABEL="GTS9W_BACK"' | cut -d: -f1 || true)
    case "$back" in
        /dev/block/mmcblk1p[0-9]*) ;;
        *) return 1 ;;
    esac
    # Android's vold usually has it mounted already (it is the card's FAT).
    dir=$(grep "^$back " /proc/mounts | cut -d' ' -f2 | head -1 || true)
    mounted=0
    if [ -z "$dir" ]; then
        mkdir -p "$FP_MNT"
        mount -t vfat "$back" "$FP_MNT" || { echo "UYARI: $back bağlanamadı"; return 0; }
        dir=$FP_MNT; mounted=1
    fi
    mkdir -p "$dir/fingerprint"
    ok=1
    for f in calib.dat egoptbds.dat; do
        cp "$FP_SRC/$f" "$dir/fingerprint/.$f.new" && mv "$dir/fingerprint/.$f.new" "$dir/fingerprint/$f" || ok=0
    done
    (cd "$dir/fingerprint" && sha256sum calib.dat egoptbds.dat > SHA256SUMS) || ok=0
    (cd "$FP_SRC" && sha256sum calib.dat egoptbds.dat) | cmp -s - "$dir/fingerprint/SHA256SUMS" || ok=0
    sync
    [ $mounted = 1 ] && { umount "$FP_MNT" || true; rmdir "$FP_MNT" 2>/dev/null || true; }
    if [ $ok = 1 ]; then echo "OK: parmak izi kalibrasyonu GTS9W_BACK/fingerprint'e yazıldı (sha256 doğru)"
    else echo "UYARI: kalibrasyon GTS9W_BACK'e yazılamadı"; fi
    return 0
}

copy_fp_calibration() {
    for f in calib.dat egoptbds.dat; do
        [ -f "$FP_SRC/$f" ] || { echo "UYARI: $FP_SRC/$f yok; parmak izi kalibrasyonu aktarılmadı"; return 0; }
    done
    copy_fp_to_back && return 0
    root=$(blkid 2>/dev/null | grep 'LABEL="GTS9W_ROOT"' | cut -d: -f1 || true)
    case "$root" in
        /dev/block/mmcblk1p[0-9]*) ;;
        *) echo "UYARI: SD kartta GTS9W_ROOT bulunamadı ($root); kalibrasyon aktarılmadı"; return 0 ;;
    esac
    if grep -q "^$root " /proc/mounts; then
        echo "UYARI: $root zaten bağlı; kalibrasyon aktarılmadı"; return 0
    fi
    mkdir -p "$FP_MNT"
    mount -t ext4 -o rw,noatime,nosuid,nodev,noexec "$root" "$FP_MNT" || {
        echo "UYARI: $root bağlanamadı; kalibrasyon aktarılmadı"; rmdir "$FP_MNT" 2>/dev/null || true; return 0; }
    [ -d "$FP_MNT/usr/lib/gts9wifi" ] || {
        echo "UYARI: $root bir gts9wifi Ubuntu kökü değil; kalibrasyon aktarılmadı"
        umount "$FP_MNT" || true; rmdir "$FP_MNT" 2>/dev/null || true; return 0; }
    dest="$FP_MNT/$FP_DEST"
    ok=1
    for f in calib.dat egoptbds.dat; do
        want=$(sha256sum "$FP_SRC/$f" | cut -d' ' -f1)
        if [ -f "$dest/$f" ] && [ "$(sha256sum "$dest/$f" | cut -d' ' -f1)" = "$want" ]; then
            echo "OK: $f zaten Ubuntu'da"
            continue
        fi
        mkdir -p "$dest" && chmod 700 "$FP_MNT/var/lib/gts9wifi/fingerprint" "$dest" &&
        cp "$FP_SRC/$f" "$dest/.$f.new" && chown 0:0 "$dest/.$f.new" && chmod 600 "$dest/.$f.new" &&
        [ "$(sha256sum "$dest/.$f.new" | cut -d' ' -f1)" = "$want" ] && mv "$dest/.$f.new" "$dest/$f" ||
            { echo "UYARI: $f kopyalanamadı"; rm -f "$dest/.$f.new"; ok=0; continue; }
        echo "OK: $f Ubuntu'ya kopyalandı (sha256 doğru)"
    done
    sync
    umount "$FP_MNT" && rmdir "$FP_MNT" 2>/dev/null || true
    [ "$ok" = 1 ] || echo "UYARI: parmak izi kalibrasyonu eksik kaldı"
    return 0
}

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

copy_fp_calibration

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
