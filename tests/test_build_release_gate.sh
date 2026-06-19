#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

set +e
OUTPUT=$(
    CATWATCHPR_SIGN_IDENTITY= \
    CATWATCHPR_NOTARY_PROFILE= \
    bash "$DIR/build_app.sh" --release 2>&1
)
STATUS=$?
set -e

[ "$STATUS" -ne 0 ] || fail "--release succeeded without signing credentials"

echo "$OUTPUT" | grep -q "CATWATCHPR_SIGN_IDENTITY" \
    || fail "--release error did not explain the missing signing identity"

if echo "$OUTPUT" | grep -q "Cleaning previous build"; then
    fail "--release started building before validating release credentials"
fi

echo "PASS: release builds are blocked until signing and notarization are configured."
