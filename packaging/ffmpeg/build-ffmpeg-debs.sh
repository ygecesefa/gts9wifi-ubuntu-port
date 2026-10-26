#!/bin/bash
# Rebuild Ubuntu noble's FFmpeg with this tablet's V4L2 M2M patches, as .deb.
#
#   sudo packaging/ffmpeg/build-ffmpeg-debs.sh [--source-only]
#   -> build/gts9wifi-ffmpeg/out/*.deb
#
# Why: Firefox (Mozilla's .deb, not the snap) decodes H.264/HEVC through the
# system libavcodec, and libavcodec's V4L2 M2M decoders reach the tablet's
# video block (Qualcomm iris).  See README.md for what each patch fixes.
#
# Same source as Ubuntu (apt-get source ffmpeg=$version), the patches
# appended to debian/patches, the version suffixed +gts9wifiN so the
# packages replace Ubuntu's 1:1 (and an Ubuntu update replaces them again).
# The build runs in a throwaway arm64 noble chroot, never on the rootfs.
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
here=$repo/packaging/ffmpeg
work=${FFMPEG_WORKDIR:-$repo/../build/gts9wifi-ffmpeg}
buildroot=$work/buildroot
out=$work/out
version=${FFMPEG_VERSION:-7:6.1.1-3ubuntu5}
suffix=${FFMPEG_SUFFIX:-+gts9wifi2}
mirror=${UBUNTU_MIRROR:-http://ports.ubuntu.com/ubuntu-ports}
source_only=0
[ "${1:-}" = --source-only ] && source_only=1

[ "$(id -u)" = 0 ] || { echo "run as root (chroot)" >&2; exit 1; }
mkdir -p "$work" "$out"

if [ ! -x "$buildroot/usr/bin/dpkg-buildpackage" ]; then
	echo "== noble arm64 build chroot"
	rm -rf "$buildroot"
	mmdebstrap --variant=buildd --architectures=arm64 \
		--components=main,restricted,universe,multiverse \
		--include=devscripts,quilt,ca-certificates \
		noble "$buildroot" \
		"deb $mirror noble main restricted universe multiverse" \
		"deb $mirror noble-updates main restricted universe multiverse" \
		"deb $mirror noble-security main restricted universe multiverse" \
		"deb-src $mirror noble main restricted universe multiverse" \
		"deb-src $mirror noble-updates main restricted universe multiverse" \
		"deb-src $mirror noble-security main restricted universe multiverse"
fi

mounted=0
umount_pseudo() {
	[ "$mounted" = 1 ] || return 0
	for d in dev/pts dev proc sys; do umount -l "$buildroot/$d" 2>/dev/null || true; done
	mounted=0
}
trap umount_pseudo EXIT
mount --bind /dev "$buildroot/dev"
mount -t devpts devpts "$buildroot/dev/pts" 2>/dev/null || true
mount -t proc proc "$buildroot/proc"
mount -t sysfs sys "$buildroot/sys"
mounted=1
cp -L /etc/resolv.conf "$buildroot/etc/resolv.conf"
run() { chroot "$buildroot" /bin/bash -euo pipefail -c "$1"; }

echo "== source ffmpeg=$version"
rm -rf "$buildroot/src"
mkdir -p "$buildroot/src/patches"
cp "$here"/patches/*.patch "$buildroot/src/patches/"
run "apt-get update -qq
	cd /src && apt-get source -qq ffmpeg=$version
	cd /src/ffmpeg-*/
	for p in /src/patches/*.patch; do
		cp \"\$p\" debian/patches/
		basename \"\$p\" >> debian/patches/series
	done
	QUILT_PATCHES=debian/patches quilt push -a -q"
[ "$source_only" = 1 ] && { echo "source unpacked in $buildroot/src"; exit 0; }

echo "== build-deps, build (long: two flavours, standard and extra)"
run "apt-get build-dep -y -qq ffmpeg=$version
	cd /src/ffmpeg-*/
	QUILT_PATCHES=debian/patches quilt pop -a -q
	DEBFULLNAME='gts9wifi' DEBEMAIL='gts9wifi@localhost' \
		dch --newversion '$version$suffix' --distribution noble --force-distribution \
		'V4L2 M2M patches for the Galaxy Tab S9 Wi-Fi (packaging/ffmpeg).'
	DEB_BUILD_OPTIONS='nocheck nodoc parallel=$(nproc)' dpkg-buildpackage -b -uc -us"
cp "$buildroot"/src/*.deb "$out/"
ls -l "$out"
