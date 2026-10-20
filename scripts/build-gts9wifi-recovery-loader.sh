#!/bin/bash
# Build the loader shared by all gts9wifi zips: the static gts9w-tool and
# update-binary (installer/update-binary.sh with the tool appended, then the
# script's length as 16 digits).  build-gts9wifi-installer-zip.sh puts it in
# the installer zip; on the tablet the installer reuses it for the two switch
# zips it makes there (android-restore.zip, ubuntu-boot.zip).
#   -> $OUT_DIR/gts9w-tool, $OUT_DIR/update-binary
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
root=${GTS9WIFI_ROOT:-$(dirname "$repo")}
out=${OUT_DIR:-$root/build/gts9wifi-installer}
mkdir -p "$out"

gcc -O2 -Wall -Wextra -static -s -o "$out/gts9w-tool" "$repo/installer/gts9w-tool.c" -lz -lzstd
file "$out/gts9w-tool" | grep -q 'statically linked' || { echo 'gts9w-tool is not static' >&2; exit 1; }
cat "$repo/installer/update-binary.sh" "$out/gts9w-tool" > "$out/update-binary"
printf '%016d' "$(stat -c %s "$repo/installer/update-binary.sh")" >> "$out/update-binary"
ls -l "$out/gts9w-tool" "$out/update-binary"
