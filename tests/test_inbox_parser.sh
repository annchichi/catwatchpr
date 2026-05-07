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

# Malformed lines that previously crashed the parser.
INBOX="$TMPCONFIG/.config/woo-sprinkles/inbox"
mkdir -p "$(dirname "$INBOX")"
cat > "$INBOX" <<'EOF'

:
:foo
foo:
foo:bar:baz
12345:comment
EOF

# Extract the inboxNotifs() body verbatim from menubar.swift.
# sed -n '/^func inboxNotifs/,/^}/p' captures from the function signature
# through the closing brace at column 0.
PARSER_BODY="$(sed -n '/^func inboxNotifs/,/^}/p' "$ROOT/menubar.swift")"

# Build a Foundation-only harness that:
#   1. Reads the inbox file path from argv[1].
#   2. Runs the extracted parser body.
#   3. Exits 0 on success, or fatally traps (exit non-zero) on the pre-fix bug.
cat > "$TMPHARNESS" <<SWIFT
import Foundation

let configDir = URL(fileURLWithPath: CommandLine.arguments[1])

${PARSER_BODY}

// Exercise the parser — this traps on the pre-fix bug.
let notifs = inboxNotifs()
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
