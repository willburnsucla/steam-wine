#!/bin/bash
# Build the Mac app that starts Windows Steam on this project's Wine and stops everything on Quit.
# Usage: scripts/build-app.sh [--name NAME] [--icon image.svg|.png] [--install]
#   --name     app name (default OpenRunner)
#   --icon     any image macOS can read, ideally square (default art/openrunner-icon.svg)
#   --install  also copy the app to ~/Applications
# The app is built in the project folder and finds the project through Contents/Resources/root.txt,
# so rebuild it if you move the project.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME=OpenRunner
ICON="$ROOT/art/openrunner-icon.svg"
INSTALL=0
while [ $# -gt 0 ]; do
    case $1 in
        --name) NAME=$2; shift 2 ;;
        --icon) ICON=$2; shift 2 ;;
        --install) INSTALL=1; shift ;;
        *) echo "usage: $0 [--name NAME] [--icon image] [--install]" >&2; exit 2 ;;
    esac
done
[ -f "$ICON" ] || { echo "icon not found: $ICON" >&2; exit 2; }

B="$ROOT/build/app"
APP="$ROOT/$NAME.app"
ID="io.github.willburnsucla.$(echo "$NAME" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')"
mkdir -p "$B"

swiftc -O "$ROOT/tools/app/render-icon.swift" -o "$B/render-icon"
swiftc -O "$ROOT/tools/app/main.swift" -o "$B/app-binary"

# Icon: every size macOS asks for, from the one source image.
SET="$B/AppIcon.iconset"
rm -rf "$SET" && mkdir -p "$SET"
for s in 16 32 128 256 512; do
    "$B/render-icon" "$ICON" "$SET/icon_${s}x${s}.png" $s
    "$B/render-icon" "$ICON" "$SET/icon_${s}x${s}@2x.png" $((s * 2))
done
iconutil -c icns "$SET" -o "$B/AppIcon.icns"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$B/app-binary" "$APP/Contents/MacOS/$NAME"
cp "$B/AppIcon.icns" "$APP/Contents/Resources/"
echo "$ROOT" > "$APP/Contents/Resources/root.txt"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$NAME</string>
    <key>CFBundleDisplayName</key><string>$NAME</string>
    <key>CFBundleIdentifier</key><string>$ID</string>
    <key>CFBundleExecutable</key><string>$NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
codesign --force --sign - "$APP"
echo "built $APP"

if [ $INSTALL = 1 ]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/$NAME.app"
    ditto "$APP" "$HOME/Applications/$NAME.app"
    echo "installed $HOME/Applications/$NAME.app"
fi
