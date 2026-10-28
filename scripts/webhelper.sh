# shellcheck shell=bash
# Steam's web helper wrapper (tools/webhelper-wrapper.c). Sourced by steam.sh and run-tests.sh;
# needs ROOT set.
WEBHELPER_WRAPPER="${WEBHELPER_WRAPPER:-$ROOT/tools/steamwebhelper-wrapper.exe}"

# Build the wrapper when it's missing or older than its source. Linked without a timestamp, so
# rebuilding the same source gives the same bytes.
build_webhelper_wrapper() {
    [ "$WEBHELPER_WRAPPER" -nt "$ROOT/tools/webhelper-wrapper.c" ] ||
        x86_64-w64-mingw32-gcc -O2 -municode -mwindows -Wl,--no-insert-timestamp \
            -o "$WEBHELPER_WRAPPER" "$ROOT/tools/webhelper-wrapper.c"
}

# Is $1 some build of our wrapper? Every build names steamwebhelper_real.exe in UTF-16, and
# Steam's own helper doesn't. Dropping the NUL bytes turns that text into plain ASCII for grep.
# grep -c reads to the end (grep -q would stop early and, under pipefail, fail the pipe).
is_webhelper_wrapper() {
    local n
    n=$(LC_ALL=C tr -d '\0' < "$1" | LC_ALL=C grep -acF 'steamwebhelper_real.exe')
    [ "${n:-0}" -gt 0 ]
}

# Put the wrapper in place of Steam's helper in cef folder $1. Steam's own helper (first run or
# a Steam update) becomes steamwebhelper_real.exe; an older build of the wrapper is only
# replaced, never moved over the real helper. Copy, then rename: an interrupted copy must not
# leave a half-written helper that the next launch would take for Steam's.
install_webhelper_wrapper() {
    local h="$1/steamwebhelper.exe"
    [ -f "$h" ] || return 0
    cmp -s "$h" "$WEBHELPER_WRAPPER" && return 0
    cp "$WEBHELPER_WRAPPER" "$h.new" || return 1
    is_webhelper_wrapper "$h" || mv "$h" "$1/steamwebhelper_real.exe"
    mv -f "$h.new" "$h"
}
