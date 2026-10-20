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
# Inputs: the SD image (build-gts9wifi-sd-image.sh), the boot set
# (build-gts9wifi-bundle.sh) and the loader built with ubuntu-boot.zip
# (build-gts9wifi-ubuntu-boot-zip.sh, run before the SD image).  Every payload entry is stored, not deflated:
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

echo "== loader (from build-gts9wifi-ubuntu-boot-zip.sh)"
for f in "$out/gts9w-tool" "$out/update-binary" "$out/ubuntu-boot.zip"; do
	test -f "$f" || { echo "missing: $f (run build-gts9wifi-ubuntu-boot-zip.sh)" >&2; exit 1; }
done
# The loader must carry the current sources, not a stale build.
head -c "$(stat -c %s "$repo/installer/update-binary.sh")" "$out/update-binary" |
	cmp -s - "$repo/installer/update-binary.sh" || { echo "stale $out/update-binary" >&2; exit 1; }

echo "== payload"
for f in "$sd" "$sd.zst" "$bundle"/{boot,init_boot,vendor_boot,dtbo}.img; do
	test -f "$f" || { echo "missing: $f" >&2; exit 1; }
done
(cd "$bundle" && sha256sum -c --quiet SHA256SUMS)
# ubuntu-boot.zip (already inside the SD image) must hold this same boot set.
for n in boot init_boot vendor_boot dtbo; do
	[ "$(unzip -p "$out/ubuntu-boot.zip" ubuntu/$n.img | sha256sum | cut -d' ' -f1)" = \
		"$(sha256sum < "$bundle/$n.img" | cut -d' ' -f1)" ] || {
		echo "ubuntu-boot.zip $n.img differs from $bundle; rebuild it and the SD image" >&2; exit 1; }
done
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
raw=$(stat -c %s "$sd")
[ $((raw % 512)) = 0 ] || { echo "SD image size $raw is not a multiple of 512" >&2; exit 1; }
echo "raw_size $raw" >> "$work/p/SHA256SUMS"
echo "raw_sectors $((raw / 512))" >> "$work/p/SHA256SUMS"

printf '# gts9wifi Ubuntu installer: see gts9wifi/install.sh (run by update-binary)\n' > "$work/updater-script"

echo "== zip"
rm -f "$zip"
"$out/gts9w-tool" zip -0 "$zip" \
	META-INF/com/google/android/update-binary="$out/update-binary" \
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
