#!/bin/bash
set -e

APP_NAME="token-ticker"
BUNDLE_NAME="token-ticker.app"
BUILD_DIR="build"
APP_PATH="$BUILD_DIR/$BUNDLE_NAME"
BINARY="$APP_PATH/Contents/MacOS/$APP_NAME"

echo "🔨 Building token-ticker..."

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

# Build release for both architectures via Swift Package Manager
echo "  → Compiling arm64..."
swift build -c release --arch arm64 2>&1 | grep -E "error:|warning:|Build complete" || true

echo "  → Compiling x86_64..."
swift build -c release --arch x86_64 2>&1 | grep -E "error:|warning:|Build complete" || true

ARM64_BIN=".build/arm64-apple-macosx/release/$APP_NAME"
X86_BIN=".build/x86_64-apple-macosx/release/$APP_NAME"

# Create universal binary
echo "  → Creating universal binary..."
lipo -create \
    "$ARM64_BIN" \
    "$X86_BIN" \
    -output "$BINARY"

chmod 755 "$BINARY"

# Copy Info.plist
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"

# Inject version from git tag (or fallback)
VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "1.0.0")
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_PATH/Contents/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$APP_PATH/Contents/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_NAME" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Token Ticker" "$APP_PATH/Contents/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Add :CFBundleName string Token Ticker" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Token Ticker" "$APP_PATH/Contents/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Token Ticker" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.tokenticker.app" "$APP_PATH/Contents/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.tokenticker.app" "$APP_PATH/Contents/Info.plist"

# Generate .icns from source PNG (always regenerate so it stays in sync)
if [ -f "Resources/token-ticker.png" ]; then
    echo "  → Generating AppIcon.icns..."
    ICONSET="build/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 64 128 256 512 1024; do
        sips -z $size $size "Resources/token-ticker.png" --out "$ICONSET/icon_${size}x${size}.png" > /dev/null
    done
    for size in 16 32 128 256 512; do
        double=$((size * 2))
        sips -z $double $double "Resources/token-ticker.png" --out "$ICONSET/icon_${size}x${size}@2x.png" > /dev/null
    done
    iconutil -c icns "$ICONSET" -o "Resources/icons/AppIcon.icns"
    rm -rf "$ICONSET"
fi

# Copy app icon into bundle
if [ -f "Resources/icons/AppIcon.icns" ]; then
    cp "Resources/icons/AppIcon.icns" "$APP_PATH/Contents/Resources/token-ticker.icns"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile token-ticker" "$APP_PATH/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string token-ticker" "$APP_PATH/Contents/Info.plist"
fi

# Copy menubar icon PNG (loaded at runtime for the menu bar extra label)
if [ -f "Resources/token-ticker.png" ]; then
    cp "Resources/token-ticker.png" "$APP_PATH/Contents/Resources/"
fi

# PkgInfo
printf "APPL????" > "$APP_PATH/Contents/PkgInfo"

# Clean extended attributes
xattr -cr "$APP_PATH"

# Sign — try Developer ID first, fall back to ad-hoc
DEVELOPER_ID="Developer ID Application:"
if codesign --force --deep --options runtime --sign "$DEVELOPER_ID" "$APP_PATH" 2>/dev/null; then
    echo "✅ Signed with Developer ID"
else
    echo "⚠️  Ad-hoc signature (not notarized)"
    codesign --force --deep --sign - "$APP_PATH"
fi

echo ""
echo "✅ Build complete: $APP_PATH"
echo "   Version: $VERSION"
echo "   Arch:    universal (arm64 + x86_64)"
echo ""
echo "Run: open $APP_PATH"
