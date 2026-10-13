#!/bin/bash
# Launch Windows Steam on our Wine with the settings that work (2026-10-12):
#  - MSync on (CrossOver's fast sync)
#  - DXMT installed for games (scripts/install-dxmt.sh on)
#  - Steam's UI rendered on the CPU, with the compositor kept in the window's own process
#    (webhelper wrapper below). Cross-process presentation fails both under DXMT
#    (issue #141) and with Wine's macOS GDI path.
#  - Audio offered to games as 5.1 and mixed down to stereo by our CoreAudio driver
#    (patches/0002). Meant to fix center-channel dialog going missing (LEGO Skywalker Saga);
#    untested in-game.
#    WINE_COREAUDIO_FORCE_5_1=0 turns it off.
# Usage: scripts/steam.sh [extra steam args]   (Ctrl-C or `scripts/steam.sh --stop` to quit)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export WINEPREFIX="$ROOT/prefixes/steam"
export WINEMSYNC=1
export WINE_COREAUDIO_FORCE_5_1="${WINE_COREAUDIO_FORCE_5_1:-1}"
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree,mshtml=;winemenubuilder.exe=d}"
export DXMT_LOG_PATH="${DXMT_LOG_PATH:-Z:${ROOT//\//\\}\\logs\\dxmt\\}"
mkdir -p "$ROOT/logs/dxmt"

if [ "${1:-}" = "--stop" ]; then
    exec "$ROOT/dist/bin/wineserver" -k
fi

# Steam's web helper draws its UI from a separate GPU process into a window owned by another
# process. Wine's macOS driver can't do cross-process window drawing (cf. Wine bug 56014), so
# the window stays black. Our wrapper (tools/webhelper-wrapper.c) starts the real helper with
# --in-process-gpu so the compositor lives in the process that owns the window.
# Steam's bootstrapper restores the original helper when file sizes don't match, hence
# -noverifyfiles. If Steam updated the helper, the new one becomes steamwebhelper_real.exe.
install_webhelper_wrapper() {
    local cef="$WINEPREFIX/drive_c/Program Files (x86)/Steam/bin/cef/cef.win64"
    local wrapper="$ROOT/tools/steamwebhelper-wrapper.exe"
    [ -f "$wrapper" ] || x86_64-w64-mingw32-gcc -O2 -municode -mwindows \
        -o "$wrapper" "$ROOT/tools/webhelper-wrapper.c"
    [ -f "$cef/steamwebhelper.exe" ] || return 0
    if ! cmp -s "$cef/steamwebhelper.exe" "$wrapper"; then
        mv "$cef/steamwebhelper.exe" "$cef/steamwebhelper_real.exe"
        cp "$wrapper" "$cef/steamwebhelper.exe"
    fi
}
install_webhelper_wrapper

exec "$ROOT/dist/bin/wine" 'C:\Program Files (x86)\Steam\steam.exe' -cef-disable-gpu -noverifyfiles "$@"
