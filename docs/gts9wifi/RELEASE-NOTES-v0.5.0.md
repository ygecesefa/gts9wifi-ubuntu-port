# v0.5.0 "GalaxyDeck" — Ubuntu 24.04 for the Galaxy Tab S9 Wi-Fi (SM-X710)

The tablet as a **game console**: Valve's **ARM64 Steam** with Windows games
through **Proton (ARM64)**, **Big Picture** at login like a Steam Deck, a
newer **Vulkan driver** for games, **gamescope**, a **Game Manager** with heat
protection, and emulators on request.

> "GalaxyDeck" is this project's name for the release. It is not a Samsung or
> Valve product, and neither company is involved.

**Testing status:** the parts below were used on the tablet (the author's
own card, set up by hand), except two that only exist in the image: Steam
downloading itself at the first start, and the Game Manager's *Install
emulators* button (the emulators themselves were installed and opened by
hand). The v0.5.0 image as a whole has not been installed on a real tablet
before release: reports are welcome (issues on
GitHub). `GTS9W_BACK/android-restore.zip` takes the tablet back to Android,
as before.

## The one file you need

`ubuntu-gts9wifi-v0.5.0-installer.zip` (check it with the `.sha256` next to
it), installed like before: from the Magisk app as a module, or as a
recovery zip ([INSTALL.md](INSTALL.md)). A 64 GB card or larger is
recommended: Windows games are big.

## First start

1. The tablet logs in **without a password** and opens **Steam Big Picture**.
2. The first time, Steam is downloaded from Valve (about 150 MB, then Steam
   updates itself, about 700 MB): **connect to Wi-Fi first**. Without a
   network you land on the desktop with a notice; open Steam again once
   connected.
3. Sign in to Steam. Windows games run with Proton: Steam picks
   *Proton 11.0 (ARM64)* or *Proton Experimental (ARM64)* by itself.
4. **Change the default password** (`ubuntu`, a notification reminds you
   once): Settings > System > Users. It is needed for system changes; the
   tablet still logs in by itself.

There is no lock screen: the tablet wakes straight back into Big Picture or
the game. Anyone holding the tablet can use it, as on a Steam Deck.

## New

### Steam (ARM64) and Proton

Valve's native ARM64 client (the one made for its own ARM hardware), not an
x86 Steam under emulation. Windows games run through Proton (ARM64): Wine,
DXVK and vkd3d-proton run as ARM64 code, only the game's own x86 code is
translated (FEX, inside Proton). Steam is not shipped in the image: its first
start downloads it from Valve and checks Valve's checksums
([packaging/steam](../../packaging/steam/)). Not supported by Valve on
hardware other than its own.

### Newer Vulkan driver for games (Mesa 26.3 Turnip)

Ubuntu's Mesa 25.2.8 drew Unreal Engine 5 games with a broken picture and
one GPU fault. Turnip from Mesa 26.3.0 (sparse buffers, shader model 6.6 in
vkd3d-proton) draws them correctly. Only Steam and its games use it; the
desktop, the camera and video keep Ubuntu's driver
([packaging/turnip](../../packaging/turnip/)). The Game Manager switches back
to the system driver if a game misbehaves.

### Big Picture inside gamescope

Big Picture and its games are drawn at **1920x1200** and scaled to the
2560x1600 screen by **gamescope** (Valve's game compositor, built for this
image: [packaging/gamescope](../../packaging/gamescope/)). Much less work for
the GPU, and in our tests games started reliably inside it (6 of 6) while
the same game hung at start on the GNOME desktop (see Known issues).
"Switch to Desktop" in Big Picture goes to the normal desktop with Steam in
a window, and back.

### Galaxy Game Manager

An app (app grid) for:

- **Open Big Picture at login** on/off.
- **Big Picture resolution**: screen, 1920x1200, 1680x1050, 1440x900, 1280x800.
- **While a game runs**: keep the screen on, lock rotation, close Android
  (Waydroid) to free memory (frozen in the background it held ~2.5 GB of
  swap during a game).
- **Heat protection**: closes the game, with a notification, when the
  processor (100 °C by default) or the battery (45 °C) stays at its limit
  for 20 s. The chip slows itself down from 90-95 °C and powers off at
  110 °C; the battery limit is about how hot the tablet feels and how fast
  the battery ages.
- **Emulators**: one tap installs RetroArch, DuckStation (PS1), Play! (PS2),
  RPCS3 (PS3), PPSSPP (PSP), Dolphin (GameCube/Wii), melonDS (DS), Ryujinx
  and Eden (Switch), Flycast (Dreamcast), xemu (Xbox) and MAME from Flathub
  (a few GB). Games, BIOS files and console keys are your own dumps.
- **Controllers**: test a controller, map one to keys (AntiMicroX, with the
  emulators). Xbox, DualShock/DualSense, Switch Pro/Joy-Con and Steam
  controller drivers are in the kernel; `steam-devices` is installed.
- Experimental: a frame-rate cap and the MangoHud overlay for every game
  (see Known issues).

### Smaller

- **zram**: compressed swap in RAM (half of the memory, zstd).
- **No background memory compaction** (`vm.compaction_proactiveness=0`):
  during a game the kernel spent 10-22 % of a core defragmenting memory.
- **Phones over USB** (MTP) show up in Files (`gvfs-backends`).
- **Solaar** (Logitech devices). Its virtual keyboard no longer takes the
  tablet out of touch mode (on-screen keyboard and auto-rotate button were
  gone).

## Known issues

- **Some new Unreal Engine 5 games do not run.** The Adreno 740 driver has
  no sparse (tiled) 2D textures, so vkd3d-proton offers Direct3D 12 feature
  level 11_1. Games with a Direct3D 11 / shader model 5 path run (Subliminal,
  The Complex); games built only for shader model 6 stop with "DirectX 12 is
  not supported" or crash (WILL: Follow the Light). Details:
  [packaging/steam/README.md](../../packaging/steam/README.md).
- **Games started from the desktop Steam window can hang at start**
  ("not responding"); the cause is not known. Start games from Big Picture.
- **Frame-rate cap and MangoHud overlay are experimental**: with them on,
  Subliminal hung at start. Use the games' own frame-rate setting.
- The FPS counter in Steam's overlay shows GPU 0 %: Steam reads GPU load
  where AMD, Intel and NVIDIA drivers publish it; the Adreno driver does not.
- Anti-cheat online games do not run (as on any Linux without the
  developer's support).
- The GNOME keyring is not unlocked by the automatic login: an app that
  stores passwords (e.g. a browser) asks for the keyring password once.

## Upgrading from v0.4.x without reinstalling

Not offered: reinstall with the zip. What the image adds is listed step by
step in [scripts/add-galaxydeck.sh](../../scripts/add-galaxydeck.sh), which
works on an image being built, not on a running tablet.
