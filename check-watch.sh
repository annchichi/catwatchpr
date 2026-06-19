#!/bin/bash

# Watch CI checks for a PR — cat notifies you when done.
# Usage: bash check-watch.sh <PR_NUMBER>
# Runs itself in the background automatically so you can keep working.

REPO="woocommerce/woocommerce"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PR="${1:-}"

if [ -z "$PR" ]; then
    echo "Usage: bash check-watch.sh <PR_NUMBER>"
    echo "Example: bash check-watch.sh 64181"
    exit 1
fi

CAT=$(cat "$HOME/.config/woo-sprinkles/cat_color" 2>/dev/null || echo "cyan")

# Re-launch in background if not already there, so the terminal stays free
if [ -z "$_CATWATCHPR_BG" ]; then
    _CATWATCHPR_BG=1 nohup bash "$0" "$PR" > /tmp/catwatchpr-$PR.log 2>&1 &
    echo "Watching CI for PR #$PR in background (PID $!)"
    echo "Cat will pop up when checks finish."
    exit 0
fi

# --watch blocks until all checks complete
# exit 0 = all pass, non-zero = failures
if gh pr checks "$PR" --repo "$REPO" --watch --interval 30 > /dev/null 2>&1; then
    swift "$DIR/woo_cat.swift" 0 0 0 "$CAT" "" 0 0 0 0 "✅ PR #$PR checks passed"
else
    swift "$DIR/woo_cat.swift" 0 0 0 "$CAT" "" 0 0 0 0 "❌ PR #$PR has failing checks"
fi
