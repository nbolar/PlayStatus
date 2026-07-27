#!/usr/bin/env bash
set -euo pipefail

require_value() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required environment variable: ${name}" >&2
    exit 1
  fi
}

require_value APPLE_DEVELOPER_IDENTITY
require_value APPLE_TEAM_ID
require_value NOTARY_PROFILE

require_value RELEASE_TAG
VERSION="$(scripts/validate-release-tag.sh "$RELEASE_TAG")"
BUILD_NUMBER="$(scripts/release-build-number.sh "$RELEASE_TAG")"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$PWD/.build/release-derived-data}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$PWD/.build/PlayStatus.xcarchive}"
DIST_DIR="${DIST_DIR:-$PWD/.build/dist}"

mkdir -p "$DIST_DIR"

xcodebuild \
  -project PlayStatus.xcodeproj \
  -scheme PlayStatus \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -archivePath "$ARCHIVE_PATH" \
  archive \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  ENABLE_HARDENED_RUNTIME=YES \
  APPLE_DEVELOPER_IDENTITY="$APPLE_DEVELOPER_IDENTITY" \
  CODE_SIGN_IDENTITY="$APPLE_DEVELOPER_IDENTITY" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID"

APP_PATH="$ARCHIVE_PATH/Products/Applications/PlayStatus.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected archived app at $APP_PATH" >&2
  exit 1
fi

sign_with_developer_id() {
  codesign \
    --force \
    --options runtime \
    --preserve-metadata=identifier,entitlements,flags \
    --sign "$APPLE_DEVELOPER_IDENTITY" \
    --timestamp \
    "$1"
}

require_automation_entitlement() {
  local app_path="$1"

  if ! codesign -d --entitlements :- "$app_path" 2>&1 |
    sed -n '/<?xml/,$p' |
    plutil -p - |
    grep -Fqx '  "com.apple.security.automation.apple-events" => true'; then
    echo "Release app is missing com.apple.security.automation.apple-events: $app_path" >&2
    exit 1
  fi
}

export_entitlements() {
  local app_path="$1"
  local output_path="$2"

  codesign -d --entitlements :- "$app_path" 2>&1 |
    sed -n '/<?xml/,$p' > "$output_path"
  plutil -lint "$output_path" >/dev/null
}

sign_app_with_developer_id() {
  codesign \
    --force \
    --options runtime \
    --preserve-metadata=identifier,flags \
    --entitlements "$APP_ENTITLEMENTS" \
    --sign "$APPLE_DEVELOPER_IDENTITY" \
    --timestamp \
    "$APP_PATH"
}

# Xcode signs the Sparkle framework itself but does not timestamp every nested
# executable in its prebuilt XCFramework. Notarization requires each of these
# components to carry this app's Developer ID signature and secure timestamp.
SPARKLE_FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE_FRAMEWORK" ]]; then
  SPARKLE_VERSION="$SPARKLE_FRAMEWORK/Versions/Current"
  SPARKLE_COMPONENTS=(
    "$SPARKLE_VERSION/Updater.app/Contents/MacOS/Updater"
    "$SPARKLE_VERSION/Autoupdate"
    "$SPARKLE_VERSION/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
    "$SPARKLE_VERSION/XPCServices/Installer.xpc/Contents/MacOS/Installer"
    "$SPARKLE_VERSION/XPCServices/Downloader.xpc"
    "$SPARKLE_VERSION/XPCServices/Installer.xpc"
    "$SPARKLE_VERSION/Updater.app"
    "$SPARKLE_FRAMEWORK"
  )

  for component in "${SPARKLE_COMPONENTS[@]}"; do
    test -e "$component"
    sign_with_developer_id "$component"
    codesign -d --verbose=4 "$component" 2>&1 | grep -q 'Timestamp='
  done
fi

# Re-seal the app after its embedded framework has been re-signed.
require_automation_entitlement "$APP_PATH"
APP_ENTITLEMENTS="$DIST_DIR/PlayStatus.app.entitlements.plist"
export_entitlements "$APP_PATH" "$APP_ENTITLEMENTS"
sign_app_with_developer_id
codesign -d --verbose=4 "$APP_PATH" 2>&1 | grep -q 'Timestamp='
codesign --verify --deep --strict --verbose=4 "$APP_PATH"
require_automation_entitlement "$APP_PATH"

ARCHS="$(lipo -archs "$APP_PATH/Contents/MacOS/PlayStatus")"
for required_arch in arm64 x86_64; do
  if [[ " $ARCHS " != *" $required_arch "* ]]; then
    echo "Release app is missing $required_arch; found: $ARCHS" >&2
    exit 1
  fi
done

NOTARY_ZIP="$DIST_DIR/PlayStatus-$VERSION-notary.zip"
FINAL_ZIP="$DIST_DIR/PlayStatus-$VERSION-build$BUILD_NUMBER.zip"
ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"

set +e
NOTARY_RESULT="$(xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)"
NOTARY_EXIT_CODE=$?
set -e
printf '%s\n' "$NOTARY_RESULT"

NOTARY_SUBMISSION_ID="$(printf '%s\n' "$NOTARY_RESULT" | sed -n 's/^[[:space:]]*id: //p' | head -n 1)"
if [[ $NOTARY_EXIT_CODE -ne 0 || "$NOTARY_RESULT" != *"status: Accepted"* ]]; then
  if [[ -n "$NOTARY_SUBMISSION_ID" ]]; then
    echo "Apple notarization log for submission $NOTARY_SUBMISSION_ID:" >&2
    xcrun notarytool log "$NOTARY_SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" || true
  fi
  echo "Apple notarization did not accept $NOTARY_ZIP" >&2
  exit 1
fi

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

APP_BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
if [[ "$APP_BUILD_NUMBER" != "$BUILD_NUMBER" ]]; then
  echo "Archive build number $APP_BUILD_NUMBER does not match tagged build number $BUILD_NUMBER" >&2
  exit 1
fi

rm -f "$FINAL_ZIP"
ditto -c -k --keepParent "$APP_PATH" "$FINAL_ZIP"

VERIFY_DIR="$(mktemp -d)"
trap 'rm -rf "$VERIFY_DIR"' EXIT
ditto -x -k "$FINAL_ZIP" "$VERIFY_DIR"
VERIFY_APP="$VERIFY_DIR/PlayStatus.app"
test -d "$VERIFY_APP"
codesign --verify --deep --strict --verbose=4 "$VERIFY_APP"
spctl --assess --type execute --verbose=4 "$VERIFY_APP"
require_automation_entitlement "$VERIFY_APP"

SHA256="$(shasum -a 256 "$FINAL_ZIP" | awk '{print $1}')"
echo "Built $FINAL_ZIP"
echo "SHA-256: $SHA256"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "version=$VERSION"
    echo "build_number=$BUILD_NUMBER"
    echo "asset_path=$FINAL_ZIP"
    echo "sha256=$SHA256"
    echo "derived_data_path=$DERIVED_DATA_PATH"
  } >> "$GITHUB_OUTPUT"
fi
