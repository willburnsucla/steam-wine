#!/bin/bash
# Wine's Retina mode. It covers Steam's window and every game at once; Wine reads it for all
# programs alike (dlls/winemac.drv/macdrv_main.c).
#   off (what install-steam.sh sets): Windows programs see the size macOS's display setting
#       "looks like" (3008x1692 on a 4K screen scaled that way) and macOS scales them up. Games
#       default to that size and run fast; Steam's text is a little soft.
#   on: they see every pixel macOS draws (6016x3384 on that screen) at 2x DPI. Steam is crisp,
#       but games default to that full size: Moon Sweepers ran at 22 fps there, 60 at 3008x1692.
# Takes effect the next time Steam starts. Usage: scripts/hidpi.sh on|off [prefix]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export WINEPREFIX=${2:-$ROOT/prefixes/steam} WINEDEBUG=-all WINEMSYNC=1
wine() { "$ROOT/dist/bin/wine" "$@" >/dev/null; }
case ${1:?on|off} in
on)  retina=y; dpi=192 ;;
off) retina=n; dpi=96 ;;
*)   echo "usage: $0 on|off [prefix]"; exit 1 ;;
esac
running=$(lsof -t "$ROOT/dist/lib/wine/x86_64-unix/ntdll.so" 2>/dev/null || true)
wine reg add 'HKCU\Software\Wine\Mac Driver' /v RetinaMode /d $retina /f
wine reg add 'HKCU\Control Panel\Desktop' /v LogPixels /t REG_DWORD /d $dpi /f
wine reg add 'HKCU\Software\Wine\Fonts' /v LogPixels /t REG_DWORD /d $dpi /f
# With Steam running, the change sits in its live registry until Steam exits. Otherwise wait for
# the short-lived Wine server `wine reg` started to save it.
if [ -n "$running" ]; then
    echo "hidpi $1 (RetinaMode=$retina, LogPixels=$dpi): quit and reopen Steam to see it"
else
    "$ROOT/dist/bin/wineserver" -w
    echo "hidpi $1 (RetinaMode=$retina, LogPixels=$dpi)"
fi
