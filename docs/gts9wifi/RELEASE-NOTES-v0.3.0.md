# v0.3.0 (in progress) — Ubuntu 24.04 for the Galaxy Tab S9 Wi-Fi (SM-X710)

**Not released yet.** These changes are in the repository and were tested
on the tablet one by one; the v0.3.0 installer zip (a new image built from
them) has not been built or tested yet. Until it is, v0.2.0 is the release
to install.

## New

### Android apps: Waydroid

Waydroid comes installed. Its first launch (app grid → *Waydroid*) asks
for Vanilla or GApps and downloads the Android image (LineageOS 20,
Android 13; ~1 GB, ~3 GB on the card: use a 32 GB card if you want room for
apps). On the tablet: boots, GPU-accelerated (`freedreno FD740`,
OpenGL ES 3.2, Mesa 26), network.

What this tablet needed:
- its own binder devices (`binder.devices=…,anbox-binder,anbox-hwbinder,anbox-vndbinder`
  in the kernel command line): the fingerprint stack already holds
  `vndbinder`;
- Waydroid binds the host's `/vendor/lib64/egl` into the container (meant
  for Halium phones); here `/vendor` is Samsung's Android vendor partition,
  so the container got Qualcomm's Android-only Adreno driver and Android's
  display server aborted. `waydroid-container.service.d` hides `/vendor`
  from Waydroid only.

GApps: Google refuses the sign-in ("Something went wrong") until the
device is registered: read its ID with
`sudo waydroid shell -- sqlite3 /data/data/com.google.android.gsf/databases/gservices.db "select value from main where name='android_id';"`
and enter it at <https://www.google.com/android/uncertified>.

### PlayStation Remote Play with hardware decoding: chiaki-ng

chiaki-ng comes installed, patched to decode the stream on the tablet's
video block (Qualcomm iris, V4L2 M2M) instead of the CPU: PS5 1080p60 H.264
at ~30 % of one core instead of ~380 %, smooth, no dropped frames
([packaging/chiaki-ng](../../packaging/chiaki-ng/), release
`chiaki-ng-gts9wifi-1`). *Hardware Decoder: auto* picks it. Use **H264**;
H.265 is not verified on iris yet. A 4 MiB UDP buffer and Wi-Fi power
save off (both in the image) removed the glitches.

### Boot animation

A galaxy swirls up around the Ubuntu logo instead of kernel text: the
video is decoded by iris and shown by the display controller
(`gts9wifi-boot-animation.service`, [branding/boot-animation](../../branding/boot-animation/)).
Kernel messages no longer go to the screen (serial console and `dmesg`
only). Plymouth was tried first and dropped: it draws every frame in
software and stuttered on the 2560×1600 panel.

### Faster boot

The login screen comes at ~9 s instead of ~16 s:
`gts9wifi-panel-coldboot-recover` now runs its 7 s platform suspend cycle
only when the panel really did not answer at probe (its ID read
00 00 00); on this tablet it always answers.

### Power key and screen lock

- Waking with the power key no longer puts the tablet straight back to
  sleep (the screen came on for a moment, then went off): a press while
  the screen is dark, while a suspend is on its way, or right after a
  resume only wakes it.
- *Tab9 Extras → Screen lock → Wake without the password* (off by
  default): the password is asked once, at login.

### Network

- Wi-Fi uses the tablet's own MAC address (from Samsung's EFS, read-only)
  instead of a new random one at every boot, so the router keeps giving it
  the same IP address.
- Wi-Fi power save off: steady latency (~5 ms to the router instead of
  50 ms average with 140 ms peaks).

## Recovery

Separate release `recovery-orangefox-1`: OrangeFox that decrypts `/data` on
LineageOS 22, plus `vbmeta-disabled-SM-X710.tar.md5` for stock One UI.

## Known issues

- Browsers still decode video in software. Firefox finds iris (V4L2 M2M)
  but drops it after the first frame: its frames come back without a
  timestamp because Firefox leaves FFmpeg's time base unset; a fix in
  FFmpeg is possible (not done yet). Chromium has no V4L2 decoder outside
  ChromeOS.
- The boot animation starts ~4 s into the boot (a black screen before).
