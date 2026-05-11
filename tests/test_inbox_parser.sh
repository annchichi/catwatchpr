#!/bin/bash
# Smoke test: menubar.swift must not crash on malformed inbox lines.
#
# Strategy: extract the inboxNotifs() parser logic from menubar.swift into a
# Foundation-only harness (no AppKit) so Swift's default exception handler
# terminates the process on a fatal error — enabling exit-code detection.
# AppKit's exception handler intercepts fatal errors and keeps the process alive
# (routing them to .ips crash reports instead), so running the full menubar.swift
# and checking process aliveness is not a reliable detection method.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$DIR/.."
TMPCONFIG="$(mktemp -d)"
TMPSTDERR="$(mktemp)"
TMPHARNESS="$(mktemp).swift"

cleanup() { rm -rf "$TMPCONFIG" "$TMPSTDERR" "$TMPHARNESS"; }
trap cleanup EXIT

# Lines covering both old and new formats, plus malformed variants.
INBOX="$TMPCONFIG/.config/woo-sprinkles/inbox"
mkdir -p "$(dirname "$INBOX")"
cat > "$INBOX" <<'EOF'

:
:foo
foo:
foo:bar:baz
12345:comment
woocommerce/woocommerce#999:review_requested
annchichi/catwatchpr#1:mention
:owner/repo#1
owner/repo#abc:bad_number
EOF

# Extract InboxEntry struct + PRMenuInfo class + inboxNotifs() from menubar.swift.
# STRUCT_BODY: everything from 'struct InboxEntry' up to (not including) 'func inboxNotifs'.
# FUNC_BODY  : the inboxNotifs() function through its closing ^} brace.
STRUCT_BODY="$(awk '/^struct InboxEntry/{p=1} /^func inboxNotifs/{p=0} p' "$ROOT/menubar.swift")"
FUNC_BODY="$(sed -n '/^func inboxNotifs/,/^}/p' "$ROOT/menubar.swift")"
PARSER_BODY="${STRUCT_BODY}
${FUNC_BODY}"

# Build a Foundation-only harness that:
#   1. Reads the inbox file path from argv[1].
#   2. Defines the InboxEntry type and inboxNotifs() extracted from menubar.swift.
#   3. Exits 0 on success, or fatally traps (exit non-zero) on any fatal error.
cat > "$TMPHARNESS" <<SWIFT
import Foundation

let configDir = URL(fileURLWithPath: CommandLine.arguments[1])

${PARSER_BODY}

// Exercise the parser — this traps on the pre-fix bug.
let notifs = inboxNotifs()
guard notifs.count == 3 else {
    fputs("FAIL: expected 3 entries, got \(notifs.count)\n", stderr)
    exit(1)
}
print("parsed \(notifs.count) notif(s)")
SWIFT

# Run the harness (no AppKit — Swift's own exception handler will terminate it).
swift "$TMPHARNESS" "$(dirname "$INBOX")" >/dev/null 2>"$TMPSTDERR"
EXIT=$?

if [ "$EXIT" -eq 0 ]; then
    echo "PASS: menubar.swift survived malformed inbox (parser exited 0)."
    exit 0
else
    echo "FAIL: menubar.swift parser crashed on malformed inbox (exit $EXIT)."
    echo "----- last 20 lines of stderr -----"
    tail -20 "$TMPSTDERR" 2>/dev/null
    exit 1
fi
