#!/bin/bash
# Build the gts9wifi (SM-X710) baseline kernel.
#
# Baseline = the kernel recipe that is known to boot this tablet: the Fedora
# gts9wifi port's prepare.sh (its patches, out-of-tree X710 drivers and board
# DTS) on Linux v7.2, plus the Ubuntu userspace fragment (AppArmor, squashfs,
# overlayfs, netfilter).  Ultra-only SoC improvements are layered on later,
# one at a time, after this baseline has booted.
#
# For quick iterations on the same tree use rebuild-gts9wifi-kernel-incremental.sh.
#
# The source tree is exported fresh from the pinned tag on every run, so no
# patch from an earlier attempt can leak into the build.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
root=${GTS9WIFI_ROOT:-$(dirname "$repo")}
fedora=${FEDORA_REF:-$root/fedora-ref}
kernel_git=${KERNEL_GIT:-$root/build/linux-mainline}
tag=${LINUX_TAG:-v7.2}
commit=${LINUX_COMMIT:-8d3ae59288f1e7d58d76558a6ee96d533bc5019f}
work=${KERNEL_WORKDIR:-$root/build/gts9wifi-kernel}
tree=$work/linux-src
out=$work/out
jobs=${JOBS:-$(nproc)}

for f in "$fedora/kernel/prepare.sh" "$repo/kernel/config/config-gts9wifi-ubuntu.fragment"; do
	test -f "$f" || { echo "missing: $f" >&2; exit 1; }
done

head=$(git -C "$kernel_git" rev-parse "$tag^{commit}")
[ "$head" = "$commit" ] || { echo "$tag is $head, expected $commit" >&2; exit 1; }

echo "== 1/5 fresh source tree from $tag ($commit)"
rm -rf "$tree"
mkdir -p "$tree" "$out"
git -C "$kernel_git" archive "$commit" | tar -x -C "$tree"

echo "== 2/5 Fedora gts9wifi recipe (patches, drivers, DTS, base config)"
bash "$fedora/kernel/prepare.sh" "$tree" > "$work/prepare.log" 2>&1 || {
	tail -40 "$work/prepare.log" >&2; exit 1; }
# prepare.sh registers its drivers with echo 'obj-$(CONFIG_X)\t+= x.o'; bash's
# echo writes the \t literally, make then never sees obj-m for them, and the
# eight fingerprint/SPU modules (EL721, K250A, SPSS, SPCOM, ...) were silently
# not built although .config says =m.  Turn the literal \t into a tab.
grep -rlF '\t+=' --include=Makefile "$tree/drivers" | xargs -r sed -i 's/\\t+=/\t+=/'
if grep -qE 'FAILED|Reversed \(or previously applied\)|\.rej' "$work/prepare.log"; then
	grep -nE 'FAILED|Reversed|\.rej' "$work/prepare.log" >&2
	echo "a patch did not apply cleanly on $tag" >&2
	exit 1
fi

# This port's own fixes on top of the Fedora recipe, in order.
for p in "$repo"/kernel/patches-gts9wifi/*.patch; do
	[ -e "$p" ] || continue
	echo "   patch: ${p##*/}"
	patch -d "$tree" -p1 --forward --no-backup-if-mismatch < "$p" >> "$work/prepare.log" 2>&1 || {
		echo "patch failed: $p" >&2; exit 1; }
done

echo "== 3/5 Ubuntu userspace fragment"
cd "$tree"
scripts/kconfig/merge_config.sh -m .config \
	"$repo/kernel/config/config-gts9wifi-ubuntu.fragment" > "$work/merge.log" 2>&1
make ARCH=arm64 LLVM=1 olddefconfig > /dev/null
for sym in DRM_PANEL_SAMSUNG_ANA38407 TOUCHSCREEN_FTS1BA90A TOUCHSCREEN_WACOM_WEZ01 \
	BATTERY_SM5714 TYPEC_SM5714 ATH11K_PCI SECURITY_APPARMOR SQUASHFS; do
	grep -qE "^CONFIG_$sym=[ym]" .config || { echo "CONFIG_$sym is not enabled" >&2; exit 1; }
done

echo "== 4/5 Image.gz, dtbs, modules (-j$jobs)"
make ARCH=arm64 LLVM=1 -j"$jobs" Image.gz dtbs modules > "$work/build.log" 2>&1 || {
	tail -60 "$work/build.log" >&2; exit 1; }
krel=$(make -s ARCH=arm64 LLVM=1 kernelrelease)

echo "== 5/5 collect outputs ($krel)"
rm -rf "$out/modules-root"
make ARCH=arm64 LLVM=1 INSTALL_MOD_PATH="$out/modules-root" INSTALL_MOD_STRIP=1 \
	modules_install > "$work/modules_install.log" 2>&1
rm -f "$out/modules-root/lib/modules/$krel/build" "$out/modules-root/lib/modules/$krel/source"
cp arch/arm64/boot/Image.gz "$out/Image.gz"
cp arch/arm64/boot/dts/qcom/sm8550-samsung-gts9wifi.dtb "$out/"
cp .config "$out/config"
echo "$krel" > "$out/kernel.release"

# The X710 drivers must be present, built in or as modules.
# grep -c reads the whole stream: grep -q would exit early, SIGPIPE zcat and,
# under pipefail, report a present driver as missing.
for drv in ana38407 fts1ba90a wez01 sm5714; do
	in_image=$(zcat "$out/Image.gz" | grep -ac "$drv" || true)
	as_module=$(find "$out/modules-root" -name "*${drv}*.ko*" | wc -l)
	if [ "${in_image:-0}" -eq 0 ] && [ "$as_module" -eq 0 ]; then
		echo "driver $drv is missing from the build" >&2
		exit 1
	fi
done
(cd "$out" && sha256sum Image.gz sm8550-samsung-gts9wifi.dtb config > SHA256SUMS)
echo "kernel $krel ready in $out"
