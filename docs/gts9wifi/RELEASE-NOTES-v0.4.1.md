# v0.4.1 — Ubuntu 24.04 for the Galaxy Tab S9 Wi-Fi (SM-X710)

A fix release: **do not upgrade to Ubuntu 26.04**, and support for Android
ROMs whose partitions are erofs (HyperOS ports).

## ⚠️ Do not accept "Upgrade to Ubuntu 26.04"

GNOME offers the new Ubuntu release. On this image the upgrade replaces the
packages rebuilt for the tablet with Ubuntu's own, and the tablet loses:

- the cameras (Ubuntu's libcamera replaces the one with autofocus and the
  software ISP),
- the fingerprint reader (Ubuntu's libfprint has no EL721 driver),
- Waydroid (removed: its repository is switched off by the upgrade),
- Firefox's hardware video (Ubuntu's Firefox snap comes back).

There is no way back short of installing again. v0.4.1 turns the offer off
(`/etc/update-manager/release-upgrades`: `Prompt=never`). **On v0.4.0, turn
it off yourself:**

```sh
sudo sed -i 's/^Prompt=.*/Prompt=never/' /etc/update-manager/release-upgrades
```

Normal updates (security fixes within 24.04) are not affected. A port to
26.04 means rebuilding those packages and will come as a release of its own.

Already upgraded? Install v0.4.1 again (answer YES to "ERASE the card");
copy what you need off the card first.

## Android ROMs with erofs partitions (HyperOS ports)

Some ROMs ship Samsung's vendor image as erofs instead of ext4. Ubuntu
mounts Android's `vendor` read-only for the sensors' configuration
(rotation, light, compass) and the fingerprint reader's Android helpers;
the mount only knew ext4 and failed. It now takes either, and the zips also
recognise the tablet by `ro.product.vendor.device` when a ROM renames the
rest. Tested on the tablet: the HyperOS port's vendor (erofs) mounts and
holds everything Ubuntu reads from it.

## Waydroid with the Play Store built in (build it yourself)

The image does not contain an Android image: the first launch of Waydroid
downloads one (~1 GB). The GApps images do not fit into a release file
(GitHub's 2 GiB limit), but the build can include them:
`WAYDROID_GAPPS=1` for `scripts/build-gts9wifi-rootfs.sh`, or
`scripts/add-waydroid-images.sh` on a built rootfs. The OMX fix from v0.4.0
now also applies to such built-in images.

## Testing status

The changes were tested on the tablet on their own (the erofs mount, the
upgrade setting). The v0.4.1 image as a whole was not installed on a real
tablet before release; `GTS9W_BACK/android-restore.zip` takes the tablet
back to Android, as before.

Everything else is as in [v0.4.0](RELEASE-NOTES-v0.4.0.md).
