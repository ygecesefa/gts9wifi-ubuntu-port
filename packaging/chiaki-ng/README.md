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
| [0001](patches/0001-Decode-with-V4L2-M2M-decoders-v4l2m2m-hardware-decod.patch) | a **v4l2m2m** choice under *Settings → Video → Hardware Decoder*: decodes with the V4L2 M2M decoder; frames come back in system memory (NV12) and take the software frame path to the Vulkan renderer. The decoder is opened with the stream's size: opened at 0x0 (as chiaki-ng opens its decoders), iris cannot set up its picture buffers and gives only green frames |
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
| opened at 1920x1080 (0001) | 298 | 0 | luma 126, same as software |

## Install

```sh
flatpak uninstall io.github.streetpea.Chiaki4deck   # the Flathub build, if installed
flatpak install --user chiaki-ng-gts9wifi.flatpak
```

Then *Settings → Video → Hardware Decoder: v4l2m2m*, *Stream → Codec: H264*.
