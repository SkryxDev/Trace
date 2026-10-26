#!/bin/zsh
# Trace — a tiny clipboard history for macOS.
# Copyright (C) 2026 SkryxDev
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Builds Trace in Release mode and packages it into a drag-to-install disk
# image with a custom background. Run from the repository root:
#
#     Scripts/make-dmg.sh [label]       # e.g. Scripts/make-dmg.sh beta
#
# The result is written to dist/Trace-<version>[-label].dmg.

set -euo pipefail

LABEL="${1:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Build/Products/Release/Trace.app"
VOLUME="Trace"

echo "› Building Trace (Release)…"
xcodebuild -project "$ROOT/Trace.xcodeproj" -scheme Trace -configuration Release \
    -derivedDataPath "$BUILD" build -quiet

# Sign with a real certificate when one is available: an ad-hoc signature
# changes with every build, so macOS would forget the Accessibility permission
# after each update. Override with SIGN_IDENTITY="…" or SIGN_IDENTITY="-".
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -p codesigning -v 2>/dev/null \
    | grep -m1 -oE '"(Developer ID Application|Apple Development): [^"]+"' | tr -d '"' || true)}"
IDENTITY="${IDENTITY:--}"
echo "› Signing with: $IDENTITY"
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")"
NAME="Trace-$VERSION${LABEL:+-$LABEL}"
OUTPUT="$ROOT/dist/$NAME.dmg"

STAGE="$(mktemp -d)"
TEMP_DMG="$(mktemp -u).dmg"
trap 'hdiutil detach "/Volumes/$VOLUME" -quiet 2>/dev/null || true; rm -rf "$STAGE" "$TEMP_DMG"' EXIT

echo "› Preparing the disk image contents…"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/.background"
swift "$ROOT/Scripts/dmg-background.swift" "$STAGE/.background" >/dev/null
tiffutil -cathidpicheck "$STAGE/.background/background.png" "$STAGE/.background/background@2x.png" \
    -out "$STAGE/.background/background.tiff" 2>/dev/null
rm "$STAGE/.background/"*.png

# A volume with the same name would be mounted under another path.
hdiutil detach "/Volumes/$VOLUME" -quiet 2>/dev/null || true

hdiutil create -volname "$VOLUME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$TEMP_DMG" -quiet
hdiutil attach "$TEMP_DMG" -readwrite -noverify -noautoopen -quiet

echo "› Arranging the Finder window…"
# Window: 640 × 420 points, icons centred where the background expects them.
osascript <<EOF
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 840, 568}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "Trace.app" of container window to {170, 205}
        set position of item "Applications" of container window to {470, 205}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF

# Finder drops a custom volume icon added before the window is arranged.
cp "$APP/Contents/Resources/AppIcon.icns" "/Volumes/$VOLUME/.VolumeIcon.icns"
SetFile -a C "/Volumes/$VOLUME"
SetFile -a V "/Volumes/$VOLUME/.background" "/Volumes/$VOLUME/.VolumeIcon.icns"
rm -rf "/Volumes/$VOLUME/.fseventsd"
chmod -Rf go-w "/Volumes/$VOLUME" 2>/dev/null || true
sync
hdiutil detach "/Volumes/$VOLUME" -quiet

echo "› Compressing…"
mkdir -p "$ROOT/dist"
rm -f "$OUTPUT"
hdiutil convert "$TEMP_DMG" -format ULFO -o "$OUTPUT" -quiet

echo "✓ $OUTPUT"
shasum -a 256 "$OUTPUT"
