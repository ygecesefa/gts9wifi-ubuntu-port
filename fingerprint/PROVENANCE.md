# Provenance of the fingerprint sources

`libfprint/`, `include/uapi/linux/spcom.h`, `build-libfprint-el721.sh` and
`build-fingerprint-secure-owner.sh` come from the Galaxy Tab S9 Ultra Ubuntu port
(agcarbajo/ubuntu-galaxy-tab-s9-ultra, commit 916e2f1), where the same EgisTec EL721
reader works end to end. Licences are unchanged (see `libfprint/copyright`:
LGPL-2.1+ for the libfprint driver, BSD-3-Clause for the QTEE bridge).

Changes for the X710 (gts9wifi), each visible in `git log -p` on these files:

- paths: firmware and runtime under `/var/lib/gts9wifi/fingerprint`,
  `/run/gts9wifi-*` state, `gts9wifi-gatekeeper`;
- the board code sent to the dualfp TA: `X716` (what this tablet's EL721
  driver reports) instead of `X916`;
- the touchscreen: FTS1BA90A at `10-0049` (Goodix `13-005d` on the Ultra);
  its FOD press/release interface is not written yet.

Nothing proprietary is in this repository: Samsung's binaries, the signed
TA and the calibration blobs are copied from the tablet's own partitions at
install time by `device/usr/libexec/gts9wifi-fingerprint-runtime`.
`liblog_capture.c` is this port's own (the Ultra port's equivalent is not
published).

The fingerprint UI chain comes from the same Ultra port commit:

- `device/usr/share/gnome-shell/extensions/gts9wifi-fingerprint-overlay@tabs9linux/`
  (Ultra: `gts9u-fingerprint-overlay@agcarbajo`, MIT): the optical target,
  the shade that compensates the panel's global HBM, and the lock-screen/GDM
  integration.  Changed: identifiers, and `geometry.js` for the 11" panel
  (short side 148.1 mm, sensor 20.6 mm in from the long axis' end, measured
  with evtest on the tablet).
- `device/usr/libexec/gts9wifi-fingerprint-ui` and its systemd/D-Bus files:
  the availability lease broker, D-Bus name `io.github.ygecesefa.Gts9wifiFingerprintUI`.
- `gnome-presented-bridge/`: the Clutter "presented" GObject bridge
  (typelib `Gts9wifiPresented`), built by `build-fingerprint-userspace.sh`.
