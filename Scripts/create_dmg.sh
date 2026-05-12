#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/R2Trans.app"
DMG_ROOT_DIR="$BUILD_DIR/dmg-root"
DMG_PATH="$BUILD_DIR/R2Trans.dmg"

"$ROOT_DIR/Scripts/build_app.sh" >/dev/null

rm -rf "$DMG_ROOT_DIR" "$DMG_PATH"
mkdir -p "$DMG_ROOT_DIR"

ditto "$APP_DIR" "$DMG_ROOT_DIR/R2Trans.app"
ln -s /Applications "$DMG_ROOT_DIR/Applications"

hdiutil create \
    -volname "R2Trans" \
    -srcfolder "$DMG_ROOT_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

echo "$DMG_PATH"
