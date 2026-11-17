#!/bin/bash
# GalaxyDeck: turn the image into a console-style tablet for Steam.
#
#   add-galaxydeck.sh ROOTFS USER
#
# Run by build-gts9wifi-rootfs.sh (GTS9WIFI_GALAXYDECK=1, the default), or on
# an already built rootfs. Needs root and network (apt inside the chroot).
#
# What goes in (each part is described in its own directory):
#   packaging/turnip      newer Turnip, Vulkan for Steam and its games only
#   packaging/gamescope   gamescope: Big Picture and games at a lower
#                         resolution, scaled to the panel
#   packaging/steam       Steam launcher, Game Manager, session service (screen
#                         on, rotation lock, heat protection, Android closed
#                         during games), "Switch to Desktop" support
# and the console-style login the user chose: automatic login, no forced
# password change, no lock screen, Big Picture at login, a one-time hint to
# change the default password.
#
# Not in the image: Valve's Steam client itself. Its first start downloads it
# from Valve (gts9wifi-steam-install, ~150 MB, then Steam updates itself), so
# the first start needs a network. Emulators are installed from the Game
# Manager on request (Flathub).
#
# Inputs (built separately, checked against their SHA256SUMS):
#   TURNIP_TAR     default $root/build/turnip/art/*/gts9wifi-turnip-*.tar.zst
#   GAMESCOPE_TAR  default $root/build/gamescope/out/gts9wifi-gamescope-*.tar.zst

set -euo pipefail

rootfs=${1:?usage: $0 ROOTFS USER}
user=${2:?usage: $0 ROOTFS USER}
repo=$(cd "$(dirname "$0")/.." && pwd)
root=${GTS9WIFI_ROOT:-$(dirname "$repo")}
steam=$repo/packaging/steam

[ "$(id -u)" = 0 ] || { echo "needs root" >&2; exit 1; }
[ -x "$rootfs/bin/bash" ] || { echo "not a rootfs: $rootfs" >&2; exit 1; }

pick() { # first match of a glob, must exist
	local f
	for f in $1; do [ -f "$f" ] && { echo "$f"; return; }; done
	echo "missing: $1" >&2; exit 1
}
turnip_tar=${TURNIP_TAR:-$(pick "$root/build/turnip/art/*/gts9wifi-turnip-*.tar.zst")}
gamescope_tar=${GAMESCOPE_TAR:-$(pick "$root/build/gamescope/out/gts9wifi-gamescope-*.tar.zst")}
for t in "$turnip_tar" "$gamescope_tar"; do
	(cd "$(dirname "$t")" && sha256sum -c --quiet SHA256SUMS) || { echo "checksum: $t" >&2; exit 1; }
done

# --- packages ----------------------------------------------------------------
echo "== GalaxyDeck: packages"
saved=0
net_enter() {
	for d in proc sys dev; do mount --bind "/$d" "$rootfs/$d"; done
	if [ -e "$rootfs/etc/resolv.conf" ] || [ -L "$rootfs/etc/resolv.conf" ]; then
		mv "$rootfs/etc/resolv.conf" "$rootfs/etc/resolv.conf.gts9wifi-build"; saved=1
	fi
	cp -L /etc/resolv.conf "$rootfs/etc/resolv.conf"
}
net_leave() {
	rm -f "$rootfs/etc/resolv.conf"
	[ "$saved" = 0 ] || mv "$rootfs/etc/resolv.conf.gts9wifi-build" "$rootfs/etc/resolv.conf"
	for d in dev sys proc; do umount "$rootfs/$d" 2>/dev/null || umount -l "$rootfs/$d"; done
}
net_enter
trap net_leave EXIT
chroot "$rootfs" apt-get -o APT::Sandbox::User=root update -qq
# Turnip needs libxcb-keysyms1; gamescope libavif16, libluajit-5.1-2,
# libseat1, libxres1; the Game Manager GTK 4 + libadwaita for Python.
chroot "$rootfs" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
	libxcb-keysyms1 libavif16 libluajit-5.1-2 libseat1 libxres1 \
	mangohud steam-devices joystick jstest-gtk solaar gvfs-backends gvfs-fuse \
	python3-gi gir1.2-gtk-4.0 gir1.2-adw-1 libnotify-bin curl unzip xz-utils
chroot "$rootfs" apt-get clean
net_leave
trap - EXIT

# --- Turnip and gamescope ----------------------------------------------------
echo "== GalaxyDeck: Turnip $(basename "$turnip_tar"), gamescope $(basename "$gamescope_tar")"
rm -rf "$rootfs/usr/lib/gts9wifi-turnip" "$rootfs/usr/lib/gts9wifi-gamescope"
tar -C "$rootfs" -xf "$turnip_tar"
tar -C "$rootfs" -xf "$gamescope_tar"
chroot "$rootfs" /usr/lib/gts9wifi-gamescope/bin/gamescope --version 2>&1 | grep -q 'gamescope version' || {
	echo "gamescope does not start in the rootfs" >&2; exit 1; }
if chroot "$rootfs" ldd /usr/lib/gts9wifi-turnip/lib/aarch64-linux-gnu/libvulkan_freedreno.so | grep -q 'not found'; then
	echo "Turnip has unresolved libraries" >&2; exit 1
fi

# --- Steam launcher, Game Manager, session service ---------------------------
echo "== GalaxyDeck: Steam launcher, Game Manager, session service"
install -m 0755 "$steam/gts9wifi-steam" "$rootfs/usr/libexec/gts9wifi-steam"
install -m 0755 "$steam/install-steam-arm64.sh" "$rootfs/usr/libexec/gts9wifi-steam-install"
install -m 0755 "$steam/gts9wifi-game-manager" "$rootfs/usr/libexec/gts9wifi-game-manager"
install -m 0755 "$steam/gts9wifi-game-session" "$rootfs/usr/libexec/gts9wifi-game-session"
install -m 0755 "$steam/gts9wifi-session-switch" "$rootfs/usr/libexec/gts9wifi-session-switch"
install -D -m 0755 "$steam/steamos-session-select" "$rootfs/usr/libexec/gts9wifi-steam-bin/steamos-session-select"
install -D -m 0755 "$steam/steamos-select-branch" "$rootfs/usr/libexec/gts9wifi-steam-bin/steamos-select-branch"
install -D -m 0644 "$steam/gts9wifi-game-session.service" "$rootfs/usr/lib/systemd/user/gts9wifi-game-session.service"
chroot "$rootfs" systemctl --global enable gts9wifi-game-session.service >/dev/null
# Steam's own shortcuts call "steam steam://rungameid/N".
cat > "$rootfs/usr/bin/steam" <<'EOF'
#!/bin/sh
# Valve's ARM64 Steam client (GalaxyDeck, packaging/steam/gts9wifi-steam).
exec /usr/libexec/gts9wifi-steam "$@"
EOF
chmod 0755 "$rootfs/usr/bin/steam"

apps=$rootfs/usr/share/applications
cat > "$apps/steam.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Steam
Comment=Valve's ARM64 Steam client
Exec=/usr/libexec/gts9wifi-steam %U
Icon=steam
Terminal=false
Categories=Game;
MimeType=x-scheme-handler/steam;x-scheme-handler/steamlink;
StartupWMClass=steam
EOF
cat > "$apps/steam-bigpicture.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Steam (Big Picture)
Comment=Steam's full-screen controller interface
Exec=/usr/libexec/gts9wifi-steam --deck
Icon=steam
Terminal=false
Categories=Game;
EOF
cat > "$apps/gts9wifi-game-manager.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Galaxy Game Manager
Comment=Big Picture, resolution, heat protection and emulators for games
Exec=/usr/libexec/gts9wifi-game-manager
Icon=applications-games
Terminal=false
Categories=Game;Settings;
EOF
install -D -m 0644 "$steam/gts9wifi-steam-bigpicture.desktop" \
	"$rootfs/etc/xdg/autostart/gts9wifi-steam-bigpicture.desktop"

# Default settings for every user: Big Picture drawn at 1920x1200 inside
# gamescope (games hung at start on the GNOME desktop, never inside it).
install -d "$rootfs/etc/skel/.config/gts9wifi"
printf 'RESOLUTION=1920x1200\n' > "$rootfs/etc/skel/.config/gts9wifi/steam.conf"
home=$(chroot "$rootfs" getent passwd "$user" | cut -d: -f6 || true)
if [ -n "$home" ] && [ -d "$rootfs$home" ] && [ ! -e "$rootfs$home/.config/gts9wifi/steam.conf" ]; then
	install -d "$rootfs$home/.config/gts9wifi"
	cp "$rootfs/etc/skel/.config/gts9wifi/steam.conf" "$rootfs$home/.config/gts9wifi/"
	chroot "$rootfs" chown -R "$user:$user" "$home/.config"
fi

# A desktop icon for the emulators, so a new user sees them: it opens the
# Game Manager and starts the install; the icon goes away once they are in.
install -d "$rootfs/etc/skel/Desktop"
cat > "$rootfs/etc/skel/Desktop/InstAll Emulators.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=InstAll Emulators
Comment=RetroArch, PlayStation 1-3, PSP, GameCube/Wii, DS, Switch, Dreamcast, Xbox and arcade emulators from Flathub (a few GB)
Exec=/usr/libexec/gts9wifi-game-manager --install-emulators
Icon=folder-download
Terminal=false
EOF
chmod 0755 "$rootfs/etc/skel/Desktop/InstAll Emulators.desktop"
if [ -n "$home" ] && [ -d "$rootfs$home" ]; then
	install -d "$rootfs$home/Desktop"
	install -m 0755 "$rootfs/etc/skel/Desktop/InstAll Emulators.desktop" "$rootfs$home/Desktop/"
	chroot "$rootfs" chown -R "$user:$user" "$home/Desktop"
fi

# --- console-style login -----------------------------------------------------
echo "== GalaxyDeck: automatic login, no lock screen"
conf=$rootfs/etc/gdm3/custom.conf
if ! grep -q '^AutomaticLoginEnable=true' "$conf"; then
	sed -i "s/^\[daemon\]\$/[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=$user/" "$conf"
fi
grep -q "^AutomaticLogin=$user\$" "$conf" || { echo "GDM automatic login not set" >&2; exit 1; }
# An expired password stops the automatic login: no forced change.
chroot "$rootfs" chage -d "$(date +%Y-%m-%d)" "$user"
cat > "$rootfs/usr/share/glib-2.0/schemas/90-gts9wifi-galaxydeck.gschema.override" <<'EOF'
# GalaxyDeck: the tablet wakes straight back into the game or Big Picture.
[org.gnome.desktop.screensaver]
lock-enabled=false
ubuntu-lock-on-suspend=false
EOF
chroot "$rootfs" glib-compile-schemas /usr/share/glib-2.0/schemas/

# Once per user: the default password is public, say how to change it.
cat > "$rootfs/usr/libexec/gts9wifi-password-hint" <<'EOF'
#!/bin/sh
mark="${XDG_CONFIG_HOME:-$HOME/.config}/gts9wifi/password-hint-shown"
[ -e "$mark" ] && exit 0
sleep 20
notify-send -u critical -i dialog-password -a GalaxyDeck "Change the default password" \
	"This tablet logs in without a password and the default password is 'ubuntu'. Set your own in Settings > System > Users."
mkdir -p "$(dirname "$mark")" && touch "$mark"
EOF
chmod 0755 "$rootfs/usr/libexec/gts9wifi-password-hint"
cat > "$rootfs/etc/xdg/autostart/gts9wifi-password-hint.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Default password hint
Exec=/usr/libexec/gts9wifi-password-hint
NoDisplay=true
X-GNOME-Autostart-Phase=Applications
EOF

echo "== GalaxyDeck: done"
