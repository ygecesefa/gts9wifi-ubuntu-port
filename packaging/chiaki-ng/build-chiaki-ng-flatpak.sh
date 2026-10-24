#!/bin/bash
# Build chiaki-ng (PlayStation Remote Play) as a Flatpak bundle that decodes
# with the tablet's video block (Qualcomm iris, V4L2 M2M).
#
#   bash packaging/chiaki-ng/build-chiaki-ng-flatpak.sh [WORK_DIR]
#
# Needs an aarch64 Linux host with flatpak and flatpak-builder (GitHub
# Actions: .github/workflows/chiaki-ng.yml, ubuntu-24.04-arm).  Output:
# WORK_DIR/out/chiaki-ng-gts9wifi.flatpak and SHA256SUMS.
#
# Recipe, all pinned:
#   1. Flathub's own manifest for io.github.streetpea.Chiaki4deck (the
#      chiaki-ng build users get from Flathub).
#   2. Its FFmpeg is built with --disable-all and only software and
#      VAAPI/Vulkan decoders: add the V4L2 M2M decoders.
#   3. chiaki-ng gets our patches in packaging/chiaki-ng/patches/.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(realpath -m "${1:-$HOME/chiaki-ng-build}")

fh_repo=https://github.com/flathub/io.github.streetpea.Chiaki4deck.git
fh_commit=c2503d11f56b6184b2d511c2b79b6a03bb2a1f53
app=io.github.streetpea.Chiaki4deck

[ "$(uname -m)" = aarch64 ] || { echo "needs an aarch64 host (the tablet's architecture)" >&2; exit 1; }
mkdir -p "$work"

echo "== 1/3 Flathub manifest $fh_commit"
fh=$work/flathub
rm -rf "$fh"
git clone -q "$fh_repo" "$fh"
git -C "$fh" checkout -q "$fh_commit"

echo "== 2/3 V4L2 M2M decoders in FFmpeg, chiaki-ng patches"
cp "$here"/patches/*.patch "$fh/"
python3 - "$fh/$app.yaml" "$here"/patches/*.patch <<'PY'
import os, sys, yaml
path, patches = sys.argv[1], sys.argv[2:]
m = yaml.safe_load(open(path))
mods = {x['name']: x for x in m['modules'] if isinstance(x, dict)}
mods['ffmpeg']['config-opts'] += [
    '--enable-v4l2-m2m',
    '--enable-decoder=h264_v4l2m2m',
    '--enable-decoder=hevc_v4l2m2m',
]
mods['chiaki-ng']['sources'] += [{'type': 'patch', 'path': os.path.basename(p)} for p in patches]
# The current KDE SDK's CMake installs json-c and miniupnpc under /app/lib64
# on aarch64, where chiaki-ng's pkg-config lookup does not search.
mods['chiaki-ng'].setdefault('build-options', {})['prepend-pkg-config-path'] = '/app/lib64/pkgconfig'
yaml.safe_dump(m, open(path, 'w'), sort_keys=False)
PY
grep -n "v4l2\|\.patch" "$fh/$app.yaml"

echo "== 3/3 build"
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
cd "$fh"
flatpak-builder --user --install-deps-from=flathub --force-clean --disable-rofiles-fuse \
	--repo="$work/repo" "$work/build" "$app.yaml"
rm -rf "$work/out" && mkdir -p "$work/out"
flatpak build-bundle --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo \
	"$work/repo" "$work/out/chiaki-ng-gts9wifi.flatpak" "$app"
(cd "$work/out" && sha256sum * > SHA256SUMS && cat SHA256SUMS)
