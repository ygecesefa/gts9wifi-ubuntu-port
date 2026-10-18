#!/bin/bash
# Build the gts9wifi (SM-X710) Ubuntu 24.04 desktop rootfs — stage A.
#
# Stage A is what the first SD boot test needs: stock Ubuntu GNOME (the
# package set of the S9 Ultra port), this tablet's kernel modules and firmware,
# and the X710 device services of the Fedora gts9wifi port.  The Ultra port's
# locally rebuilt packages (autofocus libcamera, sensors, mutter, ...) are
# stage B and are added once this image has booted.
#
# Deliberately conservative for a first boot:
#   - persist is mounted read-only (Fedora mounts it read-write)
#   - gts9wifi-bt-provision is not enabled (it rewrites boot/vendor_boot)
#   - the ADSP sensor chain is not enabled
#
# Needs root (mmdebstrap --mode=root).  Native arm64 host, no emulation.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
root=${GTS9WIFI_ROOT:-$(dirname "$repo")}
fedora=${FEDORA_REF:-$root/fedora-ref}
kernel_out=${KERNEL_OUT_DIR:-$root/build/gts9wifi-kernel/out}
firmware_tar=${FIRMWARE_TARBALL:-$root/backups/firmware/firmware-gts9wifi-from-fedora-sd.tar.gz}
rootfs=${ROOTFS_DIR:-$root/build/gts9wifi-rootfs}
suite=noble
mirror=${UBUNTU_MIRROR:-http://ports.ubuntu.com/ubuntu-ports}
hostname=gts9wifi
locale=${GTS9WIFI_LOCALE:-tr_TR.UTF-8}
keymap=${GTS9WIFI_KEYMAP:-tr}
timezone=${GTS9WIFI_TZ:-Europe/Istanbul}
user=${GTS9WIFI_USER:-ubuntu}
password=${GTS9WIFI_PW:?set GTS9WIFI_PW to the test user password}

[ "$(id -u)" = 0 ] || { echo 'run as root' >&2; exit 1; }
krel=$(cat "$kernel_out/kernel.release")
for f in "$kernel_out/modules-root/lib/modules/$krel" "$firmware_tar" "$fedora/rootfs/overlay"; do
	test -e "$f" || { echo "missing: $f" >&2; exit 1; }
done
case "$rootfs" in
	"$root"/build/*) ;;
	*) echo "refusing to build outside $root/build: $rootfs" >&2; exit 1 ;;
esac

# Package set of the S9 Ultra port, localised for Turkish instead of Spanish.
packages=$(tr -d ' \n' <<'EOF'
ubuntu-minimal,ubuntu-standard,
systemd,systemd-sysv,systemd-resolved,udev,dbus,
initramfs-tools,busybox-initramfs,
e2fsprogs,dosfstools,parted,gdisk,fdisk,
zstd,xz-utils,lz4,
sudo,locales,tzdata,console-setup,keyboard-configuration,
cloud-guest-utils,
apparmor,apparmor-utils,
snapd,squashfs-tools,
netplan.io,network-manager,wpasupplicant,
openssh-server,avahi-daemon,
protection-domain-mapper,qrtr-tools,linux-firmware,
iputils-ping,curl,wget,ca-certificates,
nano,less,htop,rsync,unzip,acl,python3,
usbutils,pciutils,ethtool,evtest,i2c-tools,v4l-utils,iw,
strace,tree,
ubuntu-desktop-minimal,gdm3,gnome-shell,gnome-session,gnome-control-center,
gnome-terminal,nautilus,gnome-text-editor,
gnome-snapshot,gstreamer1.0-gl,
mutter,xdg-desktop-portal-gnome,xdg-user-dirs,
yaru-theme-icon,yaru-theme-gtk,yaru-theme-sound,yaru-theme-gnome-shell,
gnome-keyring,libpam-gnome-keyring,
mesa-utils,mesa-vulkan-drivers,libgl1-mesa-dri,vulkan-tools,
libdrm-tests,edid-decode,
pipewire,pipewire-pulse,pipewire-audio,wireplumber,
pulseaudio-utils,
libspa-0.2-bluetooth,bluez,alsa-ucm-conf,alsa-utils,
iio-sensor-proxy,upower,power-profiles-daemon,
gstreamer1.0-plugins-good,gstreamer1.0-plugins-bad,
fonts-ubuntu,fonts-noto-color-emoji,
language-pack-tr,language-pack-gnome-tr,language-pack-en,
gnome-software,gnome-software-plugin-snap
EOF
)

hooks=$(mktemp -d)
trap 'rm -rf "$hooks"' EXIT
cat > "$hooks/configure.sh" <<HOOK
#!/bin/sh
set -eu
t="\$1"
echo '$hostname' > "\$t/etc/hostname"
printf '127.0.0.1\tlocalhost\n127.0.1.1\t$hostname\n::1\t\tlocalhost ip6-localhost ip6-loopback\n' > "\$t/etc/hosts"

printf '%s UTF-8\nen_US.UTF-8 UTF-8\n' '$locale' > "\$t/etc/locale.gen"
chroot "\$t" locale-gen >/dev/null
echo 'LANG=$locale' > "\$t/etc/default/locale"
ln -sf "/usr/share/zoneinfo/$timezone" "\$t/etc/localtime"
echo '$timezone' > "\$t/etc/timezone"
printf 'XKBMODEL="pc105"\nXKBLAYOUT="$keymap"\nXKBVARIANT=""\nXKBOPTIONS=""\nBACKSPACE="guess"\n' > "\$t/etc/default/keyboard"

# Labels, never device numbers: SD and UFS enumeration order is not fixed.
printf 'LABEL=GTS9W_ROOT\t/\text4\tdefaults,noatime,errors=remount-ro\t0 1\nLABEL=GTS9W_BOOT\t/boot\text4\tdefaults,noatime\t0 2\n' > "\$t/etc/fstab"

# LZ4 legacy initramfs: Samsung ABL concatenates the generic init_boot ramdisk
# with the vendor_boot fragment and rejects a gzip generic ramdisk.
cat > "\$t/etc/initramfs-tools/initramfs.conf" <<EOF
MODULES=most
BUSYBOX=y
KEYMAP=n
COMPRESS=lz4
COMPRESSLEVEL=9
DEVICE=
NFSROOT=auto
RUNSIZE=10%
EOF

mkdir -p "\$t/etc/netplan"
printf 'network:\n  version: 2\n  renderer: NetworkManager\n' > "\$t/etc/netplan/01-network-manager-all.yaml"
chmod 0600 "\$t/etc/netplan/01-network-manager-all.yaml"

cat > "\$t/etc/apt/sources.list.d/ubuntu.sources" <<EOF
Types: deb
URIs: $mirror
Suites: $suite $suite-updates $suite-backports $suite-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
rm -f "\$t/etc/apt/sources.list"

mkdir -p "\$t/etc/ssh/sshd_config.d"
printf 'PasswordAuthentication yes\nPermitRootLogin no\n' > "\$t/etc/ssh/sshd_config.d/10-gts9wifi.conf"
HOOK
chmod +x "$hooks/configure.sh"

echo "== 1/6 mmdebstrap $suite -> $rootfs"
if [ "${SKIP_BOOTSTRAP:-0}" = 1 ] && [ -x "$rootfs/usr/bin/gnome-shell" ]; then
	echo 'SKIP_BOOTSTRAP=1: reusing the existing package installation'
else
rm -rf -- "$rootfs"
mmdebstrap --mode=root --variant=apt --arch=arm64 \
	--components=main,restricted,universe,multiverse \
	--include="$packages" \
	--customize-hook="$hooks/configure.sh \"\$1\"" \
	"$suite" "$rootfs" \
	"deb $mirror $suite main restricted universe multiverse" \
	"deb $mirror $suite-updates main restricted universe multiverse" \
	"deb $mirror $suite-security main restricted universe multiverse"
fi

# Generic firmware under the device payload, as the Fedora port does.  Rootfs
# trees bootstrapped before linux-firmware was in the package set get it here.
if ! chroot "$rootfs" dpkg -s linux-firmware >/dev/null 2>&1; then
	echo "== installing linux-firmware into the existing rootfs"
	for d in proc sys dev; do mount --bind "/$d" "$rootfs/$d"; done
	saved=0
	if [ -e "$rootfs/etc/resolv.conf" ] || [ -L "$rootfs/etc/resolv.conf" ]; then
		mv "$rootfs/etc/resolv.conf" "$rootfs/etc/resolv.conf.gts9wifi-build"; saved=1
	fi
	cp -L /etc/resolv.conf "$rootfs/etc/resolv.conf"
	chroot "$rootfs" apt-get -o APT::Sandbox::User=root update -qq
	chroot "$rootfs" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends linux-firmware
	chroot "$rootfs" apt-get clean
	rm -f "$rootfs/etc/resolv.conf"
	[ "$saved" = 0 ] || mv "$rootfs/etc/resolv.conf.gts9wifi-build" "$rootfs/etc/resolv.conf"
	for d in dev sys proc; do umount "$rootfs/$d"; done
fi

echo "== 2/6 kernel modules ($krel) and device firmware"
install -d -m 0755 "$rootfs/usr/lib/modules"
rm -rf -- "$rootfs/usr/lib/modules/$krel"
cp -a --no-preserve=ownership "$kernel_out/modules-root/lib/modules/$krel" "$rootfs/usr/lib/modules/$krel"
test -f "$rootfs/usr/lib/modules/$krel/modules.dep" || { echo 'modules not in place' >&2; exit 1; }
chroot "$rootfs" depmod -a "$krel"
# Device payload goes last so it wins over linux-firmware's generic blobs.
tar -xzf "$firmware_tar" -C "$rootfs/usr/lib/firmware" --no-same-owner
install -d "$rootfs/boot/dtbs"
cp "$kernel_out/sm8550-samsung-gts9wifi.dtb" "$rootfs/boot/dtbs/"
cp "$kernel_out/Image.gz" "$rootfs/boot/vmlinuz-$krel"
cp "$kernel_out/config" "$rootfs/boot/config-$krel"

# 5 GHz RX: this tablet's WCN6855 reports qmi-chip-id=2, so ath11k picks the
# chip-id=2 exact-ABI slot of board-2.bin, which holds a generic payload (5 GHz
# RX ~40 dB weak: a phone hotspot 1 m away at -83 dBm).  The Fedora port put the
# device-tuned NTM_TW220 payload only into the chip-id=18 slot, which this unit
# never uses.  Copy it into the chip-id=2 slot as well (bdftool also updates
# that slot's variants, none of which this DTS selects).  Measured after the
# fix: the same hotspot at -41..-50 dBm, seven 5 GHz networks visible.
bdf=$rootfs/usr/lib/firmware/ath11k/WCN6855/hw2.1/board-2.bin
abi='bus=pci,vendor=17cb,device=1103,subsystem-vendor=17cb,subsystem-device=0108'
bdftool=$fedora/tools/bdftool.py
tuned_md5=6d42746b861fc52380a19dfdfaa702f1
slot_md5() { python3 -I "$bdftool" md5s "$bdf" | awk -v n="$abi,$1" '$3 == n {print $2}'; }
if [ "$(slot_md5 qmi-chip-id=2,qmi-board-id=255)" != "$tuned_md5" ]; then
	t=$(mktemp -d)
	python3 -I "$bdftool" dump "$bdf" "$abi,qmi-chip-id=18,qmi-board-id=255,variant=NTM_TW220" "$t/tuned.bin" >/dev/null
	[ "$(sha256sum "$t/tuned.bin" | cut -d' ' -f1)" = 77b1b9ef636ce8492723aa7c2ff2c42c2e5e81a43967d7f32bfdef93a31bf8c4 ] || {
		echo 'tuned WCN6855 payload not found in board-2.bin' >&2; exit 1; }
	python3 -I "$bdftool" swap "$bdf" "$t/fixed.bin" "$abi,qmi-chip-id=2,qmi-board-id=255" "$t/tuned.bin" >/dev/null
	install -m 0644 "$t/fixed.bin" "$bdf"
	rm -rf "$t"
fi
[ "$(slot_md5 qmi-chip-id=2,qmi-board-id=255)" = "$tuned_md5" ] || { echo 'board-2.bin chip-id=2 slot not tuned' >&2; exit 1; }

# The GPU probes before the root filesystem is mounted, so its firmware has to
# be inside the initramfs.
cat > "$rootfs/etc/initramfs-tools/hooks/gts9wifi-gpu-firmware" <<'EOF'
#!/bin/sh
[ "$1" = prereqs ] && exit 0
. /usr/share/initramfs-tools/hook-functions
for f in qcom/a740_sqe.fw qcom/gmu_gen70200.bin qcom/a740_zap.mdt \
	qcom/a740_zap.b00 qcom/a740_zap.b01 qcom/a740_zap.b02; do
	[ -f "/usr/lib/firmware/$f" ] && copy_file firmware "/usr/lib/firmware/$f"
done
exit 0
EOF
chmod 0755 "$rootfs/etc/initramfs-tools/hooks/gts9wifi-gpu-firmware"

echo "== 3/6 X710 device services (Fedora gts9wifi overlay)"
ov=$fedora/rootfs/overlay
cp -a "$ov/usr/libexec/." "$rootfs/usr/libexec/"
cp -a "$ov/usr/lib/udev/rules.d/." "$rootfs/usr/lib/udev/rules.d/"
cp -a "$ov/usr/lib/systemd/system-sleep/." "$rootfs/usr/lib/systemd/system-sleep/"
cp -a "$ov/usr/share/alsa/ucm2/." "$rootfs/usr/share/alsa/ucm2/"
cp -a "$ov/etc/systemd/logind.conf.d" "$ov/etc/systemd/journald.conf.d" "$rootfs/etc/systemd/"
for u in "$ov"/usr/lib/systemd/system/*; do
	case "${u##*/}" in
		gts9wifi-chronyd.service) continue ;;   # Ubuntu uses timesyncd
	esac
	cp -a "$u" "$rootfs/usr/lib/systemd/system/"
done
cp -a "$ov/etc/systemd/system/." "$rootfs/etc/systemd/system/"
# First boot: never write to the Android persist partition.
sed -i 's/^Options=rw,/Options=ro,/' "$rootfs/usr/lib/systemd/system/mnt-vendor-persist.mount"
sed -i 's/fedora-gts9wifi/ubuntu-gts9wifi/' "$rootfs/usr/libexec/gts9wifi-usb-gadget"
mkdir -p "$rootfs/vendor/dsp" "$rootfs/vendor/firmware_mnt" "$rootfs/mnt/vendor/persist"

# Ubuntu -> Android switch: the Android boot set saved before installation.
android=${ANDROID_BACKUP_DIR:-$root/backups/android-20261017}
db=$rootfs/usr/share/gts9wifi-dualboot/android
install -d -m 0700 "$db"
for n in boot init_boot vendor_boot dtbo; do
	install -m 0600 "$android/$n.img" "$db/$n.img"
done
(cd "$db" && sha256sum boot.img init_boot.img vendor_boot.img dtbo.img > SHA256SUMS)
diff <(grep -E ' (boot|init_boot|vendor_boot|dtbo)\.img$' "$android/SHA256SUMS" | sort) \
	<(sort "$db/SHA256SUMS") >/dev/null || { echo 'Android boot set differs from the backup' >&2; exit 1; }
install -m 0755 "$repo/dualboot/ubuntu-to-android" "$rootfs/usr/local/sbin/ubuntu-to-android"
printf '%%sudo ALL=(root) NOPASSWD: /usr/local/sbin/ubuntu-to-android\n' > "$rootfs/etc/sudoers.d/gts9wifi-android"
chmod 0440 "$rootfs/etc/sudoers.d/gts9wifi-android"
cat > "$rootfs/usr/share/applications/gts9wifi-android.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Android'e Geç
Comment=Android önyükleme imajlarını geri yükle ve yeniden başlat
Exec=sudo -n /usr/local/sbin/ubuntu-to-android
Icon=system-reboot
Terminal=true
Categories=System;
EOF

for unit in gts9wifi-usb-net.service gts9wifi-device-control.service \
	gts9wifi-panel-coldboot-recover.service gts9wifi-grow-rootfs.service \
	gts9wifi-wifi-recover.service \
	gts9wifi-x11-dir-fix.path vendor-dsp.mount vendor-firmware_mnt.mount \
	mnt-vendor-persist.mount gts9wifi-adsp-boot.service pd-mapper.service \
	ssh.service NetworkManager.service; do
	chroot "$rootfs" systemctl enable "$unit" >/dev/null 2>&1 || echo "  ! could not enable $unit"
done

echo "== 4/6 test user '$user'"
if ! chroot "$rootfs" id "$user" >/dev/null 2>&1; then
	chroot "$rootfs" useradd -m -s /bin/bash -G sudo,video,audio,input,render,netdev "$user" 2>/dev/null || \
		chroot "$rootfs" useradd -m -s /bin/bash -G sudo,video,audio,input "$user"
fi
echo "$user:$password" | chroot "$rootfs" chpasswd
chroot "$rootfs" passwd -e "$user" >/dev/null   # change the test password on first login

echo "== 5/6 initramfs for $krel"
for d in proc sys dev; do mount --bind "/$d" "$rootfs/$d"; done
trap 'for d in dev sys proc; do umount "$rootfs/$d" 2>/dev/null || true; done; rm -rf "$hooks"' EXIT
chroot "$rootfs" update-initramfs -c -k "$krel"
for d in dev sys proc; do umount "$rootfs/$d"; done
lsinitramfs "$rootfs/boot/initrd.img-$krel" | grep -cE 'a740_sqe|gmu_gen70200|a740_zap' | \
	awk '{ if ($1 < 6) { print "GPU firmware missing from initramfs" > "/dev/stderr"; exit 1 } }'

echo "== 6/6 summary"
du -sh "$rootfs"
printf 'kernel=%s\ninitramfs=%s\n' "$krel" "$rootfs/boot/initrd.img-$krel"
