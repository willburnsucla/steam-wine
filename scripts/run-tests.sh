#!/bin/bash
# Build the test programs in tools/ and run them in prefixes/test with time limits.
# Usage: scripts/run-tests.sh [--steam | --build-only]
#   --steam       also runs two tests with Steam's environment and checks that Steam's sign-in
#                 window is drawn (scripts/check-login-visual.sh)
#   --build-only  only compile the test programs (needs mingw-w64, not Wine; used by CI)
# Prints one line per test and exits with the number of failures.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE=${1:-}
case $MODE in
    ""|--steam|--build-only) ;;
    *) echo "usage: $0 [--steam | --build-only]" >&2; exit 2 ;;
esac
export WINEPREFIX="$ROOT/prefixes/test" WINEDEBUG=-all
C="$WINEPREFIX/drive_c"
T="$ROOT/tools"
[ "$MODE" = --build-only ] || mkdir -p "$C/dxvktest"

fails=0
built=" "
build() { # compiler out.exe source.c [libs...]   (a failed build counts as a failure)
    local cc=$1 out=$2 src=$3; shift 3
    built="$built$src "
    rm -f "$T/$out"
    [ "$MODE" = --build-only ] || rm -f "$C/$out"
    if "$cc" -O2 -o "$T/$out" "$T/$src" "$@"; then
        [ "$MODE" = --build-only ] || cp "$T/$out" "$C/"
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
build x86_64-w64-mingw32-gcc winlist.exe winlist.c -lgdi32 -luser32
built="${built}webhelper-wrapper.c "   # built by webhelper.sh below
# A new program in tools/ has to be added above, or CI would never compile it.
for f in "$T"/*.c; do
    case $built in *" $(basename "$f") "*) ;;
        *) printf 'FAIL  %s is not built by run-tests.sh\n' "${f#"$ROOT"/}"; fails=$((fails + 1)) ;;
    esac
done

# Installing Steam's web helper wrapper (scripts/webhelper.sh) into a fake cef folder. The real
# helper must never be lost, whatever is installed when steam.sh starts, and however many
# steam.sh instances install at once. Uses its own copy of the wrapper, so the one steam.sh
# installs isn't touched.
(
    WEBHELPER_WRAPPER="$T/webhelper-wrapper-test.exe"
    . "$ROOT/scripts/webhelper.sh"
    rm -f "$WEBHELPER_WRAPPER"
    build_webhelper_wrapper || exit 1
    W="$WEBHELPER_WRAPPER" bad=0
    X=$(mktemp -d) || exit 1
    D="$X/cef"
    older="$X/older.exe"   # an older build of the wrapper: same code, other bytes
    cp "$W" "$older"; printf 'X' | dd of="$older" bs=1 seek=136 conv=notrunc 2>/dev/null
    echo "real helper v1" > "$X/real1.exe"; echo "real helper v2" > "$X/real2.exe"
    report() { # label ok?
        if [ "$2" = 0 ]; then printf 'PASS  web helper wrapper: %s\n' "$1"
        else printf 'FAIL  web helper wrapper: %s\n' "$1"; bad=$((bad + 1)); fi
    }
    setup() { # installed-helper (or -) installed-real (or -)
        rm -rf "$D"; mkdir -p "$D"
        [ "$1" = - ] || cp "$1" "$D/steamwebhelper.exe"
        [ "$2" = - ] || cp "$2" "$D/steamwebhelper_real.exe"
    }
    installed() { # expected-real: wrapper in place and the real helper as expected?
        cmp -s "$D/steamwebhelper.exe" "$W" && cmp -s "$D/steamwebhelper_real.exe" "$1"
    }
    case_() { # label installed-helper installed-real expected-real
        setup "$2" "$3"
        install_webhelper_wrapper "$D"
        installed "$4"; report "$1" $?
    }
    case_ "first install keeps Steam's helper" "$X/real1.exe" - "$X/real1.exe"
    case_ "older wrapper build is replaced, real helper kept" "$older" "$X/real1.exe" "$X/real1.exe"
    case_ "Steam update becomes the real helper" "$X/real2.exe" "$X/real1.exe" "$X/real2.exe"
    case_ "already installed is left alone" "$W" "$X/real1.exe" "$X/real1.exe"
    case_ "interrupted install is finished" - "$X/real1.exe" "$X/real1.exe"
    # Two installs at once (two steam.sh watchers) right after a Steam update, 30 times. Helpers
    # the size of Steam's (7.5 MB) make the race window as wide as it really is. Each install is
    # retried as the watcher would, 2 s later.
    head -c 7500000 /dev/urandom > "$X/big1.exe"; head -c 7500000 /dev/urandom > "$X/big2.exe"
    lost=0
    for _ in $(seq 1 30); do
        setup "$X/big2.exe" "$X/big1.exe"
        install_webhelper_wrapper "$D" & install_webhelper_wrapper "$D" & wait
        install_webhelper_wrapper "$D"; install_webhelper_wrapper "$D"
        installed "$X/big2.exe" || lost=$((lost + 1))
    done
    report "two installs at once keep the real helper ($lost of 30 lost)" $lost
    build_webhelper_wrapper
    cp "$W" "$X/first.exe"; rm -f "$W"; sleep 1; build_webhelper_wrapper   # 1 s: a new link time
    cmp -s "$W" "$X/first.exe"; report "rebuild is byte-identical" $?
    rm -rf "$X" "$W" "$W.lock"
    exit $bad
)
fails=$((fails + $?))

if [ "$MODE" = --build-only ]; then
    [ $fails = 0 ] && printf 'PASS  build all programs in tools/\n'
    echo "$fails failure(s)"
    exit "$fails"
fi
# A fresh checkout has no test prefix yet: create it and turn DXMT on, as install-steam.sh does for
# Steam's. An existing one is left alone, so the DXMT check below still means something.
if [ ! -d "$C/windows/system32" ]; then
    "$ROOT/scripts/wine-run.sh" 120 wineboot -i > /dev/null 2>&1
    "$ROOT/scripts/install-dxmt.sh" on "$WINEPREFIX" > /dev/null
fi
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

if [ "$MODE" = --steam ]; then
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
        printf 'PASS  Steam window drawn\n'
    else
        printf 'FAIL  Steam window drawn\n      %s\n' "$line"; fails=$((fails + 1))
    fi
fi

echo "$fails failure(s)"
exit "$fails"
