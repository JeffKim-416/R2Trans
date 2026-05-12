#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/R2Trans.app"
DMG_PATH="$BUILD_DIR/R2Trans.dmg"

"$ROOT_DIR/Scripts/build_app.sh" >/dev/null

rm -f "$DMG_PATH"
hdiutil create \
    -volname "R2Trans" \
    -srcfolder "$APP_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

echo "$DMG_PATH"
