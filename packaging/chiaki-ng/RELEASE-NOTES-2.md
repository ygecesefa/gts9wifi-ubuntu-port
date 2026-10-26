# chiaki-ng with hardware decoding for the Galaxy Tab S9 Wi-Fi (Ubuntu) — build 2

Build 1 plus patch 0003: *Settings → Video → Hardware Decoder: **auto*** now
picks **v4l2m2m** (the tablet's iris video block) when FFmpeg has it. Before,
*auto* picked *vulkan*, which on this tablet decodes to a black picture, so a
fresh install showed nothing until the decoder was set by hand. This build is
the one preinstalled in Ubuntu v0.3.0.

Everything else (install steps, measurements, limits, source) as in
[build 1](https://github.com/ygecesefa/gts9wifi-ubuntu-port/blob/main/packaging/chiaki-ng/RELEASE-NOTES-1.md).
Built from commit 2f66c81 by the *chiaki-ng* workflow.
