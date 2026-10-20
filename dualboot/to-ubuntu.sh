#!/system/bin/sh
# Android -> Ubuntu on the Galaxy Tab S9 Wi-Fi (gts9wifi, SM-X710).
#
# Adapted from the Fedora gts9wifi port's to-fedora.sh.  Writes the four Linux
# boot images to boot, init_boot, vendor_boot and dtbo, then reboots.  vbmeta
# is never touched.  Run from a root shell (Magisk su).  On the way it copies
# the fingerprint sensor's calibration to the microSD for Ubuntu.
#
# Without root, flash GTS9W_BACK/ubuntu-boot.zip in recovery instead.  The
# Magisk module (installer/magisk) runs this with --yes (no prompt) and
# GTS9W_TOOL (its gts9w-tool, to unpack the zip without Android's unzip).
#
# Images:
#   1. GTS9W_BACK/ubuntu-boot.zip on the microSD: made with the image on that
#      card, so kernel and modules always match.  Required on such cards.
#   2. only for older cards without GTS9W_BACK (v0.2.0-pre1/pre2 layout):
#      /data/media/0/Ubuntu/images/{boot,init_boot,vendor_boot,dtbo}.img plus
#      SHA256SUMS (build-gts9wifi-bundle.sh)
set -eu

BASE="/data/media/0/Ubuntu/images"
BB="/dev/block/by-name"
UNPACK="/data/local/tmp/gts9w-ubuntu-boot"
BACK_MNT="/data/local/tmp/gts9w-back"
# Factory calibration of this tablet's fingerprint sensor.  It only exists in
# Android's encrypted /data, is unique to each unit and is never shipped in the
# image; Ubuntu's EL721 driver reads it from FP_DEST on the microSD root.
FP_SRC="/data/vendor/biometrics/meta"
FP_DEST="var/lib/gts9wifi/fingerprint/firmware"
FP_MNT="/data/local/tmp/gts9w-root"

BACK_DIR=""
BACK_MOUNTED=0
cleanup() {
    rm -rf "$UNPACK"
    if [ $BACK_MOUNTED = 1 ]; then
        umount "$BACK_MNT" 2>/dev/null || true
        rmdir "$BACK_MNT" 2>/dev/null || true
        BACK_MOUNTED=0
    fi
}
trap cleanup EXIT

# The card's FAT partition GTS9W_BACK (v0.2.0-pre3 layout and later).  Android's
# vold usually has it mounted already; otherwise mount it here.
open_back() {
    [ -n "$BACK_DIR" ] && return 0
    back=$(blkid 2>/dev/null | grep 'LABEL="GTS9W_BACK"' | cut -d: -f1 || true)
    case "$back" in
        /dev/block/mmcblk1p[0-9]*) ;;
        *) return 1 ;;
    esac
    BACK_DIR=$(grep "^$back " /proc/mounts | cut -d' ' -f2 | head -1 || true)
    if [ -z "$BACK_DIR" ]; then
        mkdir -p "$BACK_MNT"
        mount -t vfat "$back" "$BACK_MNT" || { echo "WARNING: could not mount $back"; return 1; }
        BACK_DIR=$BACK_MNT; BACK_MOUNTED=1
    fi
    return 0
}

# Hand calib.dat and egoptbds.dat to Ubuntu.  Cards with GTS9W_BACK: into
# GTS9W_BACK/fingerprint/, which Ubuntu's gts9wifi-import-backup installs at
# boot.  Older cards: straight into the Ubuntu root, when missing there or
# different.  Best effort: any problem is reported and the switch to Ubuntu
# goes on (only the fingerprint needs them).
copy_fp_to_back() {
    open_back || return 1
    dir=$BACK_DIR
    mkdir -p "$dir/fingerprint"
    ok=1
    for f in calib.dat egoptbds.dat; do
        cp "$FP_SRC/$f" "$dir/fingerprint/.$f.new" && mv "$dir/fingerprint/.$f.new" "$dir/fingerprint/$f" || ok=0
    done
    (cd "$dir/fingerprint" && sha256sum calib.dat egoptbds.dat > SHA256SUMS) || ok=0
    (cd "$FP_SRC" && sha256sum calib.dat egoptbds.dat) | cmp -s - "$dir/fingerprint/SHA256SUMS" || ok=0
    sync
    if [ $ok = 1 ]; then echo "OK: fingerprint calibration written to GTS9W_BACK/fingerprint (sha256 verified)"
    else echo "WARNING: could not write the calibration to GTS9W_BACK"; fi
    return 0
}

copy_fp_calibration() {
    for f in calib.dat egoptbds.dat; do
        [ -f "$FP_SRC/$f" ] || { echo "WARNING: no $FP_SRC/$f; fingerprint calibration not copied"; return 0; }
    done
    copy_fp_to_back && return 0
    root=$(blkid 2>/dev/null | grep 'LABEL="GTS9W_ROOT"' | cut -d: -f1 || true)
    case "$root" in
        /dev/block/mmcblk1p[0-9]*) ;;
        *) echo "WARNING: no GTS9W_ROOT on the SD card ($root); calibration not copied"; return 0 ;;
    esac
    if grep -q "^$root " /proc/mounts; then
        echo "WARNING: $root is already mounted; calibration not copied"; return 0
    fi
    mkdir -p "$FP_MNT"
    mount -t ext4 -o rw,noatime,nosuid,nodev,noexec "$root" "$FP_MNT" || {
        echo "WARNING: could not mount $root; calibration not copied"; rmdir "$FP_MNT" 2>/dev/null || true; return 0; }
    [ -d "$FP_MNT/usr/lib/gts9wifi" ] || {
        echo "WARNING: $root is not a gts9wifi Ubuntu root; calibration not copied"
        umount "$FP_MNT" || true; rmdir "$FP_MNT" 2>/dev/null || true; return 0; }
    dest="$FP_MNT/$FP_DEST"
    ok=1
    for f in calib.dat egoptbds.dat; do
        want=$(sha256sum "$FP_SRC/$f" | cut -d' ' -f1)
        if [ -f "$dest/$f" ] && [ "$(sha256sum "$dest/$f" | cut -d' ' -f1)" = "$want" ]; then
            echo "OK: $f already in Ubuntu"
            continue
        fi
        mkdir -p "$dest" && chmod 700 "$FP_MNT/var/lib/gts9wifi/fingerprint" "$dest" &&
        cp "$FP_SRC/$f" "$dest/.$f.new" && chown 0:0 "$dest/.$f.new" && chmod 600 "$dest/.$f.new" &&
        [ "$(sha256sum "$dest/.$f.new" | cut -d' ' -f1)" = "$want" ] && mv "$dest/.$f.new" "$dest/$f" ||
            { echo "WARNING: could not copy $f"; rm -f "$dest/.$f.new"; ok=0; continue; }
        echo "OK: $f copied to Ubuntu (sha256 verified)"
    done
    sync
    umount "$FP_MNT" && rmdir "$FP_MNT" 2>/dev/null || true
    [ "$ok" = 1 ] || echo "WARNING: fingerprint calibration incomplete"
    return 0
}

# Prefer the boot set that came with the card (see the header).  A card with
# GTS9W_BACK always has its ubuntu-boot.zip: without it, stop rather than
# write /data/media/0/Ubuntu/images, which may belong to another build (a
# kernel without matching modules boots without Wi-Fi).
pick_images() {
    open_back || return 0
    zip="$BACK_DIR/ubuntu-boot.zip"
    [ -f "$zip" ] || { echo "ERROR: no ubuntu-boot.zip on GTS9W_BACK"; exit 1; }
    rm -rf "$UNPACK"
    mkdir -p "$UNPACK"
    if [ -n "${GTS9W_TOOL:-}" ]; then
        mkdir -p "$UNPACK/ubuntu"
        for f in SHA256SUMS boot.img init_boot.img vendor_boot.img dtbo.img; do
            "$GTS9W_TOOL" extract "$zip" "ubuntu/$f" "$UNPACK/ubuntu/$f" || rm -f "$UNPACK/ubuntu/SHA256SUMS"
        done
    else
        unzip -o -q "$zip" 'ubuntu/*' -d "$UNPACK" 2>/dev/null || true
    fi
    if [ -f "$UNPACK/ubuntu/SHA256SUMS" ]; then
        BASE="$UNPACK/ubuntu"
        echo "Boot images: GTS9W_BACK/ubuntu-boot.zip (built with this card)"
    else
        echo "ERROR: could not unpack $zip"; exit 1
    fi
}

[ "$(id -u)" = 0 ] || { echo "ERROR: root needed (su), or flash GTS9W_BACK/ubuntu-boot.zip in recovery"; exit 1; }
[ "$(getprop ro.product.device)" = "gts9wifi" ] || { echo "ERROR: this device is not a gts9wifi!"; exit 1; }
pick_images
[ -f "$BASE/SHA256SUMS" ] || { echo "ERROR: no $BASE/SHA256SUMS"; exit 1; }

for name in boot init_boot vendor_boot dtbo; do
    case "$name" in
        boot|vendor_boot) expected=100663296 ;;
        init_boot) expected=8388608 ;;
        dtbo) expected=16777216 ;;
    esac
    img="$BASE/$name.img"
    part="$BB/$name"
    [ -f "$img" ] || { echo "ERROR: missing image: $img"; exit 1; }
    [ -e "$part" ] || { echo "ERROR: missing partition: $part"; exit 1; }
    case "$(readlink -f "$part")" in
        /dev/block/sd[a-f][0-9]*) ;;
        *) echo "ERROR: $part points to an unexpected device: $(readlink -f "$part")"; exit 1 ;;
    esac
    actual=$(stat -c %s "$img")
    psize=$(blockdev --getsize64 "$part")
    [ "$actual" = "$expected" ] || { echo "ERROR: wrong size of $name image: $actual"; exit 1; }
    [ "$psize" = "$expected" ] || { echo "ERROR: wrong size of $name partition: $psize"; exit 1; }
    want=$(grep " $name.img\$" "$BASE/SHA256SUMS" | cut -d' ' -f1)
    have=$(sha256sum "$img" | cut -d' ' -f1)
    [ -n "$want" ] && [ "$want" = "$have" ] || { echo "ERROR: sha256 mismatch: $name"; exit 1; }
    echo "OK: $name ($actual bytes, sha256 verified)"
done

echo
echo "WARNING: the four boot partitions (boot, init_boot, vendor_boot, dtbo) will be rewritten."
echo "Back to Android: 'Switch to Android' in Ubuntu, or GTS9W_BACK/android-restore.zip in recovery."
if [ "${1:-}" != --yes ]; then
    echo "Type UBUNTU to continue:"
    read answer
    [ "$answer" = "UBUNTU" ] || { echo "Cancelled."; exit 0; }
fi

copy_fp_calibration

for name in boot init_boot vendor_boot dtbo; do
    echo "Writing: $name"
    dd if="$BASE/$name.img" of="$BB/$name" bs=4M
done
sync
for name in boot init_boot vendor_boot dtbo; do
    size=$(stat -c %s "$BASE/$name.img")
    want=$(grep " $name.img\$" "$BASE/SHA256SUMS" | cut -d' ' -f1)
    have=$(head -c "$size" "$BB/$name" | sha256sum | cut -d' ' -f1)
    [ "$want" = "$have" ] || { echo "ERROR: $name did not verify after writing - not rebooting"; exit 1; }
done
cleanup
echo "Written and verified; rebooting."
reboot
