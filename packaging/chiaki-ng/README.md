# chiaki-ng with hardware video decoding (gts9wifi)

[chiaki-ng](https://github.com/streetpea/chiaki-ng) streams a PS4/PS5 to the
tablet (Remote Play). The Flathub build decodes the stream in software on
this tablet: its FFmpeg has only VAAPI, Vulkan and NVIDIA paths, and the
Adreno driver (Turnip) has no Vulkan Video (choosing *vulkan* gives a black
picture with sound). The tablet's video block, Qualcomm **iris**, is a
stateful **V4L2 M2M** decoder (`/dev/video17`); FFmpeg reaches it through its
`h264_v4l2m2m` / `hevc_v4l2m2m` decoders, which neither chiaki-ng nor its
FFmpeg build use.

`build-chiaki-ng-flatpak.sh` (or the *chiaki-ng* workflow) builds Flathub's
own manifest (pinned) with:

| | What |
|---|---|
| FFmpeg | `--enable-v4l2-m2m`, `h264_v4l2m2m`, `hevc_v4l2m2m` |
| [FFmpeg 0001](ffmpeg-patches/0001-v4l2m2m-drm-prime-output.patch) | the V4L2 M2M decoders can hand out their pictures as dmabufs (`AV_PIX_FMT_DRM_PRIME`) instead of copies: Lukas Rusak's series, the same as [packaging/ffmpeg](../ffmpeg/) patch 0002, on FFmpeg 7.1 |
| [0001](patches/0001-Decode-with-V4L2-M2M-decoders-v4l2m2m-hardware-decod.patch) | a **v4l2m2m** choice under *Settings → Video → Hardware Decoder*: decodes with the V4L2 M2M decoder; frames come back in system memory (NV12) and take the software frame path to the Vulkan renderer. Two things the stream does that iris does not take, each giving a green picture: the decoder opened at 0x0 (iris cannot set up its picture buffers: opened with the stream's size now), and SPS/PPS as a unit of their own (iris takes it as the end of the stream, then fails every buffer, firmware "session error 0x4000003": now held and sent in front of the next picture) |
| [0002](patches/0002-Takion-4-MiB-socket-receive-buffer.patch) | 4 MiB UDP receive buffer instead of 100 KiB: on this tablet the kernel dropped parts of each 1080p frame burst (`RcvbufErrors`), seen as glitches and corrupt frames |

| [0004](patches/0004-V4L2-M2M-take-the-decoder-s-pictures-as-dmabufs-DRM-P.patch) | **no copies of the picture**: asks the decoder for dmabuf frames and lets libplacebo import them into Vulkan (see "Zero copy" below). `CHIAKI_V4L2M2M_COPY=1` in the environment, or *zero copy* off in the settings, goes back to copies |
| [0005](patches/0005-Stream-menu-Fullscreen-switch.patch) | **Fullscreen switch in the stream menu** (next to Zoom and Stretch). On the tablet there was no way back to full screen during a stream: F11 needs a keyboard, and a double tap goes to the controller's touchpad (only a real mouse double click toggles it). Open the stream menu with the controller's menu shortcut or Ctrl+O |
| [0006](patches/0006-Controller-L2-R2-L3-R3-toggles-full-screen.patch) | **L2 + R2 + L3 + R3 on the controller toggles full screen** during a stream (on release, like the stream menu's L1 + R1 + L3 + R3). The buttons also reach the PlayStation, as with the menu combo |

0002 needs `net.core.rmem_max` of at least 4 MiB (Ubuntu's default is
208 KiB): `/etc/sysctl.d/90-gts9wifi-streaming.conf`.

Measured on the tablet with FFmpeg 6.1 (`ffmpeg -c:v h264_v4l2m2m`, 1080p60,
300 frames): H.264 decodes on iris with ~50 % of one core instead of ~380 %
in software; HEVC on iris hung in that FFmpeg (to be retested with the
Flatpak's FFmpeg 7.1).

`test/m2mtest.c` replays an H.264 file through a decoder the way chiaki-ng
feeds it (one access unit per network frame, send then pull, 60 fps). On the
tablet, `h264_v4l2m2m`, 1080p60, 299 access units:

| | frames out | packets dropped | picture |
|---|---|---|---|
| opened at 0x0 | 1 | 259 | luma 0 (green) |
| opened at 1920x1080 | 298 | 0 | luma 126, same as software |
| 1920x1080, SPS/PPS as a packet of their own (`SPLIT=1`, like the PS5) | 1 | 281 | green, "driver decode error" |

`test/drive-ffmpegdecoder.c` runs chiaki-ng's own patched
`ffmpegdecoder.c` the same way, SPS/PPS sent apart: 298 frames, no empty
frame, no firmware error. Found with an `ioctl` trace of the real session
(first output buffer: 41 bytes of SPS/PPS, then a LAST capture buffer and
`EIO` on every buffer after it).

## Install

Release `chiaki-ng-gts9wifi-1`: install steps, measurements and limits in
[RELEASE-NOTES-1.md](RELEASE-NOTES-1.md). On the tablet: ~30 % CPU instead of
~380 %, no dropped frames.

Not in the Ubuntu image yet (planned for a later version): the bundle, the
`net.core.rmem_max` sysctl and the Wi-Fi power-save setting.

## Zero copy (patch 0004, FFmpeg patch 0001)

Until build 2 every picture was copied twice on its way to the screen: out
of the decoder's buffer by FFmpeg, then up to the GPU by the renderer. The
Adreno GPU has no video decoder of its own (the reason Turnip has no Vulkan
Video), but it can take iris's pictures as they are: iris exports its
picture buffers as dmabufs, and Turnip imports a linear NV12 dmabuf.

What was measured on the tablet, 1080p60 H.264:

| Test | Result |
|---|---|
| `test/dmabuf-vulkan.c` (V4L2 and Vulkan only): picture 30 exported with `VIDIOC_EXPBUF`, imported into Turnip, read back through Vulkan | identical to the decoder's own mapping, byte for byte, both as two images (R8 + R8G8: libplacebo's way) and as one `G8_B8R8_2PLANE_420` image; colours right |
| the same, `BENCH=10`: decode only / + 1 copy / + 2 copies per picture | 3.4–4.0 % / 8.2 % / 12.3 % of one core: ~4.5 % (0.75 ms) per copy |
| `test/drive-ffmpegdecoder.c`: chiaki-ng's `ffmpegdecoder.c` with patch 0004 on FFmpeg 7.1 with the DRM PRIME patch | 118 of 118 frames as DRM PRIME (one dmabuf of 3133440 bytes, NV12, modifier LINEAR, Y at 0, UV at 2088960 = 1920 x 1088, pitch 1920); with `CHIAKI_V4L2M2M_COPY=1` 118 NV12 copies as before; transfer to software (the fallback path) works |

iris's NV12 layout: stride = width aligned to 128, UV plane at stride x
(height aligned to 32), one buffer for both planes.

Not measured yet: a stream from a PS5 through the whole application (the
renderer's import through libplacebo, CPU use of a session).
