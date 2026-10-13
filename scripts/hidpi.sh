#!/bin/bash
# Match the CrossOver bottle's display settings: Retina (full-resolution) rendering and 2x
# DPI (192) so text and UI aren't tiny. Usage: scripts/hidpi.sh on|off [prefix]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export WINEPREFIX=${2:-$ROOT/prefixes/steam} WINEDEBUG=-all WINEMSYNC=1
wine() { "$ROOT/dist/bin/wine" "$@" >/dev/null; }
case ${1:?on|off} in
on)  retina=y; dpi=192 ;;
off) retina=n; dpi=96 ;;
*)   echo "usage: $0 on|off [prefix]"; exit 1 ;;
esac
wine reg add 'HKCU\Software\Wine\Mac Driver' /v RetinaMode /d $retina /f
wine reg add 'HKCU\Control Panel\Desktop' /v LogPixels /t REG_DWORD /d $dpi /f
wine reg add 'HKCU\Software\Wine\Fonts' /v LogPixels /t REG_DWORD /d $dpi /f
"$ROOT/dist/bin/wineserver" -k
echo "hidpi $1 (RetinaMode=$retina, LogPixels=$dpi)"
