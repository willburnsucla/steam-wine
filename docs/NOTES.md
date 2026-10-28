# Notes

Technical notes behind the build: what's in CodeWeavers' source, why each workaround exists, and how the Steam problems were tracked down.

## CrossOver's source

`crossover-sources-26.3.0.tar.gz` (149 MB, from codeweavers.com/crossover/source) contains Wine (based on Wine 11.0), DXVK 1.10.3, MoltenVK, vkd3d, freetype, gnutls (with gmp and nettle), glib, gstreamer and a few tools. It doesn't contain DXMT, FEX, D3DMetal, the CrossOver app, or the app-profile database.

Compared with upstream `wine-11.0`, 221 files differ (`crossover-changed-files.txt`). The changes that matter here:

- msync, a Mach-port based replacement for wineserver synchronization (`WINEMSYNC=1`).
- winemac.drv hooks for D3DMetal, plus exported macdrv functions that DXMT relies on. A plain upstream Wine needs `-fvisibility=default` and DXMT patches to get the same; this source works with DXMT as-is.
- ntdll binary patches for old libcef versions used by other launchers (Rockstar, Ubisoft); none for Steam.

CrossOver's Steam profile adds fonts, the VC++ runtime, `d3dcompiler_47` and msync, and nothing Steam-specific. Steam works in CrossOver because of its Wine and its graphics stack, not because of hidden settings.

## Build environment

- Wine's macOS host side is x86_64 only and runs under Rosetta 2. Host libraries must be x86_64; build tools (bison, flex, mingw-w64) can be arm64.
- macOS 27's Command Line Tools ship no x86_64 `xcrun`, so the `/usr/bin/clang` shim fails when an x86_64 process (winebuild) runs it. `build-wine.sh` calls the real arm64 clang in `/Library/Developer/CommandLineTools/usr/bin` with `-arch x86_64`. configure runs its x86_64 test programs through Rosetta, so it's a normal, non-cross build.
- With Xcode installed, nothing in the toolchain works until its license is accepted, including `/usr/bin/git`.

## Dependency workarounds

- nettle: CrossOver's copy has no top-level `Makefile.in`; the GNU 3.10 release is used instead.
- gnutls 3.8.3: `--disable-gost`, because its bundled streebog clashes with nettle 3.10. Its modified `m4/hooks.m4` tests `NETTLE_LIBS` unquoted, so the value has to be a single word (`-lnettle`), or nettle silently isn't linked.
- freetype: built with CMake; the autotools path wants the `dlg` git submodule, which isn't in the tarball. macOS's zlib has no `.pc` file, so `build-deps.sh` writes one.
- pkg-config: in cross mode configure looks for `x86_64-apple-darwin-pkg-config` and silently skips libraries, so `PKG_CONFIG` is set explicitly.
- win32u: CodeWeavers removed upstream's `#ifdef SONAME_LIBVULKAN`, so their source doesn't build without Vulkan (patch 0001).

## Graphics

- DXMT needs LLVM 15 (exact major version) built for x86_64, Xcode's Metal toolchain, and `MACOSX_DEPLOYMENT_TARGET=14.0` (it uses `std::to_chars`). Its DLLs are built as Wine builtins and installed into `dist/` by `install-dxmt.sh`, which keeps Wine's originals for `install-dxmt.sh off`.
- DXMT doesn't support swapchains created by one process for another process's window ("cross-process swapchain not supported yet", DXMT issue #141).
- DXMT's D3D12 implementation (about 9,300 lines, `-Denable_d3d12=true`) is off by default upstream and changing quickly. `tools/d3d12test.c` (device, flip-model swapchain, clear, present, readback) passes on an M5 Pro. `install-dxmt.sh` replaces Wine's vkd3d-based `d3d12.dll` and keeps it for `off`.
- MoltenVK: CodeWeavers' copy can't be built from the tarball, because its `fetchDependencies` pins a SPIRV-Cross commit that exists only in an unpublished fork. Upstream MoltenVK 1.4.2 works. Wine loads it directly (`SONAME_LIBVULKAN = libMoltenVK.dylib`, found through the `deps/lib` rpath), so no portability-enumeration patch is needed.
- DXVK: CodeWeavers' 1.10.3 requires `geometryShader`, which upstream MoltenVK lacks. Gcenx's DXVK-macOS makes it optional. mingw-w64 14 needed two header fixes (`patches/dxvk`) and a forced `#include <cstdint>`.

## The black Steam window

- Symptom: Steam's sign-in window opens (Steam's own log says so) but is black. The page renders fine; a Chrome DevTools screenshot (`tools/cdp-shot.mjs`, Steam launched with `-cef-enable-debugging`) shows the full sign-in page.
- Patch 0003 (`WINE_MACDRV_DUMP_DIR`) showed that the window surface Wine hands to Cocoa is black, so the pixels never reach the window.
- Steam's web helper composites in a separate GPU process and draws into a window owned by the browser process. Wine's macOS driver can't draw across processes; Wine bug 56014 describes the same black window on Wine's Wayland driver. With the GPU on and DXMT installed, the same thing fails at the swapchain instead (DXMT #141).
- Steam ignores `-cef-single-process` (it never passes it to Chromium). The wrapper in `tools/webhelper-wrapper.c` starts the real helper with `--in-process-gpu`; Steam restores the original helper on startup unless launched with `-noverifyfiles`. With both, the window surface is fully drawn.
- `scripts/check-login-visual.sh` automates the check: it launches Steam with the surface dump and reports how much of the sign-in window is non-black.
- Steam client updates replace the helper after the launcher's check, so the restarted Steam runs it unwrapped. `steam.sh` runs a watcher next to Steam that re-wraps the file and stops unwrapped helpers (only when no `steamwebhelper_real.exe` is running, on two checks in a row); Steam restarts the helper through the wrapper. The watcher disables `set -e`/`pipefail`, since a grep with no match would otherwise end it, and matches process names case-insensitively (`steam.exe` and `Steam.exe` both occur).

## Media playback (GStreamer)

- Wine's DirectShow and Media Foundation decoders go through winegstreamer. Without it, `IGraphBuilder::RenderFile` on an MP3 fails with `VFW_E_CANNOT_RENDER`, which is how Fallout 3, New Vegas and Oblivion play music. `tools/mp3test.c` plays a generated silent MP3 (`tools/make-silent-mp3.py`) through DirectShow; with GStreamer the graph is Reader → MPEG-I Stream Splitter → MPEG Layer-3 Decoder → DirectSound.
- `build-gstreamer.sh` builds libmpg123 1.33.7 (upstream, signed by its maintainer), then GLib 2.78 and GStreamer 1.24.4 from the CrossOver tarball, all x86_64 into `deps/`, with every optional feature off except: core elements, app, audioconvert, audioresample, playback (decodebin), typefind, volume, videoconvertscale, audioparsers, id3demux, mpg123, wavparse.
- GLib needed three fixes: the tarball ships `subprojects/gvdb` as an empty submodule folder (removed so meson uses the wrap), its D-Bus code generator imports `distutils`, gone since Python 3.12 (`patches/glib/0001`), and 2.78 uses older option names (`man`, `gtk_doc`, no `introspection`). GStreamer is told `-Dbuild-tools-source=system`, otherwise it fetches its own bison and pcre2 on macOS.
- `scripts/runtime-env.sh` points GStreamer at our plugins only and keeps its registry in `prefixes/gst-registry.bin`, so another GStreamer on the Mac never mixes in. The first media playback after a rebuild takes a few extra seconds while the registry is built.

## 32-bit address space

- `WINE_LARGE_ADDRESS_AWARE=1` (set by `steam.sh`) makes Wine give 32-bit programs without the large-address-aware flag 4 GB instead of 2 GB under WoW64; 64-bit programs are unaffected. `tools/memtest.c` (built with `--disable-large-address-aware`, and refusing to run if it's flagged anyway) reserves 1920 MB without it and 3968 MB with it, and writes to a page above 2 GB.
- The variable is checked before the per-program registry setting (`HKCU\Software\Wine\AppDefaults\<exe>\LargeAddressAware`), so while it's set no single game can opt out; `WINE_LARGE_ADDRESS_AWARE=0` turns it off for the session, and the registry key can then turn it on for one game.
- CrossOver's kernel32 also stops clamping `GlobalMemoryStatus` to 2 GB for such programs once they count as large-address-aware, so old games that read total memory into a signed int could misjudge it. Upstream Wine and Proton don't have that hack. Steam's own 32-bit helpers (`SteamService.exe`, `gameoverlayui.exe` and others) also get the setting; the sign-in check passes with it.

## Controllers

- Wine's `winebus.sys` reads controllers through SDL2 (built by `build-sdl.sh`, 2.32.10, x86_64; Wine loads `libSDL2-2.0.0.dylib` through the `deps/lib` rpath). Without it, winebus logs `SDL support not compiled in!` and Xbox/Switch-style pads don't reach XInput. SDL2 has its IOKit, GameController.framework and HIDAPI backends compiled in.
- winebus picks one route per controller (`is_hidraw_enabled` in `main.c`): Xbox, Switch and generic pads go through SDL and become XInput devices; PS4/PS5 pads prefer the raw HID route, which games with native DualShock support use but XInput-only games don't see. To send PS pads through SDL instead (XInput), set `DisableHidraw` = dword 1 under `HKLM\System\CurrentControlSet\Services\WineBus` in the Steam prefix (`scripts/steam.sh --exec reg add 'HKLM\System\CurrentControlSet\Services\WineBus' /v DisableHidraw /t REG_DWORD /d 1 /f`), or per device with a `Hidraw` = 0 value under that key's `Devices` subkey. CodeWeavers' winebus also turns on PS4/PS5 rumble over Bluetooth.
- `run-tests.sh` checks that winebus logs `L"SDL" main loop started` with neither SDL failure message (a bus that failed to init also logs "main loop started", so that line alone proves nothing). The XBOX bus is disabled by Wine on macOS 15+ and UDEV/IOHID are other backends; SDL is the one that maps gamepads.
- `tools/padtest.c` polls for the whole run (Wine adds a controller a moment after its bus starts), prints each controller once, then button state: XInput pads through XInput, DirectInput-only pads through DirectInput. It needs a physical controller to pass. For a first live test, an Xbox or Switch Pro controller exercises the SDL-to-XInput path New Vegas uses.

## Audio

- Every MacGamingDB report for LEGO Star Wars: The Skywalker Saga mentions missing or quiet dialog: the game expects 5.1, and dialog is on the center channel. An offline AudioConverter test showed that CoreAudio's 5.1-to-stereo conversion maps channels and drops the center, so tagging a stream as 5.1 isn't enough. Patch 0002 mixes it down in Wine's render callback: L = FL + 0.707 C + 0.707 BL, R = FR + 0.707 C + 0.707 BR, LFE dropped, clipped.
- Wine pinned each stream to the device that was default when it started (HALOutput with a fixed device), so audio stayed on the speakers when headphones connected mid-game. Patch 0004 uses Apple's DefaultOutput unit for streams on the current default device.

## Steam quirks

- The first launches after a fresh install sometimes stalled ("CSteamEngine::BMainLoop appears to have stalled"); it didn't come back after the first few runs, including under heavy CPU load.
- Wine processes show up as `C:\...` paths in `ps`. `wine-run.sh` finds its own by the `ntdll.so` they map from `dist/`, and kills on a time limit.
- If wineserver was started with `WINEMSYNC=1`, every client needs it too.

## After Rosetta

Apple keeps Rosetta as a general-purpose tool through macOS 27, with only a subset for older games after that. CodeWeavers has shown CrossOver builds that use their own macOS port of FEX (an x86-to-ARM translator) instead of Rosetta; FEX itself is open source, but their macOS changes aren't in the published source yet.
