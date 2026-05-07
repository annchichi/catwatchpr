#!/bin/bash
# build_app.sh — assemble CatWatchPR.app from the launcher/ source.
# Output: ./CatWatchPR.app next to this script.
# Usage:  bash build_app.sh

set -euo pipefail

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
cp "$DIR/watch.sh" "$DIR/sync.sh" "$DIR/woo_cat.swift" "$DIR/cat_popup.swift" \
   "$DIR/switch-cat.sh" "$RES/scripts/"
chmod +x "$RES/scripts/"*.sh

echo "→ Compiling menubar agent..."
swiftc "$DIR/menubar.swift" -o "$RES/scripts/MenuBarAgent" \
       -framework AppKit \
       -target arm64-apple-macos13.0

echo "→ Compiling launcher Swift sources..."
SOURCES=$(find "$DIR/launcher" -name "*.swift" | tr '\n' ' ')
swiftc $SOURCES -o "$MACOS/CatWatchPR" \
       -framework SwiftUI -framework AppKit \
       -target arm64-apple-macos13.0

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
    <key>CFBundleVersion</key>         <string>1</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
EOF

echo "✓ Built: $APP"
echo "  Run with: open '$APP'"
