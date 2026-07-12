#!/usr/bin/env bash
# Assemble Hermex.app from the SwiftPM release binary, then produce the
# distributables (Hermex-<version>.zip and Hermex-<version>.dmg).
# Run on macOS from the HermexMac directory:
#   ./Packaging/package_app.sh <version>
set -euo pipefail

VERSION="${1:-0.0.0}"
# Strip a leading "v" so tag names work directly.
VERSION="${VERSION#v}"

cd "$(dirname "$0")/.."

echo "==> Building universal release binary"
swift build -c release --arch arm64 --arch x86_64

BIN_PATH="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Hermex"
test -f "$BIN_PATH"

DIST=dist
APP="$DIST/Hermex.app"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Assembling app bundle"
cp "$BIN_PATH" "$APP/Contents/MacOS/Hermex"
sed "s/APP_VERSION/$VERSION/g" Packaging/Info.plist > "$APP/Contents/Info.plist"

echo "==> Generating AppIcon.icns"
ICONSET="$DIST/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Packaging/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Packaging/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP"

echo "==> Creating zip"
ditto -c -k --keepParent "$APP" "$DIST/Hermex-$VERSION-macos.zip"

echo "==> Creating dmg"
DMG_ROOT="$DIST/dmg-root"
mkdir -p "$DMG_ROOT"
cp -R "$APP" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create -volname "Hermex" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DIST/Hermex-$VERSION-macos.dmg"
rm -rf "$DMG_ROOT"

echo "==> Done"
ls -la "$DIST"
