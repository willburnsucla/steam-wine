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

# Is a process whose command line contains $1 running? (grep -v grep: grep's own command
# line contains the pattern.)
running() { ps -axo args | grep -v grep | grep -qiF "$1"; }   # Steam shows as steam.exe or Steam.exe

# A Steam client update replaces the helper mid-launch, after the check above, so the restarted
# Steam would run it unwrapped (black window). While Steam runs, re-wrap a replaced helper and
# stop an unwrapped one; Steam restarts its helper, this time through the wrapper.
watch_webhelper() {
    # This runs in a background subshell; a grep with no match must not end it.
    set +e +o pipefail
    local cef="$WINEPREFIX/drive_c/Program Files (x86)/Steam/bin/cef/cef.win64"
    local wrapper="$ROOT/tools/steamwebhelper-wrapper.exe" seen=0 strikes=0 pids
    while sleep 2; do
        if running 'C:\Program Files (x86)\Steam\steam.exe'; then
            seen=1
        elif [ $seen = 1 ]; then
            break   # Steam has exited
        fi
        [ -f "$cef/steamwebhelper.exe" ] || continue
        cmp -s "$cef/steamwebhelper.exe" "$wrapper" || install_webhelper_wrapper
        # Unwrapped = helper processes running but none of them is steamwebhelper_real.exe.
        # Require it on two checks in a row, so a wrapper that is still starting its real
        # helper isn't mistaken for an unwrapped one.
        pids=$(ps -axo pid,args | grep -F 'cef.win64\steamwebhelper.exe' | grep -v grep | awk '{print $1}')
        if [ -n "$pids" ] && ! running 'cef.win64\steamwebhelper_real.exe'; then
            strikes=$((strikes + 1))
            [ $strikes -ge 2 ] && { kill $pids 2>/dev/null; strikes=0; }
        else
            strikes=0
        fi
    done
}
watch_webhelper > /dev/null 2>&1 &

exec "$ROOT/dist/bin/wine" 'C:\Program Files (x86)\Steam\steam.exe' -cef-disable-gpu -noverifyfiles "$@"
