#!/bin/bash
# Put Waydroid's Android images (GApps: with the Play Store) into a rootfs,
# so Waydroid needs no download on its first launch.
#
#   sudo scripts/add-waydroid-images.sh ROOTFS [DOWNLOAD_DIR]
#   sudo scripts/add-waydroid-images.sh --remove ROOTFS
#
# Waydroid uses images found in /usr/share/waydroid-extra/images in place
# (tools/actions/initializer.py, preinstalled_images_paths): the first
# launch still shows "Initialize Waydroid", and its button sets Waydroid up
# from these at once.  gts9wifi-waydroid-omx-fix follows waydroid.cfg's
# images_path, so the OMX fix applies to them too.
#
# Images: the newest arm64 LineageOS 20 GAPPS system and MAINLINE vendor
# from Waydroid's OTA server (ota.waydro.id, the same Waydroid downloads),
# checked against the sha256 the OTA server lists.  ~1.4 GB zipped, ~3 GB
# unpacked: this does not fit the 2 GiB a GitHub release file may have, so
# public installer zips are built without it.
set -euo pipefail

if [ "${1:-}" = --remove ]; then
	rm -rf "${2:?rootfs}/usr/share/waydroid-extra"
	exit 0
fi
rootfs=${1:?usage: $0 ROOTFS [DOWNLOAD_DIR]}
dl=${2:-$(cd "$(dirname "$0")/../.." && pwd)/build/waydroid-gapps}
dest=$rootfs/usr/share/waydroid-extra/images
test -d "$rootfs/usr/lib/waydroid" || { echo "no Waydroid in $rootfs" >&2; exit 1; }
mkdir -p "$dl"

for t in system/lineage/waydroid_arm64/GAPPS vendor/waydroid_arm64/MAINLINE; do
	curl -fsS "https://ota.waydro.id/$t.json" | python3 -c '
import json, sys
r = json.load(sys.stdin)["response"][0]
print(r["id"], r["filename"], r["url"])'
done > "$dl/ota.txt"

: > "$dl/SHA256SUMS"
while read -r sum name url; do
	[ -f "$dl/$name" ] && echo "$sum  $dl/$name" | sha256sum -c --quiet 2>/dev/null ||
		curl -fsSL -o "$dl/$name" "$url"
	echo "$sum  $name" >> "$dl/SHA256SUMS"
done < "$dl/ota.txt"
(cd "$dl" && sha256sum -c SHA256SUMS)

rm -rf "$dest"
mkdir -p "$dest"
while read -r sum name url; do
	unzip -o -q "$dl/$name" '*.img' -d "$dest"
done < "$dl/ota.txt"
test -f "$dest/system.img" && test -f "$dest/vendor.img" || {
	echo "system.img/vendor.img missing in the OTA zips" >&2; exit 1; }
cut -d' ' -f2 "$dl/ota.txt" > "$dest/SOURCE"
chmod 0644 "$dest"/*
ls -l "$dest"
