# Shared build environment. Source this from the other scripts.
# Host libraries are x86_64 (Wine's macOS host side runs under Rosetta);
# we cross-compile them from the arm64 side so configure never runs x86_64 code.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/src/sources"
BUILD="$ROOT/build"
DEPS="$ROOT/deps"          # x86_64 host libraries
WINE_PREFIX_DIR="$ROOT/dist" # installed Wine

export MACOSX_DEPLOYMENT_TARGET=13.0
export CC="clang -arch x86_64"
export CXX="clang++ -arch x86_64"
export CFLAGS="-O2 -I$DEPS/include"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-L$DEPS/lib -Wl,-rpath,$DEPS/lib"
# Only see our own x86_64 libs, never /opt/homebrew's arm64 ones.
export PKG_CONFIG_LIBDIR="$DEPS/lib/pkgconfig"
# In cross mode configure otherwise looks for x86_64-apple-darwin-pkg-config and skips libs.
export PKG_CONFIG=/opt/homebrew/bin/pkg-config
export PKG_CONFIG_PATH=""
export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:$PATH"

HOST_TRIPLE=x86_64-apple-darwin
BUILD_TRIPLE=aarch64-apple-darwin
JOBS=$(sysctl -n hw.ncpu)

mkdir -p "$BUILD" "$DEPS"
