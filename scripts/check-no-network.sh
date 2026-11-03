#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

# The only URL literal allowed in Sources: the public repository link shown by the About dialog (TAK-45).
# The app never requests it; it only hands the URL to the OS, which opens it in the default web browser.
# A line is allowed only when it is in this file and contains exactly this literal.
allowed_file='Sources/FolzioCore/About/AboutInfo.swift'
allowed_literal='"https://github.com/yoshidax/folzio"'

matches=$(
    grep -rnE 'URLSession|NWConnection|import[[:space:]]+Network|\bhttp\b|https?://' Sources --include='*.swift' |
        awk -v file="$allowed_file" -v literal="$allowed_literal" \
            'index($0, file ":") == 1 && index($0, literal) { next } { print }' || true
)

if [[ -n "$matches" ]]; then
    echo "$matches"
    echo "network API reference found in Sources" >&2
    exit 1
fi

echo "no network API references in Sources"
