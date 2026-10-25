#!/bin/bash
# Make the boot animation video from galaxy.mp4 into a directory, e.g. a
# rootfs:
#
#   bash branding/boot-animation/make-boot-video.sh DEST_DIR
#   -> DEST_DIR/usr/share/gts9wifi/boot-animation/galaxy.mp4
#
# galaxy.mp4 (20 s, 1280x720, 24 fps): a galaxy swirls up and an Ubuntu logo
# blooms in its core at ~4.5 s.  gts9wifi-boot-animation.service plays it
# from ~4 s into the boot until GDM takes the screen, at least 5 s, so the
# video starts at 2.5 s (the swirl already bright, the logo ~2 s in).  Scaled
# here, once, to 2560x1440 (Lanczos plus a light unsharp mask: sharper than
# the display controller's scaler), H.264 High, no audio: the tablet's
# video block (iris) decodes it and the display controller shows it, so
# the CPU stays idle.  ~30 MB.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
dest=$1/usr/share/gts9wifi/boot-animation
mkdir -p "$dest"
ffmpeg -v error -y -ss 2.5 -i "$here/galaxy.mp4" -an \
	-vf "scale=2560:1440:flags=lanczos,unsharp=5:5:0.6:5:5:0.0" \
	-c:v libx264 -preset slow -crf 16 -profile:v high -level 5.1 -pix_fmt yuv420p \
	-movflags +faststart "$dest/galaxy.mp4"
du -h "$dest/galaxy.mp4"
