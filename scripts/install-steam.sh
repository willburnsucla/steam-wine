#!/bin/bash
# Create the Windows environment (prefix) and install Windows Steam into it.
# Usage: scripts/install-steam.sh [prefix]   (default: prefixes/steam)
# Then start Steam with scripts/steam.sh (or "Steam (Wine).command"). The first launch updates
# Steam itself (~250 MB) before the sign-in window appears.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export WINEPREFIX="${1:-$ROOT/prefixes/steam}" WINEMSYNC=1
SETUP="$ROOT/downloads/SteamSetup.exe"

mkdir -p "$ROOT/downloads" "$(dirname "$WINEPREFIX")"
[ -f "$SETUP" ] || curl -fL --retry 3 -o "$SETUP" \
    https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe

"$ROOT/scripts/wine-run.sh" 120 wineboot -i
"$ROOT/scripts/wine-run.sh" 300 "$SETUP" /S
[ -f "$WINEPREFIX/drive_c/Program Files (x86)/Steam/steam.exe" ] || { echo "Steam install failed"; exit 1; }
"$ROOT/dist/bin/wineserver" -k || true

"$ROOT/scripts/install-dxmt.sh" on "$WINEPREFIX"
"$ROOT/scripts/hidpi.sh" on "$WINEPREFIX"
echo "Steam installed in $WINEPREFIX. Start it with scripts/steam.sh"
