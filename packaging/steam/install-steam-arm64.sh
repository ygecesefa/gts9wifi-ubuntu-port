#!/bin/bash
# Install Valve's ARM64 Steam client for the logged-in user (gts9wifi).
#
# Everything is downloaded from Valve and checked against Valve's own
# checksums before it is unpacked:
#   client   https://client-update.steamstatic.com/steam_client_linuxarm64
#            (the package list; each entry has a "sha2")
#   runtime  https://repo.steampowered.com/steamrt3c/images/<version>/
#            (SHA256SUMS in the same directory)
#
# Only two things are unpacked here: the client's bootstrap binary
# (steamrtarm64/steam) and the Steam Linux Runtime 3 for ARM64, whose
# libraries the bootstrap is started with. On its first start the client
# downloads the rest of itself (about 1 GB) into ~/.local/share/Steam.
#
# Run as the user, not as root. Nothing outside $HOME is written; the two
# system files (AppArmor profile, controller udev rules) come with the image,
# see README.md.
#
# The layout and the start line are the ones Switchdeck uses on the Nintendo
# Switch (https://github.com/SildurFX/Switchdeck, install-steam.sh, GPL-3.0),
# without its Tegra parts: no Box64, no client downgrade, no replaced
# DXVK/VKD3D, no ARMv8.0 Proton build.

set -euo pipefail

CLIENT_BASE=https://client-update.steamstatic.com
CLIENT_MANIFEST=${STEAM_MANIFEST:-steam_client_linuxarm64}
RT_BASE=https://repo.steampowered.com/steamrt3c/images
RT_CHANNEL=${STEAM_RUNTIME_CHANNEL:-latest-public-beta}
RT_NAME=steam-runtime-steamrt-arm64

STEAMROOT="$HOME/.local/share/Steam"
STEAMHOME="$HOME/.steam"
RTROOT="$STEAMROOT/steamrtarm64"
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

die() { echo "install-steam-arm64: $*" >&2; exit 1; }

[ "$(id -u)" != 0 ] || die "run as the user, not as root"
[ "$(uname -m)" = aarch64 ] || die "this is the ARM64 client; machine is $(uname -m)"
# The client and FEX are built for 4 KiB pages (Valve closed the 16 KiB report).
[ "$(getconf PAGESIZE)" = 4096 ] || die "kernel page size is $(getconf PAGESIZE), 4096 needed"
for t in curl unzip tar xz sha256sum awk; do
	command -v "$t" >/dev/null || die "missing tool: $t"
done
if pgrep -u "$(id -u)" -f 'steamrtarm64/steam' >/dev/null; then
	die "Steam is running; close it first"
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fetch() { curl -fL --retry 5 --retry-delay 2 -o "$2" "$1"; }
check() { # file sha256
	echo "$2  $1" | sha256sum -c --status - || die "checksum mismatch: $(basename "$1")"
}

mkdir -p "$STEAMROOT" "$STEAMHOME"

# --- client bootstrap ------------------------------------------------------
if [ ! -x "$RTROOT/steam" ] || [ -n "${FORCE:-}" ]; then
	echo "Steam client package list ($CLIENT_MANIFEST)"
	fetch "$CLIENT_BASE/$CLIENT_MANIFEST" "$tmp/manifest.vdf"
	# "bins_linuxarm64_linuxarm64" { "file" "<name>" ... "sha2" "<sha256>" ... }
	read -r zip sha < <(awk -v want='"bins_linuxarm64_linuxarm64"' '
		$1 == want { in_e = 1; next }
		in_e && $1 == "\"file\"" { gsub(/"/, "", $2); f = $2 }
		in_e && $1 == "\"sha2\"" { gsub(/"/, "", $2); s = $2 }
		in_e && $1 == "}" { print f, s; exit }' "$tmp/manifest.vdf")
	[ -n "${zip:-}" ] && [ ${#sha} = 64 ] || die "bins_linuxarm64_linuxarm64 not in the package list"
	case "$zip" in */*|*..*) die "unexpected file name in the package list: $zip" ;; esac
	echo "Downloading $zip"
	fetch "$CLIENT_BASE/$zip" "$tmp/bins.zip"
	check "$tmp/bins.zip" "$sha"
	unzip -q -o -d "$STEAMROOT" "$tmp/bins.zip" steamrtarm64/steam
	chmod 755 "$RTROOT/steam"
	rm -f "$tmp/bins.zip"
fi

# --- Steam Linux Runtime 3 (ARM64) -----------------------------------------
if [ ! -x "$RTROOT/pv-runtime/$RT_NAME/run" ] || [ -n "${FORCE:-}" ]; then
	ver=$(curl -fsSL "$RT_BASE/$RT_CHANNEL.txt" | tr -d '[:space:]')
	case "$ver" in ''|*[!0-9A-Za-z._-]*) die "unexpected runtime version: $ver" ;; esac
	echo "Steam Linux Runtime $ver"
	fetch "$RT_BASE/$ver/SHA256SUMS" "$tmp/SHA256SUMS"
	sha=$(awk -v f="*$RT_NAME.tar.xz" '$2 == f { print $1 }' "$tmp/SHA256SUMS")
	[ ${#sha} = 64 ] || die "$RT_NAME.tar.xz not in SHA256SUMS"
	fetch "$RT_BASE/$ver/$RT_NAME.tar.xz" "$tmp/rt.tar.xz"
	check "$tmp/rt.tar.xz" "$sha"
	rm -rf "$RTROOT/pv-runtime/$RT_NAME"
	mkdir -p "$RTROOT/pv-runtime"
	tar -xf "$tmp/rt.tar.xz" -C "$RTROOT/pv-runtime"
	rm -f "$tmp/rt.tar.xz"
fi

# --- the links Steam and games look for ------------------------------------
ln -fsn "$STEAMROOT" "$STEAMHOME/root"
ln -fsn "$STEAMROOT" "$STEAMHOME/steam"
ln -fsn "$STEAMROOT/linux32" "$STEAMHOME/sdk32"
ln -fsn "$STEAMROOT/linux64" "$STEAMHOME/sdk64"
ln -fsn "$STEAMROOT/linuxarm64" "$STEAMHOME/sdkarm64"
# The client looks for its 32-bit helpers (gldriverquery, vulkandriverquery)
# in steamrtarm32, which Valve does not ship; the 64-bit ones answer the same.
ln -fsn steamrtarm64 "$STEAMROOT/steamrtarm32"

# --- launcher and menu entry -----------------------------------------------
launcher=/usr/libexec/gts9wifi-steam
if [ ! -x "$launcher" ]; then           # not in the image: use the copy next to this script
	install -D -m 755 "$HERE/gts9wifi-steam" "$STEAMROOT/gts9wifi-steam"
	launcher="$STEAMROOT/gts9wifi-steam"
fi
# The shortcuts Steam itself creates call "steam steam://rungameid/N". In the
# image that is /usr/bin/steam; here ~/.local/bin, which Ubuntu puts on PATH
# at the next login if it exists.
if ! command -v steam >/dev/null; then
	mkdir -p "$HOME/.local/bin"
	ln -fsn "$launcher" "$HOME/.local/bin/steam"
fi
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/steam.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Steam
Comment=Valve's ARM64 Steam client
Exec=$launcher %U
Icon=steam
Terminal=false
Categories=Game;
MimeType=x-scheme-handler/steam;x-scheme-handler/steamlink;
StartupWMClass=steam
EOF
cat > "$HOME/.local/share/applications/steam-bigpicture.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Steam (Big Picture)
Comment=Steam's full-screen controller interface
Exec=$launcher --deck
Icon=steam
Terminal=false
Categories=Game;
EOF

# Screen on, rotation lock and heat protection while a game runs. In the
# image this is /usr/lib/systemd/user/gts9wifi-game-session.service.
if [ ! -x /usr/libexec/gts9wifi-game-session ]; then
	install -D -m 755 "$HERE/gts9wifi-game-session" "$STEAMROOT/gts9wifi-game-session"
	mkdir -p "$HOME/.config/systemd/user"
	sed "s|/usr/libexec/gts9wifi-game-session|$STEAMROOT/gts9wifi-game-session|" \
		"$HERE/gts9wifi-game-session.service" > "$HOME/.config/systemd/user/gts9wifi-game-session.service"
	systemctl --user daemon-reload
	systemctl --user enable --now gts9wifi-game-session.service
fi
# A Big Picture icon on the desktop too (GNOME's desktop icons start only
# files marked as trusted).
desktop_dir=$(xdg-user-dir DESKTOP 2>/dev/null || true)
if [ -n "$desktop_dir" ] && [ "$desktop_dir" != "$HOME" ] && [ -d "$desktop_dir" ]; then
	install -m 755 "$HOME/.local/share/applications/steam-bigpicture.desktop" \
		"$desktop_dir/Steam Big Picture.desktop"
	gio set "$desktop_dir/Steam Big Picture.desktop" metadata::trusted true 2>/dev/null || true
fi

# "Switch to Desktop" / "Return to Gaming Mode" (see steamos-session-select).
[ -x /usr/libexec/gts9wifi-steam-bin/steamos-session-select ] ||
	install -D -m 755 "$HERE/steamos-session-select" "$STEAMROOT/gts9wifi-bin/steamos-session-select"
[ -x /usr/libexec/gts9wifi-session-switch ] ||
	install -m 755 "$HERE/gts9wifi-session-switch" "$STEAMROOT/gts9wifi-session-switch"
manager=/usr/libexec/gts9wifi-game-manager
if [ ! -x "$manager" ]; then
	install -D -m 755 "$HERE/gts9wifi-game-manager" "$STEAMROOT/gts9wifi-game-manager"
	manager="$STEAMROOT/gts9wifi-game-manager"
fi
cat > "$HOME/.local/share/applications/gts9wifi-game-manager.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Galaxy Game Manager
Comment=Frame rate limit, performance overlay and graphics driver for Steam games
Exec=$manager
Icon=applications-games
Terminal=false
Categories=Game;Settings;
EOF

echo
echo "Done. Start Steam from the app grid; the first start downloads the client."
if [ "$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null)" = 1 ] &&
   [ ! -e /etc/apparmor.d/gts9wifi-steam ]; then
	echo "NOTE: this kernel restricts user namespaces and /etc/apparmor.d/gts9wifi-steam is missing (see README.md)."
fi
