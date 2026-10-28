#!/bin/bash
# Check whether a CrossOver source release can replace the pinned one (scripts/versions.sh).
# Downloads crossover-sources-<version>.tar.gz, unpacks its wine and glib into
# build/crossover-check.noindex/<version>/ (.noindex keeps Spotlight from indexing tens of
# thousands of source files each run), and applies this project's patches to them in order, as
# the build does: patches/*.patch on wine, patches/glib/*.patch on glib. A patch that only
# applies with fuzz gets a warning. It also checks that GLib's subproject wraps still ask for what
# versions.sh pins. DXVK patches aren't checked; DXVK-macOS is pinned on its own.
# Usage: scripts/update-crossover.sh <version> [--apply]
#   --apply  when everything applies: move the current src/sources aside to
#            src/sources-<old version>, unpack the new one, pin <version> in versions.sh, and run
#            fetch-sources.sh for GLib's subprojects. Then rebuild with scripts/build-all.sh.
# PATCH_DIR=dir checks the patches in dir (and dir/glib) instead of patches/.
# A new version's checksum is taken from the download itself (CodeWeavers publishes none).
# Exits 0 when everything applies, 1 naming each check that fails, 2 on any other error.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/scripts/versions.sh"
PATCH_DIR="${PATCH_DIR:-$ROOT/patches}"

usage() { echo "usage: $0 <version> [--apply]" >&2; exit 2; }
[ $# = 1 ] || [ $# = 2 ] || usage
V=$1
APPLY=0
if [ $# = 2 ]; then [ "$2" = --apply ] || usage; APPLY=1; fi
[[ $V =~ ^[0-9]+(\.[0-9]+)+$ ]] || { echo "not a version: $V" >&2; exit 2; }
n=0
for p in "$PATCH_DIR"/*.patch; do [ -e "$p" ] && n=$((n + 1)); done
[ $n -gt 0 ] || { echo "no patches in $PATCH_DIR" >&2; exit 2; }

TAR="$ROOT/downloads/crossover-sources-$V.tar.gz"
if [ ! -f "$TAR" ]; then
    mkdir -p "$ROOT/downloads"
    if ! curl -fL --retry 3 -o "$TAR.part" \
        "https://media.codeweavers.com/pub/crossover/source/crossover-sources-$V.tar.gz"; then
        rm -f "$TAR.part"
        echo "download failed: CrossOver $V sources" >&2
        exit 2
    fi
    # Keep it only if it really is the source tarball (not an error page or a cut-off file).
    if ! tar -tzf "$TAR.part" sources/wine/VERSION >/dev/null 2>&1; then
        rm -f "$TAR.part"
        echo "the download for CrossOver $V isn't a CrossOver source tarball" >&2
        exit 2
    fi
    mv "$TAR.part" "$TAR"
fi
SUM=$(shasum -a 256 "$TAR" | cut -d' ' -f1)
if [ "$V" = "$CROSSOVER_VERSION" ] && [ "$SUM" != "$CROSSOVER_SHA256" ]; then
    echo "checksum mismatch for the pinned $V: got $SUM" >&2
    exit 2
fi

CHECK="$ROOT/build/crossover-check.noindex/$V"
rm -rf "$CHECK"
mkdir -p "$CHECK"
if ! tar -xzf "$TAR" -C "$CHECK" sources/wine sources/glib; then
    echo "$TAR has no sources/wine or sources/glib" >&2
    exit 2
fi
echo "CrossOver $V: $(cat "$CHECK/sources/wine/VERSION"), sha256 $SUM"

fails=0
pass() { printf 'PASS  %s\n' "$1"; }
warn() { printf 'WARN  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }

check_patches() { # source-dir patch-dir label
    local p out
    for p in "$2"/*.patch; do
        [ -e "$p" ] || continue
        if patch -d "$1" -p1 -s -f -F0 --dry-run < "$p" >/dev/null 2>&1; then
            patch -d "$1" -p1 -s -f -F0 < "$p" >/dev/null 2>&1
            pass "$3 $(basename "$p")"
        elif out=$(patch -d "$1" -p1 -s -f < "$p" 2>&1); then
            warn "$3 $(basename "$p") applies only with fuzz; worth refreshing"
        else
            fail "$3 $(basename "$p")"
            printf '%s\n' "$out" | sed 's/^/      /'
        fi
    done
}
check_patches "$CHECK/sources/wine" "$PATCH_DIR" wine
if [ -d "$PATCH_DIR/glib" ]; then
    check_patches "$CHECK/sources/glib" "$PATCH_DIR/glib" glib
else
    warn "no glib patches checked ($PATCH_DIR/glib doesn't exist)"
fi

check_wrap() { # wrap-file key pinned-value pin-names
    local v
    v=$(sed -nE "s/^$2 *= *//p" "$CHECK/sources/glib/subprojects/$1" 2>/dev/null | head -1)
    if [ "$v" = "$3" ]; then
        pass "glib $1 $2 matches versions.sh"
    else
        fail "glib $1 $2 is now '${v:-missing}', pinned '$3'; update $4 in versions.sh"
    fi
}
check_wrap pcre2.wrap source_hash "$PCRE2_SHA256" "PCRE2_VERSION and PCRE2_SHA256"
check_wrap pcre2.wrap patch_hash "$PCRE2_PATCH_SHA256" "PCRE2_WRAP and PCRE2_PATCH_SHA256"
check_wrap gvdb.wrap revision "$GVDB_COMMIT" GVDB_COMMIT
check_wrap libffi.wrap revision "$LIBFFI_WRAP_REVISION" "LIBFFI_WRAP_REVISION and LIBFFI_COMMIT"
check_wrap proxy-libintl.wrap revision "$PROXY_LIBINTL_WRAP_REVISION" \
    "PROXY_LIBINTL_WRAP_REVISION and PROXY_LIBINTL_COMMIT"

if [ $fails -gt 0 ]; then
    echo "$fails check(s) failed; $V's sources are in ${CHECK#"$ROOT"/} to look at the rejects" \
        "(replaced on the next run)"
    exit 1
fi
rm -rf "$CHECK"
if [ $APPLY = 0 ]; then
    echo "everything applies to $V"
    [ "$V" = "$CROSSOVER_VERSION" ] || echo "to switch: $0 $V --apply"
    exit 0
fi
finish() { echo "pinned CrossOver $V, but fetch-sources.sh failed; run it again to finish" >&2; exit 2; }
if [ "$V" = "$CROSSOVER_VERSION" ]; then
    # Already pinned. An earlier --apply may have stopped before fetching GLib's subprojects.
    [ -d "$ROOT/src/sources/wine" ] || "$ROOT/scripts/fetch-sources.sh" || finish
    echo "already pinned to $V"
    exit 0
fi

# Unpack first (no network needed), then pin, then fetch what the tarball doesn't carry.
OLD="$ROOT/src/sources-$CROSSOVER_VERSION"
[ ! -e "$OLD" ] || { echo "${OLD#"$ROOT"/} already exists; move it out of the way first" >&2; exit 2; }
if [ -d "$ROOT/src/sources" ]; then
    mv "$ROOT/src/sources" "$OLD"
    kept="previous sources kept in ${OLD#"$ROOT"/}"
else
    kept="there were no previous sources to keep"
fi
mkdir -p "$ROOT/src"
tar -xzf "$TAR" -C "$ROOT/src" || { echo "couldn't unpack $TAR into src/" >&2; exit 2; }
tmp=$(mktemp "$ROOT/scripts/versions.sh.XXXXXX")
sed -e "s/^CROSSOVER_VERSION=.*/CROSSOVER_VERSION=$V/" \
    -e "s/^CROSSOVER_SHA256=.*/CROSSOVER_SHA256=$SUM/" "$ROOT/scripts/versions.sh" > "$tmp"
chmod 644 "$tmp"
mv "$tmp" "$ROOT/scripts/versions.sh"
( . "$ROOT/scripts/versions.sh"; [ "$CROSSOVER_VERSION" = "$V" ] && [ "$CROSSOVER_SHA256" = "$SUM" ] ) ||
    { echo "couldn't pin $V in scripts/versions.sh" >&2; exit 2; }
"$ROOT/scripts/fetch-sources.sh" || finish
echo "pinned CrossOver $V ($kept); now run scripts/build-all.sh"
