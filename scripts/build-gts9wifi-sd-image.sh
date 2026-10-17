#!/bin/bash
# Build the gts9wifi microSD image from the stage A rootfs.
#
#   p1  ext4  GTS9W_BOOT  512 MiB   /boot (kernel, initramfs, DTB copies)
#   p2  ext4  GTS9W_ROOT  rest      /     (grown to the whole card on first boot)
#
# MBR, 512-byte sectors (the X710 microSD uses 512-byte logical sectors).
# The image is kept small so writing it over adb is quick; the
# gts9wifi-grow-rootfs service expands p2 on the card.
#
# Needs root (loop devices).  Never touches a real block device.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
root=${GTS9WIFI_ROOT:-$(dirname "$repo")}
rootfs=${ROOTFS_DIR:-$root/build/gts9wifi-rootfs}
out=${SD_IMAGE_OUT:-$root/build/gts9wifi-sd.img}
slack_mib=${SLACK_MIB:-3072}
boot_mib=512

[ "$(id -u)" = 0 ] || { echo 'run as root' >&2; exit 1; }
test -d "$rootfs/etc" || { echo "missing rootfs: $rootfs" >&2; exit 1; }

used_mib=$(du -sm --exclude=./boot "$rootfs" | cut -f1)
root_mib=$(( (used_mib * 115 / 100) + slack_mib ))
total_mib=$(( 4 + boot_mib + root_mib ))
echo "== image: ${total_mib} MiB (rootfs ${used_mib} MiB used, p2 ${root_mib} MiB)"

rm -f "$out"
truncate -s "${total_mib}M" "$out"
sfdisk --quiet "$out" <<EOF
label: dos
unit: sectors
sector-size: 512
start=8192, size=$((boot_mib * 2048)), type=83
start=$((8192 + boot_mib * 2048)), type=83
EOF

loop=$(losetup --show -f -P "$out")
mnt=$(mktemp -d)
cleanup() {
	umount -R "$mnt" 2>/dev/null || true
	losetup -d "$loop" 2>/dev/null || true
	rmdir "$mnt" 2>/dev/null || true
}
trap cleanup EXIT

mkfs.ext4 -q -L GTS9W_BOOT "${loop}p1"
mkfs.ext4 -q -L GTS9W_ROOT "${loop}p2"
mount "${loop}p2" "$mnt"
mkdir -p "$mnt/boot"
mount "${loop}p1" "$mnt/boot"

echo "== copying rootfs"
rsync -aHAX --numeric-ids "$rootfs/" "$mnt/"

for f in etc/fstab boot/dtbs/sm8550-samsung-gts9wifi.dtb; do
	test -e "$mnt/$f" || { echo "missing in image: $f" >&2; exit 1; }
done
grep -q 'LABEL=GTS9W_ROOT' "$mnt/etc/fstab" || { echo 'fstab does not mount GTS9W_ROOT' >&2; exit 1; }
ls "$mnt"/boot/initrd.img-* >/dev/null

sync
umount "$mnt/boot" "$mnt"
e2fsck -fy "${loop}p1" >/dev/null || true
e2fsck -fy "${loop}p2" >/dev/null || true
blkid "${loop}p1" "${loop}p2"
cleanup
trap - EXIT

echo "== compressing"
zstd -T0 -10 -f -q "$out" -o "$out.zst"
sha256sum "$out" "$out.zst" > "$out.SHA256SUMS"
ls -l "$out" "$out.zst"
