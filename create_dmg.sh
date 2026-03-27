#!/bin/bash
set -e

APP_NAME="token-ticker"
BUNDLE_NAME="token-ticker.app"
APP_PATH="build/$BUNDLE_NAME"
VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "1.0.0")
DMG_NAME="token-ticker-$VERSION.dmg"
DMG_TMP="build/tmp-dmg"
DMG_FINAL="build/$DMG_NAME"

# Ensure app is built
if [ ! -d "$APP_PATH" ]; then
    echo "❌ $APP_PATH not found — run ./build.sh first"
    exit 1
fi

echo "📦 Creating DMG: $DMG_NAME"

# Clean up
rm -rf "$DMG_TMP" "$DMG_FINAL"
mkdir -p "$DMG_TMP"

# Copy app bundle
cp -r "$APP_PATH" "$DMG_TMP/"

# Remove quarantine attributes
xattr -cr "$DMG_TMP/$BUNDLE_NAME"

# Applications symlink for drag-install
ln -s /Applications "$DMG_TMP/Applications"

# Create a read-write DMG first
RW_DMG="build/tmp-rw.dmg"
hdiutil create \
    -volname "token-ticker" \
    -srcfolder "$DMG_TMP" \
    -ov \
    -fs HFS+ \
    -format UDRW \
    "$RW_DMG"

# Mount it
MOUNT_DIR=$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen | \
    awk '/\/Volumes/ { print $NF }')

echo "  → Mounted at: $MOUNT_DIR"

# Style the DMG window with AppleScript
osascript << APPLESCRIPT
tell application "Finder"
    tell disk "token-ticker"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 100, 680, 360}
        set iconSize of icon view options of container window to 100
        set arrangement of icon view options of container window to not arranged
        set position of item "$BUNDLE_NAME" of container window to {120, 120}
        set position of item "Applications" of container window to {360, 120}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

# Set volume icon
if [ -f "Resources/icons/AppIcon.icns" ]; then
    cp "Resources/icons/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
    SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
fi

# Unmount
sync
hdiutil detach "$MOUNT_DIR" -quiet

# Convert to compressed read-only DMG
echo "  → Compressing..."
hdiutil convert "$RW_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_FINAL"

# Clean up
rm -rf "$DMG_TMP" "$RW_DMG"

echo ""
echo "✅ DMG created: $DMG_FINAL"
echo ""
echo "To install: open $DMG_FINAL"
