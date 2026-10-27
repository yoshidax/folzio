#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release --product make-icon
bin_dir="$(swift build -c release --product make-icon --show-bin-path)"

raw=".build/AppIcon.raw"
iconset=".build/AppIcon.iconset"

rm -rf "$raw" "$iconset"
mkdir -p "$iconset"

"$bin_dir/make-icon" "$raw"

copy_slot() {
    cp "$raw/icon_${1}x${1}.png" "$iconset/$2"
}

copy_slot 16 icon_16x16.png
copy_slot 32 icon_16x16@2x.png
copy_slot 32 icon_32x32.png
copy_slot 64 icon_32x32@2x.png
copy_slot 128 icon_128x128.png
copy_slot 256 icon_128x128@2x.png
copy_slot 256 icon_256x256.png
copy_slot 512 icon_256x256@2x.png
copy_slot 512 icon_512x512.png
copy_slot 1024 icon_512x512@2x.png

check_size() {
    local file="$iconset/$1"
    local expected="$2"
    local width
    local height

    width="$(sips -g pixelWidth "$file" | awk '/pixelWidth/ {print $2}')"
    height="$(sips -g pixelHeight "$file" | awk '/pixelHeight/ {print $2}')"

    if [[ "$width" != "$expected" || "$height" != "$expected" ]]; then
        echo "make-icon: $1 is ${width}x${height}, expected ${expected}x${expected}" >&2
        exit 1
    fi
}

check_size icon_16x16.png 16
check_size icon_16x16@2x.png 32
check_size icon_32x32.png 32
check_size icon_32x32@2x.png 64
check_size icon_128x128.png 128
check_size icon_128x128@2x.png 256
check_size icon_256x256.png 256
check_size icon_256x256@2x.png 512
check_size icon_512x512.png 512
check_size icon_512x512@2x.png 1024

iconutil -c icns "$iconset" -o .build/AppIcon.icns

echo "created .build/AppIcon.icns"
