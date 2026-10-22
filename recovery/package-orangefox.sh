#!/bin/bash
# Packages a built OrangeFox recovery.img three ways for a release:
#
#   bash recovery/package-orangefox.sh RECOVERY_IMG OUT_DIR NAME
#
#   NAME.img       the raw image (dd from root, or TWRP Install Image)
#   NAME.zip       a recovery zip (TWRP / OrangeFox Install or sideload) that
#                  writes recovery.img to the recovery partition and reads it
#                  back: recovery/zip/update-binary
#   NAME.tar.md5   for Odin's AP slot: a tar with recovery.img and Samsung's
#                  md5 trailer (the md5 of the tar appended as text)
#
# and NAME.sha256 with the sha256 of all three.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
img=$(realpath "$1")
out=$(realpath -m "$2")
name=$3

mkdir -p "$out"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cp "$img" "$out/$name.img"

cp "$img" "$work/recovery.img"
(cd "$work" && sha256sum recovery.img > recovery.img.sha256)
mkdir -p "$work/META-INF/com/google/android"
cp "$here/zip/update-binary" "$work/META-INF/com/google/android/update-binary"
echo "# the work is done by update-binary" > "$work/META-INF/com/google/android/updater-script"
rm -f "$out/$name.zip"
(cd "$work" && zip -q -X "$out/$name.zip" META-INF/com/google/android/update-binary \
	META-INF/com/google/android/updater-script recovery.img.sha256 && zip -q -X -0 "$out/$name.zip" recovery.img)

(cd "$work" && tar -H ustar --owner=0 --group=0 --numeric-owner -cf "$name.tar" recovery.img)
md5sum -t "$work/$name.tar" | sed "s#  .*#  $name.tar#" >> "$work/$name.tar"
mv "$work/$name.tar" "$out/$name.tar.md5"

(cd "$out" && sha256sum "$name.img" "$name.zip" "$name.tar.md5" > "$name.sha256" && cat "$name.sha256")
