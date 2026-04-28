#!/bin/bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$DIR/WooSprinklesMenuBar.app"
CONTENTS="$APP/Contents"
BINARY="$CONTENTS/MacOS/WooSprinklesMenuBar"

mkdir -p "$CONTENTS/MacOS"

echo "Compiling menubar.swift..."
swiftc "$DIR/menubar.swift" -o "$BINARY"
if [ $? -ne 0 ]; then echo "Compile failed"; exit 1; fi

cat > "$CONTENTS/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.annchiahui.woo-sprinkles.menubar</string>
    <key>CFBundleName</key>
    <string>WooSprinklesMenuBar</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "Built: $APP"
