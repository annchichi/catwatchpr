#!/bin/bash

# Woo Sprinkles — watch for activity on YOUR PRs
# Run every 5 minutes via launchd.

REPO="woocommerce/woocommerce"
CAT=$(cat "$HOME/.config/woo-sprinkles/cat_color" 2>/dev/null || echo "${WOO_SPRINKLES_CAT:-cyan}")
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$HOME/.config/woo-sprinkles"
SEEN_FILE="$CONFIG/seen_notif_ids"
PREV_PRS_FILE="$CONFIG/prev_open_prs"
INBOX_FILE="$CONFIG/inbox"

mkdir -p "$CONFIG"
touch "$SEEN_FILE"
touch "$PREV_PRS_FILE"
touch "$INBOX_FILE"
date +%s > "$CONFIG/last_checked"

# Upsert a PR into the persistent inbox (one entry per PR, latest reason wins)
inbox_upsert() {
    local pr="$1" reason="$2"
    grep -v "^${pr}:" "$INBOX_FILE" > "$INBOX_FILE.tmp" 2>/dev/null || true
    echo "${pr}:${reason}" >> "$INBOX_FILE.tmp"
    mv "$INBOX_FILE.tmp" "$INBOX_FILE"
}

# Remove a PR from the inbox (called when merged)
inbox_remove() {
    local pr="$1"
    grep -v "^${pr}:" "$INBOX_FILE" > "$INBOX_FILE.tmp" 2>/dev/null || true
    mv "$INBOX_FILE.tmp" "$INBOX_FILE"
}

# Get your open PR numbers
my_prs=$(gh pr list --author "@me" --repo "$REPO" --state open \
    --json number --jq '.[].number' 2>/dev/null | tr '\n' ' ')

# Detect merges: PRs that were open last run but are gone now
prev_prs=$(cat "$PREV_PRS_FILE" 2>/dev/null || echo "")
merged_prs=()
for pr in $prev_prs; do
    if ! echo " $my_prs " | grep -qw "$pr"; then
        state=$(gh pr view "$pr" --repo "$REPO" --json state --jq '.state' 2>/dev/null)
        if [ "$state" = "MERGED" ]; then
            merged_prs+=("$pr")
            inbox_remove "$pr"
        fi
    fi
done
echo "$my_prs" > "$PREV_PRS_FILE"

# Celebrate merged PRs immediately
if [ ${#merged_prs[@]} -gt 0 ]; then
    merged_list=$(IFS=','; echo "${merged_prs[*]}")
    swift "$DIR/woo_cat.swift" 0 0 0 "$CAT" "" 0 0 0 0 "" "$merged_list"
fi

if [ -z "$my_prs" ]; then
    exit 0
fi

# CI check monitoring — detect when running checks complete on any open PR
CI_FILE="$CONFIG/ci_watching"
touch "$CI_FILE"
prev_watching=$(cat "$CI_FILE" 2>/dev/null | tr '\n' ' ')
now_watching=""

for pr in $my_prs; do
    checks=$(gh pr checks "$pr" --repo "$REPO" 2>/dev/null)
    [ -z "$checks" ] && continue

    has_pending=$(echo "$checks" | awk -F'\t' '$2=="pending"{c++} END{print c+0}')
    has_fail=$(echo "$checks"    | awk -F'\t' '$2=="fail"{c++} END{print c+0}')

    if [ "$has_pending" -gt 0 ]; then
        now_watching="$now_watching$pr "
    elif echo " $prev_watching " | grep -qw "$pr"; then
        # Was running last check — now finished
        if [ "$has_fail" -gt 0 ]; then
            inbox_upsert "$pr" "ci_fail"
            swift "$DIR/woo_cat.swift" 0 0 0 "$CAT" "" 0 0 0 0 "❌ PR #$pr has failing checks" &
        else
            inbox_upsert "$pr" "ci_pass"
            swift "$DIR/woo_cat.swift" 0 0 0 "$CAT" "" 0 0 0 0 "✅ PR #$pr is clear to merge!" &
        fi
    fi
done
echo "$now_watching" > "$CI_FILE"

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

[ -z "$notif_tsv" ] && exit 0

# Keep only notifications on YOUR PRs
my_notif_tsv=""
while IFS=$'\t' read -r id reason pr; do
    if echo " $my_prs " | grep -qw "$pr"; then
        my_notif_tsv+="$id"$'\t'"$reason"$'\t'"$pr"$'\n'
    fi
done <<< "$notif_tsv"

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
            inbox_upsert "$pr" "$reason"
        fi
    fi
done <<< "$my_notif_tsv"

active_pr_list=$(IFS=','; echo "${active_prs[*]}")

# Show the cat — pass all active PR numbers so it can show them and tap correctly
swift "$DIR/woo_cat.swift" 0 0 0 "$CAT" "$active_pr_list" 0 0 0 "$new_count"
