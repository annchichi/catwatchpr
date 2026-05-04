#!/bin/bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Preflight ────────────────────────────────────────────────────────────────

# 1. Homebrew
if ! command -v brew &>/dev/null; then
    echo "→ Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    echo ""
    echo "✓ Homebrew installed."
    echo "  Please close this terminal, open a new one, then run setup.sh again."
    exit 0
fi

# Install Woo Sprinkles launchd agents
AGENTS="$HOME/Library/LaunchAgents"

chmod +x "$DIR/sync.sh" "$DIR/watch.sh"

for plist in com.annchiahui.woo-sprinkles.menubar.plist \
             com.annchiahui.woo-sprinkles.watch.plist \
             com.annchiahui.woo-sprinkles.sync.plist; do
    dest="$AGENTS/$plist"
    # Unload first if already running
    launchctl unload "$dest" 2>/dev/null || true
    cp "$DIR/$plist" "$dest"
    launchctl load "$dest"
    echo "✓ loaded $plist"
done

echo ""
echo "Done. The cat will:"
echo "  · check GitHub notifications every 5 minutes"
echo "  · sync PR branches silently at 9am"
echo "  · only show up when something needs you"
echo ""
echo "Test notification watch now:  bash $DIR/watch.sh"
echo "Test branch sync now:         bash $DIR/sync.sh"
echo "Switch cat theme:             bash $DIR/switch-cat.sh [mochi|boba|matcha|miso]"

# Greeting — cat-aware, time-aware for Mochi
cat_name=$(cat "$HOME/.config/woo-sprinkles/cat_name" 2>/dev/null || echo "mochi")
cat_color=$(cat "$HOME/.config/woo-sprinkles/cat_color" 2>/dev/null || echo "cyan")
hour=$(date +%H)
case "$cat_name" in
    boba)   greeting="Hey! I've got your PRs covered ✨" ;;
    matcha) greeting="PRs synced. You're good." ;;
    miso)   greeting="hello… watching over your PRs" ;;
    *)
        if   [ "$hour" -lt 12 ]; then greeting="Good morning! Watching your PRs"
        elif [ "$hour" -lt 17 ]; then greeting="Good afternoon! Watching your PRs"
        else                          greeting="Good evening! Watching your PRs"
        fi ;;
esac
swift "$DIR/woo_cat.swift" 0 0 0 "$cat_color" "" 0 0 0 0 "$greeting"
