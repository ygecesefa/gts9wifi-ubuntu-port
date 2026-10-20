#!/bin/bash
# Build the gts9wifi microSD image from the stage A rootfs.
#
#   p1  FAT32 GTS9W_BACK  512 MiB   Android boot-set backup + restore zip, written
#                                   by the recovery installer; FAT so that any
#                                   recovery (and Android) can read it
#   p2  ext4  GTS9W_BOOT  512 MiB   /boot (kernel, initramfs, DTB copies)
#   p3  ext4  GTS9W_ROOT  rest      /     (grown to the whole card on first boot)
#
# MBR, 512-byte sectors (the X710 microSD uses 512-byte logical sectors).
# The image is kept small so writing it over adb is quick; the
# gts9wifi-grow-rootfs service expands p3 (the last partition) on the card.
# Ubuntu finds every partition by label, never by number.
#
# Needs root (loop devices).  Never touches a real block device.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
root=${GTS9WIFI_ROOT:-$(dirname "$repo")}
rootfs=${ROOTFS_DIR:-$root/build/gts9wifi-rootfs}
out=${SD_IMAGE_OUT:-$root/build/gts9wifi-sd.img}
slack_mib=${SLACK_MIB:-3072}
boot_mib=512
back_mib=512

[ "$(id -u)" = 0 ] || { echo 'run as root' >&2; exit 1; }
test -d "$rootfs/etc" || { echo "missing rootfs: $rootfs" >&2; exit 1; }

used_mib=$(du -sm --exclude=./boot "$rootfs" | cut -f1)
root_mib=$(( (used_mib * 115 / 100) + slack_mib ))
total_mib=$(( 4 + back_mib + boot_mib + root_mib ))
echo "== image: ${total_mib} MiB (rootfs ${used_mib} MiB used, p3 ${root_mib} MiB)"

rm -f "$out"
truncate -s "${total_mib}M" "$out"
sfdisk --quiet "$out" <<EOF
label: dos
unit: sectors
sector-size: 512
start=8192, size=$((back_mib * 2048)), type=c
start=$((8192 + back_mib * 2048)), size=$((boot_mib * 2048)), type=83
start=$((8192 + (back_mib + boot_mib) * 2048)), type=83
EOF

loop=$(losetup --show -f -P "$out")
mnt=$(mktemp -d)
cleanup() {
	umount -R "$mnt" 2>/dev/null || true
	losetup -d "$loop" 2>/dev/null || true
	rmdir "$mnt" 2>/dev/null || true
}
trap cleanup EXIT

mkfs.vfat -F 32 -n GTS9W_BACK "${loop}p1" >/dev/null
mkfs.ext4 -q -L GTS9W_BOOT "${loop}p2"
mkfs.ext4 -q -L GTS9W_ROOT "${loop}p3"
mount "${loop}p1" "$mnt"
cp "$repo/installer/GTS9W_BACK-README.txt" "$mnt/README.txt"
umount "$mnt"
mount "${loop}p3" "$mnt"
mkdir -p "$mnt/boot"
mount "${loop}p2" "$mnt/boot"

echo "== copying rootfs"
# Only versioned trees belong in /usr/lib/modules; skip anything a broken
# earlier build may have copied to its top level.
rsync -aHAX --numeric-ids \
	--exclude='/usr/lib/modules/kernel' --exclude='/usr/lib/modules/modules.*' \
	"$rootfs/" "$mnt/"

for f in etc/fstab boot/dtbs/sm8550-samsung-gts9wifi.dtb; do
	test -e "$mnt/$f" || { echo "missing in image: $f" >&2; exit 1; }
done
grep -q 'LABEL=GTS9W_ROOT' "$mnt/etc/fstab" || { echo 'fstab does not mount GTS9W_ROOT' >&2; exit 1; }
ls "$mnt"/boot/initrd.img-* >/dev/null

sync
umount "$mnt/boot" "$mnt"
e2fsck -fy "${loop}p2" >/dev/null || true
e2fsck -fy "${loop}p3" >/dev/null || true
blkid "${loop}p1" "${loop}p2" "${loop}p3"
cleanup
trap - EXIT

echo "== compressing"
zstd -T0 -10 -f -q "$out" -o "$out.zst"
sha256sum "$out" "$out.zst" > "$out.SHA256SUMS"
ls -l "$out" "$out.zst"
