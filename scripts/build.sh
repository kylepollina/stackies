#!/bin/bash
# Builds build/Stackies.app. Pass --install to also copy it into /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Stackies.app

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Stackies"

if [ ! -f build/AppIcon.icns ]; then
    mkdir -p build/AppIcon.iconset
    swift scripts/make-icon.swift build/icon-1024.png
    for size in 16 32 128 256 512; do
        sips -z $size $size build/icon-1024.png --out build/AppIcon.iconset/icon_${size}x${size}.png >/dev/null
        sips -z $((size * 2)) $((size * 2)) build/icon-1024.png --out build/AppIcon.iconset/icon_${size}x${size}@2x.png >/dev/null
    done
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Stackies"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" >/dev/null

echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
    rm -rf /Applications/Stackies.app
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/Stackies.app"
fi
