#!/bin/bash
# Choose the D3D10/11 backend for one game in prefixes/steam.
# Usage: scripts/game-graphics.sh <exe path inside the prefix> dxmt|dxvk
#   dxmt: default; uses DXMT installed into our Wine (scripts/install-dxmt.sh on).
#   dxvk: copies DXVK (dist/dxvk/x64) next to the game's exe and sets a per-exe override
#         (HKCU\Software\Wine\AppDefaults\<exe>\DllOverrides) so only that game uses it.
# Example: scripts/game-graphics.sh "steamapps/common/LEGO Star Wars - The Skywalker Saga/LEGOSTARWARSSKYWALKERSAGA_DX11.exe" dxvk
#   (relative paths are taken from the Steam folder)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export WINEPREFIX="$ROOT/prefixes/steam" WINEDEBUG=-all WINEMSYNC=1
STEAM="$WINEPREFIX/drive_c/Program Files (x86)/Steam"
EXE=${1:?exe path}; MODE=${2:?dxmt|dxvk}
case $EXE in /*) ;; *) EXE="$STEAM/$EXE" ;; esac
[ -f "$EXE" ] || { echo "not found: $EXE"; exit 1; }
DIR=$(dirname "$EXE"); NAME=$(basename "$EXE")
KEY="HKCU\\Software\\Wine\\AppDefaults\\$NAME\\DllOverrides"
DLLS="d3d11 dxgi d3d10core"
wine() { "$ROOT/dist/bin/wine" "$@"; }

case $MODE in
dxvk)
    for d in $DLLS; do cp "$ROOT/dist/dxvk/x64/$d.dll" "$DIR/"; done
    for d in $DLLS; do wine reg add "$KEY" /v "$d" /d native,builtin /f >/dev/null; done
    echo "$NAME -> DXVK"
    ;;
dxmt)
    # Remove only files that are byte-identical to our DXVK build, never the game's own DLLs.
    for d in $DLLS; do
        if [ -f "$DIR/$d.dll" ] && cmp -s "$DIR/$d.dll" "$ROOT/dist/dxvk/x64/$d.dll"; then
            mv "$DIR/$d.dll" "$ROOT/logs/removed-$NAME-$d.dll"
        fi
    done
    wine reg delete "$KEY" /f >/dev/null 2>&1 || true
    echo "$NAME -> DXMT"
    ;;
*) echo "usage: $0 <exe> dxmt|dxvk"; exit 1 ;;
esac
