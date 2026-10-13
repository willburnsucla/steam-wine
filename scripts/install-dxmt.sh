#!/bin/bash
# Switch our Wine between DXMT (D3D11/10 -> Metal) and Wine's own wined3d.
# Usage: scripts/install-dxmt.sh on|off [prefix]
# Follows DXMT's install guide for builds with -Dwine_builtin_dll=true:
# winemetal.so -> lib/wine/x86_64-unix; d3d11/dxgi/d3d10core/winemetal.dll -> lib/wine/*-windows,
# winemetal.dll also into the prefix's system32 (and syswow64 for 32-bit).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE=${1:?on|off}
PREFIX=${2:-$ROOT/prefixes/steam}
LIB="$ROOT/dist/lib/wine"
DX="$ROOT/dist/dxmt"
BACKUP="$LIB/wined3d-originals"
DLLS="d3d11 dxgi d3d10core"

case $MODE in
on)
    for arch in x86_64-windows i386-windows; do
        mkdir -p "$BACKUP/$arch"
        for d in $DLLS; do
            [ -e "$BACKUP/$arch/$d.dll" ] || cp -p "$LIB/$arch/$d.dll" "$BACKUP/$arch/$d.dll"
        done
    done
    cp "$DX/x86_64-unix/winemetal.so" "$LIB/x86_64-unix/"
    for d in $DLLS winemetal; do
        cp "$DX/x86_64-windows/$d.dll" "$LIB/x86_64-windows/"
        cp "$DX/i386/i386-windows/$d.dll" "$LIB/i386-windows/"
    done
    cp "$DX/x86_64-windows/winemetal.dll" "$PREFIX/drive_c/windows/system32/"
    cp "$DX/i386/i386-windows/winemetal.dll" "$PREFIX/drive_c/windows/syswow64/"
    # The prefix's system32 holds copies of builtin DLLs from wineboot; refresh them too.
    for d in $DLLS; do
        cp "$DX/x86_64-windows/$d.dll" "$PREFIX/drive_c/windows/system32/"
        cp "$DX/i386/i386-windows/$d.dll" "$PREFIX/drive_c/windows/syswow64/"
    done
    echo "DXMT on"
    ;;
off)
    for arch in x86_64-windows i386-windows; do
        for d in $DLLS; do cp -p "$BACKUP/$arch/$d.dll" "$LIB/$arch/"; done
    done
    for d in $DLLS; do
        cp -p "$BACKUP/x86_64-windows/$d.dll" "$PREFIX/drive_c/windows/system32/"
        cp -p "$BACKUP/i386-windows/$d.dll" "$PREFIX/drive_c/windows/syswow64/"
    done
    rm -f "$LIB/x86_64-unix/winemetal.so" "$LIB/x86_64-windows/winemetal.dll" "$LIB/i386-windows/winemetal.dll"
    echo "DXMT off (wined3d)"
    ;;
*) echo "usage: $0 on|off [prefix]"; exit 1 ;;
esac
