#!/bin/bash
# Build SDL2 (game controllers for Wine's winebus) as an x86_64 library in deps/.
# Wine loads it by name (libSDL2-2.0.0.dylib), found through the deps/lib rpath.
set -euo pipefail
source "$(dirname "$0")/env.sh"
unset CC CXX CFLAGS CXXFLAGS LDFLAGS   # CMake picks the architecture itself

SDL_VERSION=2.32.10
s="$ROOT/src/SDL2-$SDL_VERSION"
[ -d "$s" ] || tar -xzf "$ROOT/downloads/SDL2-$SDL_VERSION.tar.gz" -C "$ROOT/src"
rm -rf "$BUILD/sdl2"
cmake -S "$s" -B "$BUILD/sdl2" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=x86_64 \
    -DCMAKE_INSTALL_PREFIX="$DEPS" -DCMAKE_INSTALL_NAME_DIR="$DEPS/lib" \
    -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST=OFF \
    -DSDL_JOYSTICK=ON -DSDL_HAPTIC=ON -DSDL_HIDAPI=ON -DSDL_HIDAPI_JOYSTICK=ON \
    -DCMAKE_IGNORE_PREFIX_PATH="/opt/homebrew;/usr/local"   # never pick up arm64/foreign libraries
cmake --build "$BUILD/sdl2" && cmake --install "$BUILD/sdl2"
