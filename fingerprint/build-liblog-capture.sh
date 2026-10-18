#!/bin/bash
# Build liblog_capture.so for Android's bionic, without an NDK.
#
#   build-liblog-capture.sh LIBC_SO OUT_SO
#
# LIBC_SO is the tablet's bionic libc.so (the copy gts9wifi-fingerprint-runtime
# put in /var/lib/gts9wifi/fingerprint/runtime/lib64); it is only linked
# against, to record the DT_NEEDED and the symbol versions.
set -euo pipefail
libc=${1:?usage: $0 LIBC_SO OUT_SO}
out=${2:?usage: $0 LIBC_SO OUT_SO}
src=$(dirname "$0")/liblog_capture.c
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$libc" "$tmp/libc.so"
clang --target=aarch64-linux-android29 -O2 -fPIC -fvisibility=hidden \
	-ffreestanding -Wall -Wextra -Werror -c "$src" -o "$tmp/liblog_capture.o"
clang --target=aarch64-linux-android29 -fuse-ld=lld -shared -nostdlib \
	-Wl,-soname,liblog_capture.so -Wl,--hash-style=gnu -Wl,-z,now \
	"$tmp/liblog_capture.o" -L"$tmp" -lc -o "$out"
llvm-readelf -d "$out" | grep -E 'NEEDED|SONAME'
