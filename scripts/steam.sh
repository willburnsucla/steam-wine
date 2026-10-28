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
#  - 4 GB of address space for 32-bit games (Fallout 3/New Vegas run out at 2 GB), without
#    patching their exes. WINE_LARGE_ADDRESS_AWARE=0 turns it off.
# Usage: scripts/steam.sh [extra steam args]   (Ctrl-C or `scripts/steam.sh --stop` to quit)
#        scripts/steam.sh --wait   wait until Steam and everything else Wine runs has exited
#        scripts/steam.sh --exec <program> [args]   run a program in Steam's prefix with Steam's
#            environment (installers, mod managers, tests). Start Steam first if the program
#            launches a game. EXEC_TIME_LIMIT=<seconds> is for tests: when it's hit, everything
#            Wine started (Steam included) is stopped.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/runtime-env.sh"
export WINEPREFIX="$ROOT/prefixes/steam"
export WINEMSYNC=1
export WINE_COREAUDIO_FORCE_5_1="${WINE_COREAUDIO_FORCE_5_1:-1}"
export WINE_LARGE_ADDRESS_AWARE="${WINE_LARGE_ADDRESS_AWARE:-1}"
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree,mshtml=;winemenubuilder.exe=d}"
export DXMT_LOG_PATH="${DXMT_LOG_PATH:-Z:${ROOT//\//\\}\\logs\\dxmt\\}"
mkdir -p "$ROOT/logs/dxmt"

# Our Wine's processes, one "pid command line" per line. Only processes using our ntdll count:
# CrossOver or another Wine may be running a Steam of its own.
NTDLL="$ROOT/dist/lib/wine/x86_64-unix/ntdll.so"
our_procs() {
    local pids
    pids=$(lsof -t "$NTDLL" 2>/dev/null | paste -sd, -)
    [ -z "$pids" ] || ps -o pid=,args= -p "$pids"
}
has() { grep -iF "$2" <<<"$1" >/dev/null; }   # Steam shows as steam.exe or Steam.exe

if [ "${1:-}" = "--stop" ]; then
    exec "$ROOT/dist/bin/wineserver" -k
fi
if [ "${1:-}" = "--wait" ]; then
    exec "$ROOT/dist/bin/wineserver" -w
fi

if [ "${1:-}" = "--exec" ]; then
    shift
    [ $# -gt 0 ] || { echo "usage: steam.sh --exec <program> [args]" >&2; exit 2; }
    case "${EXEC_TIME_LIMIT:-}" in
        *[!0-9]*) echo "EXEC_TIME_LIMIT must be a number of seconds" >&2; exit 2 ;;
    esac
    if [ -n "${EXEC_TIME_LIMIT:-}" ]; then
        exec "$ROOT/scripts/wine-run.sh" "$EXEC_TIME_LIMIT" "$@"
    fi
    exec "$ROOT/dist/bin/wine" "$@"
fi

# Steam already running in our Wine: hand over to it, which brings its window forward. Not in its
# first 45 s, though: until Steam is ready to take a hand-over, a second steam.exe starts a whole
# second Steam, and the two stall each other (a second click on the app while Steam starts).
steam_pid=$(our_procs | grep -iF 'C:\Program Files (x86)\Steam\steam.exe' | awk 'NR == 1 {print $1}' || true)
if [ -n "$steam_pid" ]; then
    age=$(ps -o etime= -p "$steam_pid" | awk -F'[-:]' '{
        if (NF == 2) print $1 * 60 + $2; else if (NF == 3) print $1 * 3600 + $2 * 60 + $3
        else print $1 * 86400 + $2 * 3600 + $3 * 60 + $4 }')
    if [ "${age:-0}" -lt 45 ]; then
        echo "Steam is still starting; not starting it again"
        exit 0
    fi
    exec "$ROOT/dist/bin/wine" 'C:\Program Files (x86)\Steam\steam.exe' -cef-disable-gpu -noverifyfiles "$@"
fi

# Steam's web helper draws its UI from a separate GPU process into a window owned by another
# process. Wine's macOS driver can't do cross-process window drawing (cf. Wine bug 56014), so
# the window stays black. Our wrapper (tools/webhelper-wrapper.c) starts the real helper with
# --in-process-gpu so the compositor lives in the process that owns the window.
# Steam's bootstrapper restores the original helper when file sizes don't match, hence
# -noverifyfiles. If Steam updated the helper, the new one becomes steamwebhelper_real.exe.
# The build and install steps are in scripts/webhelper.sh.
source "$ROOT/scripts/webhelper.sh"
CEF="$WINEPREFIX/drive_c/Program Files (x86)/Steam/bin/cef/cef.win64"
build_webhelper_wrapper
install_webhelper_wrapper "$CEF"


# A Steam client update replaces the helper mid-launch, after the check above, so the restarted
# Steam would run it unwrapped (black window). While Steam runs, re-wrap a replaced helper and
# stop an unwrapped one; Steam restarts its helper, this time through the wrapper.
watch_webhelper() {
    # This runs in a background subshell; a grep with no match must not end it.
    set +e +o pipefail
    local seen=0 strikes=0 procs pids
    while sleep 2; do
        procs=$(our_procs)
        if has "$procs" 'C:\Program Files (x86)\Steam\steam.exe'; then
            seen=1
        elif [ $seen = 1 ]; then
            break   # Steam has exited
        elif ! kill -0 $$ 2>/dev/null; then
            break   # Steam never started: the wine this script became ($$) is already gone
        fi
        install_webhelper_wrapper "$CEF"
        # Unwrapped = helper processes running but none of them is steamwebhelper_real.exe.
        # Require it on two checks in a row, so a wrapper that is still starting its real
        # helper isn't mistaken for an unwrapped one.
        pids=$(grep -F 'cef.win64\steamwebhelper.exe' <<<"$procs" | awk '{print $1}')
        if [ -n "$pids" ] && ! has "$procs" 'cef.win64\steamwebhelper_real.exe'; then
            strikes=$((strikes + 1))
            [ $strikes -ge 2 ] && { kill $pids 2>/dev/null; strikes=0; }
        else
            strikes=0
        fi
    done
}
watch_webhelper > /dev/null 2>&1 &

exec "$ROOT/dist/bin/wine" 'C:\Program Files (x86)\Steam\steam.exe' -cef-disable-gpu -noverifyfiles "$@"
