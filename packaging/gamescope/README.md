# gamescope for Ubuntu 24.04 arm64 (gts9wifi)

[gamescope](https://github.com/ValveSoftware/gamescope) is Valve's game
compositor: it runs a game (or all of Steam) in its own small compositor and
scales the picture to the screen. It is what gives the Steam Deck one
resolution and one frame-rate cap for every game. Ubuntu 24.04 has no
gamescope package for arm64.

`build-gamescope.sh` (or the *gamescope* workflow) builds gamescope 3.17.0
into `/usr/lib/gts9wifi-gamescope`. Its bundled wlroots 0.20 needs libraries
newer than noble's, so the build also puts these into that directory's
`lib/` (found through the binary's RUNPATH; the system's copies stay):

| library | noble | built |
|---|---|---|
| wayland | 1.22 | 1.24.0 |
| wayland-protocols (build only) | 1.34 | 1.47 |
| libdrm | 2.4.125 | 2.4.131 |
| pixman | 0.42 | 0.46.4 |
| xkbcommon | 1.6 | 1.8.1 |
| Vulkan headers (build only) | 1.3.275 | 1.4.335 |

wlroots, libliftoff, vkroots and libdisplay-info are gamescope's own
submodules, linked statically. OpenVR and the unit tests are off.

Install on the tablet:

    sudo apt install libavif16 libluajit-5.1-2 libseat1 libxres1
    sudo tar -C / -xf gts9wifi-gamescope-3.17.0.tar.zst

**Status (2026-11-17):** built in an Ubuntu 24.04 container on the build
host, installed on the tablet, `gamescope --version` runs and all libraries
resolve. Not yet used with a game or with Steam. The package still carries
files of gamescope's v4l-utils subproject that nothing uses (to be pruned).
