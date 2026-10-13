#!/bin/bash
# Build CrossOver's Wine (src/sources/wine) for macOS as an x86_64 program under Rosetta,
# the standard macOS route. Wine builds its own tools in the same tree; PE side via mingw-w64.
# Usage: scripts/build-wine.sh [configure|build|install ...]   (default: all three)
set -euo pipefail
source "$(dirname "$0")/env.sh"

WINE_SRC="$SRC/wine"
# macOS 27's Command Line Tools have no x86_64 xcrun, so the clang/ld shims fail when an
# x86_64 process (e.g. winebuild) spawns them. Use the real arm64-only binaries, which run
# natively from either side, and target x86_64. configure runs its x86_64 test programs
# through Rosetta, so this is a normal (non-cross) build.
TC=/Library/Developer/CommandLineTools/usr/bin
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export CC="$TC/clang -arch x86_64" CXX="$TC/clang++ -arch x86_64"
export AR="$TC/ar" RANLIB="$TC/ranlib" STRIP="$TC/strip" NM="$TC/nm"
X86=""

# Apply our patches (patches/*.patch) to the Wine source once.
apply_patches() {
    for p in "$ROOT"/patches/*.patch; do
        [ -e "$p" ] || continue
        if patch -d "$WINE_SRC" -p1 -R -s -f --dry-run < "$p" >/dev/null 2>&1; then
            echo "already applied: $(basename "$p")"
        else
            patch -d "$WINE_SRC" -p1 -s < "$p" && echo "applied: $(basename "$p")"
        fi
    done
}

configure_wine() {
    apply_patches
    rm -rf "$BUILD/wine" && mkdir -p "$BUILD/wine" && cd "$BUILD/wine"
    $X86 "$WINE_SRC/configure" \
        --build=x86_64-apple-darwin --host=x86_64-apple-darwin \
        --prefix="$WINE_PREFIX_DIR" \
        --enable-archs=i386,x86_64 \
        --with-mingw \
        --with-coreaudio --with-cups --with-vulkan --with-freetype --with-gnutls --with-opencl \
        --without-alsa --without-capi --without-dbus --without-ffmpeg --without-fontconfig \
        --without-gettext --without-gettextpo --without-gphoto --without-gssapi \
        --without-gstreamer --without-inotify --without-krb5 --without-netapi --without-oss \
        --without-pcap --without-pcsclite --without-pulse --without-sane --without-sdl \
        --without-udev --without-usb --without-v4l2 --without-wayland --without-x \
        --disable-tests
}

build_wine() {
    apply_patches
    cd "$BUILD/wine" && $X86 make -j$JOBS
}

install_wine() {
    cd "$BUILD/wine" && $X86 make install
}

targets=("$@")
[ ${#targets[@]} -eq 0 ] && targets=(configure build install)
for t in "${targets[@]}"; do
    echo "=== $t"
    case $t in
        configure) configure_wine ;;
        build) build_wine ;;
        install) install_wine ;;
        *) echo "unknown step $t"; exit 1 ;;
    esac
done
echo "=== done: ${targets[*]}"
