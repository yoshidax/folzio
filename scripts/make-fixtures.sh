#!/bin/bash
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "usage: scripts/make-fixtures.sh <output-directory> [--big]" >&2
    exit 2
fi

output="$1"
shift
mkdir -p "$output"

cd "$(dirname "$0")/.."
swift run make-fixtures "$output" "$@"
