#!/bin/bash
# Fails when a source comment still contains Japanese text.
# Covers Swift comments, localization resource comments, and published shell scripts.
set -euo pipefail

cd "$(dirname "$0")/.."

japanese='[\p{Hiragana}\p{Katakana}\p{Han}]'
status=0

report() {
    echo "Japanese text found in $1" >&2
    status=1
}

if rg -n --pcre2 "^\s*//.*$japanese" Sources Tests --glob '*.swift'; then
    report "Swift comments"
fi

if rg -n --pcre2 "^\s*(/\*|\*).*$japanese" Sources Tests --glob '*.swift'; then
    report "Swift block comments"
fi

if rg -n --pcre2 "^\s*(/\*|<!--).*$japanese" Sources/FolzioLocalization/Resources; then
    report "localization resource comments"
fi

if rg -n --pcre2 "^\s*//.*$japanese" Package.swift; then
    report "Package.swift comments"
fi

if rg -n --pcre2 "^\s*#.*$japanese" scripts/check-*.sh scripts/make-*.sh; then
    report "published shell script comments"
fi

if ((status != 0)); then
    exit 1
fi

echo "source comments are English-only"
