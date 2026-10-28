#!/bin/bash
# End-to-end test of the Mac app: open it, wait for Steam's sign-in window, quit the app while
# Steam is running, and check nothing is left behind (no Wine process, no steam.sh watcher).
# Usage: scripts/test-app.sh [path/to/App.app]   (default: OpenRunner.app in the project)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/OpenRunner.app}"
NAME="$(basename "$APP" .app)"
L="$ROOT/prefixes/steam/drive_c/Program Files (x86)/Steam/logs"
NTDLL="$ROOT/dist/lib/wine/x86_64-unix/ntdll.so"
wine_procs() { lsof -t "$NTDLL" 2>/dev/null | wc -l | tr -d ' '; }
watchers() { ps -axo args | grep -v grep | grep -c "$ROOT/scripts/steam.sh"; }
fails=0
result() { if [ "$1" = ok ]; then printf 'PASS  %s\n' "$2"; else printf 'FAIL  %s\n' "$2"; fails=$((fails + 1)); fi; }

[ -d "$APP" ] || { printf 'FAIL  %s exists\n' "$APP"; exit 1; }
"$ROOT/scripts/steam.sh" --stop >/dev/null 2>&1; sleep 3

since=$(date '+%Y-%m-%d %H:%M:%S')
open "$APP"
login=no
for _ in $(seq 1 90); do
    if awk -v s="[$since]" 'substr($0,1,21) >= s' "$L/webhelper.txt" 2>/dev/null | grep -q 'DesktopLoginWindow.*WasHidden 0'; then
        login=yes; break
    fi
    sleep 1
done
[ $login = yes ] && result ok "app starts Steam to its sign-in window" || result no "app starts Steam to its sign-in window"
sleep 3

osascript -e "quit app \"$NAME\"" >/dev/null 2>&1
for _ in $(seq 1 20); do
    [ "$(wine_procs)" = 0 ] && [ "$(watchers)" = 0 ] && ! pgrep -xq "$NAME" && break
    sleep 1
done
[ "$(wine_procs)" = 0 ] && result ok "quit stops every Wine process" || result no "quit stops every Wine process ($(wine_procs) left)"
[ "$(watchers)" = 0 ] && result ok "quit stops the steam.sh watcher" || result no "quit stops the steam.sh watcher"
! pgrep -xq "$NAME" && result ok "app itself exits" || result no "app itself exits"

# Clean up anything a failure left behind.
"$ROOT/scripts/steam.sh" --stop >/dev/null 2>&1
echo "$fails failure(s)"
exit "$fails"
