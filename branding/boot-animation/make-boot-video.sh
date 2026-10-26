#!/bin/bash
# Make the boot animation videos into a directory, e.g. a rootfs:
#
#   bash branding/boot-animation/make-boot-video.sh DEST_DIR
#   -> DEST_DIR/usr/share/gts9wifi/boot-animation/{ID.mp4,animations.list}
#
# gts9wifi-boot-animation.service plays the one chosen in Tab9 Extras
# (/var/lib/gts9wifi/boot-animation, default blackhole) from ~4 s into the boot
# until GDM takes the screen, at least 5 s.  Each source is cut to start
# where those first seconds look best, scaled here, once, to 2560x1440
# (Lanczos plus a light unsharp mask: sharper than the display controller's
# scaler), H.264 High, no audio: the tablet's video block (iris) decodes it
# and the display controller shows it, so the CPU stays idle.
#
# ANIMATIONS: id|label|start (s)|hold the last frame (s)
#   galaxy     20 s, 1280x720, 24 fps: a galaxy swirls up and an Ubuntu logo
#              blooms in its core at ~4.5 s; from 2.5 s the swirl is already
#              bright and the logo comes ~2 s in.  ~30 MB.
#   blackhole  10 s, 1280x720, 24 fps: a black hole, the camera dives into
#              it and an Ubuntu logo forms inside from ~7 s; from 3.5 s the
#              dive and the logo fit the first 5 s.  The video ends at 10 s,
#              so its last frame (the logo) is held for 10 s more in case GDM
#              is late (gst-launch would leave the screen black at the end).
#
# A new animation is a source video here plus one line below; the list file
# is what Tab9 Extras offers.
set -euo pipefail

ANIMATIONS='
blackhole|Black hole|3.5|10
galaxy|Galaxy|2.5|0
'

here=$(cd "$(dirname "$0")" && pwd)
dest=$1/usr/share/gts9wifi/boot-animation
mkdir -p "$dest"
: >"$dest/animations.list"
while IFS='|' read -r id label start hold; do
	[ -n "$id" ] || continue
	vf="scale=2560:1440:flags=lanczos,unsharp=5:5:0.6:5:5:0.0"
	[ "$hold" = 0 ] || vf="$vf,tpad=stop_mode=clone:stop_duration=$hold"
	ffmpeg -nostdin -v error -y -ss "$start" -i "$here/$id.mp4" -an -vf "$vf" \
		-c:v libx264 -preset slow -crf 16 -profile:v high -level 5.1 -pix_fmt yuv420p \
		-movflags +faststart "$dest/$id.mp4"
	printf '%s|%s\n' "$id" "$label" >>"$dest/animations.list"
	du -h "$dest/$id.mp4"
done <<EOF
$ANIMATIONS
EOF
