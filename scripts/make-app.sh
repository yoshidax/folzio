#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

version="${FOLZIO_VERSION:-0.1.0}"
build_number="${FOLZIO_BUILD_NUMBER:-1}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$build_number" =~ ^[0-9]+$ ]]; then
    echo "Invalid app version or build number" >&2
    exit 1
fi

if [[ -n "${FOLZIO_ARCH:-}" && "$FOLZIO_ARCH" != arm64 ]]; then
    echo "Unsupported release architecture: $FOLZIO_ARCH" >&2
    exit 1
fi

if [[ "${FOLZIO_ARCH:-}" == arm64 ]]; then
    swift build -c release --arch arm64 --product FolzioApp
else
    swift build -c release --product FolzioApp
fi

app=".build/Folzio.app"

rm -rf "$app"

scripts/make-icon.sh

if [[ "${FOLZIO_ARCH:-}" == arm64 ]]; then
    bin_dir="$(swift build -c release --arch arm64 --product FolzioApp --show-bin-path)"
else
    bin_dir="$(swift build -c release --product FolzioApp --show-bin-path)"
fi

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

cp "$bin_dir/FolzioApp" "$app/Contents/MacOS/Folzio"
chmod +x "$app/Contents/MacOS/Folzio"

cp .build/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

localization_bundle="$bin_dir/Folzio_FolzioLocalization.bundle/Contents/Resources"
for language in ja en; do
    source_dir="$localization_bundle/$language.lproj"
    if [ ! -f "$source_dir/Localizable.strings" ] || [ ! -f "$source_dir/Localizable.stringsdict" ]; then
        echo "翻訳リソースがありません: $source_dir" >&2
        rm -rf "$app"
        exit 1
    fi
    mkdir -p "$app/Contents/Resources/$language.lproj"
    cp "$source_dir"/Localizable.* "$app/Contents/Resources/$language.lproj/"
done

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Folzio</string>
    <key>CFBundleIdentifier</key>
    <string>local.folzio.Folzio</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>ja</string>
        <string>en</string>
    </array>
    <key>CFBundleName</key>
    <string>Folzio</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>APP_VERSION_PLACEHOLDER</string>
    <key>CFBundleVersion</key>
    <string>APP_BUILD_PLACEHOLDER</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$app/Contents/Info.plist"
codesign --force --sign - "$app"

echo "created $app"
