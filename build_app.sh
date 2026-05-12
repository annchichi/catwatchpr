#!/bin/bash
# build_app.sh — assemble CatWatchPR.app from the launcher/ source,
# then package it into CatWatchPR.dmg for distribution.
# Output: ./CatWatchPR.app and ./CatWatchPR.dmg next to this script.
# Usage:  bash build_app.sh [--install]
#         --install also deploys to /Applications and reloads LaunchAgents
#         so edits go live in the running menubar without manual copy.

set -euo pipefail

INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        *) echo "Unknown arg: $arg" >&2; exit 2 ;;
    esac
done

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$DIR/CatWatchPR.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"

echo "→ Cleaning previous build..."
rm -rf "$APP"
mkdir -p "$MACOS" "$RES/scripts" "$RES/launchd"

echo "→ Staging launchd plist templates..."
for label in com.annchiahui.woo-sprinkles.menubar \
             com.annchiahui.woo-sprinkles.watch \
             com.annchiahui.woo-sprinkles.sync; do
    src="$DIR/$label.plist"
    dest="$RES/launchd/$label.plist"
    # Replace any existing absolute path with the placeholder; the launcher
    # substitutes __BUNDLE_PATH__ at install time.
    sed -E "s|/Users/[^/]+/tools/woo-sprinkles|__BUNDLE_PATH__/Contents/Resources/scripts|g" \
        "$src" > "$dest"
done

echo "→ Bundling scripts..."
cp "$DIR/watch.sh" "$DIR/sync.sh" "$DIR/switch-cat.sh" "$RES/scripts/"
chmod +x "$RES/scripts/"*.sh

echo "→ Compiling menubar agent..."
swiftc "$DIR/menubar.swift" -o "$RES/scripts/MenuBarAgent" \
       -framework AppKit \
       -target arm64-apple-macos13.0

echo "→ Compiling cat popup..."
# Pre-compile woo_cat.swift so users without a working Swift toolchain can still
# render the cat (avoids "select a toolchain which matches the SDK" runtime errors).
swiftc "$DIR/woo_cat.swift" -o "$RES/scripts/CatPopup" \
       -framework AppKit \
       -target arm64-apple-macos13.0

echo "→ Compiling launcher Swift sources..."
SOURCES=$(find "$DIR/launcher" -name "*.swift" | tr '\n' ' ')
swiftc $SOURCES -o "$MACOS/CatWatchPR" \
       -framework SwiftUI -framework AppKit \
       -target arm64-apple-macos13.0

echo "→ Generating app icon (Mochi pixel cat)..."
ICONSET="$RES/AppIcon.iconset"
mkdir -p "$ICONSET"
RENDER="$DIR/tools/render_icon.swift"
swift "$RENDER" 16   "$ICONSET/icon_16x16.png"
swift "$RENDER" 32   "$ICONSET/icon_16x16@2x.png"
cp    "$ICONSET/icon_16x16@2x.png"   "$ICONSET/icon_32x32.png"
swift "$RENDER" 64   "$ICONSET/icon_32x32@2x.png"
swift "$RENDER" 128  "$ICONSET/icon_128x128.png"
swift "$RENDER" 256  "$ICONSET/icon_128x128@2x.png"
cp    "$ICONSET/icon_128x128@2x.png" "$ICONSET/icon_256x256.png"
swift "$RENDER" 512  "$ICONSET/icon_256x256@2x.png"
cp    "$ICONSET/icon_256x256@2x.png" "$ICONSET/icon_512x512.png"
swift "$RENDER" 1024 "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$RES/AppIcon.icns"
rm -rf "$ICONSET"

echo "→ Writing Info.plist..."
cat > "$CONTENTS/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>      <string>com.annchiahui.catwatchpr</string>
    <key>CFBundleName</key>            <string>CatWatchPR</string>
    <key>CFBundleDisplayName</key>     <string>CatWatchPR</string>
    <key>CFBundleExecutable</key>      <string>CatWatchPR</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>CFBundleShortVersionString</key><string>0.2.4</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
EOF

echo "✓ Built: $APP"
echo "  Run with: open '$APP'"

echo "→ Packaging DMG..."
DMG="$DIR/CatWatchPR.dmg"
DMG_STAGING="$DIR/.dmg-staging"
rm -rf "$DMG_STAGING" "$DMG"
mkdir -p "$DMG_STAGING"
cp -R "$APP" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "CatWatchPR" \
               -srcfolder "$DMG_STAGING" \
               -ov -format UDZO \
               "$DMG" >/dev/null
rm -rf "$DMG_STAGING"
echo "✓ Built: $DMG"

if [ "$INSTALL" -eq 1 ]; then
    DEST="/Applications/CatWatchPR.app"
    echo "→ Installing to $DEST..."
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"

    echo "→ Reloading LaunchAgents..."
    for label in com.annchiahui.woo-sprinkles.menubar \
                 com.annchiahui.woo-sprinkles.watch \
                 com.annchiahui.woo-sprinkles.sync; do
        launchctl bootout "gui/$UID/$label" 2>/dev/null || true
        launchctl bootstrap "gui/$UID" "$HOME/Library/LaunchAgents/$label.plist" \
            && echo "  ✓ $label"
    done
    echo "✓ Installed and live."
fi
