# shellcheck shell=bash
# Steam's web helper wrapper (tools/webhelper-wrapper.c). Sourced by steam.sh and run-tests.sh;
# needs ROOT set.
WEBHELPER_WRAPPER="${WEBHELPER_WRAPPER:-$ROOT/tools/steamwebhelper-wrapper.exe}"

# Build the wrapper when it's missing or older than its source. Linked to a temporary file and
# renamed, so nobody copies a half-written wrapper; no link timestamp, so rebuilding the same
# source gives the same bytes.
build_webhelper_wrapper() {
    [ "$WEBHELPER_WRAPPER" -nt "$ROOT/tools/webhelper-wrapper.c" ] && return 0
    local tmp
    tmp=$(mktemp "$WEBHELPER_WRAPPER.XXXXXX") || return 1
    if x86_64-w64-mingw32-gcc -O2 -municode -mwindows -Wl,--no-insert-timestamp \
        -o "$tmp" "$ROOT/tools/webhelper-wrapper.c"; then
        mv -f "$tmp" "$WEBHELPER_WRAPPER"
    else
        rm -f "$tmp"
        return 1
    fi
}

# Is $1 some build of our wrapper? Every build names steamwebhelper_real.exe in UTF-16, and
# Steam's own helper doesn't. Dropping the NUL bytes turns that text into plain ASCII for grep.
# grep -c reads to the end (grep -q would stop early and, under pipefail, fail the pipe).
is_webhelper_wrapper() {
    local n
    n=$(LC_ALL=C tr -d '\0' < "$1" | LC_ALL=C grep -acF 'steamwebhelper_real.exe')
    [ "${n:-0}" -gt 0 ]
}

# Does cef folder $1 need the wrapper put in place? Yes when steamwebhelper.exe isn't the
# current wrapper, or when it's missing next to a real helper (an install that was cut off
# between its two renames).
webhelper_needs_install() {
    local h="$1/steamwebhelper.exe"
    if [ -f "$h" ]; then
        ! cmp -s "$h" "$WEBHELPER_WRAPPER"
    else
        [ -f "$1/steamwebhelper_real.exe" ]
    fi
}

# Put the wrapper in place of Steam's helper in cef folder $1. Steam's own helper (first run or
# a Steam update) becomes steamwebhelper_real.exe; an older build of the wrapper is only
# replaced, never moved over the real helper.
# Two steam.sh instances can both be watching, so installs take a lock (a folder; a lock older
# than a minute was left by a killed steam.sh) and look again once they hold it. When the lock
# is busy this returns and the watcher tries again 2 s later. The wrapper goes in under a
# temporary name first, so a cut-off copy never looks like Steam's helper.
install_webhelper_wrapper() {
    local h="$1/steamwebhelper.exe" lock="$WEBHELPER_WRAPPER.lock" tmp st=0
    webhelper_needs_install "$1" || return 0
    if ! mkdir "$lock" 2>/dev/null; then
        [ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ] || return 0
        rmdir "$lock" 2>/dev/null
        mkdir "$lock" 2>/dev/null || return 0
    fi
    if webhelper_needs_install "$1"; then
        if tmp=$(mktemp "$1/steamwebhelper.XXXXXX"); then
            if cp "$WEBHELPER_WRAPPER" "$tmp" && chmod 644 "$tmp" &&
               { [ ! -f "$h" ] || is_webhelper_wrapper "$h" || mv "$h" "$1/steamwebhelper_real.exe"; }; then
                mv -f "$tmp" "$h" || st=1
            else
                rm -f "$tmp"
                st=1
            fi
        else
            st=1
        fi
    fi
    rmdir "$lock"
    return $st
}
