#!/bin/bash
# End-to-end tests of the Mac app. Each of the first four starts real Steam.
#   1. open the app, wait for Steam's sign-in window, click the app again (Dock reopen), quit,
#      and check nothing is left behind (no Wine process, no steam.sh watcher, app gone)
#   2. Steam already running when the app opens, the way it is after Steam restarts itself to
#      update: the app must stay open, and quitting it must still stop everything
#   3. quit one second after opening: nothing may be left behind
#   4. Steam's own Exit (steam.exe -shutdown) closes the app
#   5. project folder gone: the app must say so instead of vanishing, and not recreate the folder
# Usage: scripts/test-app.sh [path/to/App.app]
#   (default: build/app/OpenRunner.app if it's there, else ~/Applications/OpenRunner.app)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/build/app/OpenRunner.app}"
[ -n "${1:-}" ] || [ -d "$APP" ] || APP="$HOME/Applications/OpenRunner.app"
NAME="$(basename "$APP" .app)"
L="$ROOT/prefixes/steam/drive_c/Program Files (x86)/Steam/logs"
NTDLL="$ROOT/dist/lib/wine/x86_64-unix/ntdll.so"
wine_procs() { lsof -t "$NTDLL" 2>/dev/null | wc -l | tr -d ' '; }
watchers() { ps -axo args | grep -v grep | grep -c "$ROOT/scripts/steam.sh"; }
app_running() { pgrep -xq "$NAME"; }
steam_count() { # steam.exe processes in our Wine
    local p
    for p in $(lsof -t "$NTDLL" 2>/dev/null); do ps -o args= -p "$p"; done |
        grep -ciE '^C:\\Program Files \(x86\)\\Steam\\steam\.exe'
}
fails=0
result() { if [ "$1" = ok ]; then printf 'PASS  %s\n' "$2"; else printf 'FAIL  %s\n' "$2"; fails=$((fails + 1)); fi; }
check() { if eval "$2"; then result ok "$1"; else result no "$1"; fi; }

stop_all() { # leave nothing running for the next scenario
    "$ROOT/scripts/steam.sh" --stop >/dev/null 2>&1
    pkill -f "$ROOT/scripts/steam.sh" 2>/dev/null
    pkill -x "$NAME" 2>/dev/null
    sleep 3
}
wait_signin() { # since-timestamp: wait up to 180 s for Steam's sign-in window, or its main
    local _      # window when it signs in by itself (usually seconds; a busy Mac can take a minute)
    for _ in $(seq 1 180); do
        awk -v s="[$1]" 'substr($0,1,21) >= s' "$L/webhelper.txt" 2>/dev/null |
            grep -qE '(DesktopLoginWindow|SP Desktop_uid[0-9]+)[^:]*: WasHidden 0' && return 0
        sleep 1
    done
    return 1
}
quit_and_check() { # label: quit the app, then check everything stopped
    osascript -e "quit app \"$NAME\"" >/dev/null 2>&1
    local _
    for _ in $(seq 1 30); do
        [ "$(wine_procs)" = 0 ] && [ "$(watchers)" = 0 ] && ! app_running && break
        sleep 1
    done
    check "$1: quit stops every Wine process" '[ "$(wine_procs)" = 0 ]'
    check "$1: quit stops the steam.sh watcher" '[ "$(watchers)" = 0 ]'
    check "$1: app itself exits" '! app_running'
}

[ -d "$APP" ] || { printf 'FAIL  %s exists\n' "$APP"; exit 1; }
stop_all

# 1. Normal start and quit, with a second click while Steam is still starting.
since=$(date '+%Y-%m-%d %H:%M:%S')
open "$APP"
sleep 3
open "$APP"   # what an impatient second click does
check "app starts Steam to its window" 'wait_signin "$since"'
sleep 5
check "second click while starting doesn't start a second Steam" '[ "$(steam_count)" = 1 ]'
open "$APP"   # app already running: macOS sends it a reopen, as a Dock click does
sleep 8
check "reopen keeps a single app" '[ "$(pgrep -x "$NAME" | wc -l | tr -d " ")" = 1 ]'
check "reopen keeps a single Steam" '[ "$(steam_count)" = 1 ]'
quit_and_check "normal"
stop_all

# 2. Steam already running.
since=$(date '+%Y-%m-%d %H:%M:%S')
mkdir -p "$ROOT/logs"
"$ROOT/scripts/steam.sh" >> "$ROOT/logs/test-app-steam.log" 2>&1 &
if wait_signin "$since"; then
    open "$APP"
    sleep 20
    check "Steam already running: app stays open" 'app_running'
    quit_and_check "Steam already running"
else
    result no "Steam already running: Steam started from steam.sh"
fi
stop_all

# 3. Quit right after opening.
open "$APP"
sleep 1
quit_and_check "quit after 1 s"
sleep 10   # anything that starts late would show up now
check "quit after 1 s: still nothing running 10 s later" '[ "$(wine_procs)" = 0 ] && [ "$(watchers)" = 0 ]'
stop_all

# 4. Steam's own Exit.
since=$(date '+%Y-%m-%d %H:%M:%S')
open "$APP"
if wait_signin "$since"; then
    sleep 3
    "$ROOT/scripts/steam.sh" --exec 'C:\Program Files (x86)\Steam\steam.exe' -shutdown >/dev/null 2>&1
    for _ in $(seq 1 45); do app_running || break; sleep 1; done
    check "Steam's Exit closes the app" '! app_running'
    check "Steam's Exit: nothing left running" '[ "$(wine_procs)" = 0 ] && [ "$(watchers)" = 0 ]'
else
    result no "Steam's Exit: app starts Steam"
fi
stop_all

# 5. Project folder gone: a copy of the app pointing at a folder that doesn't exist.
T="$ROOT/build/app-test"
rm -rf "$T" && mkdir -p "$T"
ditto "$APP" "$T/$NAME.app"
echo "$T/missing-project" > "$T/$NAME.app/Contents/Resources/root.txt"
codesign --force --sign - "$T/$NAME.app" >/dev/null 2>&1
open "$T/$NAME.app"
sleep 5
check "project gone: app stays open to explain" 'pgrep -f "$T/$NAME.app/Contents/MacOS" >/dev/null'
check "project gone: old folder isn't recreated" '[ ! -e "$T/missing-project" ]'
pkill -f "$T/$NAME.app/Contents/MacOS" 2>/dev/null
rm -rf "$T"

stop_all
echo "$fails failure(s)"
exit "$fails"
