# FFmpeg (libavcodec60) for hardware video in Firefox

Ubuntu noble's FFmpeg 6.1.1 with patches for the V4L2 M2M decoders that
drive the tablet's video block (Qualcomm iris, `/dev/video*` named
`qcom-iris-decoder`).

Mozilla's Firefox `.deb` (packages.mozilla.org, not Ubuntu's snap, which
brings its own FFmpeg) decodes H.264 and HEVC through the system
`libavcodec.so.60`, and libavcodec's `h264_v4l2m2m` / `hevc_v4l2m2m` reach
iris. Unpatched, Firefox shows the first frame from iris, then drops the
hardware decoder and decodes in software.

Result on the tablet (H.264 High 2560x1440 24 fps, `MOZ_LOG=FFmpegVideo:5`):
every frame from iris (`V4L2 Got one frame`, 1135 frames, no
`IsHardwareAccelerated=false`), Firefox's decoder process at ~0 % CPU
instead of ~45 % in software.

## Patches

| Patch | Fixes |
|---|---|
| `0001-v4l2-buffers-pass-timestamps-without-time-base.patch` | libavcodec rescales packet timestamps with `pkt_timebase`, else `time_base`. Firefox sets neither (a decoder's `time_base` defaults to 0/1): every packet went to iris at timestamp 0 and every frame came back as `AV_NOPTS_VALUE` (a division by the 0 numerator). With neither valid, timestamps now pass through unchanged (V4L2's own 1/1000000). |
| `0002-v4l2m2m-drm-prime-output.patch` | Firefox's V4L2 path takes `frame->data[0]` as an `AVDRMFrameDescriptor` and imports the dmabuf (it was written for the Raspberry Pi FFmpeg); upstream v4l2m2m returns NV12 copies in system memory, so Firefox read pixels as a descriptor and gave up after the first frame. Lukas Rusak's series (Kodi; carried by LibreELEC, taken from LibreELEC.tv `4fada3363c`, FFmpeg 6.0.1) outputs `AV_PIX_FMT_DRM_PRIME` frames that point at the V4L2 capture buffers, NV12 still available. Two lines of the decoder definition placed by hand for 6.1. |

chiaki-ng needed two more iris workarounds
([packaging/chiaki-ng](../chiaki-ng/), patch 0001): the decoder opened with
the stream size, and SPS/PPS sent in front of the next picture. Firefox does
not hit them: it gives the size and `avcC` extradata at open, and
libavcodec's `h264_mp4toannexb` filter puts SPS/PPS in front of each IDR.

## Build

```sh
sudo FFMPEG_SUFFIX=+gts9wifi2 packaging/ffmpeg/build-ffmpeg-debs.sh
# -> build/gts9wifi-ffmpeg/out/*_6.1.1-3ubuntu5+gts9wifi2_*.deb
```

A throwaway arm64 noble chroot (`mmdebstrap`), `apt-get source
ffmpeg=7:6.1.1-3ubuntu5`, the patches appended to `debian/patches`,
`dpkg-buildpackage -b` (both of Ubuntu's flavours, standard and extra;
~35 min on a Raspberry Pi 5). `--source-only` stops after applying the
patches.

## In the image

`scripts/build-gts9wifi-rootfs.sh` installs `libavcodec60`, `libavutil58`
and `libswresample4` from this build (the versions depend on each other
exactly), pins them (`/etc/apt/preferences.d/gts9wifi-ffmpeg`, priority
1001) so an Ubuntu update of `ffmpeg` does not replace them unnoticed,
installs Mozilla's Firefox, and `etc/firefox/policies/policies.json` sets
`media.hardware-video-decoding.force-enabled` for every profile. When
Ubuntu ships a new `ffmpeg`, rebuild with `FFMPEG_VERSION=` set to it.

On a running tablet: `sudo apt install ./libavcodec60_*.deb ./libavutil58_*.deb
./libswresample4_*.deb` (and the `-dev`/other FFmpeg packages that are
installed, from the same build), plus the pin and the policy file.
