#!/bin/bash

# Woo Sprinkles — watch for activity on YOUR PRs
# Run every 5 minutes via launchd.

# Allow tests to source us without running the orchestration body.
# Pass --source-only as the first argument to define helpers and return.
SOURCE_ONLY=0
if [ "${1:-}" = "--source-only" ]; then
    SOURCE_ONLY=1
fi

# Parse a state-file line. Echoes "OWNER REPO NUMBER" for qualified refs
# (owner/repo#N), or empty for legacy or invalid input.
parse_pr_ref() {
    local line="$1"
    if [[ "$line" =~ ^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)#([0-9]+)$ ]]; then
        echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
    fi
}

# Read a state file and emit only lines that parse as qualified refs.
read_qualified_refs() {
    local file="$1"
    [ -f "$file" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        if [ -n "$(parse_pr_ref "$line")" ]; then
            echo "$line"
        fi
    done < "$file"
}

# Build a notification dedup key. A GitHub notification thread id is stable for
# the life of the PR — the SAME id covers the assignment, every review, and
# every reply. Deduping on the bare id therefore suppresses all activity after
# the first event we saw. Combine the id with updated_at so a re-surfaced thread
# (new reply -> newer updated_at) yields a different key and re-notifies.
notif_key() {
    echo "${1}@${2}"
}

# Read a notif tsv (id\treason\tref\tupdated) on stdin, emit sorted dedup keys.
# Rows missing the updated_at column are skipped (cannot be deduped safely).
notif_keys() {
    awk -F'\t' 'NF>=4 && $4!="" {print $1"@"$4}' | sort
}

ci_pass_message() {
    local ref="$1" review_decision="${2:-}" merge_state="${3:-}" is_draft="${4:-false}"

    if [ "$is_draft" = "true" ]; then
        echo "✅ PR $ref checks passed; still a draft"
    elif [ "$review_decision" = "APPROVED" ] && [ "$merge_state" = "CLEAN" ]; then
        echo "✅ PR $ref is clear to merge!"
    elif [ "$merge_state" = "BLOCKED" ] || [ "$review_decision" = "REVIEW_REQUIRED" ] || [ "$review_decision" = "CHANGES_REQUESTED" ]; then
        echo "✅ PR $ref checks passed; review still needed"
    elif [ -n "$review_decision$merge_state" ]; then
        echo "✅ PR $ref checks passed; not merge-ready yet"
    else
        echo "✅ PR $ref checks passed"
    fi
}

ci_review_message() {
    local ref="$1" has_fail="${2:-0}"

    if [ "$has_fail" -gt 0 ]; then
        echo "❌ PR $ref has failing checks; review may need to wait"
    else
        echo "✅ PR $ref checks passed; ready for your review"
    fi
}

# Run a gh command. On non-zero exit, log to stderr and signal failure
# (caller should exit 0 to abort the tick without overwriting state).
# Echoes stdout on success.
gh_safe() {
    local label="$1"; shift
    local out
    out=$("$@" 2>&1)
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "watch.sh: $label failed (exit $rc): $out" >&2
        return $rc
    fi
    echo "$out"
}

# When sourced by tests, exit here without running the orchestration body.
if [ "$SOURCE_ONLY" -eq 1 ]; then
    return 0 2>/dev/null || exit 0
fi

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
    grep -Fv "${pr}:" "$INBOX_FILE" > "$INBOX_FILE.tmp" 2>/dev/null || true
    echo "${pr}:${reason}" >> "$INBOX_FILE.tmp"
    mv "$INBOX_FILE.tmp" "$INBOX_FILE"
}

# Remove a PR from the inbox (called when merged)
inbox_remove() {
    local pr="$1"
    grep -Fv "${pr}:" "$INBOX_FILE" > "$INBOX_FILE.tmp" 2>/dev/null || true
    mv "$INBOX_FILE.tmp" "$INBOX_FILE"
}

# Open PRs you authored OR are requested to review (anywhere on GitHub).
# Each line of output is "owner/repo#number". Uses `gh search prs` because
# `gh pr list` is repo-scoped — there is no global mode without --repo.
authored=$(gh_safe "search authored" \
    gh search prs --author "@me" --state open --limit 100 \
    --json number,repository \
    --jq '.[] | "\(.repository.nameWithOwner)#\(.number)"') \
    || exit 0
review_requested=$(gh_safe "search review-requested" \
    gh search prs --review-requested "@me" --state open --limit 100 \
    --json number,repository \
    --jq '.[] | "\(.repository.nameWithOwner)#\(.number)"') \
    || exit 0
authored_prs=$(printf '%s\n' "$authored" | sort -u | grep -v '^$' | tr '\n' ' ')
my_prs=$(printf '%s\n%s\n' "$authored" "$review_requested" | sort -u | grep -v '^$' | tr '\n' ' ')

# Detect merges: PRs you authored that were open last run but are gone now.
# Use read_qualified_refs so legacy (pre-v0.2.0) bare-number lines are skipped.
prev_prs=$(read_qualified_refs "$PREV_PRS_FILE" | tr '\n' ' ')
merged_prs=()
for ref in $prev_prs; do
    # Skip if ref is still in the current authored set
    if echo " $authored_prs " | grep -qw "$ref"; then continue; fi
    # Parse owner/repo#N → "owner repo N" (3 tokens)
    read -r owner name number <<< "$(parse_pr_ref "$ref")"
    [ -z "$number" ] && continue
    state=$(gh pr view "$number" --repo "$owner/$name" --json state --jq '.state' 2>/dev/null)
    if [ "$state" = "MERGED" ]; then
        merged_prs+=("$ref")
        inbox_remove "$ref"
    fi
done
echo "$authored_prs" | tr ' ' '\n' | grep -v '^$' > "$PREV_PRS_FILE"

# Celebrate merged PRs immediately
if [ ${#merged_prs[@]} -gt 0 ]; then
    merged_list=$(IFS=','; echo "${merged_prs[*]}")
    "$DIR/CatPopup" 0 0 0 "$CAT" "" 0 0 0 0 "" "$merged_list"
fi

if [ -z "$my_prs" ]; then
    exit 0
fi

# CI check monitoring — detect when running checks complete on PRs you authored
# or were requested to review. Wording differs by audience: author lifecycle
# vs reviewer readiness.
CI_FILE="$CONFIG/ci_watching"
touch "$CI_FILE"
prev_watching=$(read_qualified_refs "$CI_FILE" | tr '\n' ' ')
now_watching=""

for ref in $my_prs; do
    read -r owner name number <<< "$(parse_pr_ref "$ref")"
    [ -z "$number" ] && continue
    checks=$(gh pr checks "$number" --repo "$owner/$name" 2>/dev/null)
    [ -z "$checks" ] && continue

    has_pending=$(echo "$checks" | awk -F'\t' '$2=="pending"{c++} END{print c+0}')
    has_fail=$(echo "$checks"    | awk -F'\t' '$2=="fail"{c++} END{print c+0}')

    if [ "$has_pending" -gt 0 ]; then
        now_watching="$now_watching$ref "
    elif echo " $prev_watching " | grep -qw "$ref"; then
        # Was running last check — now finished
        if ! echo " $authored_prs " | grep -qw "$ref"; then
            reason="ci_pass"
            [ "$has_fail" -gt 0 ] && reason="ci_fail"
            inbox_upsert "$ref" "$reason"
            "$DIR/CatPopup" 0 0 0 "$CAT" "" 0 0 0 0 "$(ci_review_message "$ref" "$has_fail")"
        elif [ "$has_fail" -gt 0 ]; then
            inbox_upsert "$ref" "ci_fail"
            "$DIR/CatPopup" 0 0 0 "$CAT" "" 0 0 0 0 "❌ PR $ref has failing checks"
        else
            merge_info=$(gh pr view "$number" --repo "$owner/$name" \
                --json reviewDecision,mergeStateStatus,isDraft \
                --jq '[.reviewDecision // "", .mergeStateStatus // "", (.isDraft | tostring)] | @tsv' 2>/dev/null)
            IFS=$'\t' read -r review_decision merge_state is_draft <<< "$merge_info"
            inbox_upsert "$ref" "ci_pass"
            "$DIR/CatPopup" 0 0 0 "$CAT" "" 0 0 0 0 "$(ci_pass_message "$ref" "$review_decision" "$merge_state" "$is_draft")"
        fi
    fi
done
echo "$now_watching" | tr ' ' '\n' | grep -v '^$' > "$CI_FILE"

# Fetch ALL unread PR notifications, regardless of repo. Each row carries
# a fully-qualified ref so downstream membership checks match my_prs.
notif_tsv=$(gh_safe "api notifications" \
    gh api notifications --jq '
      [.[] | select(.unread == true and .subject.type == "PullRequest")
       | { id: .id, reason: .reason,
           ref: "\(.repository.full_name)#\(.subject.url | split("/") | last)",
           updated: .updated_at }]
      | .[] | "\(.id)\t\(.reason)\t\(.ref)\t\(.updated)"') \
    || exit 0

[ -z "$notif_tsv" ] && exit 0

# Keep only notifications on YOUR involved PRs
my_notif_tsv=""
while IFS=$'\t' read -r id reason ref updated; do
    if echo " $my_prs " | grep -qw "$ref"; then
        my_notif_tsv+="$id"$'\t'"$reason"$'\t'"$ref"$'\t'"$updated"$'\n'
    fi
done <<< "$notif_tsv"

[ -z "$my_notif_tsv" ] && exit 0

# Which notifications are new? Dedup on "id@updated" (see notif_key): the thread
# id alone is stable across a PR's whole life, so updated_at is what tells us a
# thread has fresh activity (a new reply) since we last saw it.
current_keys=$(echo "$my_notif_tsv" | notif_keys)
new_keys=$(comm -23 <(echo "$current_keys") <(sort "$SEEN_FILE"))

# Always update seen file with current keys
echo "$current_keys" > "$SEEN_FILE"

[ -z "$new_keys" ] && exit 0

# Collect unique PRs with the first reason seen for each
new_count=$(echo "$new_keys" | grep -c .)
active_prs=()
active_pr_ids=()
while IFS=$'\t' read -r id reason ref updated; do
    if echo "$new_keys" | grep -qx "$(notif_key "$id" "$updated")"; then
        if ! printf '%s\n' "${active_pr_ids[@]}" | grep -qx "$ref"; then
            active_pr_ids+=("$ref")
            active_prs+=("${ref}:${reason}")
            inbox_upsert "$ref" "$reason"
        fi
    fi
done <<< "$my_notif_tsv"

active_pr_list=$(IFS=','; echo "${active_prs[*]}")

# Show the cat — pass all active PR refs so it can show them and tap correctly
"$DIR/CatPopup" 0 0 0 "$CAT" "$active_pr_list" 0 0 0 "$new_count"
