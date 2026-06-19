#!/bin/bash
# Regression: CI pass/fail popups should describe why the PR matters to the user.
#
# If a PR only appears because the current user was requested for review, the
# cat can still surface CI status, but the wording should be review-specific:
# "ready for your review", not "clear to merge".

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$DIR/.."
TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

fail() { echo "FAIL: $1"; exit 1; }

REF="woocommerce/woocommerce#64564"

RUN="$TMP/run"
mkdir -p "$RUN" "$TMP/bin"
cp "$ROOT/watch.sh" "$RUN/watch.sh"

POPUP_LOG="$TMP/popup.log"
: > "$POPUP_LOG"
cat > "$RUN/CatPopup" <<EOF
#!/bin/bash
echo "popup: \$*" >> "$POPUP_LOG"
EOF
chmod +x "$RUN/CatPopup"

CHECKS_FIXTURE="$TMP/checks.tsv"
cat > "$TMP/bin/gh" <<EOF
#!/bin/bash
case "\$1 \$2" in
  "search prs")
    if printf '%s\n' "\$@" | grep -q -- '--review-requested'; then echo "$REF"; fi
    ;;
  "pr checks") cat "$CHECKS_FIXTURE" ;;
  "pr view") printf 'CHANGES_REQUESTED\tBLOCKED\tfalse\n' ;;
  "api notifications") : ;;
  *) : ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/gh"

export HOME="$TMP/home"
mkdir -p "$HOME/.config/woo-sprinkles"
echo "pink" > "$HOME/.config/woo-sprinkles/cat_color"
export PATH="$TMP/bin:$PATH"

run_tick() { ( cd "$RUN" && CHECKS_FIXTURE="$CHECKS_FIXTURE" bash "$RUN/watch.sh" ); }

printf 'build\tpending\n' > "$CHECKS_FIXTURE"
run_tick
[ ! -s "$POPUP_LOG" ] || fail "pending reviewer-requested PR should not fire a popup yet"

printf 'build\tpass\n' > "$CHECKS_FIXTURE"
run_tick
grep -q "checks passed; ready for your review" "$POPUP_LOG" \
    || fail "reviewer-requested PR should get review-specific CI popup; got: $(cat "$POPUP_LOG")"
if grep -q "clear to merge" "$POPUP_LOG"; then
    fail "reviewer-requested PR should not claim clear to merge"
fi

echo "PASS: reviewer-requested PRs get review-specific CI popups"
