#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

if grep -rnE 'URLSession|NWConnection|import[[:space:]]+Network|\bhttp\b|https?://' Sources --include='*.swift'; then
    echo "network API reference found in Sources" >&2
    exit 1
fi

echo "no network API references in Sources"
