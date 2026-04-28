#!/bin/bash

# Woo Sprinkles — sync all open PR branches and show the cat
# Usage: ./sync.sh [cat_color]
#   cat_color: cyan (default) | lime | pink | ghost

REPO="woocommerce/woocommerce"
CAT=$(cat "$HOME/.config/woo-sprinkles/cat_color" 2>/dev/null || echo "${WOO_SPRINKLES_CAT:-${1:-cyan}}")
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

updated=0
skipped=0
conflicts=0
conflict_prs=()

prs=$(gh pr list --author "@me" --repo "$REPO" --state open --json number --jq '.[].number' 2>/dev/null)

for pr in $prs; do
    result=$(gh pr update-branch "$pr" 2>&1)
    if echo "$result" | grep -q "already up-to-date"; then
        ((skipped++))
    elif echo "$result" | grep -q "updated"; then
        ((updated++))
    else
        ((conflicts++))
        conflict_prs+=("$pr")
    fi
done

# Join conflict PR numbers as comma-separated string
conflict_list=$(IFS=','; echo "${conflict_prs[*]}")

# Fetch unread direct-attention notifications and break down by type
notif_data=$(gh api notifications --jq '
  [.[] | select(.unread == true and
    (.reason == "review_requested" or .reason == "mention" or .reason == "assign"))]
  | {
      r: [.[] | select(.reason == "review_requested")] | length,
      m: [.[] | select(.reason == "mention")]          | length,
      a: [.[] | select(.reason == "assign")]           | length
    }
  | "\(.r) \(.m) \(.a)"
' 2>/dev/null || echo "0 0 0")

notif_reviews=$(echo "$notif_data" | awk '{print $1}')
notif_mentions=$(echo "$notif_data" | awk '{print $2}')
notif_assigns=$(echo "$notif_data"  | awk '{print $3}')

# Only show the cat when something actually needs attention
if [ "$conflicts" -gt 0 ] || [ "$notif_reviews" -gt 0 ] || \
   [ "$notif_mentions" -gt 0 ] || [ "$notif_assigns" -gt 0 ]; then
    swift "$DIR/woo_cat.swift" "$updated" "$skipped" "$conflicts" "$CAT" \
        "$conflict_list" "$notif_reviews" "$notif_mentions" "$notif_assigns"
fi
