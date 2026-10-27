#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

resources="Sources/FixtureKit/Resources"
mkdir -p "$resources"

if ! command -v cwebp >/dev/null 2>&1 || ! command -v img2webp >/dev/null 2>&1; then
    echo "cwebp and img2webp are required (brew install webp)" >&2
    exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/render.swift" <<'SWIFT'
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

func writePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("cannot create destination \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("cannot write \(url.path)")
    }
}

func makeImage(width: Int, height: Int, index: Int) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("cannot create context")
    }

    let palette: [(CGFloat, CGFloat, CGFloat)] = [
        (0.20, 0.50, 0.85),
        (0.85, 0.40, 0.25),
        (0.25, 0.70, 0.45),
        (0.70, 0.45, 0.80),
        (0.90, 0.75, 0.25),
        (0.30, 0.75, 0.80),
    ]
    let color = palette[index % palette.count]
    context.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.5)
    let inset = CGFloat(min(width, height)) * 0.2
    context.fillEllipse(in: CGRect(
        x: inset + CGFloat(index) * inset * 0.4,
        y: inset,
        width: CGFloat(width) - inset * 2,
        height: CGFloat(height) - inset * 2
    ))

    guard let image = context.makeImage() else {
        fatalError("cannot create image")
    }
    return image
}

writePNG(makeImage(width: 320, height: 240, index: 0), to: directory.appendingPathComponent("static.png"))
for index in 0..<6 {
    writePNG(
        makeImage(width: 160, height: 120, index: index),
        to: directory.appendingPathComponent("frame\(index).png")
    )
}
SWIFT

swift "$tmp/render.swift" "$tmp"

cwebp -quiet -q 70 "$tmp/static.png" -o "$resources/static.webp"
img2webp -d 120 -loop 0 \
    "$tmp/frame0.png" "$tmp/frame1.png" "$tmp/frame2.png" \
    "$tmp/frame3.png" "$tmp/frame4.png" "$tmp/frame5.png" \
    -o "$resources/animated.webp"

for file in "$resources/static.webp" "$resources/animated.webp"; do
    size="$(stat -f%z "$file")"
    echo "$file: $size bytes"
    if [ "$size" -gt 10240 ]; then
        echo "$file exceeds 10KB" >&2
        exit 1
    fi
done
