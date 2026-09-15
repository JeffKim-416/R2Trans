#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/R2Trans.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
INFO_PLIST="$CONTENTS_DIR/Info.plist"
SWIFT_BUILD_ROOT="$BUILD_DIR/swift-build"
SWIFT_CACHE_DIR="$BUILD_DIR/swift-cache"
SWIFT_CONFIG_DIR="$BUILD_DIR/swift-config"
SWIFT_SECURITY_DIR="$BUILD_DIR/swift-security"
MODULE_CACHE_DIR="$BUILD_DIR/module-cache"
ICON_SOURCE="$ROOT_DIR/Assets/R2Trans-icon.png"
ICONSET_DIR="$BUILD_DIR/R2Trans.iconset"
BUNDLE_IDENTIFIER="io.github.r2trans.R2Trans"

CODESIGN_IDENTITY="${R2TRANS_CODESIGN_IDENTITY:-}"
TEAM_ID="${R2TRANS_TEAM_ID:-}"
PROVISIONING_PROFILE="${R2TRANS_PROVISIONING_PROFILE:-}"
ALLOW_ADHOC="${R2TRANS_ALLOW_ADHOC:-0}"
REQUIRE_DISTRIBUTION="${R2TRANS_REQUIRE_DISTRIBUTION:-0}"

cd "$ROOT_DIR"

fail() {
    echo "error: $*" >&2
    exit 1
}

normalize_marketing_version() {
    local raw_version="$1"
    local version="${raw_version#v}"

    if [[ ! "$version" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]]; then
        fail "Invalid R2Trans version '$raw_version'. Expected vX.Y.Z or X.Y.Z."
    fi

    echo "$version"
}

read_tracked_version() {
    [[ -f "$VERSION_FILE" ]] || fail "Missing tracked VERSION file at $VERSION_FILE."

    local raw_version
    raw_version="$(tr -d '[:space:]' < "$VERSION_FILE")"
    [[ -n "$raw_version" ]] || fail "VERSION must not be empty."
    normalize_marketing_version "$raw_version"
}

validate_boolean_flag() {
    local name="$1"
    local value="$2"
    [[ "$value" == "0" || "$value" == "1" ]] || fail "$name must be 0 or 1."
}

validate_boolean_flag "R2TRANS_ALLOW_ADHOC" "$ALLOW_ADHOC"
validate_boolean_flag "R2TRANS_REQUIRE_DISTRIBUTION" "$REQUIRE_DISTRIBUTION"
[[ -f "$ICON_SOURCE" ]] || fail "Missing app icon source at $ICON_SOURCE."
command -v sips >/dev/null || fail "sips is required to build the app icon."
xcrun --find iconutil >/dev/null || fail "iconutil is required to build the app icon."

APP_VERSION="$(read_tracked_version)"
if [[ -n "${R2TRANS_VERSION:-}" ]]; then
    REQUESTED_VERSION="$(normalize_marketing_version "$R2TRANS_VERSION")"
    [[ "$REQUESTED_VERSION" == "$APP_VERSION" ]] || fail \
        "R2TRANS_VERSION ($REQUESTED_VERSION) does not match tracked VERSION ($APP_VERSION)."
fi

EXACT_TAG="$(git describe --tags --exact-match --match 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null || true)"
if [[ -n "$EXACT_TAG" ]]; then
    TAG_VERSION="$(normalize_marketing_version "$EXACT_TAG")"
    [[ "$TAG_VERSION" == "$APP_VERSION" ]] || fail \
        "Git tag $EXACT_TAG does not match tracked VERSION $APP_VERSION."
fi

APP_BUILD_VERSION="${R2TRANS_BUILD_VERSION:-$APP_VERSION}"
if [[ ! "$APP_BUILD_VERSION" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
    fail "Invalid R2Trans build version '$APP_BUILD_VERSION'. Expected a numeric build version."
fi

if [[ -z "$CODESIGN_IDENTITY" ]]; then
    if [[ "$ALLOW_ADHOC" == "1" ]]; then
        CODESIGN_IDENTITY="-"
    else
        fail "R2TRANS_CODESIGN_IDENTITY is required. For local development only, explicitly set R2TRANS_ALLOW_ADHOC=1."
    fi
fi

if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
    [[ "$ALLOW_ADHOC" == "1" ]] || fail "Ad-hoc signing requires R2TRANS_ALLOW_ADHOC=1."
    [[ "$REQUIRE_DISTRIBUTION" == "0" ]] || fail "Distribution builds may not use ad-hoc signing."
    SIGNING_MODE="adhoc"
    echo "warning: building with an ad-hoc signature for local development; this artifact must not be distributed" >&2
else
    SIGNING_MODE="distribution"
    [[ "$CODESIGN_IDENTITY" == "Developer ID Application: "* ]] || fail \
        "R2TRANS_CODESIGN_IDENTITY must name a Developer ID Application identity."
    [[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || fail "R2TRANS_TEAM_ID must be a 10-character Apple Developer Team ID."
    [[ -f "$PROVISIONING_PROFILE" ]] || fail "R2TRANS_PROVISIONING_PROFILE must point to a Developer ID provisioning profile."
fi

mkdir -p \
    "$SWIFT_BUILD_ROOT" \
    "$SWIFT_CACHE_DIR" \
    "$SWIFT_CONFIG_DIR" \
    "$SWIFT_SECURITY_DIR" \
    "$MODULE_CACHE_DIR"

export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR"

build_architecture() {
    local architecture="$1"
    local triple="${architecture}-apple-macosx13.0"
    local scratch_path="$SWIFT_BUILD_ROOT/$architecture"
    local build_arguments=(
        --cache-path "$SWIFT_CACHE_DIR"
        --config-path "$SWIFT_CONFIG_DIR"
        --security-path "$SWIFT_SECURITY_DIR"
        --scratch-path "$scratch_path"
        --configuration release
        --triple "$triple"
    )

    if ! swift build "${build_arguments[@]}" >&2; then
        fail "$architecture Swift build failed."
    fi

    local binary_directory
    binary_directory="$(swift build "${build_arguments[@]}" --show-bin-path)"
    [[ -x "$binary_directory/R2Trans" ]] || fail "Missing $architecture R2Trans executable after Swift build."
    echo "$binary_directory/R2Trans"
}

ARM64_EXECUTABLE="$(build_architecture arm64)"
X86_64_EXECUTABLE="$(build_architecture x86_64)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$CONTENTS_DIR/Resources"

create_icon_file() {
    local size="$1"
    local name="$2"
    sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET_DIR/$name" >/dev/null
}

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
create_icon_file 16 icon_16x16.png
create_icon_file 32 icon_16x16@2x.png
create_icon_file 32 icon_32x32.png
create_icon_file 64 icon_32x32@2x.png
create_icon_file 128 icon_128x128.png
create_icon_file 256 icon_128x128@2x.png
create_icon_file 256 icon_256x256.png
create_icon_file 512 icon_256x256@2x.png
create_icon_file 512 icon_512x512.png
create_icon_file 1024 icon_512x512@2x.png
xcrun iconutil -c icns "$ICONSET_DIR" -o "$CONTENTS_DIR/Resources/R2Trans.icns"

xcrun lipo -create \
    "$ARM64_EXECUTABLE" \
    "$X86_64_EXECUTABLE" \
    -output "$MACOS_DIR/R2Trans"
xcrun lipo "$MACOS_DIR/R2Trans" -verify_arch arm64 x86_64
chmod 755 "$MACOS_DIR/R2Trans"

cat > "$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>R2Trans</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_IDENTIFIER</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleIconFile</key>
    <string>R2Trans.icns</string>
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
    <string>R2Trans uses the microphone for live interpretation and live transcription.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>R2Trans captures system audio for live interpretation and live transcription from videos, browsers, and calls.</string>
</dict>
</plist>
PLIST

ENTITLEMENTS_PATH="$BUILD_DIR/R2Trans.entitlements"
if [[ "$SIGNING_MODE" == "adhoc" ]]; then
    /usr/libexec/PlistBuddy -c "Add :R2TransAllowsLegacyKeychainFallback bool true" "$INFO_PLIST"
    cat > "$ENTITLEMENTS_PATH" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
PLIST
else
    PROFILE_PLIST="$BUILD_DIR/provisioning-profile.plist"
    security cms -D -i "$PROVISIONING_PROFILE" > "$PROFILE_PLIST"

    PROFILE_TEAM_ID="$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$PROFILE_PLIST" 2>/dev/null || true)"
    PROFILE_PROVISIONS_ALL_DEVICES="$(/usr/libexec/PlistBuddy -c 'Print :ProvisionsAllDevices' "$PROFILE_PLIST" 2>/dev/null || true)"
    PROFILE_APP_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$PROFILE_PLIST" 2>/dev/null || true)"
    if [[ -z "$PROFILE_APP_IDENTIFIER" ]]; then
        PROFILE_APP_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$PROFILE_PLIST" 2>/dev/null || true)"
    fi
    EXPECTED_APP_IDENTIFIER="$PROFILE_APP_IDENTIFIER"

    [[ "$PROFILE_TEAM_ID" == "$TEAM_ID" ]] || fail \
        "Provisioning profile Team ID '$PROFILE_TEAM_ID' does not match R2TRANS_TEAM_ID '$TEAM_ID'."
    [[ "$PROFILE_PROVISIONS_ALL_DEVICES" == "true" ]] || fail \
        "R2TRANS_PROVISIONING_PROFILE must be a Developer ID provisioning profile."
    [[ "$PROFILE_APP_IDENTIFIER" == *".$BUNDLE_IDENTIFIER" ]] || fail \
        "Provisioning profile app identifier '$PROFILE_APP_IDENTIFIER' does not target '$BUNDLE_IDENTIFIER'."

    cp "$PROVISIONING_PROFILE" "$CONTENTS_DIR/embedded.provisionprofile"
    cat > "$ENTITLEMENTS_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.application-identifier</key>
    <string>$EXPECTED_APP_IDENTIFIER</string>
    <key>com.apple.developer.team-identifier</key>
    <string>$TEAM_ID</string>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>keychain-access-groups</key>
    <array>
        <string>$EXPECTED_APP_IDENTIFIER</string>
    </array>
</dict>
</plist>
PLIST
fi

plutil -lint "$INFO_PLIST" "$ENTITLEMENTS_PATH" >/dev/null

if [[ "$SIGNING_MODE" == "distribution" ]]; then
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --entitlements "$ENTITLEMENTS_PATH" \
        --sign "$CODESIGN_IDENTITY" \
        "$APP_DIR"
else
    codesign \
        --force \
        --options runtime \
        --entitlements "$ENTITLEMENTS_PATH" \
        --sign - \
        "$APP_DIR"
fi

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
xcrun lipo "$MACOS_DIR/R2Trans" -verify_arch arm64 x86_64

SIGNATURE_DETAILS="$(codesign -dv --verbose=4 "$APP_DIR" 2>&1)"
grep -Eq '^CodeDirectory .*flags=.*runtime' <<< "$SIGNATURE_DETAILS" || fail \
    "Signed app is missing the hardened runtime flag."

SIGNED_ENTITLEMENTS_PATH="$BUILD_DIR/signed-entitlements.plist"
codesign -d --entitlements :- "$APP_DIR" > "$SIGNED_ENTITLEMENTS_PATH" 2>/dev/null
plutil -lint "$SIGNED_ENTITLEMENTS_PATH" >/dev/null

if [[ "$SIGNING_MODE" == "distribution" ]]; then
    grep -Fq "Authority=$CODESIGN_IDENTITY" <<< "$SIGNATURE_DETAILS" || fail \
        "Signed app does not use the requested Developer ID Application identity."
    grep -Eq '^Timestamp=' <<< "$SIGNATURE_DETAILS" || fail \
        "Signed app is missing a secure timestamp."

    ACTUAL_TEAM_ID="$(sed -n 's/^TeamIdentifier=//p' <<< "$SIGNATURE_DETAILS")"
    [[ "$ACTUAL_TEAM_ID" == "$TEAM_ID" ]] || fail \
        "Signed app Team ID '$ACTUAL_TEAM_ID' does not match '$TEAM_ID'."

    ACTUAL_APP_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.application-identifier' "$SIGNED_ENTITLEMENTS_PATH" 2>/dev/null || true)"
    ACTUAL_KEYCHAIN_GROUP="$(/usr/libexec/PlistBuddy -c 'Print :keychain-access-groups:0' "$SIGNED_ENTITLEMENTS_PATH" 2>/dev/null || true)"
    [[ "$ACTUAL_APP_IDENTIFIER" == "$EXPECTED_APP_IDENTIFIER" ]] || fail \
        "Signed app application identifier '$ACTUAL_APP_IDENTIFIER' does not match '$EXPECTED_APP_IDENTIFIER'."
    [[ "$ACTUAL_KEYCHAIN_GROUP" == "$EXPECTED_APP_IDENTIFIER" ]] || fail \
        "Signed app Keychain access group '$ACTUAL_KEYCHAIN_GROUP' does not match '$EXPECTED_APP_IDENTIFIER'."
fi

echo "$APP_DIR"
