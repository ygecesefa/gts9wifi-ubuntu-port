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

Install on the tablet: `sudo tar -C / -xf gts9wifi-turnip-26.3.0.tar.zst`.
Remove: `sudo rm -r /usr/lib/gts9wifi-turnip`.

**Status: not yet built or tried on the tablet.**
