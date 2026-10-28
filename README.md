# steam-wine

Windows Steam and Windows games on Apple Silicon Macs, running on a Wine I build myself from CodeWeavers' published CrossOver source; no CrossOver license, no Whisky, no Game Porting Toolkit.

While CrossOver is good software, it costs $74 per Mac, and every free option I tried was stuck on 2022-era Wine that the 2026 Steam client won't even boot on. CodeWeavers publishes the Wine they ship under the LGPL, so this project builds that source (CrossOver 26.3, based on Wine 11.0), adds DXMT for Direct3D 11 on Metal, MoltenVK and DXVK as a fallback, and carries a handful of patches for the problems that came up along the way. Built and tested on an M5 Pro MacBook Pro running macOS 27.0.1, with LEGO Star Wars: The Skywalker Saga as the test game.

## What works

- Windows Steam: install, self-update, sign-in, library, downloads.
- Direct3D 10/11 games through DXMT (Metal), with DXVK (Vulkan through MoltenVK) as a per-game fallback.
- Direct3D 12 through DXMT's experimental D3D12 support; a test program renders and presents correctly, but don't expect demanding DX12 games to run yet.
- Vulkan through MoltenVK.
- Game controllers through SDL2. Xbox and Switch Pro controllers (USB or Bluetooth) show up to games as standard XInput pads. PS4/PS5 controllers show up as their own device, which games with native DualShock support use; XInput-only games such as New Vegas need Steam Input or a registry switch (see docs/NOTES.md). Not yet tested with a physical controller; after `scripts/run-tests.sh`, `scripts/wine-run.sh 30 'C:\padtest.exe' 10` lists what games see and shows button presses.
- 4 GB of address space for 32-bit games, without patching their executables (Fallout 3 and New Vegas otherwise run out at 2 GB). It applies to every 32-bit program Steam starts; if an old 32-bit game misbehaves, `WINE_LARGE_ADDRESS_AWARE=0 scripts/steam.sh` turns it off for the session.
- MP3 and WAV audio through GStreamer, so older games' DirectShow music plays (Fallout 3, New Vegas and Oblivion play music this way; not yet tested in those games). Media Foundation goes through the same plugins but is untested, and no video decoders are built.
- Games render at the size your display setting "looks like" (3008×1692 on a 4K screen scaled that way) and macOS scales them up, so they run fast. `scripts/hidpi.sh on` makes Steam's text crisper, but every game then defaults to the full pixel size (6016×3384 on that screen), where Moon Sweepers dropped from 60 fps to 22.
- Game audio offered as 5.1 and mixed down to stereo, so center-channel dialog isn't lost; audio follows the macOS output device (headphones connected mid-game get the sound).

## What doesn't

- Games with kernel-level anti-cheat (Valorant, Fortnite, many shooters); no Wine setup runs those.
- Reliable Direct3D 12. DXMT's implementation is young; CrossOver uses Apple's closed-source D3DMetal, which this project doesn't include.
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

`build-all.sh` fetches every source at a pinned version (`fetch-sources.sh` checks the downloads against SHA-256 sums), then builds the x86_64 libraries, GStreamer, SDL2, MoltenVK, Wine, LLVM 15 and DXMT, and DXVK. `scripts/run-tests.sh` builds small test programs and checks each piece (DirectX 9/11/12, Vulkan, audio, MP3 playback, 4 GB for 32-bit games, the controller layer); `--steam` also runs some of them with Steam's own environment and checks that Steam's sign-in window is drawn, while `--build-only` just compiles them (no Wine needed). `install-steam.sh` creates the Windows environment in `prefixes/steam`, installs Steam from Valve's CDN, turns on DXMT and leaves Retina mode off (see `scripts/hidpi.sh`).

## Play

Open OpenRunner (`scripts/build-app.sh --install` builds it and moves it into your Applications folder), or run `scripts/steam.sh` from a terminal (`Steam (Wine).command` does the same from Finder). Sign in, install a game, play. Steam updates itself on the first launch (about 250 MB), and a game's first run is slow while shaders compile.

OpenRunner stays open as long as anything runs in Steam's Wine, including while Steam restarts itself after an update, and closes once you exit Steam. Quitting OpenRunner quits Steam and everything Wine started; clicking its Dock icon brings Steam's window forward. Its log is `logs/openrunner.log`.

- `scripts/build-app.sh --name <name> --icon <image>` rebuilds the app with another name or icon (any image macOS can read, fitted to a square; the default is `art/openrunner-icon.svg`). Without `--install` the app stays in `build/app/`. Rebuild it if you move the project folder. The app is signed only on this Mac, so each rebuild makes macOS forget the permissions you gave it, such as the microphone for voice chat.
- `scripts/steam.sh --stop` quits Steam and everything Wine started.
- `scripts/steam.sh --exec <program>` runs a Windows program (an installer, a mod manager) inside Steam's environment with the same settings. Start Steam first if the program launches a game, so the game's Steam session gets Steam's fixes.
- `scripts/game-graphics.sh <path to the game's exe> dxvk` switches one game to DXVK; `dxmt` switches it back.
- `WINE_COREAUDIO_FORCE_5_1=0 scripts/steam.sh` turns off the 5.1 downmix, and `WINE_COREAUDIO_FOLLOW_DEFAULT=0` keeps game audio on the device that was selected when the game started.

## Updating

Every pinned version, checksum and commit lives in `scripts/versions.sh`. When CodeWeavers publishes a new CrossOver source release, `scripts/update-crossover.sh <version>` downloads it and applies this project's Wine and GLib patches to a scratch copy; it names any patch that no longer applies, and leaves the scratch copy in `build/crossover-check.noindex/` so you can look at the rejects. `--apply` pins the new version, keeps the old sources as `src/sources-<old version>` and unpacks the new ones, after which `scripts/build-all.sh` rebuilds everything. CodeWeavers doesn't publish checksums, so a new version's SHA-256 comes from the download itself.

On every push, GitHub Actions (`.github/workflows/check.yml`) runs shellcheck over the scripts, builds the test programs and the Mac app, and checks that the patches still apply to the pinned CrossOver release. A full Wine build takes too long for CI, so `scripts/run-tests.sh` on a built checkout is still the real test.

## How it works

Wine's macOS side still runs under Rosetta, so every library it links against has to be an Intel build; `build-deps.sh` cross-compiles gmp, nettle, gnutls and freetype from the arm64 side into `deps/`. The CrossOver tarball isn't quite buildable as shipped (nettle is missing its Makefile.in, gnutls's configure never links nettle, and freetype wants a git submodule that isn't there), and `docs/NOTES.md` covers each workaround.

The black Steam window was the hard part. Steam's web helper, a build of Chromium 126, runs its compositor in a separate GPU process that draws into a window owned by the browser process; while Windows and Linux handle that without complaint, Wine's macOS driver can't draw across processes, so the sign-in window stayed black even though the page itself rendered. CrossOver gets around this through D3DMetal. This project instead wraps `steamwebhelper.exe` (`tools/webhelper-wrapper.c`) and starts the real helper with `--in-process-gpu`, which keeps the compositor inside the process that owns the window. Steam restores its original helper whenever file sizes don't match, hence `-noverifyfiles`. A Steam client update still replaces the helper mid-launch, so the launcher keeps a small watcher running alongside Steam; it re-wraps a replaced helper and stops an unwrapped one, and Steam restarts its helper through the wrapper within about 10 seconds.

| Patch | What it does |
|---|---|
| `0001-win32u-build-without-libvulkan` | Restores upstream's guard so Wine builds without a Vulkan loader |
| `0002-winecoreaudio-opt-in-5.1-with-stereo-downmix` | Offers games 5.1 and mixes it down to stereo; CoreAudio maps channels without mixing them, which dropped the center channel |
| `0003-winemac-debug-surface-dump` | `WINE_MACDRV_DUMP_DIR` saves each window surface handed to Cocoa, for debugging without screen capture |
| `0004-winecoreaudio-follow-default-output-device` | Audio on the default device follows macOS output changes |
| `dxvk/0001`, `dxvk/0002` | Header fixes for mingw-w64 14 |
| `glib/0001` | GLib 2.78's D-Bus code generator without Python's removed `distutils` |

## Credits

CodeWeavers, for publishing CrossOver's source; the Wine project; DXMT, a Direct3D 11-to-Metal layer by 3Shain; MoltenVK from the Khronos Group; DXVK and Gcenx's DXVK-macOS fork; and notpop's steam-on-m1-wine, whose write-up of the steamwebhelper problem pointed the way.

## License

LGPL-2.1-or-later, the same as Wine; see `LICENSE`. Everything fetched at build time stays under its own license.
