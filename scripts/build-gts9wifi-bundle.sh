#!/bin/bash
# Package the gts9wifi (SM-X710) kernel and Ubuntu initramfs as the Android
# boot header v4 images the X710 ABL boots.
#
# Layout is the one the Fedora gts9wifi port validated on this tablet:
#   boot.img         kernel + appended DTB, empty cmdline
#   init_boot.img    empty generic ramdisk (the 8 MiB partition cannot hold
#                    an initramfs with this kernel's modules)
#   vendor_boot.img  the full initramfs as the platform fragment + DTB +
#                    cmdline + bootconfig
#   dtbo.img         zero page, deliberately not a DT table, so ABL takes the
#                    appended-DTB fallback
# vbmeta is NOT produced: the Fedora switch scripts never write it and the
# tablet boots Linux with its current vbmeta.
#
# This script never flashes anything.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
root=${GTS9WIFI_ROOT:-$(dirname "$repo")}
tools=${ANDROID_TOOLS:-$root/fedora-ref/tools}
kernel_out=${KERNEL_OUT_DIR:-$root/build/gts9wifi-kernel/out}
rootfs=${ROOTFS_DIR:-$root/build/gts9wifi-rootfs}
out=${BUNDLE_OUT_DIR:-$root/build/gts9wifi-bundle}
cfg=$repo/configs/gts9wifi

krel=$(cat "$kernel_out/kernel.release")
initramfs=${INITRAMFS:-$rootfs/boot/initrd.img-$krel}
image=$kernel_out/Image.gz
dtb=$kernel_out/sm8550-samsung-gts9wifi.dtb

boot_size=100663296
init_boot_size=8388608
vendor_boot_size=100663296
dtbo_size=16777216

for f in "$tools/mkbootimg.py" "$tools/avbtool" "$image" "$dtb" "$initramfs" \
	"$cfg/cmdline.txt" "$cfg/bootconfig.txt"; do
	test -f "$f" || { echo "missing input: $f" >&2; exit 1; }
done

mkdir -p "$out"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

add_hash_footer() {
	local target=$1 partition=$2 size=$3 salt
	salt=$(sha256sum "$target" | cut -d' ' -f1)
	python3 "$tools/avbtool" add_hash_footer --image "$target" \
		--partition_name "$partition" --partition_size "$size" --salt "$salt"
}

cmdline=$(tr '\n' ' ' < "$cfg/cmdline.txt" | sed 's/[[:space:]]*$//')
grep -q 'root=LABEL=GTS9W_ROOT' <<<"$cmdline" || { echo 'cmdline has no GTS9W_ROOT root' >&2; exit 1; }

# The initramfs must reach ABL as an LZ4 legacy stream.
case $(head -c4 "$initramfs" | od -An -tx1 | tr -d ' \n') in
	02214c18) cp "$initramfs" "$tmp/initramfs.lz4" ;;
	1f8b*) gzip -dc "$initramfs" | lz4 -l -12 - "$tmp/initramfs.lz4" >/dev/null ;;
	*)  # initramfs-tools may emit a modern LZ4 frame; normalise it.
		lz4 -dc "$initramfs" | lz4 -l -12 - "$tmp/initramfs.lz4" >/dev/null ;;
esac
[ "$(head -c4 "$tmp/initramfs.lz4" | od -An -tx1 | tr -d ' \n')" = 02214c18 ] || {
	echo 'could not produce an LZ4 legacy initramfs' >&2; exit 1; }

echo "== boot.img (kernel $krel + appended DTB)"
cat "$image" "$dtb" > "$tmp/Image.gz-dtb"
python3 "$tools/mkbootimg.py" --kernel "$tmp/Image.gz-dtb" --cmdline '' \
	--header_version 4 --os_version 13 --os_patch_level 2025-07 -o "$out/boot.img"
add_hash_footer "$out/boot.img" boot "$boot_size"

echo "== init_boot.img (empty generic ramdisk)"
mkdir -p "$tmp/empty"
touch -d '@0' "$tmp/empty"
(cd "$tmp/empty" && find . -print0 | cpio --reproducible --null -o --format=newc 2>/dev/null) \
	| lz4 -l -12 - "$tmp/empty.lz4" >/dev/null
python3 "$tools/mkbootimg.py" --ramdisk "$tmp/empty.lz4" --header_version 4 -o "$out/init_boot.img"
add_hash_footer "$out/init_boot.img" init_boot "$init_boot_size"

echo "== vendor_boot.img (initramfs + DTB + cmdline + bootconfig)"
python3 "$tools/mkbootimg.py" \
	--ramdisk_type platform --ramdisk_name '' \
	--vendor_ramdisk_fragment "$tmp/initramfs.lz4" \
	--dtb "$dtb" --vendor_cmdline "$cmdline" --header_version 4 \
	--vendor_boot "$out/vendor_boot.img" \
	--base 0x80000000 --kernel_offset 0x8000 --ramdisk_offset 0x02000000 \
	--tags_offset 0x01e00000 --pagesize 4096 --dtb_offset 0x1f00000 \
	--vendor_bootconfig "$cfg/bootconfig.txt"
add_hash_footer "$out/vendor_boot.img" vendor_boot "$vendor_boot_size"

echo "== dtbo.img (zero page)"
rm -f "$out/dtbo.img"
truncate -s 4096 "$out/dtbo.img"
add_hash_footer "$out/dtbo.img" dtbo "$dtbo_size"

for spec in boot.img:$boot_size init_boot.img:$init_boot_size \
	vendor_boot.img:$vendor_boot_size dtbo.img:$dtbo_size; do
	name=${spec%%:*}; want=${spec##*:}
	got=$(stat -c %s "$out/$name")
	[ "$got" -eq "$want" ] || { echo "$name: expected $want, got $got" >&2; exit 1; }
done
rm -f "$out/vbmeta.img"
(cd "$out" && sha256sum boot.img init_boot.img vendor_boot.img dtbo.img > SHA256SUMS)
printf 'kernel_release=%s\ncmdline=%s\n' "$krel" "$cmdline" > "$out/bundle-info.txt"
cat "$out/SHA256SUMS"
