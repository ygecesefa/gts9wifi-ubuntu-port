#!/bin/bash
# Build gts9wifi-imu (the tablet's gyroscope and accelerometer at ~200 Hz)
# with its own copy of libssc, for Ubuntu 24.04 arm64.
#
#   build-gyropad.sh [WORKDIR]      (default: ./gyropad-build)
#
# Runs on Ubuntu 24.04 arm64 (a container: docker run --rm --network host
# -v "$PWD":/src:ro -v OUT:/work ubuntu:24.04 bash /src/build-gyropad.sh /work).
# Result: WORKDIR/out/gts9wifi-gyropad-<version>.tar.zst, unpacked at / on
# the tablet: /usr/lib/gts9wifi-gyropad/{bin/gts9wifi-imu,lib/libssc.so.2}.
# The system's libssc (iio-sensor-proxy, 26 Hz) is not touched.
#
# libssc is the image's (packaging/sensors): v0.4.4 from codeberg with the
# sync-wait fix, plus one change here: SSC_SAMPLE_RATE picks a higher rate.

set -euo pipefail

LIBSSC_VERSION=0.4.4
VERSION=1
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
PREFIX=/usr/lib/gts9wifi-gyropad
WORK=$(mkdir -p "${1:-gyropad-build}" && cd "${1:-gyropad-build}" && pwd)
cd "$WORK"

SUDO=sudo; [ "$(id -u)" != 0 ] || SUDO=
export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq --no-install-recommends \
	build-essential pkg-config ninja-build git ca-certificates python3 python3-venv \
	libglib2.0-dev libqmi-glib-dev libmbim-glib-dev libprotobuf-c-dev protobuf-c-compiler protobuf-compiler \
	python3-dev patchelf zstd

# libssc 0.4.4 needs meson >= 1.4 (noble: 1.3.2).
python3 -m venv venv && venv/bin/pip install -q 'meson>=1.4'
export PATH="$WORK/venv/bin:$PATH"

rm -rf libssc stage stage-ssc out
git clone --quiet --depth 1 --branch "v$LIBSSC_VERSION" https://codeberg.org/DylanVanAssche/libssc.git libssc
cd libssc
patch -p1 < "$repo/packaging/sensors/fix-ssc-sync-wait-busy-loop.patch"
# The lowest rate the sensor offers, unless SSC_SAMPLE_RATE (Hz) asks for
# more: then the lowest one at or above it, or the highest one.
python3 - src/libssc-sensor.c <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = """					/* Only a single sample rate is supported for now. */
					for (gsize j = 0; j < attr_msg->attr[i]->value_array->n_v; j++) {
						if (attr_msg->attr[i]->value_array->v[j]->has_f
						 && attr_msg->attr[i]->value_array->v[j]->f > 0) {
							priv->sample_rate = attr_msg->attr[i]->value_array->v[j]->f;
							break;
						}
					}"""
new = """					/* gts9wifi: SSC_SAMPLE_RATE (Hz) picks the lowest offered rate
					 * at or above it (or the highest); unset, the first rate. */
					{
						const gchar *want_s = g_getenv ("SSC_SAMPLE_RATE");
						gfloat want = want_s ? (gfloat) g_ascii_strtod (want_s, NULL) : 0;
						gfloat best = 0, highest = 0;
						for (gsize j = 0; j < attr_msg->attr[i]->value_array->n_v; j++) {
							gfloat f;
							if (!attr_msg->attr[i]->value_array->v[j]->has_f)
								continue;
							f = attr_msg->attr[i]->value_array->v[j]->f;
							if (f <= 0)
								continue;
							if (f > highest)
								highest = f;
							if (want <= 0) {
								best = f;
								break;
							}
							if (f >= want && (best == 0 || f < best))
								best = f;
						}
						priv->sample_rate = best > 0 ? best : highest;
					}"""
assert s.count(old) == 1, "libssc sample-rate block not found"
open(p, "w").write(s.replace(old, new))
PY
meson setup output --prefix=/usr --libdir=lib/aarch64-linux-gnu -Dbuildtype=release
meson compile -C output >/dev/null
DESTDIR="$WORK/stage-ssc" meson install --no-rebuild -C output >/dev/null
cd "$WORK"

ssc=$WORK/stage-ssc/usr
mkdir -p "stage$PREFIX/bin" "stage$PREFIX/lib"
cp -a "$ssc"/lib/aarch64-linux-gnu/libssc.so.* "stage$PREFIX/lib/"
gcc -O2 -Wall -o "stage$PREFIX/bin/gts9wifi-imu" "$here/gts9wifi-imu.c" \
	-I"$ssc/include/libssc" $(pkg-config --cflags glib-2.0 gio-2.0 gobject-2.0) \
	-L"$ssc/lib/aarch64-linux-gnu" -lssc $(pkg-config --libs glib-2.0 gio-2.0 gobject-2.0)
patchelf --set-rpath "$PREFIX/lib" "stage$PREFIX/bin/gts9wifi-imu"
strip --strip-unneeded "stage$PREFIX/bin/gts9wifi-imu" $(find "stage$PREFIX/lib" -type f -name "libssc.so*")
objdump -p "stage$PREFIX/bin/gts9wifi-imu" | grep -E "NEEDED|RUNPATH"

mkdir -p out
tar -C stage --owner=0 --group=0 --numeric-owner -cf - "${PREFIX#/}" |
	zstd -19 -q -o "out/gts9wifi-gyropad-$VERSION.tar.zst" -f
(cd out && sha256sum *.tar.zst > SHA256SUMS && cat SHA256SUMS)
