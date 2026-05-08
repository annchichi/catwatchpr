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

echo "PASS: watch.sh helper tests"
