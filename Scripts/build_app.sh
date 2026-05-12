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

normalize_marketing_version() {
    local raw_version="$1"
    local version="${raw_version#v}"

    if [[ ! "$version" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]]; then
        echo "Invalid R2Trans version '$raw_version'. Expected vX.Y.Z or X.Y.Z." >&2
        exit 1
    fi

    echo "$version"
}

resolve_app_version() {
    local exact_tag=""

    if [[ -n "${R2TRANS_VERSION:-}" ]]; then
        normalize_marketing_version "$R2TRANS_VERSION"
        return
    fi

    exact_tag="$(git describe --tags --exact-match --match 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null || true)"
    if [[ -n "$exact_tag" ]]; then
        normalize_marketing_version "$exact_tag"
        return
    fi

    normalize_marketing_version "${R2TRANS_DEFAULT_VERSION:-0.1.0}"
}

APP_VERSION="$(resolve_app_version)"
APP_BUILD_VERSION="${R2TRANS_BUILD_VERSION:-$APP_VERSION}"

if [[ ! "$APP_BUILD_VERSION" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
    echo "Invalid R2Trans build version '$APP_BUILD_VERSION'. Expected a numeric build version." >&2
    exit 1
fi

mkdir -p "$BUILD_DIR/home" "$BUILD_DIR/cache" "$BUILD_DIR/module-cache"

export HOME="$BUILD_DIR/home"
export XDG_CACHE_HOME="$BUILD_DIR/cache"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache"

swift build --scratch-path "$SWIFT_BUILD_DIR" -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp "$SWIFT_BUILD_DIR/release/R2Trans" "$MACOS_DIR/R2Trans"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
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
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_BUILD_VERSION</string>
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
