#!/bin/bash

# Woo Sprinkles — watch for activity on YOUR PRs
# Run every 5 minutes via launchd.

REPO="woocommerce/woocommerce"
CAT=$(cat "$HOME/.config/woo-sprinkles/cat_color" 2>/dev/null || echo "${WOO_SPRINKLES_CAT:-cyan}")
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$HOME/.config/woo-sprinkles"
SEEN_FILE="$CONFIG/seen_notif_ids"
PREV_PRS_FILE="$CONFIG/prev_open_prs"

mkdir -p "$CONFIG"
touch "$SEEN_FILE"
touch "$PREV_PRS_FILE"
date +%s > "$CONFIG/last_checked"

# Get your open PR numbers
my_prs=$(gh pr list --author "@me" --repo "$REPO" --state open \
    --json number --jq '.[].number' 2>/dev/null | tr '\n' ' ')

# Detect merges: PRs that were open last run but are gone now
prev_prs=$(cat "$PREV_PRS_FILE" 2>/dev/null || echo "")
merged_prs=()
for pr in $prev_prs; do
    if ! echo " $my_prs " | grep -qw "$pr"; then
        state=$(gh pr view "$pr" --repo "$REPO" --json state --jq '.state' 2>/dev/null)
        [ "$state" = "MERGED" ] && merged_prs+=("$pr")
    fi
done
echo "$my_prs" > "$PREV_PRS_FILE"

# Celebrate merged PRs immediately
if [ ${#merged_prs[@]} -gt 0 ]; then
    merged_list=$(IFS=','; echo "${merged_prs[*]}")
    swift "$DIR/woo_cat.swift" 0 0 0 "$CAT" "" 0 0 0 0 "" "$merged_list"
fi

if [ -z "$my_prs" ]; then
    echo "0" > "$CONFIG/pending_count"
    echo ""  > "$CONFIG/pending_notifs"
    exit 0
fi

# Fetch unread notifications for this repo that are on PullRequests
notif_tsv=$(gh api notifications --jq '
  [.[] | select(
    .unread == true and
    .repository.full_name == "woocommerce/woocommerce" and
    .subject.type == "PullRequest"
  ) | {
    id:     .id,
    reason: .reason,
    pr:     (.subject.url | split("/") | last)
  }] | .[] | "\(.id)\t\(.reason)\t\(.pr)"
' 2>/dev/null || true)

[ -z "$notif_tsv" ] && { echo "" > "$CONFIG/pending_notifs"; exit 0; }

# Keep only notifications on YOUR PRs
my_notif_tsv=""
while IFS=$'\t' read -r id reason pr; do
    if echo " $my_prs " | grep -qw "$pr"; then
        my_notif_tsv+="$id"$'\t'"$reason"$'\t'"$pr"$'\n'
    fi
done <<< "$notif_tsv"

# Write current unread count for the menu bar icon
pending=$(echo "$my_notif_tsv" | grep -c . 2>/dev/null || echo 0)
[ -z "$my_notif_tsv" ] && pending=0
echo "$pending" > "$CONFIG/pending_count"

# Write pr:reason pairs so the menu bar can list them in the dropdown
echo "$my_notif_tsv" | awk -F'\t' 'NF>=3 && $3!="" && !seen[$3]++ {print $3":"$2}' \
    > "$CONFIG/pending_notifs"

[ -z "$my_notif_tsv" ] && exit 0

# Which IDs are new (not seen before)?
current_ids=$(echo "$my_notif_tsv" | awk -F'\t' '{print $1}' | sort)
new_ids=$(comm -23 <(echo "$current_ids") <(sort "$SEEN_FILE"))

# Always update seen file with current IDs
echo "$current_ids" > "$SEEN_FILE"

[ -z "$new_ids" ] && exit 0

# Collect unique PRs with the first reason seen for each
new_count=$(echo "$new_ids" | grep -c .)
active_prs=()
active_pr_ids=()
while IFS=$'\t' read -r id reason pr; do
    if echo "$new_ids" | grep -qF "$id"; then
        if ! printf '%s\n' "${active_pr_ids[@]}" | grep -qx "$pr"; then
            active_pr_ids+=("$pr")
            active_prs+=("${pr}:${reason}")
        fi
    fi
done <<< "$my_notif_tsv"

active_pr_list=$(IFS=','; echo "${active_prs[*]}")

# Show the cat — pass all active PR numbers so it can show them and tap correctly
swift "$DIR/woo_cat.swift" 0 0 0 "$CAT" "$active_pr_list" 0 0 0 "$new_count"
