#!/bin/bash
# Build the two bionic LD_PRELOAD shims, without an NDK:
# liblog_capture.so (Android log -> stderr) and libvmmem_shim.so (libspcom's
# mem_buf calls, done by the kernel heap here).
#
#   build-liblog-capture.sh LIBC_SO|stub OUT_SO   (libvmmem_shim.so goes next to it)
#
# "stub" links against a generated libc.so that only declares the four
# symbols used (write, snprintf, vsnprintf, abort) in bionic's LIBC version
# node, so the image build needs nothing from the tablet; at run time the
# shims bind to the tablet's real bionic libc.
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
if [ "$libc" = stub ]; then
	printf 'LIBC { global: write; snprintf; vsnprintf; abort; local: *; };\n' > "$tmp/libc.map"
	printf 'void write(void){}\nvoid snprintf(void){}\nvoid vsnprintf(void){}\nvoid abort(void){}\n' > "$tmp/stub.c"
	clang --target=aarch64-linux-android29 -w -fPIC -shared -nostdlib -fuse-ld=lld \
		-Wl,-soname,libc.so -Wl,--version-script="$tmp/libc.map" \
		"$tmp/stub.c" -o "$tmp/libc.so"
else
	cp "$libc" "$tmp/libc.so"
fi
clang --target=aarch64-linux-android29 -O2 -fPIC -fvisibility=hidden \
	-ffreestanding -Wall -Wextra -Werror -c "$src" -o "$tmp/liblog_capture.o"
clang --target=aarch64-linux-android29 -fuse-ld=lld -shared -nostdlib \
	-Wl,-soname,liblog_capture.so -Wl,--hash-style=gnu -Wl,-z,now \
	"$tmp/liblog_capture.o" -L"$tmp" -lc -o "$out"
llvm-readelf -d "$out" | grep -E 'NEEDED|SONAME'
clang --target=aarch64-linux-android29 -O2 -fPIC -fvisibility=hidden \
	-ffreestanding -Wall -Wextra -Werror -shared -nostdlib -fuse-ld=lld \
	-Wl,-soname,libvmmem_shim.so "$(dirname "$0")/libvmmem_shim.c" \
	-o "$(dirname "$out")/libvmmem_shim.so"
