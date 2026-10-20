#!/bin/bash
# Build ubuntu-boot.zip and the recovery loader shared by all gts9wifi zips.
#
# ubuntu-boot.zip is flashed in recovery to switch to Ubuntu without root and
# without the Android-side script (to-ubuntu.sh): it writes the four Ubuntu
# boot images of this build and reads them back.  build-gts9wifi-sd-image.sh
# puts it on the card's FAT partition GTS9W_BACK, next to the
# android-restore.zip the installer makes on the tablet, so both ways are a
# zip on the card.  Layout (AnyKernel3-style, like the other zips):
#   META-INF/com/google/android/update-binary   loader + gts9w-tool
#   META-INF/com/google/android/updater-script  placeholder
#   ubuntu/restore.sh                           installer/restore.sh
#   ubuntu/{boot,init_boot,vendor_boot,dtbo}.img, SHA256SUMS, info.txt
#
# Also leaves $OUT_DIR/gts9w-tool and $OUT_DIR/update-binary (loader with the
# tool appended) for build-gts9wifi-installer-zip.sh.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
root=${GTS9WIFI_ROOT:-$(dirname "$repo")}
version=${1:?usage: $0 VERSION   (e.g. v0.2.0-pre3)}
bundle=${BUNDLE_DIR:-$root/build/gts9wifi-bundle}
out=${OUT_DIR:-$root/build/gts9wifi-installer}
zip=$out/ubuntu-boot.zip

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$out" "$work/u"

echo "== gts9w-tool (static arm64) and loader"
gcc -O2 -Wall -Wextra -static -s -o "$out/gts9w-tool" "$repo/installer/gts9w-tool.c" -lz -lzstd
file "$out/gts9w-tool" | grep -q 'statically linked' || { echo 'gts9w-tool is not static' >&2; exit 1; }
cat "$repo/installer/update-binary.sh" "$out/gts9w-tool" > "$out/update-binary"
printf '%016d' "$(stat -c %s "$repo/installer/update-binary.sh")" >> "$out/update-binary"

echo "== ubuntu-boot.zip"
(cd "$bundle" && sha256sum -c --quiet SHA256SUMS)
cp "$bundle"/{boot,init_boot,vendor_boot,dtbo}.img "$work/u/"
(cd "$work/u" && sha256sum boot.img init_boot.img vendor_boot.img dtbo.img > SHA256SUMS)
{
	echo "Ubuntu boot images, gts9wifi port $version ($(git -C "$repo" rev-parse --short HEAD))."
	echo "They boot the Ubuntu microSD this zip came with (root=LABEL=GTS9W_ROOT)."
} > "$work/u/info.txt"
printf '# gts9wifi Ubuntu boot set: see ubuntu/restore.sh (run by update-binary)\n' > "$work/updater-script"
rm -f "$zip"
"$out/gts9w-tool" zip -0 "$zip" \
	META-INF/com/google/android/update-binary="$out/update-binary" \
	META-INF/com/google/android/updater-script="$work/updater-script" \
	ubuntu/restore.sh="$repo/installer/restore.sh" \
	ubuntu/boot.img="$work/u/boot.img" \
	ubuntu/init_boot.img="$work/u/init_boot.img" \
	ubuntu/vendor_boot.img="$work/u/vendor_boot.img" \
	ubuntu/dtbo.img="$work/u/dtbo.img" \
	ubuntu/SHA256SUMS="$work/u/SHA256SUMS" \
	ubuntu/info.txt="$work/u/info.txt"
unzip -tq "$zip"
unzip -l "$zip"
ls -l "$zip"
