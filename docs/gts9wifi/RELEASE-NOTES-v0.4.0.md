# v0.4.0 — Ubuntu 24.04 for the Galaxy Tab S9 Wi-Fi (SM-X710)

**Firefox with hardware video**, Google sign-in in **Waydroid**, a new
boot animation with a choice in Tab9 Extras, and the screen no longer
lighting up before an idle suspend.

**Testing status:** every change below was tested on the tablet on its
own. The v0.4.0 image as a whole has not been installed on a real tablet
before release: reports are welcome (issues on GitHub). If something is
wrong, `GTS9W_BACK/android-restore.zip` takes the tablet back to Android, as
before.

## The one file you need

`ubuntu-gts9wifi-v0.4.0-installer.zip` (check it with the `.sha256` next to
it), installed exactly like before: from the Magisk app as a module, or as a
recovery zip ([INSTALL.md](INSTALL.md)). The card needs 16 GB; 32 GB if you
want room for Android apps.

## New

### Firefox, with hardware video decoding

The image had no browser. It now has **Mozilla's Firefox** (`.deb` from
packages.mozilla.org, updated through apt; not Ubuntu's snap), and videos in
**H.264 and HEVC play on the tablet's video block** (Qualcomm iris) instead
of the CPU: every frame from iris, Firefox's decoder process at ~0 % CPU
instead of ~45 %. Nothing to switch on: `/etc/firefox/policies` turns
hardware decoding on for every profile.

What it took ([packaging/ffmpeg](../../packaging/ffmpeg/)): Firefox decodes
through the system FFmpeg, whose V4L2 M2M decoders reach iris, but dropped
them after the first frame. Ubuntu's FFmpeg 6.1.1 is rebuilt with two
patches: timestamps that survive when the caller sets no time base (Firefox
sets none: every frame came back without a time), and DRM PRIME (dmabuf)
output from the V4L2 decoders, which Firefox's V4L2 path expects (Lukas
Rusak's series from Kodi/LibreELEC). The patched libraries are pinned so an
Ubuntu FFmpeg update does not replace them unnoticed.

VP9 and AV1 (YouTube's defaults) still decode in software: Firefox decodes
them with its own bundled FFmpeg, which has no V4L2 decoders. A YouTube
add-on that asks for H.264 (e.g. *enhanced-h264ify*) should make YouTube use
the hardware path; this was not tested on the tablet.

### Waydroid: Google sign-in and Android storage

On v0.3.0 Android's internal storage never mounted (a "system error" at the
first launch, apps crashing on storage) and the Google sign-in hung at
*Checking info…* / *Something went wrong*, even after registering the device.
Cause: Waydroid's arm64 vendor image declares an OMX codec service it does
not ship; Android's media server waits for it forever, the storage service
that needs it is killed and restarted every minute. `gts9wifi-waydroid-omx-fix`
now runs before Waydroid starts and puts a copy of the image's manifest
without that entry into Waydroid's overlay (the downloaded image itself is
not changed; nothing happens once Waydroid's image is fixed). On the tablet:
storage mounts, Play Store sign-in works.

You still register the device once for GApps (Google requires it for
uncertified devices): [RELEASE-NOTES-v0.3.0.md](RELEASE-NOTES-v0.3.0.md#android-apps-waydroid).

### Boot animation: Black hole (new default), or Galaxy

A new animation: a black hole, a dive into it, and the Ubuntu logo forming
inside. *Tab9 Extras → Boot → Boot animation* picks it or the Galaxy one
from v0.3.0; the list is read from
`/usr/share/gts9wifi/boot-animation/animations.list`, so more can be added.

### The screen no longer lights up before an idle suspend

Shortly before suspending on its own, GNOME showed "Automatic suspend —
Suspending soon because of inactivity" as an urgent notification, which
turned the dark screen back on. GNOME skips that warning on tablets, but
this one reports itself as a convertible (so the power key can tell a press
from a hold); Tab9 Extras now drops the warning. The suspend comes at the
same time as before.

### Smaller image

Firmware for hardware the tablet cannot have (NVIDIA GPUs, Mellanox and
Marvell network switches, ~260 MB) is left out.

## Known issues

- VP9/AV1 video in Firefox decodes in software (see above). Chromium-based
  browsers have no V4L2 decoder outside ChromeOS.
- The boot animation starts ~4 s into the boot (a black screen before).
- Fingerprint enrolment works but GNOME Settings shows no progress
  (~17 touches).
- Linux 7.2.1–7.2.6 break Wi-Fi on this tablet; the kernel stays on 7.2.0.

## Already on v0.3.0?

Most of this can be applied on a running tablet; see the commits for each
part. The Waydroid fix is two files:
[`device/usr/libexec/gts9wifi-waydroid-omx-fix`](../../device/usr/libexec/gts9wifi-waydroid-omx-fix)
to `/usr/libexec/` and
[`gts9wifi-omx-fix.conf`](../../device/etc/systemd/system/waydroid-container.service.d/gts9wifi-omx-fix.conf)
to `/etc/systemd/system/waydroid-container.service.d/`, then
`sudo systemctl daemon-reload && sudo systemctl restart waydroid-container`.
