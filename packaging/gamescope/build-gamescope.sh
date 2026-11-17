#!/bin/bash
# Build gamescope (Valve's game compositor) for Ubuntu 24.04 arm64, which has
# no gamescope package for this architecture.
#
#   build-gamescope.sh [WORKDIR]      (default: ./gamescope-build)
#
# Result: WORKDIR/out/gts9wifi-gamescope-<version>.tar.zst, to be unpacked at
# / on the tablet: /usr/lib/gts9wifi-gamescope/bin/gamescope, the few files
# it installs next to itself, and in lib/ the four libraries it needs newer
# than Ubuntu 24.04 has (wayland, libdrm, pixman, xkbcommon; found through the binary's
# RUNPATH, the system's copies are not touched). Its other libraries come
# from Ubuntu packages (listed at the end of the build and in README.md).
#
# The build installs into the real /usr/lib/gts9wifi-gamescope of the machine
# it runs on (a container or a CI runner), then packs that directory.
#
# Why: gamescope runs a game (or all of Steam) in its own small compositor
# and scales its picture to the screen. That gives one resolution and one
# frame-rate cap for every game, set outside the game: on this tablet,
# rendering at 1920x1200 instead of the panel's 2560x1600.
#
# Runs on Ubuntu 24.04 arm64: the GitHub runner ubuntu-24.04-arm, or a
# container (docker run --rm -v "$PWD":/src -w /src ubuntu:24.04 bash
# packaging/gamescope/build-gamescope.sh /src/build). Needs root or sudo for
# the build packages.

set -euo pipefail

GAMESCOPE_VERSION=3.17.0
VULKAN_HEADERS_VERSION=v1.4.335
# gamescope's bundled wlroots wants these newer than noble's
# (wayland 1.22, wayland-protocols 1.34, libdrm 2.4.125, pixman 0.42,
# xkbcommon 1.6):
WAYLAND_VERSION=1.24.0
WAYLAND_PROTOCOLS_VERSION=1.47
LIBDRM_VERSION=libdrm-2.4.131
PIXMAN_VERSION=pixman-0.46.4
XKBCOMMON_VERSION=xkbcommon-1.8.1
PREFIX=/usr/lib/gts9wifi-gamescope

WORK=$(mkdir -p "${1:-gamescope-build}" && cd "${1:-gamescope-build}" && pwd)
cd "$WORK"

SUDO=sudo; [ "$(id -u)" != 0 ] || SUDO=
[ "$(dpkg --print-architecture)" = arm64 ] || { echo "arm64 only" >&2; exit 1; }

export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq --no-install-recommends \
	build-essential pkg-config ninja-build python3-venv git ca-certificates cmake \
	glslang-tools hwdata zstd binutils \
	libdrm-dev libvulkan-dev libwayland-dev wayland-protocols libxkbcommon-dev \
	libx11-dev libxdamage-dev libxcomposite-dev libxrender-dev libxext-dev \
	libxfixes-dev libxxf86vm-dev libxtst-dev libxres-dev libxmu-dev libxi-dev \
	libxcursor-dev libx11-xcb-dev libxcb1-dev libxcb-composite0-dev libxcb-xinput-dev \
	libxcb-icccm4-dev libxcb-ewmh-dev libxcb-res0-dev libxcb-render-util0-dev \
	libxcb-dri3-dev libxcb-present-dev libxcb-shm0-dev libxcb-xfixes0-dev \
	libpipewire-0.3-dev libavif-dev libsdl2-dev libcap-dev libinput-dev libseat-dev \
	libdisplay-info-dev libdecor-0-dev libluajit-5.1-dev libeis-dev libudev-dev \
	libpixman-1-dev libglm-dev libstb-dev libbenchmark-dev libsystemd-dev \
	libgbm-dev libegl-dev libgles-dev xwayland \
	libffi-dev libexpat1-dev libxml2-dev libxcb-xkb-dev bison patchelf

python3 -m venv venv
venv/bin/pip install -q 'meson>=1.5'
export PATH="$WORK/venv/bin:$PATH"

# gamescope 3.17 needs Vulkan headers >= 1.4.335 (VK_EXT_present_timing);
# noble has 1.3.275. Headers only, for the build: /usr/local/include comes
# before /usr/include, nothing of them is installed on the tablet.
if [ ! -d Vulkan-Headers ]; then
	git clone --depth 1 --branch "$VULKAN_HEADERS_VERSION" https://github.com/KhronosGroup/Vulkan-Headers.git
fi
cmake -S Vulkan-Headers -B vkh-build -DCMAKE_INSTALL_PREFIX=/usr/local >/dev/null
$SUDO cmake --install vkh-build >/dev/null

# --- newer wayland, wayland-protocols, libdrm, pixman into $PREFIX ----------
fetch() { # repository (gitlab.freedesktop.org path or full URL), directory, tag
	local url=$1
	case "$url" in https://*) ;; *) url="https://gitlab.freedesktop.org/$url.git" ;; esac
	[ -d "$2" ] || git clone --depth 1 --branch "$3" "$url" "$2"
}
dep() { # name, meson options...
	local name=$1; shift
	rm -rf "dep-$name"
	meson setup "dep-$name" "$name" --prefix="$PREFIX" --libdir=lib --buildtype=release "$@" >/dev/null
	ninja -C "dep-$name" >/dev/null
	$SUDO env PATH="$PATH" ninja -C "dep-$name" install >/dev/null
	echo "== built $name"
}
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"
export LDFLAGS="-Wl,-rpath,$PREFIX/lib"
$SUDO rm -rf "$PREFIX"
fetch wayland/wayland wayland "$WAYLAND_VERSION"
dep wayland -Ddocumentation=false -Dtests=false -Ddtd_validation=false
fetch wayland/wayland-protocols wayland-protocols "$WAYLAND_PROTOCOLS_VERSION"
dep wayland-protocols -Dtests=false
fetch mesa/libdrm libdrm "$LIBDRM_VERSION"
dep libdrm -Dintel=disabled -Dradeon=disabled -Damdgpu=disabled -Dnouveau=disabled \
	-Dvmwgfx=disabled -Dfreedreno=enabled -Dtests=false -Dman-pages=disabled \
	-Dvalgrind=disabled -Dcairo-tests=disabled
fetch pixman/pixman pixman "$PIXMAN_VERSION"
dep pixman -Dtests=disabled -Ddemos=disabled -Dgtk=disabled
fetch https://github.com/xkbcommon/libxkbcommon.git libxkbcommon "$XKBCOMMON_VERSION"
dep libxkbcommon -Denable-docs=false -Denable-tools=false -Denable-wayland=false \
	-Denable-xkbregistry=false -Denable-x11=true \
	-Dxkb-config-root=/usr/share/X11/xkb -Dx-locale-root=/usr/share/X11/locale

if [ ! -d gamescope ]; then
	git clone --depth 1 --branch "$GAMESCOPE_VERSION" --recurse-submodules --shallow-submodules \
		https://github.com/ValveSoftware/gamescope.git
fi
git -C gamescope rev-parse HEAD

rm -rf build out
# wlroots, libliftoff and vkroots are gamescope's own pinned submodules and
# are linked statically (force_fallback_for is gamescope's documented way).
# OpenVR is for VR headsets: off.
meson setup build gamescope \
	--prefix="$PREFIX" --buildtype=release \
	-Dforce_fallback_for=wlroots,libliftoff,vkroots \
	-Denable_openvr_support=false \
	-Denable_tests=false \
	-Dbenchmark=disabled
ninja -C build
$SUDO env PATH="$PATH" ninja -C build install

bin="$PREFIX/bin/gamescope"
[ -x "$bin" ] || { echo "gamescope binary missing" >&2; exit 1; }
# Only what runs: no headers, pkg-config files, static libraries, scanner.
$SUDO rm -rf "$PREFIX/include" "$PREFIX/lib/pkgconfig" "$PREFIX/share/pkgconfig" \
	"$PREFIX/share/wayland" "$PREFIX/share/wayland-protocols" "$PREFIX/share/aclocal" \
	"$PREFIX/share/libdrm" "$PREFIX/bin/wayland-scanner"
$SUDO find "$PREFIX" -name '*.a' -delete
$SUDO find "$PREFIX" -type f \( -name '*.so*' -o -path '*/bin/*' \) -exec strip --strip-unneeded {} + 2>/dev/null || true
for f in "$PREFIX"/bin/* $(find "$PREFIX" -name 'libVkLayer*.so'); do
	$SUDO patchelf --set-rpath "$PREFIX/lib" "$f"
done
echo "== libraries gamescope needs from Ubuntu packages"
objdump -p "$bin" | awk '/NEEDED/ {print $2}' | sort > "$WORK/NEEDED.txt"
for l in $(cat "$WORK/NEEDED.txt"); do [ -e "$PREFIX/lib/$l" ] && echo "  (own) $l" || echo "  $l"; done
echo "== unresolved (must be empty)"
ldd "$bin" | grep "not found" || true
echo "== installed files"
find "$PREFIX" \( -type f -o -type l \) | sort

mkdir -p out
tar -C / --owner=0 --group=0 --numeric-owner -cf - "${PREFIX#/}" |
	zstd -19 -q -o "out/gts9wifi-gamescope-$GAMESCOPE_VERSION.tar.zst" -f
cp NEEDED.txt out/
(cd out && sha256sum "gts9wifi-gamescope-$GAMESCOPE_VERSION.tar.zst" > SHA256SUMS && cat SHA256SUMS)
