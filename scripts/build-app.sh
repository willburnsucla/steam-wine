#!/bin/bash
# Build the Mac app that starts Windows Steam on this project's Wine and stops everything on Quit.
# Usage: scripts/build-app.sh [--name NAME] [--icon image.svg|.png] [--install]
#   --name     app name: letters, digits, spaces, dots, dashes, underscores (default OpenRunner)
#   --icon     any image macOS can read, ideally square (default art/openrunner-icon.svg)
#   --install  move the app to ~/Applications, replacing an older copy
# The app is built in build/app/ and finds the project through Contents/Resources/root.txt, so
# rebuild it if you move the project.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME=OpenRunner
ICON="$ROOT/art/openrunner-icon.svg"
INSTALL=0
usage() { echo "usage: $0 [--name NAME] [--icon image] [--install]" >&2; exit 2; }
while [ $# -gt 0 ]; do
    case $1 in
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --icon) [ $# -ge 2 ] || usage; ICON=$2; shift 2 ;;
        --install) INSTALL=1; shift ;;
        *) usage ;;
    esac
done
re='^[A-Za-z0-9][A-Za-z0-9 ._-]*$'
[[ $NAME =~ $re ]] || { echo "app name can only use letters, digits, spaces, . _ -: $NAME" >&2; exit 2; }
[ -f "$ICON" ] || { echo "icon not found: $ICON" >&2; exit 2; }
DEST="$HOME/Applications/$NAME.app"
if [ $INSTALL = 1 ] && [ -e "$DEST" ] && [ ! -f "$DEST/Contents/Resources/root.txt" ]; then
    echo "$DEST exists and wasn't built by this script; not replacing it" >&2
    exit 2
fi

B="$ROOT/build/app"
APP="$B/$NAME.app"
ID="io.github.willburnsucla.$(echo "$NAME" | LC_ALL=C tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')"
mkdir -p "$B"

# Same minimum macOS as Info.plist says (swiftc otherwise targets the building Mac's version).
swiftc -O -target arm64-apple-macos14.0 "$ROOT/tools/app/render-icon.swift" -o "$B/render-icon"
swiftc -O -target arm64-apple-macos14.0 "$ROOT/tools/app/main.swift" -o "$B/app-binary"

# Icon: every size macOS asks for, from the one source image.
SET="$B/AppIcon.iconset"
rm -rf "$SET" && mkdir -p "$SET"
for s in 16 32 128 256 512; do
    "$B/render-icon" "$ICON" "$SET/icon_${s}x${s}.png" $s
    "$B/render-icon" "$ICON" "$SET/icon_${s}x${s}@2x.png" $((s * 2))
done
iconutil -c icns "$SET" -o "$B/AppIcon.icns"

# Wine's processes count as the app's for macOS privacy prompts, so the app carries the usage
# texts for what Steam and games may ask for (voice chat, webcams, LAN game transfers).
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$B/app-binary" "$APP/Contents/MacOS/$NAME"
cp "$B/AppIcon.icns" "$APP/Contents/Resources/"
echo "$ROOT" > "$APP/Contents/Resources/root.txt"
cat > "$APP/Contents/Info.plist" <<PLIST
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
    <key>NSMicrophoneUsageDescription</key><string>Steam and your games use the microphone for voice chat.</string>
    <key>NSCameraUsageDescription</key><string>Some games and Steam features use the camera.</string>
    <key>NSLocalNetworkUsageDescription</key><string>Steam uses your local network to copy games between computers and for Remote Play.</string>
</dict>
</plist>
PLIST
plutil -lint -s "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "built $APP"

if [ $INSTALL = 1 ]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"
    ditto "$APP" "$DEST"
    rm -rf "$APP"   # one copy only, so Spotlight and the Dock don't show two
    echo "installed $HOME/Applications/$NAME.app"
fi
