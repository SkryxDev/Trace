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

# Ad-hoc signed by default, so no personal certificate details end up in the
# app. Pass SIGN_IDENTITY="Developer ID Application: …" to sign with a real one.
IDENTITY="${SIGN_IDENTITY:--}"
echo "› Signing with: ${IDENTITY/#-/ad-hoc}"
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
mkdir "$STAGE/.background" "$STAGE/.fseventsd"
touch "$STAGE/.fseventsd/no_log"
swift "$ROOT/Scripts/dmg-background.swift" "$STAGE/.background" >/dev/null
tiffutil -cathidpicheck "$STAGE/.background/background.png" "$STAGE/.background/background@2x.png" \
    -out "$STAGE/.background/background.tiff" 2>/dev/null
rm "$STAGE/.background/"*.png

# A volume with the same name would be mounted under another path.
hdiutil detach "/Volumes/$VOLUME" -quiet 2>/dev/null || true

hdiutil create -volname "$VOLUME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$TEMP_DMG" -quiet
hdiutil attach "$TEMP_DMG" -readwrite -noverify -noautoopen -quiet

echo "› Arranging the Finder window…"
APP_X=170; APPS_X=470; ICON_Y=205

# Finder stores icon positions relative to the view's current scroll offset,
# which depends on the machine building the image (for example, when hidden
# files are shown). Arrange, read back what Finder saved, and correct.
arrange() {
    local dx=$1 dy=$2
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
        set position of item "Trace.app" of container window to {$((APP_X - dx)), $((ICON_Y - dy))}
        set position of item "Applications" of container window to {$((APPS_X - dx)), $((ICON_Y - dy))}
        -- Park hidden items off to the right on the icon row: above the icons they
        -- would shift the view, inside the window they would cover the artwork.
        repeat with hiddenName in {".background", ".fseventsd"}
            if exists item hiddenName of container window then
                set position of item hiddenName of container window to {$((1000 - dx)), $((ICON_Y - dy))}
            end if
        end repeat
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF
    sync
}

# Prints the position Finder stored for an item: "x y".
stored_position() {
    python3 - "/Volumes/$VOLUME/.DS_Store" "$1" <<'EOF'
import struct, sys
data, name = open(sys.argv[1], "rb").read(), sys.argv[2]
key = struct.pack(">I", len(name)) + name.encode("utf-16-be") + b"Ilocblob"
i = data.find(key)
if i < 0:
    sys.exit(1)
x, y = struct.unpack(">II", data[i + len(key) + 4 : i + len(key) + 12])
print(x, y)
EOF
}

DX=0; DY=0
for attempt in 1 2 3 4; do
    arrange $DX $DY
    sleep 1
    read -r X Y <<< "$(stored_position Trace.app)"
    if [[ "$X" == "$APP_X" && "$Y" == "$ICON_Y" ]]; then
        break
    fi
    DX=$((DX + X - APP_X)); DY=$((DY + Y - ICON_Y))
    echo "  Finder saved $X,$Y — correcting by $DX,$DY"
done
read -r X Y <<< "$(stored_position Trace.app)"
[[ "$X" == "$APP_X" && "$Y" == "$ICON_Y" ]] || { echo "✗ Could not place the icons ($X,$Y)"; exit 1; }

# Finder deletes a volume icon that is already there while it arranges the
# window, so add it now and only park it next to the other hidden items.
cp "$APP/Contents/Resources/AppIcon.icns" "/Volumes/$VOLUME/.VolumeIcon.icns"
SetFile -a C "/Volumes/$VOLUME"
osascript <<EOF
tell application "Finder"
    tell disk "$VOLUME"
        open
        if exists item ".VolumeIcon.icns" of container window then
            set position of item ".VolumeIcon.icns" of container window to {$((1000 - DX)), $((ICON_Y - DY))}
        end if
        close
    end tell
end tell
EOF
sync
[[ -f "/Volumes/$VOLUME/.VolumeIcon.icns" ]] || { echo "✗ The volume icon went missing"; exit 1; }
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
