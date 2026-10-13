#!/bin/bash
# Build DXVK (D3D10/11 -> Vulkan) for MoltenVK with mingw-w64. Output: dist/dxvk/x64, x32.
# Source: Gcenx/DXVK-macOS (1.10.x branch, maintained). CodeWeavers' tarball copy requires
# geometryShader, which upstream MoltenVK lacks (their MoltenVK fork isn't buildable); the
# macOS fork makes it optional.
set -euo pipefail
source "$(dirname "$0")/env.sh"
unset CC CXX CFLAGS CXXFLAGS LDFLAGS
# DXVK 1.10.3 predates GCC 15's stricter headers (uint32_t/int32_t without <cstdint>).
# Wrap the mingw C++ compilers to force-include <cstdint> instead of patching the source.
WRAP="$BUILD/dxvk-wrappers"
mkdir -p "$WRAP"
for t in x86_64-w64-mingw32-g++ i686-w64-mingw32-g++; do
    printf '#!/bin/sh\nexec %s -include cstdint "$@"\n' "$(command -v $t)" > "$WRAP/$t"
    chmod +x "$WRAP/$t"
done
export PATH="$WRAP:$PATH"
cd "$ROOT/src/dxvk-macos"
for p in "$ROOT"/patches/dxvk/*.patch; do
    [ -e "$p" ] || continue
    # Apply only where still needed (already applied, or fixed upstream, is fine).
    patch -p1 -R -s -f --dry-run < "$p" >/dev/null 2>&1 && continue
    patch -p1 -s -f --dry-run < "$p" >/dev/null 2>&1 && patch -p1 -s < "$p" && echo "applied $(basename "$p")"
done
rm -rf "$BUILD/dxvk" && mkdir -p "$BUILD/dxvk"  # package-release.sh needs it to exist
./package-release.sh cx "$BUILD/dxvk" --no-package
rm -rf "$ROOT/dist/dxvk" && mkdir -p "$ROOT/dist/dxvk"
cp -R "$BUILD"/dxvk/dxvk-*/x64 "$BUILD"/dxvk/dxvk-*/x32 "$ROOT/dist/dxvk/"
ls "$ROOT/dist/dxvk/x64"
