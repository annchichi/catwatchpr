#!/bin/bash
# Regression tests for automatic update prompt gating.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$DIR/.."
TMPHARNESS="$(mktemp).swift"
TMPSTDERR="$(mktemp)"

cleanup() { rm -f "$TMPHARNESS" "$TMPSTDERR"; }
trap cleanup EXIT

fail() { echo "FAIL: $1"; exit 1; }

VERSION_HELPER="$(sed -n '/^func isNewerVersion/,/^}/p' "$ROOT/menubar.swift")"
PROMPT_HELPER="$(sed -n '/^func shouldAutoPromptUpdate/,/^}/p' "$ROOT/menubar.swift")"

cat > "$TMPHARNESS" <<SWIFT
import Foundation

${VERSION_HELPER}

${PROMPT_HELPER}

func expect(_ condition: Bool, _ message: String) {
    if !condition {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

expect(shouldAutoPromptUpdate(remote: "0.2.9", local: "0.2.8", lastPrompted: nil),
       "newer unprompted version should auto-prompt")
expect(!shouldAutoPromptUpdate(remote: "0.2.9", local: "0.2.8", lastPrompted: "0.2.9"),
       "same previously prompted version should not auto-prompt")
expect(!shouldAutoPromptUpdate(remote: "0.2.8", local: "0.2.8", lastPrompted: nil),
       "equal version should not auto-prompt")
expect(!shouldAutoPromptUpdate(remote: "0.2.7", local: "0.2.8", lastPrompted: nil),
       "older version should not auto-prompt")

print("PASS: update prompt gating")
SWIFT

if swift "$TMPHARNESS" 2>"$TMPSTDERR"; then
    exit 0
else
    cat "$TMPSTDERR"
    fail "update prompt gating failed"
fi
