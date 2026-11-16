# Newer Turnip next to the system Mesa (gts9wifi)

Ubuntu 24.04 has Mesa 25.2.8. Its Turnip (Vulkan on Adreno 740) lacks things
newer Windows games need through Proton; seen on the tablet with an Unreal
Engine 5 game (Subliminal, D3D12 → vkd3d-proton): menus fine, garbage in
game, one `gpu fault … hangcheck recover` in the kernel log, and
`sparseBinding = false` in `vulkaninfo`.

`build-turnip.sh` (or the *turnip* workflow) builds **only the Vulkan
driver** of Mesa 26.3.0 into `/usr/lib/gts9wifi-turnip`. The system Mesa
stays as it is, so desktop, camera (GPU soft ISP) and video are not
affected. A program gets the new driver only through

    VK_DRIVER_FILES=/usr/lib/gts9wifi-turnip/share/vulkan/icd.d/freedreno_icd.aarch64.json

which the Steam launcher ([packaging/steam](../steam/)) sets when the file
exists; `GTS9WIFI_STEAM_SYSTEM_MESA=1` goes back to the system driver.

Install on the tablet:

    sudo apt install libxcb-keysyms1      # the one library the driver needs that the image lacks
    sudo tar -C / -xf gts9wifi-turnip-26.3.0.tar.zst

Remove: `sudo rm -r /usr/lib/gts9wifi-turnip`.

**Status (2026-11-15):** built by the workflow (run 43742143040) and
installed on the tablet. `vulkaninfo` with the variable above reports
`Mesa 26.3.0`, `sparseBinding = true`, `sparseResidencyBuffer = true`
(`sparseResidencyImage2D` stays false). **Subliminal renders correctly in game with it** (user, 2026-11-16); no GPU fault in the kernel log during that session. vkd3d now reports shader model 6.6 (6.0 before) but still feature level 11_1, so the game stays on its SM5 path.
