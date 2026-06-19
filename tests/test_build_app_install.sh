#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

DEST="$TMP/Applications/CatWatchPR.app"
mkdir -p "$TMP/home"

set +e
HOME="$TMP/home" \
CATWATCHPR_INSTALL_DEST="$DEST" \
bash "$DIR/build_app.sh" --install > "$TMP/install.log" 2>&1
STATUS=$?
set -e

if [ "$STATUS" -ne 0 ]; then
    echo "FAIL: build_app.sh --install exited $STATUS"
    cat "$TMP/install.log"
    exit 1
fi

test -x "$DEST/Contents/MacOS/CatWatchPR" || {
    echo "FAIL: app was not installed to CATWATCHPR_INSTALL_DEST"
    cat "$TMP/install.log"
    exit 1
}

for label in menubar watch sync; do
    plist="$TMP/home/Library/LaunchAgents/com.annchiahui.woo-sprinkles.$label.plist"
    test -f "$plist" || {
        echo "FAIL: $label plist missing after build_app.sh --install"
        cat "$TMP/install.log"
        exit 1
    }
    if grep -q "__BUNDLE_PATH__\|__HOME__" "$plist"; then
        echo "FAIL: $label plist still has placeholders"
        cat "$plist"
        exit 1
    fi
    if ! grep -q "$DEST/Contents/Resources/scripts" "$plist"; then
        echo "FAIL: $label plist does not point at installed app resources"
        cat "$plist"
        exit 1
    fi
done

echo "PASS: build_app.sh --install installs the app and writes launch agents."
