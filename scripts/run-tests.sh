#!/bin/bash
# Build the test programs in tools/ and run them in prefixes/test with time limits.
# Usage: scripts/run-tests.sh [--steam]
#   --steam also checks that Steam's sign-in window is drawn (scripts/check-login-visual.sh).
# Prints one line per test and exits with the number of failures.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export WINEPREFIX="$ROOT/prefixes/test" WINEDEBUG=-all
C="$WINEPREFIX/drive_c"
T="$ROOT/tools"
mkdir -p "$C/dxvktest"

fails=0
build() { # compiler out.exe source.c [libs...]   (a failed build counts as a failure)
    local cc=$1 out=$2 src=$3; shift 3
    rm -f "$T/$out" "$C/$out"
    if "$cc" -O2 -o "$T/$out" "$T/$src" "$@"; then
        cp "$T/$out" "$C/"
    else
        printf 'FAIL  build %s\n' "$out"; fails=$((fails + 1))
    fi
}
build x86_64-w64-mingw32-gcc d3d9test.exe d3d9test.c -ld3d9
build i686-w64-mingw32-gcc d3d9test32.exe d3d9test.c -ld3d9
build x86_64-w64-mingw32-gcc d3d11test.exe d3d11test.c -ld3d11 -ldxgi -luuid -lgdi32 -luser32
build x86_64-w64-mingw32-gcc d3d12test.exe d3d12test.c -ld3d12 -ldxgi -luuid
build x86_64-w64-mingw32-gcc vktest.exe vktest.c
build x86_64-w64-mingw32-gcc wasapitest.exe wasapitest.c -lole32 -luuid
build x86_64-w64-mingw32-gcc mp3test.exe mp3test.c -lole32 -lstrmiids -luuid
build i686-w64-mingw32-gcc mp3test32.exe mp3test.c -lole32 -lstrmiids -luuid
build i686-w64-mingw32-gcc memtest32.exe memtest.c -Wl,--disable-large-address-aware
build x86_64-w64-mingw32-gcc padtest.exe padtest.c -ldinput8 -ldxguid -lxinput -lole32
cp "$T/d3d11test.exe" "$ROOT/dist/dxvk/x64/d3d11.dll" "$ROOT/dist/dxvk/x64/dxgi.dll" "$C/dxvktest/"
python3 -I "$T/make-silent-mp3.py" "$C/silence.mp3" 3 > /dev/null

check() { # label [NEED=<text the output must contain>] [env assignments...] -- program
    local label=$1 need=""; shift
    case "$1" in NEED=*) need=${1#NEED=}; shift ;; esac
    local envs=()
    while [ "$1" != "--" ]; do envs+=("$1"); shift; done; shift
    local out
    out=$(env ${envs[@]+"${envs[@]}"} "$ROOT/scripts/wine-run.sh" 60 "$@" 2>&1)  # bash 3.2: empty array + set -u
    if grep -q 'RESULT: PASS' <<<"$out" && { [ -z "$need" ] || grep -qF "$need" <<<"$out"; }; then
        printf 'PASS  %s\n' "$label"
    else
        printf 'FAIL  %s\n' "$label"; fails=$((fails + 1))
        grep -E 'hr=|adapter|RESULT|wine-run' <<<"$out" | sed 's/^/      /'
        [ -n "$need" ] && printf '      (needed output: %s)\n' "$need"
    fi
}
check "D3D9 32-bit (wined3d)" -- 'C:\d3d9test32.exe'
check "D3D9 64-bit (wined3d)" -- 'C:\d3d9test.exe'
# Make sure the right layer ran, not a silent fallback to wined3d (which also reports the Apple
# GPU): DXMT and DXVK each log a line wined3d never prints, and DXMT's DLLs must be installed.
dxmt_ok=1
for d in d3d11 dxgi d3d12; do
    cmp -s "$ROOT/dist/dxmt/x86_64-windows/$d.dll" "$C/windows/system32/$d.dll" || dxmt_ok=0
done
if [ $dxmt_ok = 1 ]; then printf 'PASS  DXMT installed in the test prefix\n'
else printf 'FAIL  DXMT installed in the test prefix (run scripts/install-dxmt.sh on prefixes/test)\n'; fails=$((fails + 1)); fi
check "D3D11 (DXMT)" "NEED=Maximum supported feature level" "DXMT_LOG_LEVEL=info" -- 'C:\d3d11test.exe'
check "D3D11 (DXVK)" "NEED=DXVK: v" "DXVK_LOG_LEVEL=info" "WINEDLLOVERRIDES=d3d11,dxgi=n,b;mscoree,mshtml=" -- 'C:\dxvktest\d3d11test.exe'
check "D3D12 (DXMT)" -- 'C:\d3d12test.exe'
check "Vulkan (MoltenVK)" -- 'C:\vktest.exe'
check "WASAPI stereo" "WINE_COREAUDIO_FORCE_5_1=0" -- 'C:\wasapitest.exe'
check "WASAPI 5.1 downmix" "WINE_COREAUDIO_FORCE_5_1=1" -- 'C:\wasapitest.exe'
check "MP3 via DirectShow 32-bit" -- 'C:\mp3test32.exe'
check "MP3 via DirectShow 64-bit" -- 'C:\mp3test.exe'
check "4 GB for 32-bit games" "WINE_LARGE_ADDRESS_AWARE=1" -- 'C:\memtest32.exe'
# Controller support: winebus (in a fresh prefix session, so its log is ours) must start its
# SDL bus. Without a controller attached that's as far as an automated check can go; padtest.exe
# lists real controllers.
"$ROOT/dist/bin/wineserver" -k 2>/dev/null; sleep 1
# "main loop started" alone isn't proof (a bus that failed to init logs it too), so also require
# that neither SDL failure message appears.
out=$(WINEDEBUG='+hid' "$ROOT/scripts/wine-run.sh" 60 'C:\padtest.exe' 1 2>&1)
if grep -q 'L"SDL" main loop started' <<<"$out" \
    && ! grep -qE 'SDL support not compiled in|L"SDL" bus (init|wait) returned|Unhandled (exception|page fault)' <<<"$out"; then
    printf 'PASS  Controller support (SDL bus started)\n'
else
    printf 'FAIL  Controller support (SDL bus started)\n'; fails=$((fails + 1))
    grep -E 'SDL' <<<"$out" | sed 's/^/      /' | head -5
fi
"$ROOT/dist/bin/wineserver" -k 2>/dev/null

if [ "${1:-}" = "--steam" ]; then
    # The same programs with exactly the environment Steam gives games (steam.sh --exec).
    S="$ROOT/prefixes/steam/drive_c"
    cp "$C/memtest32.exe" "$C/mp3test32.exe" "$C/silence.mp3" "$S/"
    for prog in memtest32 mp3test32; do
        out=$(EXEC_TIME_LIMIT=60 "$ROOT/scripts/steam.sh" --exec "C:\\$prog.exe" 2>&1)
        if grep -q 'RESULT: PASS' <<<"$out"; then
            printf 'PASS  %s with Steam'"'"'s environment\n' "$prog"
        else
            printf 'FAIL  %s with Steam'"'"'s environment\n' "$prog"; fails=$((fails + 1))
            grep -E 'RESULT|reserved|WaitFor' <<<"$out" | sed 's/^/      /'
        fi
    done
    "$ROOT/scripts/steam.sh" --stop 2>/dev/null; sleep 2
    rm -f "$S/memtest32.exe" "$S/mp3test32.exe" "$S/silence.mp3"

    line=$("$ROOT/scripts/check-login-visual.sh" regression)
    if grep -q 'nonblack=100.0%' <<<"$line" && grep -q 'login=yes' <<<"$line"; then
        printf 'PASS  Steam sign-in window drawn\n'
    else
        printf 'FAIL  Steam sign-in window drawn\n      %s\n' "$line"; fails=$((fails + 1))
    fi
fi

echo "$fails failure(s)"
exit "$fails"
