#!/bin/bash
# Is Steam's login window actually drawn? Launches Steam with the macdrv surface dump
# (patches/0003, WINE_MACDRV_DUMP_DIR), waits for the login window, then measures the dumped
# window surface: what Wine hands to Cocoa, i.e. what's on screen.
# Usage: scripts/check-login-visual.sh <label> [steam args]
#   env: STEAMWEBHELPER_EXTRA_FLAGS (for tools/webhelper-wrapper.c), plus anything steam.sh takes.
# Prints the webhelper process types, whether the wrapper survived, and % non-black pixels.
# Leaves logs/surfaces-<label>/login.png for a look.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL=${1:?label}; shift
L="$ROOT/prefixes/steam/drive_c/Program Files (x86)/Steam/logs"
C="$ROOT/prefixes/steam/drive_c/Program Files (x86)/Steam/bin/cef/cef.win64"
D="$ROOT/logs/surfaces-$LABEL"
mkdir -p "$D"
date > "$ROOT/logs/heartbeat"

"$ROOT/scripts/steam.sh" --stop >/dev/null 2>&1; sleep 3
since=$(date '+%Y-%m-%d %H:%M:%S')
(WINE_MACDRV_DUMP_DIR="$D" "$ROOT/scripts/steam.sh" "$@" > "$D/steam.log" 2>&1 &)
login=no
for i in $(seq 1 60); do
    if awk -v s="[$since]" 'substr($0,1,21) >= s' "$L/webhelper.txt" | grep -q 'DesktopLoginWindow.*WasHidden 0'; then
        login="yes (${i}s)"; break
    fi
    sleep 1
done
sleep 8   # let a few frames land
procs=$(ps -axo args | grep -F 'Steam\bin\cef' | grep -v grep |
        sed -E 's/.*(steamwebhelper(_real)?\.exe) (-nocrashdialog|--type=[a-z-]+)?.*/\1 \3/' | sort | uniq -c | tr '\n' ';')
wrapper=$([ "$(stat -f %z "$C/steamwebhelper.exe")" -lt 1000000 ] && echo kept || echo RESTORED-BY-STEAM)
"$ROOT/scripts/steam.sh" --stop >/dev/null 2>&1; sleep 3

# The login window is the largest dumped surface.
big=$(ls -S "$D"/*.bmp 2>/dev/null | head -1)
pct=n/a
if [ -n "$big" ]; then
    sips -s format png "$big" --out "$D/login.png" >/dev/null 2>&1
    pct=$(python3 -I -c '
import struct, sys
d = open(sys.argv[1], "rb").read()
off = struct.unpack_from("<I", d, 10)[0]
px = d[off:]
idx = range(0, len(px) - 3, 4 * 97)
nz = sum(1 for i in idx if px[i] | px[i + 1] | px[i + 2])
print(f"{100 * nz / len(idx):.1f}%")' "$big")
fi
printf '%s\t%s\tlogin=%s\tnonblack=%s\twrapper=%s\tflags=%s\tprocs=%s\n' "$(date '+%H:%M:%S')" "$LABEL" \
    "$login" "$pct" "$wrapper" "${STEAMWEBHELPER_EXTRA_FLAGS:-default}" "$procs" | tee -a "$ROOT/logs/visual-tests.tsv"
