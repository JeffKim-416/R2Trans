#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/R2Trans.app"
INSTALL_DIR="/Applications/R2Trans.app"

"$ROOT_DIR/Scripts/build_app.sh" >/dev/null

rm -rf "$INSTALL_DIR"
ditto "$APP_DIR" "$INSTALL_DIR"
xattr -dr com.apple.quarantine "$INSTALL_DIR" 2>/dev/null || true

open "$INSTALL_DIR"
echo "$INSTALL_DIR"
