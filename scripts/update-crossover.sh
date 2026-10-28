#!/bin/bash
# Check whether a CrossOver source release can replace the pinned one (scripts/versions.sh).
# Downloads crossover-sources-<version>.tar.gz, unpacks its wine and glib into
# build/crossover-check/<version>/, and applies this project's patches to them in order, as the
# build does: patches/*.patch on wine, patches/glib/*.patch on glib. It also checks that GLib's
# pcre2 wrap still matches the PCRE2_ pins. DXVK patches aren't checked; DXVK-macOS is pinned on
# its own.
# Usage: scripts/update-crossover.sh <version> [--apply]
#   --apply  when everything applies: pin <version> in versions.sh, move the current src/sources
#            aside to src/sources-<old version>, and run fetch-sources.sh to unpack the new one.
#            Then rebuild with scripts/build-all.sh.
# PATCH_DIR=dir checks the patches in dir (and dir/glib) instead of patches/.
# A new version's checksum is taken from the download itself (CodeWeavers publishes none).
# Exits 0 when everything applies, 1 naming each patch that doesn't, 2 on a usage or download error.
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

TAR="$ROOT/downloads/crossover-sources-$V.tar.gz"
if [ ! -f "$TAR" ]; then
    mkdir -p "$ROOT/downloads"
    if ! curl -fL --retry 3 -o "$TAR.part" \
        "https://media.codeweavers.com/pub/crossover/source/crossover-sources-$V.tar.gz"; then
        rm -f "$TAR.part"
        echo "download failed: CrossOver $V sources" >&2
        exit 2
    fi
    mv "$TAR.part" "$TAR"
fi
SUM=$(shasum -a 256 "$TAR" | cut -d' ' -f1)
if [ "$V" = "$CROSSOVER_VERSION" ] && [ "$SUM" != "$CROSSOVER_SHA256" ]; then
    echo "checksum mismatch for the pinned $V: got $SUM" >&2
    exit 2
fi

CHECK="$ROOT/build/crossover-check/$V"
rm -rf "$CHECK"
mkdir -p "$CHECK"
if ! tar -xzf "$TAR" -C "$CHECK" sources/wine sources/glib; then
    echo "$TAR has no sources/wine or sources/glib" >&2
    exit 2
fi
echo "CrossOver $V: $(cat "$CHECK/sources/wine/VERSION"), sha256 $SUM"

fails=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }

check_patches() { # source-dir patch-dir label
    local p out
    for p in "$2"/*.patch; do
        [ -e "$p" ] || continue
        if out=$(patch -d "$1" -p1 -s -f < "$p" 2>&1); then
            pass "$3 $(basename "$p")"
        else
            fail "$3 $(basename "$p")"
            printf '%s\n' "$out" | sed 's/^/      /'
        fi
    done
}
check_patches "$CHECK/sources/wine" "$PATCH_DIR" wine
check_patches "$CHECK/sources/glib" "$PATCH_DIR/glib" glib

W="$CHECK/sources/glib/subprojects/pcre2.wrap"
if grep -qxF "source_hash = $PCRE2_SHA256" "$W" 2>/dev/null &&
   grep -qxF "patch_hash = $PCRE2_PATCH_SHA256" "$W"; then
    pass "glib pcre2.wrap matches the PCRE2_ pins"
else
    fail "glib pcre2.wrap no longer matches the PCRE2_ pins in versions.sh"
fi

if [ $fails -gt 0 ]; then
    echo "$fails check(s) failed; $V's sources are left in ${CHECK#"$ROOT"/} for rebasing the patches"
    exit 1
fi
rm -rf "$CHECK"
if [ $APPLY = 0 ]; then
    echo "everything applies to $V"
    [ "$V" = "$CROSSOVER_VERSION" ] || echo "to switch: $0 $V --apply"
    exit 0
fi
if [ "$V" = "$CROSSOVER_VERSION" ]; then
    echo "already pinned to $V"
    exit 0
fi

OLD="$ROOT/src/sources-$CROSSOVER_VERSION"
[ ! -e "$OLD" ] || { echo "${OLD#"$ROOT"/} already exists; move it out of the way first" >&2; exit 2; }
sed -i '' -e "s/^CROSSOVER_VERSION=.*/CROSSOVER_VERSION=$V/" \
    -e "s/^CROSSOVER_SHA256=.*/CROSSOVER_SHA256=$SUM/" "$ROOT/scripts/versions.sh"
[ ! -d "$ROOT/src/sources" ] || mv "$ROOT/src/sources" "$OLD"
"$ROOT/scripts/fetch-sources.sh"
echo "pinned CrossOver $V (previous sources kept in ${OLD#"$ROOT"/}); now run scripts/build-all.sh"
