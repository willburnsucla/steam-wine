#!/bin/bash
# Switch our Wine between DXMT (D3D11/10 -> Metal) and Wine's own wined3d.
# Usage: scripts/install-dxmt.sh on|off|status [prefix]   (status prints on or off)
# Follows DXMT's install guide for builds with -Dwine_builtin_dll=true:
# winemetal.so -> lib/wine/x86_64-unix; d3d11/dxgi/d3d10core/winemetal.dll -> lib/wine/*-windows,
# winemetal.dll also into the prefix's system32 (and syswow64 for 32-bit).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE=${1:?on|off|status}
PREFIX=${2:-$ROOT/prefixes/steam}
LIB="$ROOT/dist/lib/wine"
DX="$ROOT/dist/dxmt"
BACKUP="$LIB/wined3d-originals"
DLLS="d3d11 dxgi d3d10core"
D3D12=d3d12   # 64-bit only, and only if DXMT was built with enable_d3d12

# Is DXMT what Wine has installed? DXMT's d3d11 imports winemetal.dll and Wine's doesn't. The
# DLLs are always switched as a set, so d3d11 speaks for all of them.
dxmt_installed() { LC_ALL=C grep -qa 'winemetal.dll' "$LIB/x86_64-windows/d3d11.dll"; }

case $MODE in
status)
    if dxmt_installed; then echo on; else echo off; fi
    ;;
on)
    # Back up Wine's own DLLs whenever they're what's installed: the first time, and again after a
    # Wine rebuild has put new ones back (an old backup would restore the previous build's).
    if ! dxmt_installed; then
        for arch in x86_64-windows i386-windows; do
            mkdir -p "$BACKUP/$arch"
            for d in $DLLS; do cp -p "$LIB/$arch/$d.dll" "$BACKUP/$arch/$d.dll"; done
        done
        cp -p "$LIB/x86_64-windows/$D3D12.dll" "$BACKUP/x86_64-windows/"
    fi
    cp "$DX/x86_64-unix/winemetal.so" "$LIB/x86_64-unix/"
    for d in $DLLS winemetal; do
        cp "$DX/x86_64-windows/$d.dll" "$LIB/x86_64-windows/"
        cp "$DX/i386/i386-windows/$d.dll" "$LIB/i386-windows/"
    done
    if [ -f "$DX/x86_64-windows/$D3D12.dll" ]; then
        cp "$DX/x86_64-windows/$D3D12.dll" "$LIB/x86_64-windows/"
        cp "$DX/x86_64-windows/$D3D12.dll" "$PREFIX/drive_c/windows/system32/"
    fi
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
    if [ -f "$BACKUP/x86_64-windows/$D3D12.dll" ]; then
        cp -p "$BACKUP/x86_64-windows/$D3D12.dll" "$LIB/x86_64-windows/"
        cp -p "$BACKUP/x86_64-windows/$D3D12.dll" "$PREFIX/drive_c/windows/system32/"
    fi
    rm -f "$LIB/x86_64-unix/winemetal.so" "$LIB/x86_64-windows/winemetal.dll" "$LIB/i386-windows/winemetal.dll"
    echo "DXMT off (wined3d)"
    ;;
*) echo "usage: $0 on|off|status [prefix]"; exit 1 ;;
esac
