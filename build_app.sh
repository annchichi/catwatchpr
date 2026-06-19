#!/bin/bash
# build_app.sh — assemble CatWatchPR.app from the launcher/ source,
# then package it into CatWatchPR.dmg.
# Output: ./CatWatchPR.app and ./CatWatchPR.dmg next to this script.
# Usage:  bash build_app.sh [--install] [--release]
#         default builds are ad-hoc signed for local testing only.
#         --install also deploys to /Applications and reloads LaunchAgents
#         so edits go live in the running menubar without manual copy.
#         --release requires Developer ID signing + notarization credentials.

set -euo pipefail

VERSION="0.2.10"
INSTALL=0
RELEASE=0
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        --release) RELEASE=1 ;;
        *) echo "Unknown arg: $arg" >&2; exit 2 ;;
    esac
done

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$DIR/CatWatchPR.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"
DMG="$DIR/CatWatchPR.dmg"

SIGN_IDENTITY="${CATWATCHPR_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${CATWATCHPR_NOTARY_PROFILE:-}"
INSTALL_DEST="${CATWATCHPR_INSTALL_DEST:-/Applications/CatWatchPR.app}"

die() {
    echo "✗ $*" >&2
    exit 1
}

if [ "$INSTALL" -eq 1 ] && [ "$RELEASE" -eq 1 ]; then
    die "--install and --release cannot be combined."
fi

if [ "$RELEASE" -eq 1 ]; then
    if [ -z "$SIGN_IDENTITY" ]; then
        die "Public release builds require CATWATCHPR_SIGN_IDENTITY, for example: Developer ID Application: Your Name (TEAMID)."
    fi
    if [ -z "$NOTARY_PROFILE" ]; then
        die "Public release builds require CATWATCHPR_NOTARY_PROFILE from xcrun notarytool store-credentials."
    fi
    if ! security find-identity -v -p codesigning | grep -F "$SIGN_IDENTITY" >/dev/null; then
        die "Signing identity not found in this keychain: $SIGN_IDENTITY"
    fi
    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        die "Notary profile is missing or unusable: $NOTARY_PROFILE"
    fi
fi

sign_executable() {
    local target="$1"
    if [ "$RELEASE" -eq 1 ]; then
        codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$target"
    else
        codesign --force --sign - "$target"
    fi
}

sign_app_bundle() {
    if [ "$RELEASE" -eq 1 ]; then
        codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
    else
        codesign --force --deep --sign - "$APP"
    fi
}

notarize_release_dmg() {
    echo "→ Signing DMG..."
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

    echo "→ Notarizing DMG..."
    xcrun notarytool submit "$DMG" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    echo "→ Stapling notarization ticket..."
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"

    echo "→ Verifying Gatekeeper accepts the DMG..."
    spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"

    echo "→ Verifying Gatekeeper accepts the app from the mounted DMG..."
    local mountpoint
    mountpoint="$(mktemp -d /private/tmp/catwatchpr-mount.XXXXXX)"
    hdiutil attach -nobrowse -readonly -mountpoint "$mountpoint" "$DMG" >/dev/null
    set +e
    spctl --assess --type execute --verbose=4 "$mountpoint/CatWatchPR.app"
    local app_status=$?
    hdiutil detach "$mountpoint" >/dev/null
    local detach_status=$?
    set -e
    rmdir "$mountpoint" 2>/dev/null || true
    [ "$detach_status" -eq 0 ] || die "Could not detach mounted release DMG."
    [ "$app_status" -eq 0 ] || die "Gatekeeper rejected CatWatchPR.app inside the release DMG."
}

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
if ! iconutil -c icns "$ICONSET" -o "$RES/AppIcon.icns"; then
    echo "  ! iconutil could not package the generated iconset; using bundled fallback icon."
    cp "$DIR/assets/AppIcon.icns" "$RES/AppIcon.icns"
fi
rm -rf "$ICONSET"

echo "→ Writing Info.plist..."
cat > "$CONTENTS/Info.plist" <<EOF
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
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
EOF

echo "→ Signing app bundle..."
sign_executable "$RES/scripts/MenuBarAgent"
sign_executable "$RES/scripts/CatPopup"
sign_executable "$MACOS/CatWatchPR"
sign_app_bundle
codesign --verify --deep --strict --verbose=4 "$APP"

echo "✓ Built: $APP"
echo "  Run with: open '$APP'"

if [ "$INSTALL" -eq 0 ]; then
    echo "→ Packaging DMG..."
    DMG_STAGING="$DIR/.dmg-staging"
    TMP_DMG="/private/tmp/CatWatchPR.dmg"
    rm -rf "$DMG_STAGING" "$DMG" "$TMP_DMG"
    mkdir -p "$DMG_STAGING"
    cp -R "$APP" "$DMG_STAGING/"
    ln -s /Applications "$DMG_STAGING/Applications"
    hdiutil create -volname "CatWatchPR" \
                   -srcfolder "$DMG_STAGING" \
                   -ov -format UDZO \
                   "$TMP_DMG" >/dev/null
    mv "$TMP_DMG" "$DMG"
    rm -rf "$DMG_STAGING"
    echo "✓ Built: $DMG"

    if [ "$RELEASE" -eq 1 ]; then
        notarize_release_dmg
        echo "✓ Release DMG is signed, notarized, stapled, and accepted by Gatekeeper."
    else
        echo "  Local build only: this DMG is not notarized and should not be published."
        echo "  For a public release, run: CATWATCHPR_SIGN_IDENTITY='Developer ID Application: ...' CATWATCHPR_NOTARY_PROFILE='...' bash build_app.sh --release"
    fi
fi

if [ "$INSTALL" -eq 1 ]; then
    DEST="$INSTALL_DEST"
    echo "→ Installing to $DEST..."
    mkdir -p "$(dirname "$DEST")"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"

    echo "→ Installing LaunchAgents..."
    "$DEST/Contents/MacOS/CatWatchPR" install
    echo "✓ Installed and live."
fi
