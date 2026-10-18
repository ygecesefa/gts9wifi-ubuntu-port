#!/bin/bash
# Rebuild the gts9wifi kernel in the existing source tree, together with its
# modules, after a local change (a new patch, a driver edit, a config tweak).
#
#   rebuild-gts9wifi-kernel-incremental.sh [--rootfs]
#
# build-gts9wifi-kernel.sh exports a fresh tree on every run; this script is
# the fast path for iterating on that tree.  It always rebuilds Image.gz, the
# DTB and every module in one make, because the kernel uses
# DEBUG_INFO_BTF_MODULES without MODULE_ALLOW_BTF_MISMATCH: modules built
# against an earlier vmlinux are refused at load time (this broke ath11k
# Wi-Fi on 2026-10-18 when only Image.gz was rebuilt).
#
# Outputs, in $KERNEL_WORKDIR/out:
#   Image.gz, sm8550-samsung-gts9wifi.dtb, config, kernel.release, SHA256SUMS
#   modules-root/                 the matching module tree
#   modules-<release>.tar.gz      that tree, for install-gts9wifi-modules-live.sh
# The previous Image.gz and module tree are kept as *.prev.
#
# --rootfs also installs the modules and kernel into the build rootfs and
# refreshes its initramfs, so build-gts9wifi-bundle.sh makes a vendor_boot
# that matches.  Nothing is written to the tablet.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
root=${GTS9WIFI_ROOT:-$(dirname "$repo")}
work=${KERNEL_WORKDIR:-$root/build/gts9wifi-kernel}
rootfs=${ROOTFS_DIR:-$root/build/gts9wifi-rootfs}
tree=$work/linux-src
out=$work/out
jobs=${JOBS:-$(nproc)}
with_rootfs=0
case ${1:-} in
	'') ;;
	--rootfs) with_rootfs=1 ;;
	*) echo "usage: $0 [--rootfs]" >&2; exit 1 ;;
esac

[ -f "$tree/.config" ] || { echo "no configured tree in $tree; run build-gts9wifi-kernel.sh" >&2; exit 1; }
cd "$tree"

echo "== 1/4 Image.gz, dtbs, modules (-j$jobs)"
make ARCH=arm64 LLVM=1 -j"$jobs" Image.gz dtbs modules > "$work/incr.log" 2>&1 || {
	tail -60 "$work/incr.log" >&2; exit 1; }
krel=$(make -s ARCH=arm64 LLVM=1 kernelrelease)

echo "== 2/4 modules_install ($krel)"
rm -rf "$out/modules-root.next"
make ARCH=arm64 LLVM=1 INSTALL_MOD_PATH="$out/modules-root.next" INSTALL_MOD_STRIP=1 \
	modules_install > "$work/modules_install.log" 2>&1 || {
	tail -40 "$work/modules_install.log" >&2; exit 1; }
mods=$out/modules-root.next/lib/modules/$krel
rm -f "$mods/build" "$mods/source"

# The image and the modules must come from the same vmlinux: compare the
# vermagic of a module with the release, and check that the module was
# finalised (BTF) after the vmlinux that was just linked.
ko=drivers/net/wireless/ath/ath11k/ath11k_pci.ko
[ -f "$ko" ] || { echo "$ko was not built" >&2; exit 1; }
modinfo -F vermagic "$ko" | grep -q "^$krel " || { echo "vermagic of $ko does not match $krel" >&2; exit 1; }
[ "$ko" -nt vmlinux ] || { echo "$ko is older than vmlinux (stale BTF)" >&2; exit 1; }

echo "== 3/4 collect outputs"
[ -f "$out/Image.gz" ] && cp "$out/Image.gz" "$out/Image.gz.prev"
rm -rf "$out/modules-root.prev"
[ -d "$out/modules-root" ] && mv "$out/modules-root" "$out/modules-root.prev"
mv "$out/modules-root.next" "$out/modules-root"
cp arch/arm64/boot/Image.gz "$out/Image.gz"
cp arch/arm64/boot/dts/qcom/sm8550-samsung-gts9wifi.dtb "$out/"
cp .config "$out/config"
echo "$krel" > "$out/kernel.release"
tar -C "$out/modules-root/lib/modules" -czf "$out/modules-$krel.tar.gz.tmp" "$krel"
mv "$out/modules-$krel.tar.gz.tmp" "$out/modules-$krel.tar.gz"
(cd "$out" && sha256sum Image.gz sm8550-samsung-gts9wifi.dtb config "modules-$krel.tar.gz" > SHA256SUMS)

if [ "$with_rootfs" = 1 ]; then
	echo "== 4/4 install into $rootfs and refresh its initramfs"
	[ -x "$rootfs/usr/sbin/update-initramfs" ] || { echo "no rootfs at $rootfs" >&2; exit 1; }
	sudo rm -rf "$rootfs/usr/lib/modules/$krel"
	sudo cp -a --no-preserve=ownership "$out/modules-root/lib/modules/$krel" "$rootfs/usr/lib/modules/$krel"
	sudo cp "$out/Image.gz" "$rootfs/boot/vmlinuz-$krel"
	sudo chroot "$rootfs" depmod -a "$krel"
	mounted=()
	cleanup() { for ((i=${#mounted[@]}-1; i>=0; i--)); do sudo umount "${mounted[i]}"; done; }
	trap cleanup EXIT
	for d in proc sys dev; do sudo mount --bind "/$d" "$rootfs/$d"; mounted+=("$rootfs/$d"); done
	sudo chroot "$rootfs" update-initramfs -u -k "$krel"
	cleanup; mounted=(); trap - EXIT
	echo "next: scripts/build-gts9wifi-bundle.sh, then verify-gts9wifi-bundle.py"
else
	echo "== 4/4 skipped (no --rootfs)"
fi
echo "kernel $krel ready in $out (modules-$krel.tar.gz for the live install)"
