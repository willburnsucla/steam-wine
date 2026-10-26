#!/bin/bash
# Build GStreamer for Wine's winegstreamer (DirectShow / Media Foundation playback) as x86_64
# libraries in deps/: libmpg123 (upstream), GLib and GStreamer (from CrossOver's tarball).
# Only the pieces Wine and MP3/WAV playback need are enabled.
# Usage: scripts/build-gstreamer.sh [mpg123|glib|gstreamer ...]   (default: all, in order)
set -euo pipefail
source "$(dirname "$0")/env.sh"

MPG123_VERSION=1.33.7
CROSS="$BUILD/x86_64-darwin.ini"

# Meson cross file: x86_64 code from the arm64 side. Rosetta runs the x86_64 test programs, so
# no exe wrapper is needed.
write_cross_file() {
    cat > "$CROSS" <<EOF
[binaries]
c = ['clang', '-arch', 'x86_64']
cpp = ['clang++', '-arch', 'x86_64']
objc = ['clang', '-arch', 'x86_64']
objcpp = ['clang++', '-arch', 'x86_64']
ar = 'ar'
strip = 'strip'
pkg-config = '$PKG_CONFIG'

[properties]
needs_exe_wrapper = false
pkg_config_libdir = '$DEPS/lib/pkgconfig'

[built-in options]
c_link_args = ['-Wl,-rpath,$DEPS/lib']
cpp_link_args = ['-Wl,-rpath,$DEPS/lib']
objc_link_args = ['-Wl,-rpath,$DEPS/lib']

[host_machine]
system = 'darwin'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF
}

meson_x86() { # source-dir build-dir [meson options...]
    local src=$1 dir=$2; shift 2
    rm -rf "$dir"
    # The cross file supplies compilers and flags; env.sh's x86_64 CC/CFLAGS would confuse
    # meson's native (build-machine) compiler detection.
    env -u CC -u CXX -u CFLAGS -u CXXFLAGS -u LDFLAGS \
        meson setup "$dir" "$src" --cross-file "$CROSS" --prefix "$DEPS" --libdir lib \
        --buildtype release --wrap-mode nodownload -Ddefault_library=shared "$@"
    meson compile -C "$dir" && meson install -C "$dir"
}

apply_patches() { # source-dir patch-dir: apply each patch once (skip if already applied)
    local p
    for p in "$2"/*.patch; do
        [ -e "$p" ] || continue
        patch -d "$1" -p1 -R -s -f --dry-run < "$p" >/dev/null 2>&1 && continue
        patch -d "$1" -p1 -s < "$p" || { echo "patch failed: $p" >&2; return 1; }
        echo "applied $(basename "$p")"
    done
}

build_mpg123() {
    local s="$ROOT/src/mpg123-$MPG123_VERSION"
    [ -d "$s" ] || tar -xjf "$ROOT/downloads/mpg123-$MPG123_VERSION.tar.bz2" -C "$ROOT/src"
    rm -rf "$BUILD/mpg123" && mkdir -p "$BUILD/mpg123" && cd "$BUILD/mpg123"
    "$s/configure" --host=$HOST_TRIPLE --build=$BUILD_TRIPLE --prefix="$DEPS" \
        --disable-components --enable-libmpg123 --disable-static --with-cpu=x86-64
    make -j$JOBS && make install
}

build_glib() {
    write_cross_file
    # libffi, pcre2, proxy-libintl and gvdb are GLib subprojects that fetch-sources.sh puts in
    # place at pinned commits/hashes; nothing is downloaded here. intl always comes from
    # proxy-libintl so an x86_64 gettext in /usr/local can't leak in.
    apply_patches "$SRC/glib" "$ROOT/patches/glib"
    rm -rf "$BUILD/glib"
    env -u CC -u CXX -u CFLAGS -u CXXFLAGS -u LDFLAGS \
        meson setup "$BUILD/glib" "$SRC/glib" --cross-file "$CROSS" --prefix "$DEPS" --libdir lib \
        --buildtype release -Ddefault_library=shared --wrap-mode nodownload --force-fallback-for=intl \
        -Dtests=false -Dnls=disabled -Dman=false -Dgtk_doc=false -Dlibmount=disabled \
        -Dselinux=disabled -Dxattr=false -Dsysprof=disabled -Ddtrace=false -Dsystemtap=false \
        -Dlibelf=disabled  # GLib 2.78's option names
    meson compile -C "$BUILD/glib" && meson install -C "$BUILD/glib"
}

build_gstreamer() {
    write_cross_file
    meson_x86 "$SRC/gstreamer" "$BUILD/gstreamer" \
        -Dauto_features=disabled -Dbuild-tools-source=system \
        -Dbase=enabled -Dgood=enabled -Dugly=disabled -Dbad=disabled -Dlibav=disabled \
        -Ddevtools=disabled -Dges=disabled -Drtsp_server=disabled -Dpython=disabled \
        -Dintrospection=disabled -Dtests=disabled -Dexamples=disabled -Ddoc=disabled \
        -Dnls=disabled -Dorc=disabled -Dtls=disabled -Dlibnice=disabled -Dtools=enabled \
        -Dgstreamer:tools=enabled -Dgstreamer:check=enabled \
        -Dgst-plugins-base:app=enabled -Dgst-plugins-base:audioconvert=enabled \
        -Dgst-plugins-base:audioresample=enabled -Dgst-plugins-base:playback=enabled \
        -Dgst-plugins-base:typefind=enabled -Dgst-plugins-base:volume=enabled \
        -Dgst-plugins-base:videoconvertscale=enabled \
        -Dgst-plugins-good:audioparsers=enabled -Dgst-plugins-good:id3demux=enabled \
        -Dgst-plugins-good:mpg123=enabled -Dgst-plugins-good:wavparse=enabled
}

targets=("$@")
[ ${#targets[@]} -eq 0 ] && targets=(mpg123 glib gstreamer)
for t in "${targets[@]}"; do
    echo "=== building $t"
    "build_$t"
done
echo "=== done: ${targets[*]}"
