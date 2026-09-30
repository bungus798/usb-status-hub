#!/bin/bash
# Builds USB Status Hub and assembles the .app bundle in ./build.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
swiftc -parse-as-library \
    -target arm64-apple-macos13.0 \
    -O \
    Sources/USBStatusHub/*.swift \
    -o "build/USBStatusHub"

APP="build/USB Status Hub.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mv "build/USBStatusHub" "$APP/Contents/MacOS/USB Status Hub"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Built: $APP"
