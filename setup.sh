#!/bin/bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Preflight ────────────────────────────────────────────────────────────────

# 1. Homebrew
if ! command -v brew &>/dev/null; then
    echo "→ Installing Homebrew..."
    if ! /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
        echo "✗ Homebrew installation failed. Please install it manually: https://brew.sh"
        exit 1
    fi
    echo ""
    echo "✓ Homebrew installed."
    echo "  Please close this terminal, open a new one, then run setup.sh again."
    echo "  If 'brew' is still not found after reopening, follow the instructions the installer printed above."
    exit 0
fi

# 2. GitHub CLI
if ! command -v gh &>/dev/null; then
    echo "→ Installing GitHub CLI..."
    brew install gh
fi

# 3. GitHub auth
if ! gh auth status &>/dev/null; then
    echo "→ Let's log you into GitHub..."
    gh auth login
fi

# 4. Repo selection
gh_user=$(gh api /user --jq .login 2>/dev/null)
DEFAULT_REPO="woocommerce/woocommerce"

if [[ -n "$gh_user" ]] && gh api "/orgs/woocommerce/members/$gh_user" --silent 2>/dev/null; then
    # User is in the woocommerce org — suggest the default
    read -rp "Watch $DEFAULT_REPO? [Y/n] " repo_confirm
    repo_confirm="${repo_confirm:-Y}"
    if [[ "$repo_confirm" =~ ^[Yy]$ ]]; then
        CHOSEN_REPO="$DEFAULT_REPO"
    else
        read -rp "Which repo? (format: org/repo) " CHOSEN_REPO
    fi
else
    read -rp "Which GitHub repo do you want to watch? (format: org/repo) " CHOSEN_REPO
fi

# Validate format
if [[ ! "$CHOSEN_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    echo "✗ Invalid repo format. Expected: org/repo (e.g. mycompany/myrepo)"
    exit 1
fi

# 5. Patch repo into config files
sed -i '' "s|^REPO=.*|REPO=\"$CHOSEN_REPO\"|" "$DIR/watch.sh"
sed -i '' "s|^REPO=.*|REPO=\"$CHOSEN_REPO\"|" "$DIR/sync.sh"
echo "✓ Watching: $CHOSEN_REPO"
echo ""

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
