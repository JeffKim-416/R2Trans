#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/R2Trans.app"
APP_ARCHIVE="$BUILD_DIR/R2Trans-notarization.zip"
DMG_ROOT_DIR="$BUILD_DIR/dmg-root"
DMG_PATH="$BUILD_DIR/R2Trans.dmg"

CODESIGN_IDENTITY="${R2TRANS_CODESIGN_IDENTITY:-}"
ALLOW_ADHOC="${R2TRANS_ALLOW_ADHOC:-0}"
REQUIRE_DISTRIBUTION="${R2TRANS_REQUIRE_DISTRIBUTION:-0}"
NOTARY_PROFILE="${R2TRANS_NOTARY_PROFILE:-}"
NOTARY_KEYCHAIN="${R2TRANS_NOTARY_KEYCHAIN:-}"

fail() {
    echo "error: $*" >&2
    exit 1
}

if [[ -z "$CODESIGN_IDENTITY" && "$ALLOW_ADHOC" == "1" ]]; then
    CODESIGN_IDENTITY="-"
fi

if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
    [[ "$ALLOW_ADHOC" == "1" ]] || fail "Ad-hoc DMG creation requires R2TRANS_ALLOW_ADHOC=1."
    [[ "$REQUIRE_DISTRIBUTION" == "0" ]] || fail "Distribution DMGs may not use ad-hoc signing."
    SIGNING_MODE="adhoc"
else
    [[ -n "$CODESIGN_IDENTITY" ]] || fail "R2TRANS_CODESIGN_IDENTITY is required."
    [[ -n "$NOTARY_PROFILE" ]] || fail "R2TRANS_NOTARY_PROFILE is required for a distribution DMG."
    SIGNING_MODE="distribution"
fi

notary_submit() {
    local artifact_path="$1"
    local arguments=(
        submit "$artifact_path"
        --keychain-profile "$NOTARY_PROFILE"
        --wait
        --timeout 30m
    )

    if [[ -n "$NOTARY_KEYCHAIN" ]]; then
        arguments+=(--keychain "$NOTARY_KEYCHAIN")
    fi

    xcrun notarytool "${arguments[@]}"
}

"$ROOT_DIR/Scripts/build_app.sh" >/dev/null
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
xcrun lipo "$APP_DIR/Contents/MacOS/R2Trans" -verify_arch arm64 x86_64

if [[ "$SIGNING_MODE" == "distribution" ]]; then
    rm -f "$APP_ARCHIVE"
    ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$APP_ARCHIVE"
    notary_submit "$APP_ARCHIVE"
    xcrun stapler staple "$APP_DIR"
    xcrun stapler validate "$APP_DIR"
    spctl --assess --type execute --verbose=4 "$APP_DIR"
    rm -f "$APP_ARCHIVE"
fi

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

if [[ "$SIGNING_MODE" == "distribution" ]]; then
    codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG_PATH"
else
    codesign --force --sign - "$DMG_PATH"
fi

codesign --verify --verbose=2 "$DMG_PATH"

if [[ "$SIGNING_MODE" == "distribution" ]]; then
    notary_submit "$DMG_PATH"
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
    spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"
else
    echo "warning: created an ad-hoc signed, unnotarized DMG for local development only" >&2
fi

echo "$DMG_PATH"
