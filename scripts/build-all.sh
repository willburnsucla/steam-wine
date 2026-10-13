#!/bin/bash
# Build everything in order. Expect an hour or two on first run (LLVM and Wine dominate).
set -euo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$S/fetch-sources.sh"
"$S/build-deps.sh"        # x86_64 gmp, nettle, gnutls, freetype
"$S/build-moltenvk.sh"    # Vulkan on Metal (needed by Wine's --with-vulkan)
"$S/build-wine.sh"        # CrossOver's Wine + patches/, installed into dist/
"$S/build-dxmt.sh"        # LLVM 15, then DXMT 64- and 32-bit
"$S/build-dxvk.sh"        # DXVK-macOS fallback
echo "Build done. Next: scripts/install-steam.sh"
