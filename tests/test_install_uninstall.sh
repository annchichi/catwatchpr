#!/bin/bash
# Integration test: build the launcher, run install/uninstall via the CLI,
# and assert the right artifacts appear and disappear.
#
# Uses a temp HOME so it doesn't touch the user's real ~/.config or
# ~/Library/LaunchAgents.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$DIR/.."
TMP="$(mktemp -d)"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

echo "→ Building launcher..."
bash "$ROOT/build_app.sh" > "$TMP/build.log" 2>&1 || {
    echo "FAIL: build_app.sh"; cat "$TMP/build.log"; exit 1; }

APP="$ROOT/CatWatchPR.app"
BIN="$APP/Contents/MacOS/CatWatchPR"

# Run installer with HOME pointing at temp dir.
echo "→ Install with fake HOME..."
HOME="$TMP" "$BIN" install || {
    echo "FAIL: install command"; exit 1; }

# Assertions
for label in menubar watch sync; do
    test -f "$TMP/Library/LaunchAgents/com.annchiahui.woo-sprinkles.$label.plist" \
        || { echo "FAIL: $label plist missing"; exit 1; }
    if grep -q "__BUNDLE_PATH__\|__HOME__" \
        "$TMP/Library/LaunchAgents/com.annchiahui.woo-sprinkles.$label.plist"; then
        echo "FAIL: $label plist still has __BUNDLE_PATH__ or __HOME__ placeholder"
        exit 1
    fi
done
echo "  ✓ install wrote 3 plists"

# Uninstall
HOME="$TMP" "$BIN" uninstall || { echo "FAIL: uninstall command"; exit 1; }
for label in menubar watch sync; do
    if [ -f "$TMP/Library/LaunchAgents/com.annchiahui.woo-sprinkles.$label.plist" ]; then
        echo "FAIL: $label plist still present after uninstall"; exit 1
    fi
done
echo "  ✓ uninstall removed plists"

# Reset
HOME="$TMP" "$BIN" reset || { echo "FAIL: reset command"; exit 1; }
if [ -d "$TMP/.config/woo-sprinkles" ]; then
    echo "FAIL: reset did not wipe ~/.config/woo-sprinkles"; exit 1
fi
echo "  ✓ reset wiped config"

echo "PASS: install / uninstall / reset all work."
