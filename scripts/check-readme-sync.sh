#!/bin/bash
# Check that README.md (English) and README.ja.md (Japanese) are kept in sync.
#
#   scripts/check-readme-sync.sh [base]   (default: HEAD)
#
# 1. If one README changed since the merge base of <base> and HEAD (including uncommitted
#    and untracked changes), the other must have changed too.
#    Use --structure-only EN_FILE JA_FILE to compare an exported snapshot without Git.
# 2. Both files must have the same skeleton: headings, list items (with indentation),
#    table rows, and code blocks (comments after `#` are ignored, since they are translated).
set -euo pipefail

cd "$(dirname "$0")/.."

structure_only=0
if [[ "${1:-}" == --structure-only ]]; then
    [[ $# == 3 ]] || { echo 'Usage: check-readme-sync.sh --structure-only EN_FILE JA_FILE' >&2; exit 2; }
    structure_only=1
    en="$2"
    ja="$3"
else
    en=README.md
    ja=README.ja.md
fi
base="${1:-HEAD}"

for f in "$en" "$ja"; do
    if [[ ! -f "$f" ]]; then
        echo "$f not found" >&2
        exit 1
    fi
done

if [[ "$structure_only" == 0 ]]; then
since="$(git merge-base "$base" HEAD)"
changed="$(
    git diff --name-only "$since" -- "$en" "$ja"
    git ls-files --others --exclude-standard -- "$en" "$ja"
)"
en_changed=$(grep -cxF "$en" <<<"$changed" || true)
ja_changed=$(grep -cxF "$ja" <<<"$changed" || true)
if [[ "$en_changed" != "$ja_changed" ]]; then
    if [[ "$en_changed" -gt 0 ]]; then
        echo "$en changed but $ja did not (since $since). Update both." >&2
    else
        echo "$ja changed but $en did not (since $since). Update both." >&2
    fi
    exit 1
fi

fi

skeleton() {
    awk '
        /^[[:space:]]*```/ { in_code = !in_code; sub(/^[[:space:]]*/, ""); print "fence " $0; next }
        in_code { sub(/[[:space:]]*#.*$/, ""); sub(/[[:space:]]+$/, ""); print "code " $0; next }
        /^#+ / { match($0, /^#+/); print "heading " substr($0, 1, RLENGTH); next }
        /^[[:space:]]*([-*]|[0-9]+\.) / { match($0, /^[[:space:]]*/); print "list indent=" RLENGTH; next }
        /^[[:space:]]*\|/ { print "table"; next }
    ' "$1"
}

if ! diff -u --label "$en" --label "$ja" <(skeleton "$en") <(skeleton "$ja"); then
    echo "$en and $ja differ in structure (headings, list items, table rows, or code blocks)." >&2
    exit 1
fi

echo "$en and $ja are in sync"
