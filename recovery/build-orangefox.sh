#!/bin/bash
# Build OrangeFox recovery for the Galaxy Tab S9 Wi-Fi (gts9wifi).
#
#   bash recovery/build-orangefox.sh [WORK_DIR]
#
# Needs an x86_64 Linux host (Android's build tools are x86_64 only),
# about 60 GB free and 16 GB RAM; GitHub Actions runs it from
# .github/workflows/orangefox.yml.  Output: WORK_DIR/out/ with the
# recovery image, OrangeFox's flashable zip and SHA256SUMS.
#
# Recipe, all pinned:
#   1. OrangeFox fox_12.1 sources, synced by OrangeFox's own sync script
#      (a TWRP 12.1 minimal manifest plus OrangeFox's recovery and vendor).
#   2. Device tree: rainbowdashh/android_device_samsung_gts9wifi, the tree
#      of the TWRP "V2" that boots on this tablet (same prebuilt kernel,
#      dtb, dtbo and modules), plus our patches in recovery/patches/.
#   3. lunch twrp_gts9wifi-eng; mka adbd recoveryimage.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(realpath -m "${1:-$HOME/gts9wifi-fox}")
fox=$work/fox_12.1

sync_repo=https://gitlab.com/OrangeFox/sync.git
sync_commit=03434a833701f73430cd085738ae0bf54f2231f1
dt_repo=https://github.com/rainbowdashh/android_device_samsung_gts9wifi
dt_commit=fe92d0fbb50f6563a69d021b1e9249858bb56c03
qcom_repo=https://github.com/TeamWin/android_device_qcom_twrp-common
qcom_commit=98506f7919102378c8d52ee7d6a94a867f1b4c55

[ "$(uname -m)" = x86_64 ] || { echo "needs an x86_64 host" >&2; exit 1; }
mkdir -p "$work"

echo "== 1/3 OrangeFox fox_12.1 sources -> $fox"
if [ ! -d "$work/sync" ]; then
	git clone -q "$sync_repo" "$work/sync"
fi
git -C "$work/sync" checkout -q "$sync_commit"
if [ ! -f "$fox/build/envsetup.sh" ]; then
	(cd "$work/sync" && ./orangefox_sync.sh --branch 12.1 --path "$fox")
fi
test -f "$fox/build/envsetup.sh" && test -d "$fox/bootable/recovery" && test -d "$fox/vendor/recovery"

echo "== 2/3 device tree $dt_commit + recovery/patches"
dt=$fox/device/samsung/gts9wifi
rm -rf "$dt"
git clone -q "$dt_repo" "$dt"
git -C "$dt" checkout -q "$dt_commit"
git -C "$dt" -c user.name=build -c user.email=build@localhost am -q "$here"/patches/*.patch
git -C "$dt" log --oneline -n $(( $(ls "$here"/patches/*.patch | wc -l) + 1 ))

# /data decryption services (qseecomd, gatekeeper), named in the tree's
# twrp.dependencies; the OrangeFox sync does not read that file.
if [ ! -d "$fox/device/qcom/twrp-common" ]; then
	git clone -q "$qcom_repo" "$fox/device/qcom/twrp-common"
	git -C "$fox/device/qcom/twrp-common" checkout -q "$qcom_commit"
fi

# TWRP's vold (system/vold, TeamWin android-12.1): recovery/patches-vold/.
if ! grep -q "gts9wifi: no per-boot key" "$fox/system/vold/FsCrypt.cpp"; then
	git -C "$fox/system/vold" -c user.name=build -c user.email=build@localhost am -q "$here"/patches-vold/*.patch
fi

# OrangeFox's recovery (bootable/recovery, fox_12.1): recovery/patches-recovery/.
if ! grep -q "chosen once, not per pixel" "$fox/bootable/recovery/minuitwrp/graphics_utils.cpp"; then
	git -C "$fox/bootable/recovery" -c user.name=build -c user.email=build@localhost am -q "$here"/patches-recovery/*.patch
fi

# Default theme: OrangeFox's own "Black" style instead of "Cream".  The
# built-in /twres/themes/style.xml is the default; a style picked in the
# UI is saved under /sdcard/Fox/.theme and overrides it once /data is
# usable.
theme=$fox/bootable/recovery/gui/theme/portrait_hdpi/themes
cp "$theme/styles/Black.xml" "$theme/style.xml"

echo "== 3/3 build"
cd "$fox"
export ALLOW_MISSING_DEPENDENCIES=true LC_ALL=C
export FOX_BUILD_DEVICE=gts9wifi
export FOX_VARIANT=ubuntu-port
# envsetup.sh and lunch use unset variables and return non-zero from
# internal checks, so they run without -e/-u/pipefail; failures are
# checked explicitly.
set +eu +o pipefail
source build/envsetup.sh
lunch twrp_gts9wifi-eng || exit 1
mka adbd recoveryimage || exit 1
set -euo pipefail

prod=$fox/out/target/product/gts9wifi
rm -rf "$work/out" && mkdir -p "$work/out"
cp "$prod"/recovery.img "$work/out/"
cp "$prod"/OrangeFox-*.img "$prod"/OrangeFox-*.zip "$work/out/" 2>/dev/null || true
# The header's os_version/os_patch_level must be Android's (patch 0007):
# KeyMint rejects keys from a newer OS.
python3 - "$work/out/recovery.img" <<'PY'
import struct, sys
v = struct.unpack_from('<I', open(sys.argv[1], 'rb').read(48), 44)[0]
ver = '%d.%d.%d' % (v >> 25, (v >> 18) & 0x7f, (v >> 11) & 0x7f)
patch = '%d-%02d' % (((v >> 4) & 0x7f) + 2000, v & 0xf)
print('recovery header: os_version', ver, 'os_patch_level', patch)
sys.exit(0 if (ver, patch) == ('15.0.0', '2025-02') else 1)
PY
(cd "$work/out" && sha256sum * > SHA256SUMS && cat SHA256SUMS)
