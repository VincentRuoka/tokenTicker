#!/bin/bash
set -e

APP_NAME="token-ticker"
DISPLAY_NAME="Token Ticker"
BUNDLE_NAME="token-ticker.app"
APP_PATH="build/$BUNDLE_NAME"
VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "1.0.0")
DMG_NAME="Token-Ticker-$VERSION.dmg"
DMG_TMP="build/tmp-dmg"
DMG_FINAL="build/$DMG_NAME"

# Ensure app is built
if [ ! -d "$APP_PATH" ]; then
    echo "❌ $APP_PATH not found — run ./build.sh first"
    exit 1
fi

echo "📦 Creating DMG: $DMG_NAME ($DISPLAY_NAME v$VERSION)"

# Clean up
rm -rf "$DMG_TMP" "$DMG_FINAL"
mkdir -p "$DMG_TMP"

# Copy app bundle
cp -r "$APP_PATH" "$DMG_TMP/"

# Remove quarantine attributes
xattr -cr "$DMG_TMP/$BUNDLE_NAME"

# Applications symlink for drag-install
ln -s /Applications "$DMG_TMP/Applications"

# Copy background image
if [ -f "Resources/dmg/background.png" ]; then
    mkdir -p "$DMG_TMP/.background"
    cp "Resources/dmg/background.png" "$DMG_TMP/.background/background.png"
fi

# Create a read-write DMG first
RW_DMG="build/tmp-rw.dmg"
hdiutil create \
    -volname "$DISPLAY_NAME" \
    -srcfolder "$DMG_TMP" \
    -ov \
    -fs HFS+ \
    -format UDRW \
    "$RW_DMG"

# Mount it
MOUNT_DIR=$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen | \
    grep -o '/Volumes/.*' | tail -1)

echo "  → Mounted at: $MOUNT_DIR"
DISK_NAME=$(basename "$MOUNT_DIR")
echo "  → Volume name: $DISK_NAME"

# Hide dot-files so they don't appear in the DMG window
chflags hidden "$MOUNT_DIR/.background" 2>/dev/null || true
if [ -f "Resources/icons/AppIcon.icns" ]; then
    cp "Resources/icons/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
    chflags hidden "$MOUNT_DIR/.VolumeIcon.icns" 2>/dev/null || true
fi

# Style the DMG window with AppleScript
osascript - "$DISK_NAME" "$BUNDLE_NAME" << 'APPLESCRIPT'
on run argv
    set diskName to item 1 of argv
    set bundleName to item 2 of argv
    tell application "Finder"
        tell disk diskName
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set bounds of container window to {200, 100, 880, 520}
            set theViewOptions to icon view options of container window
            set arrangement of theViewOptions to not arranged
            set icon size of theViewOptions to 100
            set background picture of theViewOptions to file ".background:background.png"
            set position of item bundleName of container window to {170, 240}
            set position of item "Applications" of container window to {510, 240}
            close
            open
            update without registering applications
            delay 2
            close
        end tell
    end tell
end run
APPLESCRIPT

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
