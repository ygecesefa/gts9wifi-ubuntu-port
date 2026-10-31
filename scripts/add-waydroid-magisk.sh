#!/bin/bash
# Stage Magisk (Delta) for Waydroid in a rootfs: root inside Android.
#
#   sudo scripts/add-waydroid-magisk.sh ROOTFS [DOWNLOAD_DIR]
#   sudo scripts/add-waydroid-magisk.sh --remove ROOTFS
#
# The same files casualsnek/waydroid_script ("install magisk") puts into
# Waydroid's overlay: the binaries from the Magisk Delta app under
# /system/etc/init/magisk, and a bootanim.rc whose triggers start Magisk
# (stuff/magisk.py).  They are staged in /usr/share/gts9wifi/waydroid-magisk;
# gts9wifi-waydroid-magisk copies them into /var/lib/waydroid/overlay before
# the container starts, because `waydroid init` with images shipped in the
# system (add-waydroid-images.sh) deletes the overlay.  The Magisk app then
# asks once for its "additional setup"; accept, Waydroid restarts.
#
# Magisk Delta: mistrmochov/magiskdeltaorig app-release.apk (the build
# waydroid_script downloads), pinned to commit 793a784 and its sha256.
set -euo pipefail

if [ "${1:-}" = --remove ]; then
	rm -rf "${2:?rootfs}/usr/share/gts9wifi/waydroid-magisk"
	exit 0
fi
rootfs=${1:?usage: $0 ROOTFS [DOWNLOAD_DIR]}
dl=${2:-$(cd "$(dirname "$0")/../.." && pwd)/build/waydroid-magisk}
url=https://github.com/mistrmochov/magiskdeltaorig/raw/793a78430bac879b8eb9bf72d03003ebc205c294/app-release.apk
sum=a3c37c4172b6ce7fdfbcccb2a608ef84b0a267d7aaef7c183047adceb8494c80
stage=$rootfs/usr/share/gts9wifi/waydroid-magisk
mkdir -p "$dl"

apk=$dl/magisk.apk
echo "$sum  $apk" | sha256sum -c --quiet 2>/dev/null || curl -fsSL -o "$apk" "$url"
echo "$sum  $apk" | sha256sum -c

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unzip -q "$apk" 'lib/arm64-v8a/*' 'assets/*' -d "$tmp"

rm -rf "$stage"
m=$stage/overlay/system/etc/init/magisk
mkdir -p "$m" "$stage/overlay/sbin"
for f in "$tmp"/lib/arm64-v8a/lib*.so; do
	n=${f##*/lib}; cp "$f" "$m/${n%.so}"
done
cp "$apk" "$m/magisk.apk"
cp -r "$tmp/assets/chromeos" "$m/"
for f in addon.d.sh boot_patch.sh stub.apk util_functions.sh; do cp "$tmp/assets/$f" "$m/"; done

bootanim='
service bootanim /system/bin/bootanimation
    class core animation
    user graphics
    group graphics audio
    disabled
    oneshot
    ioprio rt 0
    task_profiles MaxPerformance

'
init=$stage/overlay/system/etc/init
printf '%s' "$bootanim" | gzip -n > "$init/bootanim.rc.gz"
cat > "$init/bootanim.rc" <<EOF
$bootanim
on post-fs-data
    start logd
    exec u:r:su:s0 root root -- /system/etc/init/magisk/magiskpolicy --live --magisk
    exec u:r:magisk:s0 root root -- /system/etc/init/magisk/magiskpolicy --live --magisk
    exec u:r:update_engine:s0 root root -- /system/etc/init/magisk/magiskpolicy --live --magisk
    mkdir /dev/magisk_iqeoVo2mDrO 700
    exec u:r:su:s0 root root -- /system/etc/init/magisk/magisk64 --auto-selinux --setup-sbin /system/etc/init/magisk /dev/magisk_iqeoVo2mDrO
    exec u:r:su:s0 root root -- /dev/magisk_iqeoVo2mDrO/magisk --auto-selinux --post-fs-data

on nonencrypted
    exec u:r:su:s0 root root -- /dev/magisk_iqeoVo2mDrO/magisk --auto-selinux --service

on property:vold.decrypt=trigger_restart_framework
    exec u:r:su:s0 root root -- /dev/magisk_iqeoVo2mDrO/magisk --auto-selinux --service

on property:sys.boot_completed=1
    mkdir /data/adb/magisk 755
    exec u:r:su:s0 root root -- /dev/magisk_iqeoVo2mDrO/magisk --auto-selinux --boot-complete

on property:init.svc.zygote=restarting
    exec u:r:su:s0 root root -- /dev/magisk_iqeoVo2mDrO/magisk --auto-selinux --zygote-restart

on property:init.svc.zygote=stopped
    exec u:r:su:s0 root root -- /dev/magisk_iqeoVo2mDrO/magisk --auto-selinux --zygote-restart
EOF

# waydroid_script's permissions: Magisk's files root:shell(2000) 0755,
# the rest root:root, directories 0755, files 0644.
chown -R 0:0 "$stage"
find "$stage" -type d -exec chmod 0755 {} +
find "$stage" -type f -exec chmod 0644 {} +
chown -R 0:2000 "$m"
find "$m" -exec chmod 0755 {} +
find "$stage" -type f | sort
