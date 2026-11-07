#!/bin/bash
# Build and verify an isolated arm64 application from a prepared source snapshot.
set -euo pipefail
[[ $# == 4 ]] || { echo 'Usage: package-release.sh VERSION BUILD_NUMBER SOURCE_DIR OUTPUT_DIR' >&2; exit 2; }
version="$1"
build="$2"
source_dir="$(cd "$3" && pwd -P)"
output="$4"
script_dir="$(cd "$(dirname "$0")" && pwd -P)"
python3 "$script_dir/release.py" numbers "$version" "$build"
[[ "$(uname -m)" == arm64 ]] || { echo 'Release builds require Apple silicon' >&2; exit 1; }
[[ ! -e "$output" && ! -L "$output" ]] || { echo 'Output already exists' >&2; exit 1; }
mkdir -p "$(dirname "$output")"
output="$(cd "$(dirname "$output")" && pwd -P)/$(basename "$output")"
tmp="$(mktemp -d "$(dirname "$output")/.package.XXXXXX")"
created=0
cleanup() {
    rm -rf "$tmp"
    if [[ "$created" == 1 ]]; then rm -rf "$output"; fi
}
trap cleanup EXIT
# Exclude previous build state even when this is called after the candidate tests.
python3 - "$source_dir" "$tmp/source" <<'PY'
import shutil, sys
shutil.copytree(sys.argv[1], sys.argv[2], symlinks=True,
                ignore=shutil.ignore_patterns('.git', '.build', '__pycache__'))
PY
(cd "$tmp/source" && FOLZIO_VERSION="$version" FOLZIO_BUILD_NUMBER="$build" FOLZIO_ARCH=arm64 bash scripts/make-app.sh)
verify() {
    local app="$1"
    # Bash 3.2 does not consistently apply errexit to conditional commands inside functions.
    [[ "$(lipo -archs "$app/Contents/MacOS/Folzio")" == arm64 ]] || { echo 'ZIP executable must be arm64-only' >&2; return 1; }
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" == "$version" ]] || { echo 'App version mismatch' >&2; return 1; }
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" == "$build" ]] || { echo 'App build number mismatch' >&2; return 1; }
    for language in en ja; do
        test -s "$app/Contents/Resources/$language.lproj/Localizable.strings" || return 1
        test -s "$app/Contents/Resources/$language.lproj/Localizable.stringsdict" || return 1
    done
    codesign --verify --deep --strict "$app"
}
app="$tmp/source/.build/Folzio.app"
verify "$app"
mkdir "$tmp/result" "$tmp/unpacked"
asset="Folzio-v$version-macos-arm64.zip"
ditto -c -k --norsrc --keepParent "$app" "$tmp/result/$asset"
ditto -x -k "$tmp/result/$asset" "$tmp/unpacked"
verify "$tmp/unpacked/Folzio.app"
(cd "$tmp/result" && shasum -a 256 "$asset" > SHA256SUMS)
python3 "$script_dir/release.py" assets "$tmp/result" "$version"
mkdir "$output"
created=1
mv "$tmp/result/$asset" "$tmp/result/SHA256SUMS" "$output/"
created=0
echo "Packaged $asset"
