#!/bin/bash
# Download and pin every source this project builds. Safe to re-run; skips what's present.
#   downloads/  crossover-sources-26.3.0.tar.gz (CodeWeavers' LGPL source), nettle-3.10.tar.gz,
#               mpg123-1.33.7.tar.bz2, SDL2-2.32.10.tar.gz
#   src/        sources/ (extracted CrossOver tarball), dxmt, llvm-project, moltenvk-upstream,
#               dxvk-macos
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/downloads" "$ROOT/src"

fetch() { # url file sha256 [dir]   (dir defaults to downloads/)
    local out="${4:-$ROOT/downloads}/$2"
    mkdir -p "$(dirname "$out")"
    [ -f "$out" ] || curl -fL --retry 3 -o "$out" "$1"
    echo "$3  $out" | shasum -a 256 -c -
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

fetch https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz \
    crossover-sources-26.3.0.tar.gz ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872
fetch https://ftp.gnu.org/gnu/nettle/nettle-3.10.tar.gz \
    nettle-3.10.tar.gz b4c518adb174e484cb4acea54118f02380c7133771e7e9beb98a0787194ee47c
fetch https://www.mpg123.de/download/mpg123-1.33.7.tar.bz2 \
    mpg123-1.33.7.tar.bz2 31d0e35a4ca567ec9b5ebda6c3062bb4435d6d3eacd6ef0d95cadd7854dc03ee
fetch https://github.com/libsdl-org/SDL/releases/download/release-2.32.10/SDL2-2.32.10.tar.gz \
    SDL2-2.32.10.tar.gz 5f5993c530f084535c65a6879e9b26ad441169b3e25d789d83287040a9ca5165
[ -d "$ROOT/src/sources/wine" ] || tar -xzf "$ROOT/downloads/crossover-sources-26.3.0.tar.gz" -C "$ROOT/src"

# GLib's subprojects, pinned (its wraps would otherwise download at build time, and libffi's
# points at a moving branch). The tarball ships gvdb as an empty submodule folder; clone fills it.
G=sources/glib/subprojects
clone https://gitlab.freedesktop.org/gstreamer/meson-ports/libffi.git $G/libffi 83d0cfd00d7d37af4b4349511d29f1f0512621b3
clone https://github.com/frida/proxy-libintl.git $G/proxy-libintl c03e1a74b17fa7ec467e110130775409e4828a4c
clone https://gitlab.gnome.org/GNOME/gvdb.git $G/gvdb 0854af0fdb6d527a8d1999835ac2c5059976c210
fetch https://github.com/PhilipHazel/pcre2/releases/download/pcre2-10.42/pcre2-10.42.tar.bz2 \
    pcre2-10.42.tar.bz2 8d36cd8cb6ea2a4c2bb358ff6411b0c788633a2a45dabbf1aeb4b701d1b5e840 "$ROOT/src/$G/packagecache"
fetch https://wrapdb.mesonbuild.com/v2/pcre2_10.42-2/get_patch \
    pcre2_10.42-2_patch.zip 350dc342b81a1611af43e5cc23f1b10453c7df51d5bb60ab9ee247daf03802bc "$ROOT/src/$G/packagecache"

clone https://github.com/3Shain/dxmt.git dxmt 9839e55f98d4aca103957ee4132d6395a325a9ed
git -C "$ROOT/src/dxmt" submodule update -q --init --depth 1
clone https://github.com/llvm/llvm-project.git llvm-project llvmorg-15.0.7
clone https://github.com/KhronosGroup/MoltenVK.git moltenvk-upstream v1.4.2
clone https://github.com/Gcenx/DXVK-macOS.git dxvk-macos 8f1e28deed3ad30802f7e1bdff428ec14e6e7817
