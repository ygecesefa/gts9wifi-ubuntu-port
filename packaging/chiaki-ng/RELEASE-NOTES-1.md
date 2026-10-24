# chiaki-ng with hardware decoding for the Galaxy Tab S9 Wi-Fi (Ubuntu) — build 1

PlayStation Remote Play (PS5 / PS4) on the Ubuntu port, with the stream
decoded by the tablet's own video block (**Qualcomm iris**) instead of the
CPU. It is chiaki-ng 1.10.0 as Flathub builds it, plus three changes, all in
[packaging/chiaki-ng](https://github.com/ygecesefa/gts9wifi-ubuntu-port/tree/main/packaging/chiaki-ng).

## File

`chiaki-ng-gts9wifi.flatpak` (aarch64) and its `.sha256`.

## What changes against Flathub's chiaki-ng

| | |
|---|---|
| FFmpeg | built with the V4L2 M2M decoders (`h264_v4l2m2m`, `hevc_v4l2m2m`); Flathub's has only VAAPI/Vulkan/NVIDIA, none of which this tablet has (choosing *vulkan* gives a black picture) |
| patch 0001 | **v4l2m2m** under *Settings → Video → Hardware Decoder*; the decoder is opened with the stream's size, and SPS/PPS that the console sends on their own are held for the next picture (either one made iris give a green picture) |
| patch 0002 | 4 MiB UDP receive buffer instead of 100 KiB (dropped packets showed as glitches) |

## Measured on the tablet (PS5, 1080p60, H.264, 30 Mbps, Wi-Fi 6)

| | CPU (chiaki-ng) |
|---|---|
| software decoding | ~380 % (test file), frames dropped ("buffer is full") |
| **v4l2m2m (iris)** | **~30 %**, no dropped frames, no decoder errors |

## Install (Ubuntu on the tablet)

```sh
# 4 MiB socket buffers need a larger limit (Ubuntu's default is 208 KiB)
printf 'net.core.rmem_default = 4194304\nnet.core.rmem_max = 16777216\n' |
	sudo tee /etc/sysctl.d/90-gts9wifi-streaming.conf && sudo sysctl --system

sudo apt install flatpak
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak uninstall io.github.streetpea.Chiaki4deck      # Flathub's build, if installed (your consoles and settings stay)
sha256sum -c chiaki-ng-gts9wifi.flatpak.sha256
sudo flatpak install chiaki-ng-gts9wifi.flatpak        # the runtime comes from Flathub
```

Then in chiaki-ng: *Settings → Video → Hardware Decoder:* **v4l2m2m**,
*Settings → Stream → Codec:* **H264**. Leave the stream menu with
L1 + R1 + L3 + R3.

Optional, for steady latency on Wi-Fi: turn Wi-Fi power saving off
(`/etc/NetworkManager/conf.d/zz-gts9wifi-wifi-powersave.conf` with
`[connection]` / `wifi.powersave = 2`; the `zz-` name makes it win over
Ubuntu's `default-wifi-powersave-on.conf`).

## Limits

- **H.265 (HEVC)** is offered but not verified on iris yet: use **H264**.
- Wi-Fi packet loss still shows in the log as corrupt-frame reports: a burst
  in the first seconds of a session, then one every few seconds. Not
  visible while playing in our test; a wired or 5 GHz connection close to
  the router keeps it low.
- Installed from a bundle, it does not update itself (`flatpak update`
  leaves it alone). Installing chiaki-ng from Flathub again replaces it and
  takes hardware decoding away.

## Source

chiaki-ng is AGPL-3.0. The corresponding source is chiaki-ng at commit
`c8bea264` (the one Flathub builds) with the patches in
`packaging/chiaki-ng/patches/`, built from Flathub's manifest at
`c2503d11` by `packaging/chiaki-ng/build-chiaki-ng-flatpak.sh` (GitHub
Actions workflow *chiaki-ng*). Test tools: `packaging/chiaki-ng/test/`.

## Credits

chiaki-ng (streetpea and contributors), Chiaki (Florian Märkl), FFmpeg,
libplacebo, the Flathub maintainers of io.github.streetpea.Chiaki4deck, and
the Linux media and Qualcomm iris driver developers.
