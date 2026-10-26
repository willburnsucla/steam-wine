#!/bin/bash
# Build DXMT (D3D11/D3D10 -> Metal) against our Wine build. Mirrors DXMT's CI
# (.github/workflows/ci.yml): x86_64 LLVM 15.0.7 for the shader converter, then meson.
# Needs full Xcode (Metal toolchain) for the DXMT step.
# Usage: scripts/build-dxmt.sh [llvm|dxmt64|dxmt32 ...]   (default: all)
set -euo pipefail
source "$(dirname "$0")/env.sh"

LLVM_SRC="$ROOT/src/llvm-project"
LLVM_OUT="$ROOT/toolchains/llvm-darwin"   # x86_64 LLVM 15 install
DXMT_SRC="$ROOT/src/dxmt"
DXMT_OUT="$ROOT/dist/dxmt"
# Undo env.sh's x86_64 C flags; cmake/meson pick architectures themselves here.
unset CC CXX CFLAGS CXXFLAGS LDFLAGS
# DXMT targets macOS Sonoma+ and uses libc++ APIs (std::to_chars) from macOS 13.3+.
export MACOSX_DEPLOYMENT_TARGET=14.0

build_llvm() {
    cmake -B "$BUILD/llvm" -S "$LLVM_SRC/llvm" -G Ninja \
        -DCMAKE_INSTALL_PREFIX="$LLVM_OUT" \
        -DCMAKE_OSX_ARCHITECTURES=x86_64 \
        -DLLVM_HOST_TRIPLE=x86_64-apple-darwin \
        -DLLVM_ENABLE_ASSERTIONS=On \
        -DLLVM_ENABLE_ZSTD=Off \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLVM_TARGETS_TO_BUILD="" \
        -DLLVM_BUILD_TOOLS=Off \
        -DLLVM_VERSION_PRINTER_SHOW_HOST_TARGET_INFO=Off
    cmake --build "$BUILD/llvm" && cmake --install "$BUILD/llvm"
}

build_dxmt64() {
    cd "$DXMT_SRC"
    rm -rf "$BUILD/dxmt64"
    # enable_d3d12: DXMT's Direct3D 12 implementation (experimental upstream, off by default).
    meson setup --cross-file build-win64.txt \
        -Dnative_llvm_path="$LLVM_OUT" -Dwine_build_path="$BUILD/wine" -Denable_d3d12=true \
        "$BUILD/dxmt64" --buildtype release --prefix "$DXMT_OUT" --strip
    meson compile -C "$BUILD/dxmt64" && meson install -C "$BUILD/dxmt64"
}

build_dxmt32() {
    cd "$DXMT_SRC"
    rm -rf "$BUILD/dxmt32"
    meson setup --cross-file build-win32.txt -Dwine_build_path="$BUILD/wine" \
        "$BUILD/dxmt32" --buildtype release --prefix "$DXMT_OUT/i386" --strip
    meson compile -C "$BUILD/dxmt32" && meson install -C "$BUILD/dxmt32"
}

targets=("$@")
[ ${#targets[@]} -eq 0 ] && targets=(llvm dxmt64 dxmt32)
for t in "${targets[@]}"; do
    echo "=== $t"
    "build_$t"
done
echo "=== done: ${targets[*]}"
