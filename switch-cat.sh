#!/bin/bash

# Switch your Woo Sprinkles cat theme
# Usage: bash switch-cat.sh [mochi|boba|matcha|miso]

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$HOME/.config/woo-sprinkles"
MENUBAR_PLIST="$HOME/Library/LaunchAgents/com.annchiahui.woo-sprinkles.menubar.plist"

name_to_color() {
    case "$1" in
        mochi)  echo "cyan"  ;;
        boba)   echo "pink"  ;;
        matcha) echo "lime"  ;;
        miso)   echo "ghost" ;;
        *)      echo ""      ;;
    esac
}

# Show current cat if no arg
if [ -z "$1" ]; then
    current=$(cat "$CONFIG/cat_name" 2>/dev/null || echo "mochi")
    color=$(name_to_color "$current")
    echo "Current cat: $current ($color)"
    echo ""
    echo "Available cats:"
    echo "  mochi  — cyan  (default)"
    echo "  boba   — pink"
    echo "  matcha — lime"
    echo "  miso   — ghost (pale purple)"
    echo ""
    echo "Usage: bash switch-cat.sh <name>"
    exit 0
fi

name=$(echo "$1" | tr '[:upper:]' '[:lower:]')
color=$(name_to_color "$name")

if [ -z "$color" ]; then
    echo "Unknown cat: $1"
    echo "Choose from: mochi, boba, matcha, miso"
    exit 1
fi

mkdir -p "$CONFIG"
echo "$name"  > "$CONFIG/cat_name"
echo "$color" > "$CONFIG/cat_color"

# Update the menubar plist color arg and restart
if [ -f "$MENUBAR_PLIST" ]; then
    sed -i '' -E "s#<string>(cyan|pink|lime|ghost)</string>#<string>$color</string>#" "$MENUBAR_PLIST" 2>/dev/null || true
    launchctl unload "$MENUBAR_PLIST" 2>/dev/null
    launchctl load  "$MENUBAR_PLIST"
fi

case "$name" in
    mochi)  intro="Good to see you! I'm Mochi~" ;;
    boba)   intro="Heyyy! Boba's here! ✨" ;;
    matcha) intro="Matcha. Ready." ;;
    miso)   intro="hi… I'm miso" ;;
    *)      intro="Hi, I'm $name!" ;;
esac
echo "Switched to $name!"
"$DIR/WooCat" 0 0 0 "$color" "" 0 0 0 0 "$intro"
