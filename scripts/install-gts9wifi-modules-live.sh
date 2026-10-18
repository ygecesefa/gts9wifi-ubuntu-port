#!/bin/bash
# Install a freshly built module tree on the running gts9wifi Ubuntu.
#
#   install-gts9wifi-modules-live.sh TARBALL [SSH_TARGET [SSH_OPTION...]]
#
#   TARBALL     tar.gz whose top directory is the kernel release
#               (e.g. 7.2.0-gts9wifi/), as made from out/modules-root/lib/modules
#   SSH_TARGET  default gts9wifi (Tailscale); without Wi-Fi go through the
#               USB network of the host the tablet is plugged into: copy
#               this script and the tarball there and use ubuntu@172.16.42.1
#
# The kernel is built with DEBUG_INFO_BTF_MODULES and without
# MODULE_ALLOW_BTF_MISMATCH, so modules from any other build of the tree are
# refused.  Whenever boot.img gets a new kernel, the matching modules must be
# installed with it.  The old tree is kept as <release>.bak-<date> on the
# tablet; nothing outside /usr/lib/modules is touched (no partitions).
# SUDO_PASS in the environment answers sudo on the tablet; otherwise sudo
# must work without a password.  SSHPASS, if set, is the tablet's SSH
# password (through sshpass -e) for hosts without the gts9wifi key.
set -euo pipefail

tarball=${1:?usage: $0 TARBALL [SSH_TARGET [SSH_OPTION...]]}
target=${2:-gts9wifi}
shift $(( $# >= 2 ? 2 : 1 ))
ssh_opts=("$@")
# awk reads the whole listing: head would SIGPIPE tar under pipefail.
krel=$(tar -tzf "$tarball" | awk -F/ 'NR == 1 { print $1 }')
sum=$(sha256sum "$tarball" | cut -d' ' -f1)
remote=/tmp/${tarball##*/}
wrap=()
[ -n "${SSHPASS:-}" ] && wrap=(sshpass -e)

[[ $krel =~ ^[0-9]+\.[0-9]+\.[0-9]+- ]] || { echo "unexpected top directory '$krel' in $tarball" >&2; exit 1; }
tar -tzf "$tarball" "$krel/modules.dep" >/dev/null 2>&1 \
	|| { echo "$tarball has no module tree" >&2; exit 1; }

echo "== copy $tarball ($sum) to $target"
"${wrap[@]}" scp -q "${ssh_opts[@]}" "$tarball" "$target:$remote"

echo "== install $krel on $target"
# shellcheck disable=SC2029  # values are meant to expand locally
"${wrap[@]}" ssh "${ssh_opts[@]}" "$target" \
	"SUDO_PASS='${SUDO_PASS:-}' bash -s -- '$krel' '$remote' '$sum'" <<'REMOTE'
set -euo pipefail
krel=$1 tarball=$2 sum=$3
if [ -n "$SUDO_PASS" ]; then
	asroot() { printf '%s\n' "$SUDO_PASS" | sudo -S -p '' "$@"; }
else
	asroot() { sudo -n "$@"; }
fi
echo "$sum  $tarball" | sha256sum -c --quiet
[ "$(uname -r)" = "$krel" ] || echo "note: running $(uname -r), installing $krel"
mods=/usr/lib/modules/$krel
stage=$mods.new
backup=$mods.bak-$(date +%Y%m%d-%H%M%S)
asroot rm -rf "$stage"
asroot mkdir -p "$stage"
asroot tar -xzf "$tarball" -C "$stage" --strip-components=1 --no-same-owner
[ -d "$mods" ] && asroot mv "$mods" "$backup" && echo "old tree kept: $backup"
asroot mv "$stage" "$mods"
asroot depmod -a "$krel"
rm -f "$tarball"
echo "== modules: $(find "$mods" -name '*.ko*' | wc -l)"
if [ "$(uname -r)" = "$krel" ]; then
	# A module that failed BTF/vermagic checks earlier stays unloaded until
	# it is probed again; reloading ath11k is enough to bring Wi-Fi back.
	asroot modprobe -r ath11k_pci 2>/dev/null || true
	asroot modprobe ath11k_pci && echo "ath11k_pci loaded"
	sleep 8
	nmcli -t -f DEVICE,TYPE,STATE dev | grep -E ':wifi:' || echo "no Wi-Fi device yet"
	journalctl -k -b --no-pager | grep -iE 'BTF|disagrees|invalid module format' | tail -5 || true
fi
REMOTE
echo "done; reboot the tablet to load every module from the new tree"
