# Steam (ARM64 client) on gts9wifi

**Status (2026-11-15): the client installs, updates itself (669 MB) and
starts on the tablet** with its browser sandbox on; Steam's own hardware
query reports "Turnip Adreno (TM) 740" as the default GPU. No game has been
started yet. Nothing here is in the image build yet; it goes in after a
game runs.

Valve builds a native ARM64 Steam client for its own ARM hardware (Steam
Frame, Snapdragon 8 Gen 3). It is on Valve's public update servers, runs on
other ARM64 Linux systems with 4 KiB pages, and is **not supported by Valve**
outside its own hardware. With it come **Proton (ARM64)** — Wine, DXVK and
VKD3D as ARM64 code, the game's x86 code translated by the FEX built into
Proton — and FEX for x86 Linux games. The GPU side is the tablet's own
Vulkan driver (Mesa Turnip).

| File | What |
|---|---|
| `install-steam-arm64.sh` | run as the user: downloads the client bootstrap and the Steam Linux Runtime 3 (ARM64) from Valve, checks both against Valve's checksums, writes the menu entry. Touches only `$HOME` |
| `gts9wifi-steam` | the launcher (`--deck` = full-screen controller interface). Image path: `/usr/libexec/gts9wifi-steam` |
| `gts9wifi-game-manager` | "Galaxy Game Manager", a small GTK4/libadwaita app for the launcher's settings (`~/.config/gts9wifi/steam.conf`): Big Picture resolution (gamescope, `RESOLUTION=1920x1200`), frame rate limit and MangoHud overlay (both experimental, see below), newer or system Vulkan driver, open/restart Steam. Image path: `/usr/libexec/gts9wifi-game-manager` |
| `gts9wifi-game-session` | started by the launcher, ends with it. While a game runs (Steam's `reaper SteamLaunch AppId=N` process exists): keeps the screen on (idle inhibitor), locks rotation and puts it back afterwards, and **heat protection**: when the hottest CPU/GPU sensor (default 100 °C) or the battery (default 45 °C) stays at its limit for 20 s, the game's processes are closed and a notification says why. Steam itself is not closed. Tested on the tablet with a stand-in game and a 30 °C limit. Image path: `/usr/libexec/gts9wifi-game-session` |
| `steamos-session-select` | Steam's "Switch to Desktop" (Big Picture) and "Return to Gaming Mode" (desktop client) run this SteamOS command. Without it Steam closed and took gamescope down with it ("IWaitable hung up. Aborting"). Ours tells the launcher which mode to start next and closes Steam; the launcher restarts it in that mode. Tested on the tablet both ways (with the command run the way Steam runs it). Image path: `/usr/libexec/gts9wifi-steam-bin/steamos-session-select` |
| `apparmor/gts9wifi-steam` | **not needed with this port's kernel** (mainline 7.2 has no `kernel.apparmor_restrict_unprivileged_userns`; user namespaces just work). Kept for an Ubuntu kernel, where 24.04 denies them to programs without a profile. Path: `/etc/apparmor.d/gts9wifi-steam` |

## Where it comes from

- **Client:** `https://client-update.steamstatic.com/steam_client_linuxarm64`
  is Valve's package list for the ARM64 client; every entry has a file name
  and a `sha2`. The installer takes `bins_linuxarm64_linuxarm64` from it and
  unpacks one file, `steamrtarm64/steam`. The client fetches the other
  packages itself on first start.
- **Runtime:** `https://repo.steampowered.com/steamrt3c/images/latest-public-beta.txt`
  names the current version; `steam-runtime-steamrt-arm64.tar.xz` and
  `SHA256SUMS` are in that version's directory.
- **Recipe:** which package to take, where the runtime goes and how the
  bootstrap is started are from
  [Switchdeck](https://github.com/SildurFX/Switchdeck) (`install-steam.sh`,
  `files/steam/launch-steam.sh`, GPL-3.0), which does this on the Nintendo
  Switch. Not taken, because they exist for the Switch's Tegra X1 (ARMv8.0,
  Vulkan 1.2, 4 GB): Box64, the downgrade to an April 2026 client, DXVK-Sarek
  and VKD3D-Proton 2.3.1 in place of Proton's own, the "Armv8.0" Proton
  build, the pinned bootstrap hash (the installer reads the current one from
  Valve's list instead), the disabled CEF sandbox flags, and its zram setup
  (this image has its own, `gts9wifi-zram`).

Checked on 2026-11-15 (build host, download only): list version 1794536281,
`bins_linuxarm64_linuxarm64.zip.5448e08e…` sha256 `8407347d…` matches;
runtime `3c.0.20261103.268067`, tar.xz sha256 `bc4c1319…` matches. The
bootstrap needs only libc (`readelf -d`), RUNPATH `$ORIGIN`.

## Install on a running tablet

```sh
sudo apt install steam-devices        # udev rules for controllers
./install-steam-arm64.sh
```

Remove: `rm -rf ~/.local/share/Steam ~/.steam ~/.local/share/applications/steam.desktop`
(and the AppArmor file, if installed).

## Found on the device

- The client starts `steam-runtime-launcher-service` by name: the runtime's
  `bin` directory must be on `PATH` (launcher).
- It runs `../steamrtarm32/gldriverquery` and `vulkandriverquery`, a
  directory Valve does not ship: `steamrtarm32` is a link to `steamrtarm64`
  (installer; Switchdeck does the same).

## What breaks a game's start (measured 2026-11-16)

Subliminal (UE5, D3D12 through vkd3d-proton, Proton 11.0-2 ARM64, Turnip
26.3.0), started nine times from the same Steam, 75 s each. A hanging start
shows as the frame counter in the game's log standing still after a few
hundred frames, right after two "Glyph texture is too large ... 5211x18204"
warnings that a good start does not have; GNOME then offers "Force Quit".

| ntsync module | frame cap | MangoHud | result |
|---|---|---|---|
| unloaded | none | off | starts (3 of 3) |
| **loaded** | none | off | hangs (3 of 3) |
| unloaded | **VKD3D_FRAME_RATE=30** | off | hangs (1 of 1) |
| unloaded | **MangoHud fps_limit=30** | on, hidden | hangs (1 of 1) |
| unloaded | none | **on** | hangs (1 of 1) |

So: `ntsync` is **not** loaded at boot (the modules-load.d file added for it
was removed again), and the frame cap and the overlay are off by default and
marked experimental in the Game Manager. Why three unrelated things have the
same effect is not understood; other games are untested.

## To be answered on the device

- Does a game start (pressure-vessel container, Proton ARM64)?
- `steamwebhelper.sh` pins the interface to cores 2–6 (`taskset 0x7c`, the
  Steam Frame's layout); on SM8550 that is one small core and the four
  middle cores, which is acceptable.
- Which Proton (ARM64) the client offers, and frame rates with Mesa 25.2.8
  against a newer Turnip.

## Emulators and controllers

Not Steam, but looked after by the same two programs: the Game Manager lists
the installed ones, and `gts9wifi-game-session` treats them as games (screen
on, rotation lock, heat protection). All are Flathub's own aarch64 builds:

    sudo flatpak install flathub org.ppsspp.PPSSPP org.duckstation.DuckStation \
        org.DolphinEmu.dolphin-emu org.libretro.RetroArch net.rpcs3.RPCS3 \
        io.github.ryubing.Ryujinx dev.eden_emu.eden io.github.antimicrox.antimicrox
    sudo apt install joystick jstest-gtk steam-devices

| | Flathub aarch64 (checked 2026-11-16) |
|---|---|
| yes | PPSSPP, DuckStation, Dolphin, melonDS, Flycast, RetroArch, MAME, RPCS3, Ryujinx (Ryubing), Eden, xemu, Play!, AntiMicroX |
| no | PCSX2, Azahar, Cemu, ES-DE, shadPS4 |

Games and console system files are the user's own dumps; none are shipped.

Controllers: the kernel has `xpad`, `hid-playstation` (DualSense/DualShock 4),
`hid-sony`, `hid-nintendo` (Switch Pro, Joy-Con), `hid-microsoft` and
`hid-steam` as modules; `steam-devices` gives the logged-in user access to
their raw HID nodes (Steam Input, rumble, gyro). AntiMicroX maps a controller
to keys for games without controller support; `jstest-gtk` tests one.
