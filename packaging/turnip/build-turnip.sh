#!/bin/bash
# Build a newer Turnip (Mesa's Vulkan driver for Adreno) next to the system
# Mesa, for Ubuntu 24.04 arm64.
#
#   build-turnip.sh [WORKDIR]      (default: ./turnip-build)
#
# Result: WORKDIR/out/gts9wifi-turnip-<mesa version>.tar.zst, to be unpacked
# at / on the tablet. It holds two files under /usr/lib/gts9wifi-turnip:
#   lib/aarch64-linux-gnu/libvulkan_freedreno.so
#   share/vulkan/icd.d/freedreno_icd.aarch64.json
# Nothing of the system Mesa is replaced: desktop, camera and video keep the
# distribution's driver. A program uses this one only when it is started with
#   VK_DRIVER_FILES=/usr/lib/gts9wifi-turnip/share/vulkan/icd.d/freedreno_icd.aarch64.json
# (the Steam launcher, packaging/steam/gts9wifi-steam, does that). The prefix
# is under /usr so that Steam's game containers (pressure-vessel) see it.
#
# Why: Ubuntu 24.04 has Mesa 25.2.8, whose Turnip has no sparse resources
# (sparseBinding = false). Unreal Engine 5 games under Proton (vkd3d-proton)
# then render garbage in game. Only the Vulkan driver is built: no OpenGL,
# no LLVM, no other drivers.
#
# Runs on Ubuntu 24.04 arm64 (the GitHub runner ubuntu-24.04-arm, or the
# tablet itself). Needs sudo for the build packages.

set -euo pipefail

MESA_VERSION=26.3.0
# sha256 of https://archive.mesa3d.org/mesa-26.3.0.tar.xz as downloaded on
# 2026-11-15 (the archive publishes no checksum file for this release).
MESA_SHA256=91d729aa68bb89e4ec857841300bbe922bcb3e52b1f97566ca83930d3b28343a
PREFIX=/usr/lib/gts9wifi-turnip

WORK=$(mkdir -p "${1:-turnip-build}" && cd "${1:-turnip-build}" && pwd)
cd "$WORK"

[ "$(dpkg --print-architecture)" = arm64 ] || { echo "arm64 only" >&2; exit 1; }

sudo apt-get update -qq
sudo apt-get install -y -qq --no-install-recommends \
	build-essential pkg-config ninja-build python3-venv bison flex glslang-tools \
	libdrm-dev libexpat1-dev zlib1g-dev libzstd-dev libudev-dev \
	libwayland-dev wayland-protocols libwayland-egl-backend-dev \
	libx11-dev libx11-xcb-dev libxcb1-dev libxcb-dri3-dev libxcb-present-dev \
	libxcb-randr0-dev libxcb-shm0-dev libxcb-sync-dev libxcb-xfixes0-dev \
	libxcb-keysyms1-dev libxshmfence-dev libxrandr-dev libxext-dev libxfixes-dev \
	curl xz-utils zstd

# Mesa 26.3 needs meson >= 1.5 (noble: 1.3.2) and its Python modules.
python3 -m venv venv
venv/bin/pip install -q 'meson>=1.5' mako pyyaml packaging

[ -f "mesa-$MESA_VERSION.tar.xz" ] ||
	curl -fL --retry 5 -o "mesa-$MESA_VERSION.tar.xz" "https://archive.mesa3d.org/mesa-$MESA_VERSION.tar.xz"
echo "$MESA_SHA256  mesa-$MESA_VERSION.tar.xz" | sha256sum -c -
rm -rf "mesa-$MESA_VERSION" build stage
tar -xf "mesa-$MESA_VERSION.tar.xz"

# wayland-protocols (>= 1.49) and anything else too old in noble come from
# Mesa's own meson wraps (build-time only; nothing of them is installed).
PATH="$WORK/venv/bin:$PATH" meson setup build "mesa-$MESA_VERSION" \
	--prefix="$PREFIX" --libdir=lib/aarch64-linux-gnu \
	--buildtype=release -Db_ndebug=true -Db_lto=false \
	-Dvulkan-drivers=freedreno -Dfreedreno-kmds=msm \
	-Dgallium-drivers= -Dplatforms=x11,wayland \
	-Dopengl=false -Dglx=disabled -Degl=disabled -Dgbm=disabled \
	-Dgles1=disabled -Dgles2=disabled -Dllvm=disabled \
	-Dvulkan-layers= -Dvideo-codecs= -Dtools= \
	-Dbuild-tests=false -Dlibunwind=disabled -Dlmsensors=disabled \
	-Dvalgrind=disabled -Dxmlconfig=disabled
PATH="$WORK/venv/bin:$PATH" ninja -C build
DESTDIR="$WORK/stage" PATH="$WORK/venv/bin:$PATH" ninja -C build install

icd="$WORK/stage$PREFIX/share/vulkan/icd.d/freedreno_icd.aarch64.json"
drv="$WORK/stage$PREFIX/lib/aarch64-linux-gnu/libvulkan_freedreno.so"
[ -f "$icd" ] && [ -f "$drv" ] || { echo "driver or ICD file missing" >&2; exit 1; }
strip --strip-unneeded "$drv"
grep -q "$PREFIX/lib/aarch64-linux-gnu/libvulkan_freedreno.so" "$icd" ||
	{ echo "ICD does not point into $PREFIX:"; cat "$icd"; exit 1; } >&2
# What the driver needs from the system (must all exist on the tablet).
objdump -p "$drv" | grep NEEDED

mkdir -p out
tar -C stage --owner=0 --group=0 --numeric-owner -cf - \
	"${icd#"$WORK/stage/"}" "${drv#"$WORK/stage/"}" |
	zstd -19 -q -o "out/gts9wifi-turnip-$MESA_VERSION.tar.zst" -f
(cd out && sha256sum "gts9wifi-turnip-$MESA_VERSION.tar.zst" > SHA256SUMS && cat SHA256SUMS)
