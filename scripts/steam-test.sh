#!/bin/bash
# Launch Windows Steam in prefixes/steam, wait for the login window or an engine stall,
# record the outcome, and shut everything down.
# Usage: scripts/steam-test.sh <label> [steam.exe args...]
#   env: WINEMSYNC=1 to use msync; LIMIT (default 120 s)
# Appends one line to logs/steam-tests.tsv: time, label, msync, args, outcome, seconds.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL=${1:?label}; shift
LIMIT=${LIMIT:-120}
export WINEPREFIX="$ROOT/prefixes/steam"
STEAM_LOGS="$WINEPREFIX/drive_c/Program Files (x86)/Steam/logs"
OUT="$ROOT/logs/steam-test-$LABEL.log"
NTDLL="$ROOT/dist/lib/wine/x86_64-unix/ntdll.so"

stop_all() {
    "$ROOT/dist/bin/wineserver" -k 2>/dev/null
    sleep 3
    lsof -t "$NTDLL" 2>/dev/null | xargs kill -9 2>/dev/null
}

stop_all
start=$(date +%s)
since=$(date '+%Y-%m-%d %H:%M:%S')
WINE_RUN_KEEP=1 "$ROOT/scripts/wine-run.sh" "$LIMIT" 'C:\Program Files (x86)\Steam\steam.exe' "$@" > "$OUT" 2>&1 &

# Only count webhelper.txt lines written after we started.
new_log_has() { awk -v s="[$since]" 'substr($0,1,21) >= s' "$STEAM_LOGS/webhelper.txt" 2>/dev/null | grep -q "$1"; }

outcome=timeout
while [ $(( $(date +%s) - start )) -lt "$LIMIT" ]; do
    if new_log_has "DesktopLoginWindow.*WasHidden 0"; then outcome=login-window; break; fi
    if grep -q "stalled" "$OUT"; then outcome=stall; break; fi
    if grep -q '\[wine-run\]' "$OUT"; then outcome=exited; break; fi
    sleep 1
done
secs=$(( $(date +%s) - start ))
[ "${KEEP_RUNNING:-0}" = 1 ] || stop_all
printf '%s\t%s\tmsync=%s\t%s\t%s\t%ss\n' "$since" "$LABEL" "${WINEMSYNC:-0}" "$*" "$outcome" "$secs" \
    | tee -a "$ROOT/logs/steam-tests.tsv"
