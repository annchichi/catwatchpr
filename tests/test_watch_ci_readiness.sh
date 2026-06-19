#!/bin/bash
# Regression: passing CI checks must not be described as "clear to merge" when
# GitHub says reviews or merge requirements are still blocking the PR.

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
    if printf '%s\n' "\$@" | grep -q -- '--author'; then echo "$REF"; fi
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
[ ! -s "$POPUP_LOG" ] || fail "pending checks should not fire a popup"

printf 'build\tpass\n' > "$CHECKS_FIXTURE"
run_tick

if grep -q "clear to merge" "$POPUP_LOG"; then
    fail "popup incorrectly claimed PR was clear to merge"
fi
grep -q "checks passed; review still needed" "$POPUP_LOG" \
    || fail "popup should say review still needed; got: $(cat "$POPUP_LOG")"

echo "PASS: CI pass popup respects GitHub merge/review state"
