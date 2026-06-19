#!/bin/bash
# tests/test_watch_sh.sh
# Tests pure helper functions extracted from watch.sh: state-file line
# parsers and serializers must handle both legacy bare-number lines and
# new qualified-ref lines.

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$DIR/.."
source "$ROOT/watch.sh" --source-only

fail() { echo "FAIL: $1"; exit 1; }

# 1. parse_pr_ref: accepts qualified refs, returns "OWNER REPO NUMBER" tuples
[ "$(parse_pr_ref 'woocommerce/woocommerce#12345')" = "woocommerce woocommerce 12345" ] \
    || fail "qualified ref parse"
[ "$(parse_pr_ref '12345')" = "" ] || fail "legacy bare-number must return empty (skipped)"
[ "$(parse_pr_ref '')" = "" ] || fail "empty line must return empty"
[ "$(parse_pr_ref 'garbage')" = "" ] || fail "garbage line must return empty"

# 2. read_qualified_refs handles missing file gracefully (returns nothing, exit 0)
out=$(read_qualified_refs "/nonexistent/path/that/does/not/exist")
[ -z "$out" ] || fail "read_qualified_refs on missing file should return empty, got: '$out'"

# 3. read_qualified_refs: filters legacy lines from a state file
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
printf '%s\n' "woocommerce/woocommerce#1" "12345" "" "annchichi/catwatchpr#7" "garbage" > "$TMP"
out=$(read_qualified_refs "$TMP" | tr '\n' ' ')
[ "$out" = "woocommerce/woocommerce#1 annchichi/catwatchpr#7 " ] \
    || fail "read_qualified_refs filtered output, got: '$out'"

# 4. notif_key: composite of stable thread id + updated_at timestamp
[ "$(notif_key 24085618242 2026-06-04T02:34:06Z)" = "24085618242@2026-06-04T02:34:06Z" ] \
    || fail "notif_key composite"

# 5. notif_keys: emits sorted "id@updated" keys, skipping rows missing updated_at
out=$(printf '%s\t%s\t%s\t%s\n' \
        24085618242 assign woocommerce/woocommerce-shipping#1604 2026-06-04T02:34:06Z \
    | notif_keys)
[ "$out" = "24085618242@2026-06-04T02:34:06Z" ] || fail "notif_keys basic, got: '$out'"

# 6. REGRESSION: the same thread id with a newer updated_at must produce a
#    DISTINCT key. GitHub reuses one thread id for all activity on a PR, so a
#    bare-id dedup suppressed replies on an already-seen PR (the Sam-reply bug).
old_key=$(printf '%s\t%s\t%s\t%s\n' \
        24085618242 assign woocommerce/woocommerce-shipping#1604 2026-06-04T02:20:00Z | notif_keys)
new_key=$(printf '%s\t%s\t%s\t%s\n' \
        24085618242 assign woocommerce/woocommerce-shipping#1604 2026-06-04T02:34:06Z | notif_keys)
[ "$old_key" != "$new_key" ] \
    || fail "notif_keys must differ when updated_at advances on the same thread id"

# 7. CI passing is not the same as GitHub saying the PR can merge. If reviews
#    are still blocking, do not tell the user the PR is clear to merge.
msg=$(ci_pass_message "woocommerce/woocommerce#64564" "CHANGES_REQUESTED" "BLOCKED" "false")
[ "$msg" = "✅ PR woocommerce/woocommerce#64564 checks passed; review still needed" ] \
    || fail "ci_pass_message should mention review still needed, got: '$msg'"

msg=$(ci_pass_message "woocommerce/woocommerce#64564" "APPROVED" "CLEAN" "false")
[ "$msg" = "✅ PR woocommerce/woocommerce#64564 is clear to merge!" ] \
    || fail "ci_pass_message should say clear only when approved and clean, got: '$msg'"

# 8. Reviewer-requested PRs get wording that explains the action for you.
msg=$(ci_review_message "woocommerce/woocommerce#64564" 0)
[ "$msg" = "✅ PR woocommerce/woocommerce#64564 checks passed; ready for your review" ] \
    || fail "ci_review_message pass wording, got: '$msg'"

msg=$(ci_review_message "woocommerce/woocommerce#64564" 1)
[ "$msg" = "❌ PR woocommerce/woocommerce#64564 has failing checks; review may need to wait" ] \
    || fail "ci_review_message fail wording, got: '$msg'"

echo "PASS: watch.sh helper tests"
