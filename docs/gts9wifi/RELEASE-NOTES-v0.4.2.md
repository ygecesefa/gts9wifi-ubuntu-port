# v0.4.2 — Ubuntu 24.04 for the Galaxy Tab S9 Wi-Fi (SM-X710)

A fix release: **no more Wi-Fi stutter every half minute**, which game
streaming (chiaki-ng) showed as a short freeze about once a minute.

## Wi-Fi: no background scan while connected

When the router uses one network name on 2.4 and 5 GHz (or on several
access points) and the signal is under -65 dBm, NetworkManager has
wpa_supplicant look for a better access point every 30 seconds. On this
tablet each of those scans visits every 2.4, 5 and 6 GHz channel for about
7 seconds, and the connection stalls meanwhile.

Measured on the tablet (5 GHz, -78 dBm, pinging the router):

| | before | after |
|---|---|---|
| background scans | every ~35 s, ~7 s each | none |
| pings over 30 ms | 39 in 90 s (up to 220 ms) | none in 75 s |
| average | 13 ms | 3.9 ms |

A NetworkManager dispatcher script
([`90-gts9wifi-no-bgscan`](../../device/etc/NetworkManager/dispatcher.d/90-gts9wifi-no-bgscan))
turns the background scan off once Wi-Fi is up. The tablet still moves to
another access point when the connection is lost, only not while it works.
To keep roaming (e.g. a mesh network), delete that file.

**On v0.4.0 / v0.4.1** the same fix, without reinstalling:

```sh
sudo wget -O /etc/NetworkManager/dispatcher.d/90-gts9wifi-no-bgscan \
https://raw.githubusercontent.com/ygecesefa/gts9wifi-ubuntu-port/main/device/etc/NetworkManager/dispatcher.d/90-gts9wifi-no-bgscan
sudo chmod 755 /etc/NetworkManager/dispatcher.d/90-gts9wifi-no-bgscan
nmcli radio wifi off; nmcli radio wifi on
```

## Waydroid

For your own builds: `scripts/add-waydroid-images.sh` puts Waydroid's
GApps images (with the Play Store) into the image, now the `arm64_only`
ones (this CPU has no 32-bit mode; the plain arm64 images make Android
restart at once), and `scripts/add-waydroid-magisk.sh` adds Magisk inside
Waydroid. The release image has neither (too big for a release file);
Waydroid downloads its image on the first launch, as before.

## Still true from v0.4.1

**Do not upgrade to Ubuntu 26.04**: see
[RELEASE-NOTES-v0.4.1.md](RELEASE-NOTES-v0.4.1.md). The offer is off in
this image.

## Testing status

The Wi-Fi fix was measured on the tablet as above. The v0.4.2 image as a
whole was not installed on a real tablet before release;
`GTS9W_BACK/android-restore.zip` takes the tablet back to Android, as
before.
