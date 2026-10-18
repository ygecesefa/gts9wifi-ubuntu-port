#!/bin/bash
# Reuse the pinned QTEE build dependencies; no hardware access.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
base=${UBUNTU_WORKDIR:-$(dirname "$(dirname "$here")")/build/gts9wifi-ultra}
buildroot=${BUILDROOT_DIR:-$base/buildroot}
out=$base/out/fingerprint
mkdir -p "$out" "$buildroot/build/el721-secure-owner/input"
cp -a "$here/libfprint/." "$buildroot/build/el721-secure-owner/input/"
install -m0644 "$here/include/uapi/linux/spcom.h" "$buildroot/build/el721-secure-owner/spcom.h"
mkdir -p "$buildroot/build/el721-secure-owner/include/uapi/linux"
install -m0644 "$here/include/uapi/linux/spcom.h" "$buildroot/build/el721-secure-owner/include/uapi/linux/"
chroot "$buildroot" /bin/bash -euo pipefail -c '
  cd /build/el721-secure-owner
  cc -std=c11 -Wall -Wextra -Werror -Wno-unused-function -O2 \
    input/el721-secure-owner.c -Iinclude \
    $(pkg-config --cflags --libs glib-2.0) \
    -I/build/el721-libfprint/qtee-prefix/include \
    /build/el721-libfprint/qtee-prefix/lib/libqcomtee.a \
    /build/el721-libfprint/qtee-prefix/lib/libqcbor.a \
    -lpthread -o gts9wifi-fingerprint-secure-owner
  strip --strip-unneeded gts9wifi-fingerprint-secure-owner'
install -m0755 "$buildroot/build/el721-secure-owner/gts9wifi-fingerprint-secure-owner" "$out/"
sha256sum "$out/gts9wifi-fingerprint-secure-owner"
