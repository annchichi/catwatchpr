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
