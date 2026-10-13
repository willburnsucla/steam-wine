# steam-wine

Windows Steam and Windows games on Apple Silicon Macs, running on a Wine I build myself from CodeWeavers' published CrossOver source; no CrossOver license, no Whisky, no Game Porting Toolkit.

While CrossOver is good software, it costs $74 per Mac, and every free option I tried was stuck on 2022-era Wine that the 2026 Steam client won't even boot on. CodeWeavers publishes the Wine they ship under the LGPL, so this project builds that source (CrossOver 26.3, based on Wine 11.0), adds DXMT for Direct3D 11 on Metal, MoltenVK and DXVK as a fallback, and carries a handful of patches for the problems that came up along the way. Built and tested on an M5 Pro MacBook Pro running macOS 27.0.1, with LEGO Star Wars: The Skywalker Saga as the test game.

## What works

- Windows Steam: install, self-update, sign-in, library, downloads.
- Direct3D 10/11 games through DXMT (Metal), with DXVK (Vulkan through MoltenVK) as a per-game fallback.
- Vulkan through MoltenVK.
- Retina rendering at 2x.
- Game audio offered as 5.1 and mixed down to stereo, so center-channel dialog isn't lost; audio follows the macOS output device (headphones connected mid-game get the sound).

## What doesn't

- Games with kernel-level anti-cheat (Valorant, Fortnite, many shooters); no Wine setup runs those.
- Direct3D 12. CrossOver uses Apple's closed-source D3DMetal for it, which this project doesn't include.
- Life after Rosetta. Wine's macOS side runs as an x86_64 program under Rosetta 2, which Apple keeps fully available through macOS 27 only; see docs/NOTES.md.

## Requirements

- An Apple Silicon Mac on macOS 14 or newer.
- Rosetta 2: `softwareupdate --install-rosetta --agree-to-license`
- Xcode from the App Store, with its license accepted and the Metal toolchain installed:
  `sudo xcodebuild -license accept` and `xcodebuild -downloadComponent MetalToolchain`
- Homebrew packages: `brew install bison flex pkgconf mingw-w64 meson ninja cmake autoconf glslang`
- About 10 GB of free disk space for sources and builds (plus your games), and an hour or two for the first build; LLVM and Wine take most of it.

## Build and install

```bash
scripts/build-all.sh
scripts/install-steam.sh
```

`build-all.sh` fetches every source at a pinned version (`fetch-sources.sh` checks the downloads against SHA-256 sums), then builds the x86_64 libraries, MoltenVK, Wine, LLVM 15 and DXMT, and DXVK. `install-steam.sh` creates the Windows environment in `prefixes/steam`, installs Steam from Valve's CDN, turns on DXMT and sets Retina scaling.

## Play

Double-click `Steam (Wine).command`, or run `scripts/steam.sh`. Sign in, install a game, play. Steam updates itself on the first launch (about 250 MB), and a game's first run is slow while shaders compile.

- `scripts/steam.sh --stop` quits Steam and everything Wine started.
- `scripts/game-graphics.sh <path to the game's exe> dxvk` switches one game to DXVK; `dxmt` switches it back.
- `WINE_COREAUDIO_FORCE_5_1=0 scripts/steam.sh` turns off the 5.1 downmix, and `WINE_COREAUDIO_FOLLOW_DEFAULT=0` keeps game audio on the device that was selected when the game started.

## How it works

Wine's macOS side still runs under Rosetta, so every library it links against has to be an Intel build; `build-deps.sh` cross-compiles gmp, nettle, gnutls and freetype from the arm64 side into `deps/`. The CrossOver tarball isn't quite buildable as shipped (nettle is missing its Makefile.in, gnutls's configure never links nettle, and freetype wants a git submodule that isn't there), and `docs/NOTES.md` covers each workaround.

The black Steam window was the hard part. Steam's web helper, a build of Chromium 126, runs its compositor in a separate GPU process that draws into a window owned by the browser process; while Windows and Linux handle that without complaint, Wine's macOS driver can't draw across processes, so the sign-in window stayed black even though the page itself rendered. CrossOver gets around this through D3DMetal. This project instead wraps `steamwebhelper.exe` (`tools/webhelper-wrapper.c`) and starts the real helper with `--in-process-gpu`, which keeps the compositor inside the process that owns the window. Steam restores its original helper whenever file sizes don't match, hence `-noverifyfiles`; the launcher reinstalls the wrapper whenever a Steam update replaces it.

| Patch | What it does |
|---|---|
| `0001-win32u-build-without-libvulkan` | Restores upstream's guard so Wine builds without a Vulkan loader |
| `0002-winecoreaudio-opt-in-5.1-with-stereo-downmix` | Offers games 5.1 and mixes it down to stereo; CoreAudio maps channels without mixing them, which dropped the center channel |
| `0003-winemac-debug-surface-dump` | `WINE_MACDRV_DUMP_DIR` saves each window surface handed to Cocoa, for debugging without screen capture |
| `0004-winecoreaudio-follow-default-output-device` | Audio on the default device follows macOS output changes |
| `dxvk/0001`, `dxvk/0002` | Header fixes for mingw-w64 14 |

## Credits

CodeWeavers, for publishing CrossOver's source; the Wine project; DXMT, a Direct3D 11-to-Metal layer by 3Shain; MoltenVK from the Khronos Group; DXVK and Gcenx's DXVK-macOS fork; and notpop's steam-on-m1-wine, whose write-up of the steamwebhelper problem pointed the way.

## License

LGPL-2.1-or-later, the same as Wine; see `LICENSE`. Everything fetched at build time stays under its own license.
