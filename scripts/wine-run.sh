#!/bin/bash
# Run our Wine with a hard time limit and a process-count guard.
# Usage: scripts/wine-run.sh <seconds> <wine args...>
#   env: WINEPREFIX (default prefixes/test), EXTRA env passes through.
# On timeout (unless WINE_RUN_KEEP=1) or when wine processes exceed MAX_PROCS, kills the
# prefix's wineserver and every process started from our dist/ tree.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIMIT=${1:?seconds}; shift
MAX_PROCS=${MAX_PROCS:-60}

export WINEPREFIX="${WINEPREFIX:-$ROOT/prefixes/test}"
export PATH="$ROOT/dist/bin:$PATH"
export WINEDEBUG="${WINEDEBUG:-fixme-all}"
# No mono/gecko install prompts (they'd block a headless run).
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree,mshtml=;winemenubuilder.exe=d}"
mkdir -p "$(dirname "$WINEPREFIX")"

# Wine renames its processes to Windows paths (C:\...), so find ours by the ntdll.so
# they all map from our dist/ tree. This never matches CrossOver's processes.
NTDLL="$ROOT/dist/lib/wine/x86_64-unix/ntdll.so"
our_pids() { lsof -t "$NTDLL" 2>/dev/null; pgrep -f "$ROOT/dist/bin/wineserver"; }
count_procs() { our_pids | sort -u | wc -l | tr -d ' '; }
kill_all() {
    "$ROOT/dist/bin/wineserver" -k 2>/dev/null
    sleep 2
    our_pids | xargs kill -9 2>/dev/null
}

"$ROOT/dist/bin/wine" "$@" &
pid=$!
start=$(date +%s)
status=running
while kill -0 $pid 2>/dev/null; do
    n=$(count_procs)
    if [ "$n" -gt "$MAX_PROCS" ]; then status="too-many-processes($n)"; kill_all; break; fi
    if [ $(( $(date +%s) - start )) -ge "$LIMIT" ]; then
        status=timeout
        # Kill on timeout unless the caller manages shutdown itself (e.g. steam-test.sh).
        [ "${WINE_RUN_KEEP:-0}" = 1 ] || kill_all
        break
    fi
    sleep 2
done
[ "$status" = running ] && { wait $pid; status="exited($?)"; }
echo "[wine-run] $status after $(( $(date +%s) - start ))s; wine procs now: $(count_procs)"
