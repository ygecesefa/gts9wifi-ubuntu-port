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
