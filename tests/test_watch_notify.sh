#!/bin/bash
# tests/test_watch_notify.sh
# End-to-end regression for the "reply on an already-seen PR" bug.
#
# A GitHub notification thread id is stable for the life of a PR — the SAME id
# covers the assignment, every review, and every reply. watch.sh used to dedup
# on the bare id, so once it had seen a PR's thread it suppressed all later
# activity (e.g. Sam replying to your review). The fix dedups on "id@updated_at".
#
# Strategy: stub `gh` and CatPopup, point HOME at a temp dir, and drive watch.sh
# through three ticks by swapping the notifications fixture between runs:
#   tick 1  assignment            -> cat MUST fire
#   tick 2  reply (same id, newer updated_at)  -> cat MUST fire again
#   tick 3  no change (identical to tick 2)    -> cat MUST stay silent

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$DIR/.."
TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

fail() { echo "FAIL: $1"; exit 1; }

REF="woocommerce/woocommerce-shipping#1604"
ID="24085618242"

# --- Lay out an isolated run dir so watch.sh finds its sibling CatPopup ---
RUN="$TMP/run"
mkdir -p "$RUN" "$TMP/bin"
cp "$ROOT/watch.sh" "$RUN/watch.sh"

# Mock CatPopup: record each invocation as one line.
POPUP_LOG="$TMP/popup.log"
: > "$POPUP_LOG"
cat > "$RUN/CatPopup" <<EOF
#!/bin/bash
echo "popup: \$*" >> "$POPUP_LOG"
EOF
chmod +x "$RUN/CatPopup"

# Mock gh: authored search returns our PR; everything else is empty/OPEN.
# The notifications fixture path is read fresh each call so we can swap it.
NOTIF_FIXTURE="$TMP/notif.tsv"
cat > "$TMP/bin/gh" <<EOF
#!/bin/bash
case "\$1 \$2" in
  "search prs")
    if printf '%s\n' "\$@" | grep -q -- '--author'; then echo "$REF"; fi
    ;;
  "pr checks") : ;;            # no CI checks
  "pr view") echo "OPEN" ;;    # merge detection (not expected to fire here)
  "api notifications") cat "$NOTIF_FIXTURE" ;;
  *) : ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/gh"

# --- Fake HOME with the bits watch.sh reads ---
export HOME="$TMP/home"
mkdir -p "$HOME/.config/woo-sprinkles"
echo "cyan" > "$HOME/.config/woo-sprinkles/cat_color"
export PATH="$TMP/bin:$PATH"

popup_count() { grep -c . "$POPUP_LOG"; }

run_tick() { ( cd "$RUN" && NOTIF_FIXTURE="$NOTIF_FIXTURE" bash "$RUN/watch.sh" ); }

# tick 1: assignment
printf '%s\t%s\t%s\t%s\n' "$ID" assign "$REF" "2026-06-04T02:20:00Z" > "$NOTIF_FIXTURE"
run_tick
[ "$(popup_count)" -eq 1 ] || fail "tick 1 (assignment) should fire once, got $(popup_count)"

# tick 2: Sam's reply — SAME thread id, newer updated_at
printf '%s\t%s\t%s\t%s\n' "$ID" assign "$REF" "2026-06-04T02:34:06Z" > "$NOTIF_FIXTURE"
run_tick
[ "$(popup_count)" -eq 2 ] || fail "tick 2 (reply on same thread id) should fire again, got $(popup_count) — the dedup bug"

# tick 3: nothing new (identical to tick 2) — must stay silent
run_tick
[ "$(popup_count)" -eq 2 ] || fail "tick 3 (no change) should stay silent, got $(popup_count) — dedup is broken"

echo "PASS: watch.sh notification dedup (re-notifies on new activity, silent on no change)"
