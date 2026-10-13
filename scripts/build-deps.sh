#!/bin/bash
# Build Wine's x86_64 host dependencies from the CrossOver source tarball into deps/.
# Usage: scripts/build-deps.sh [gmp|nettle|gnutls|freetype ...]   (default: all, in order)
set -euo pipefail
source "$(dirname "$0")/env.sh"

cross=(--host=$HOST_TRIPLE --build=$BUILD_TRIPLE --prefix="$DEPS")

build_gmp() {
    rm -rf "$BUILD/gmp" && mkdir -p "$BUILD/gmp" && cd "$BUILD/gmp"
    "$SRC/gnutls/gmp/configure" "${cross[@]}" --enable-shared --disable-static
    make -j$JOBS && make install
}

build_nettle() {
    # CrossOver's tarball ships nettle without its top-level Makefile.in, so use the
    # official GNU release (downloads/nettle-3.10.tar.gz, signature verified).
    local n="$ROOT/src/nettle-3.10"
    [ -d "$n" ] || tar -xzf "$ROOT/downloads/nettle-3.10.tar.gz" -C "$ROOT/src"
    rm -rf "$BUILD/nettle" && mkdir -p "$BUILD/nettle" && cd "$BUILD/nettle"
    "$n/configure" "${cross[@]}" --enable-shared --disable-static \
        --disable-openssl --disable-documentation
    make -j$JOBS && make install
}

build_gnutls() {
    rm -rf "$BUILD/gnutls" && mkdir -p "$BUILD/gnutls" && cd "$BUILD/gnutls"
    # This configure leaves NETTLE_LIBS empty, which disables nettle linking. Set them, and keep
    # each value a single word: m4/hooks.m4 tests them unquoted (test x$NETTLE_LIBS != x).
    # -L comes from LDFLAGS.
    NETTLE_LIBS="-lnettle" HOGWEED_LIBS="-lhogweed" \
    "$SRC/gnutls/gnutls/configure" "${cross[@]}" --enable-shared --disable-static \
        --with-included-libtasn1 --with-included-unistring \
        --without-p11-kit --without-idn --without-brotli --without-zstd \
        --without-tpm --without-tpm2 --without-zlib \
        --disable-doc --disable-tests --disable-tools --disable-cxx \
        --disable-nls --disable-guile \
        --disable-gost  # gnutls 3.8.3's bundled streebog clashes with nettle 3.10's
    make -j$JOBS && make install
}

build_freetype() {
    # freetype2.pc requires zlib; macOS's system zlib has no .pc file, so provide one.
    mkdir -p "$DEPS/lib/pkgconfig"
    printf 'Name: zlib\nDescription: macOS system zlib\nVersion: 1.2.12\nLibs: -lz\nCflags:\n' \
        > "$DEPS/lib/pkgconfig/zlib.pc"
    # CMake, not configure: the autotools path wants the dlg git submodule, which the
    # tarball lacks; CMake only needs it for FT_ENABLE_DEBUG_LOGGING.
    rm -rf "$BUILD/freetype"
    cmake -S "$SRC/freetype" -B "$BUILD/freetype" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=x86_64 \
        -DCMAKE_INSTALL_PREFIX="$DEPS" -DCMAKE_INSTALL_NAME_DIR="$DEPS/lib" -DBUILD_SHARED_LIBS=ON \
        -DFT_DISABLE_PNG=ON -DFT_DISABLE_BZIP2=ON -DFT_DISABLE_BROTLI=ON -DFT_DISABLE_HARFBUZZ=ON \
        -DFT_REQUIRE_ZLIB=ON
    cmake --build "$BUILD/freetype" && cmake --install "$BUILD/freetype"
}

targets=("$@")
[ ${#targets[@]} -eq 0 ] && targets=(gmp nettle gnutls freetype)
for t in "${targets[@]}"; do
    echo "=== building $t"
    "build_$t"
done
echo "=== done: ${targets[*]}"
