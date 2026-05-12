#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/R2Trans.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
SWIFT_BUILD_DIR="$BUILD_DIR/swift-build"
CODESIGN_IDENTITY="${R2TRANS_CODESIGN_IDENTITY:--}"

cd "$ROOT_DIR"

mkdir -p "$BUILD_DIR/home" "$BUILD_DIR/cache" "$BUILD_DIR/module-cache"

export HOME="$BUILD_DIR/home"
export XDG_CACHE_HOME="$BUILD_DIR/cache"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache"

swift build --scratch-path "$SWIFT_BUILD_DIR" -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp "$SWIFT_BUILD_DIR/release/R2Trans" "$MACOS_DIR/R2Trans"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>R2Trans</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.r2trans.R2Trans</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>R2Trans</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>R2Trans uses the microphone for live interpretation subtitles.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>R2Trans captures system audio so it can translate audio from videos, browsers, and calls.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_DIR" >/dev/null

echo "$APP_DIR"
