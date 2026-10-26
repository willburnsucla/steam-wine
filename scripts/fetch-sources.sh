#!/bin/bash
# Download and pin every source this project builds. Safe to re-run; skips what's present.
#   downloads/  crossover-sources-26.3.0.tar.gz (CodeWeavers' LGPL source), nettle-3.10.tar.gz
#   src/        sources/ (extracted CrossOver tarball), dxmt, llvm-project, moltenvk-upstream,
#               dxvk-macos
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/downloads" "$ROOT/src"

fetch() { # url file sha256
    local out="$ROOT/downloads/$2"
    [ -f "$out" ] || curl -fL --retry 3 -o "$out" "$1"
    echo "$3  $out" | shasum -a 256 -c -
}

clone() { # url dir ref
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
[ -d "$ROOT/src/sources/wine" ] || tar -xzf "$ROOT/downloads/crossover-sources-26.3.0.tar.gz" -C "$ROOT/src"

clone https://github.com/3Shain/dxmt.git dxmt 9839e55f98d4aca103957ee4132d6395a325a9ed
git -C "$ROOT/src/dxmt" submodule update -q --init --depth 1
clone https://github.com/llvm/llvm-project.git llvm-project llvmorg-15.0.7
clone https://github.com/KhronosGroup/MoltenVK.git moltenvk-upstream v1.4.2
clone https://github.com/Gcenx/DXVK-macOS.git dxvk-macos 8f1e28deed3ad30802f7e1bdff428ec14e6e7817
