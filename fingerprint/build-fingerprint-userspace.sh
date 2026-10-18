#!/bin/bash
# Build every userspace piece of the EL721 fingerprint stack for the image.
#
#   sudo fingerprint/build-fingerprint-userspace.sh
#
# Outputs, in $base/out (default build/gts9wifi-ultra/out):
#   packages/libfprint-2-2_*+gts9wifi*.deb   libfprint with the EL721 driver
#   fingerprint/gts9wifi-fingerprint-secure-owner
#   fingerprint/gts9wifi-binder-ctxmgr
#   fingerprint/liblog_capture.so, libvmmem_shim.so   (bionic LD_PRELOAD shims)
# Uses the noble arm64 build chroot of build-libfprint-el721.sh; nothing
# proprietary is involved (Samsung's binaries come from the tablet itself, see
# device/usr/libexec/gts9wifi-fingerprint-runtime).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
base=${UBUNTU_WORKDIR:-$(dirname "$(dirname "$here")")/build/gts9wifi-ultra}
buildroot=${BUILDROOT_DIR:-$base/buildroot}
out=$base/out/fingerprint
export UBUNTU_WORKDIR=$base
mkdir -p "$out"

echo "== libfprint (EL721)"
bash "$here/build-libfprint-el721.sh"
echo "== secure owner"
bash "$here/build-fingerprint-secure-owner.sh"
echo "== binder context manager"
mkdir -p "$buildroot/build/ctxmgr"
install -m0644 "$here/binder-ctxmgr/gts9wifi-binder-ctxmgr.c" "$buildroot/build/ctxmgr/"
chroot "$buildroot" /bin/sh -ec 'cd /build/ctxmgr
cc -std=gnu11 -O2 -Wall -Wextra -Werror gts9wifi-binder-ctxmgr.c -o gts9wifi-binder-ctxmgr
strip gts9wifi-binder-ctxmgr'
install -m0755 "$buildroot/build/ctxmgr/gts9wifi-binder-ctxmgr" "$out/"
echo "== bionic shims"
bash "$here/build-liblog-capture.sh" stub "$out/liblog_capture.so"
(cd "$out" && sha256sum gts9wifi-fingerprint-secure-owner gts9wifi-binder-ctxmgr \
	liblog_capture.so libvmmem_shim.so > SHA256SUMS && cat SHA256SUMS)
