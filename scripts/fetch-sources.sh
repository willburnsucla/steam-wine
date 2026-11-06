#!/bin/bash
# Download and pin every source this project builds. Safe to re-run; skips what's present.
# The versions, sums and commits are in scripts/versions.sh.
#   downloads/  crossover-sources-<version>.tar.gz (CodeWeavers' LGPL source), nettle, mpg123, SDL2
#   src/        sources/ (extracted CrossOver tarball), dxmt, llvm-project, moltenvk-upstream,
#               dxvk-macos
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/scripts/versions.sh"
mkdir -p "$ROOT/downloads" "$ROOT/src"

fetch() { # url file sha256 [dir]   (dir defaults to downloads/)
    local out="${4:-$ROOT/downloads}/$2"
    mkdir -p "$(dirname "$out")"
    # Download under a temporary name, so an interrupted download is never taken for a finished one.
    if [ ! -f "$out" ]; then
        curl -fL --retry 3 -o "$out.part" "$1"
        mv "$out.part" "$out"
    fi
    if ! echo "$3  $out" | shasum -a 256 -c -; then
        mv "$out" "$out.bad"
        echo "checksum mismatch: moved to $out.bad; run again to download it afresh" >&2
        exit 1
    fi
}

clone() { # url dir ref   (dir relative to src/)
    local dir="$ROOT/src/$2"
    if [ ! -d "$dir/.git" ]; then
        git init -q "$dir"
        git -C "$dir" remote add origin "$1"
    fi
    git -C "$dir" fetch -q --depth 1 origin "$3"
    git -C "$dir" checkout -q FETCH_HEAD
    echo "$2 at $(git -C "$dir" rev-parse --short HEAD)"
}

CX=crossover-sources-$CROSSOVER_VERSION.tar.gz
fetch "https://media.codeweavers.com/pub/crossover/source/$CX" "$CX" "$CROSSOVER_SHA256"
fetch "https://ftp.gnu.org/gnu/nettle/nettle-$NETTLE_VERSION.tar.gz" \
    "nettle-$NETTLE_VERSION.tar.gz" "$NETTLE_SHA256"
fetch "https://www.mpg123.de/download/mpg123-$MPG123_VERSION.tar.bz2" \
    "mpg123-$MPG123_VERSION.tar.bz2" "$MPG123_SHA256"
fetch "https://github.com/libsdl-org/SDL/releases/download/release-$SDL2_VERSION/SDL2-$SDL2_VERSION.tar.gz" \
    "SDL2-$SDL2_VERSION.tar.gz" "$SDL2_SHA256"
[ -d "$ROOT/src/sources/wine" ] || tar -xzf "$ROOT/downloads/$CX" -C "$ROOT/src"

# GLib's subprojects, pinned (its wraps would otherwise download at build time, and libffi's
# points at a moving branch). The tarball ships gvdb as an empty submodule folder; clone fills it.
G=sources/glib/subprojects
clone https://gitlab.freedesktop.org/gstreamer/meson-ports/libffi.git $G/libffi "$LIBFFI_COMMIT"
clone https://github.com/frida/proxy-libintl.git $G/proxy-libintl "$PROXY_LIBINTL_COMMIT"
clone https://gitlab.gnome.org/GNOME/gvdb.git $G/gvdb "$GVDB_COMMIT"
fetch "https://github.com/PhilipHazel/pcre2/releases/download/pcre2-$PCRE2_VERSION/pcre2-$PCRE2_VERSION.tar.bz2" \
    "pcre2-$PCRE2_VERSION.tar.bz2" "$PCRE2_SHA256" "$ROOT/src/$G/packagecache"
fetch "https://wrapdb.mesonbuild.com/v2/pcre2_$PCRE2_WRAP/get_patch" \
    "pcre2_${PCRE2_WRAP}_patch.zip" "$PCRE2_PATCH_SHA256" "$ROOT/src/$G/packagecache"

clone https://github.com/3Shain/dxmt.git dxmt "$DXMT_COMMIT"
git -C "$ROOT/src/dxmt" submodule update -q --init --depth 1
clone https://github.com/llvm/llvm-project.git llvm-project "$LLVM_COMMIT"
clone https://github.com/KhronosGroup/MoltenVK.git moltenvk-upstream "$MOLTENVK_COMMIT"
clone https://github.com/Gcenx/DXVK-macOS.git dxvk-macos "$DXVK_MACOS_COMMIT"
