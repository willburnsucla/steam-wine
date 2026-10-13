#!/bin/bash
# Build upstream MoltenVK (Vulkan on Metal, KhronosGroup v1.4.2) and copy the dylib into
# deps/lib so Wine's configure can find it (--with-vulkan).
# CodeWeavers' copy in the tarball can't be built: its fetchDependencies pins a SPIRV-Cross
# commit that exists only in their unpublished fork.
# fetchDependencies clones the pinned revisions in ExternalRevisions/ from GitHub.
set -euo pipefail
source "$(dirname "$0")/env.sh"
unset CC CXX CFLAGS CXXFLAGS LDFLAGS
MVK="$ROOT/src/moltenvk-upstream"
cd "$MVK"
[ -d External/build ] || ./fetchDependencies --macos
make macos
cp -p Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib "$DEPS/lib/"
install_name_tool -id "$DEPS/lib/libMoltenVK.dylib" "$DEPS/lib/libMoltenVK.dylib"
lipo -archs "$DEPS/lib/libMoltenVK.dylib"
codesign --force --sign - "$DEPS/lib/libMoltenVK.dylib"
