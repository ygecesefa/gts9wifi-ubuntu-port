#!/bin/bash
# Build the recovery installer zip: ubuntu-gts9wifi-<version>-installer.zip
#
# Flashed in recovery (LineageOS recovery or TWRP, best via `adb sideload`),
# it backs up the tablet's Android boot images into an android-restore.zip it
# builds on the device, erases the microSD and writes the Ubuntu image, then
# writes the four Ubuntu boot images.  Layout (AnyKernel3-style):
#   META-INF/com/google/android/update-binary   loader + gts9w-tool
#   META-INF/com/google/android/updater-script  placeholder
#   gts9wifi/install.sh                         the installer itself
#   gts9wifi/restore.sh                         goes into android-restore.zip
#   gts9wifi/{sd.img.zst,*.img,SHA256SUMS,version.txt}
#
# Inputs: the SD image (build-gts9wifi-sd-image.sh) and the boot set
# (build-gts9wifi-bundle.sh).  Every payload entry is stored, not deflated:
# the image is already zstd, and gts9w-tool only reads stored entries.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
root=${GTS9WIFI_ROOT:-$(dirname "$repo")}
version=${1:?usage: $0 VERSION   (e.g. v0.2.0-pre3)}
sd=${SD_IMAGE:-$root/build/gts9wifi-sd.img}
bundle=${BUNDLE_DIR:-$root/build/gts9wifi-bundle}
out=${OUT_DIR:-$root/build/gts9wifi-installer}
zip=$out/ubuntu-gts9wifi-$version-installer.zip

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$out" "$work/p"

echo "== gts9w-tool (static arm64)"
gcc -O2 -Wall -Wextra -static -s -o "$work/gts9w-tool" "$repo/installer/gts9w-tool.c" -lz -lzstd
file "$work/gts9w-tool" | grep -q 'statically linked' || { echo 'gts9w-tool is not static' >&2; exit 1; }

echo "== payload"
for f in "$sd" "$sd.zst" "$bundle"/{boot,init_boot,vendor_boot,dtbo}.img; do
	test -f "$f" || { echo "missing: $f" >&2; exit 1; }
done
(cd "$bundle" && sha256sum -c --quiet SHA256SUMS)
raw_sha=$(grep " $sd\$" "$sd.SHA256SUMS" | cut -d' ' -f1)
[ -n "$raw_sha" ] || { echo "no sha for $sd in $sd.SHA256SUMS" >&2; exit 1; }
# The raw sha is trusted from the image build; check the .zst still matches it.
[ "$(zstd -dc "$sd.zst" | sha256sum | cut -d' ' -f1)" = "$raw_sha" ] || {
	echo "$sd.zst does not decompress to $raw_sha" >&2; exit 1; }
# Old layout (2 partitions) images have no GTS9W_BACK for the restore zip.
sfdisk -d "$sd" | grep -q 'type=c' || { echo "$sd has no FAT GTS9W_BACK partition" >&2; exit 1; }

cp "$repo/installer/install.sh" "$repo/installer/restore.sh" "$work/p/"
cp "$bundle"/{boot,init_boot,vendor_boot,dtbo}.img "$work/p/"
printf '%s (port %s)\n' "$version" "$(git -C "$repo" rev-parse --short HEAD)" > "$work/p/version.txt"
(cd "$work/p" && sha256sum boot.img init_boot.img vendor_boot.img dtbo.img install.sh restore.sh) \
	> "$work/p/SHA256SUMS"
echo "$(sha256sum < "$sd.zst" | cut -d' ' -f1)  sd.img.zst" >> "$work/p/SHA256SUMS"
echo "$raw_sha  sd.img" >> "$work/p/SHA256SUMS"
echo "raw_size $(stat -c %s "$sd")" >> "$work/p/SHA256SUMS"

cat "$repo/installer/update-binary.sh" "$work/gts9w-tool" > "$work/update-binary"
printf '%016d' "$(stat -c %s "$repo/installer/update-binary.sh")" >> "$work/update-binary"
printf '# gts9wifi Ubuntu installer: see gts9wifi/install.sh (run by update-binary)\n' > "$work/updater-script"

echo "== zip"
rm -f "$zip"
"$work/gts9w-tool" zip -0 "$zip" \
	META-INF/com/google/android/update-binary="$work/update-binary" \
	META-INF/com/google/android/updater-script="$work/updater-script" \
	gts9wifi/SHA256SUMS="$work/p/SHA256SUMS" \
	gts9wifi/version.txt="$work/p/version.txt" \
	gts9wifi/install.sh="$work/p/install.sh" \
	gts9wifi/restore.sh="$work/p/restore.sh" \
	gts9wifi/boot.img="$work/p/boot.img" \
	gts9wifi/init_boot.img="$work/p/init_boot.img" \
	gts9wifi/vendor_boot.img="$work/p/vendor_boot.img" \
	gts9wifi/dtbo.img="$work/p/dtbo.img" \
	gts9wifi/sd.img.zst="$sd.zst"
unzip -tq "$zip"
unzip -l "$zip"
(cd "$out" && sha256sum "$(basename "$zip")" > "$(basename "$zip").sha256")
ls -l "$zip"
cat "$zip.sha256"
