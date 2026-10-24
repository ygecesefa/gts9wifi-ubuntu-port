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
| [0001](patches/0001-Decode-with-V4L2-M2M-decoders-v4l2m2m-hardware-decod.patch) | a **v4l2m2m** choice under *Settings → Video → Hardware Decoder*: decodes with the V4L2 M2M decoder; frames come back in system memory (NV12) and take the software frame path to the Vulkan renderer. Two things the stream does that iris does not take, each giving a green picture: the decoder opened at 0x0 (iris cannot set up its picture buffers: opened with the stream's size now), and SPS/PPS as a unit of their own (iris takes it as the end of the stream, then fails every buffer, firmware "session error 0x4000003": now held and sent in front of the next picture) |
| [0002](patches/0002-Takion-4-MiB-socket-receive-buffer.patch) | 4 MiB UDP receive buffer instead of 100 KiB: on this tablet the kernel dropped parts of each 1080p frame burst (`RcvbufErrors`), seen as glitches and corrupt frames |

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
