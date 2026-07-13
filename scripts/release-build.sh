#!/usr/bin/env bash
set -euo pipefail

require_value() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required environment variable: ${name}" >&2
    exit 1
  fi
}

require_value RELEASE_TAG
require_value APPLE_DEVELOPER_IDENTITY
require_value APPLE_TEAM_ID
require_value NOTARY_PROFILE

if [[ ! "$RELEASE_TAG" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "RELEASE_TAG must use the vX.Y.Z format; got: $RELEASE_TAG" >&2
  exit 1
fi

if ! git ls-remote --exit-code --tags origin "refs/tags/$RELEASE_TAG^{}" >/dev/null; then
  echo "Release tags must be annotated tags: $RELEASE_TAG" >&2
  exit 1
fi

VERSION="${RELEASE_TAG#v}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$PWD/.build/release-derived-data}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$PWD/.build/PlayStatus.xcarchive}"
DIST_DIR="${DIST_DIR:-$PWD/.build/dist}"

mkdir -p "$DIST_DIR"

MARKETING_VERSION="$(
  xcodebuild -project PlayStatus.xcodeproj -scheme PlayStatus -configuration Release -showBuildSettings |
    awk -F ' = ' '$1 ~ /MARKETING_VERSION$/ { print $2; exit }'
)"

if [[ "$MARKETING_VERSION" != "$VERSION" ]]; then
  echo "Tag $RELEASE_TAG does not match MARKETING_VERSION $MARKETING_VERSION" >&2
  exit 1
fi

xcodebuild \
  -project PlayStatus.xcodeproj \
  -scheme PlayStatus \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -archivePath "$ARCHIVE_PATH" \
  -xcconfig config/Distribution.xcconfig \
  archive \
  APPLE_DEVELOPER_IDENTITY="$APPLE_DEVELOPER_IDENTITY" \
  CODE_SIGN_IDENTITY="$APPLE_DEVELOPER_IDENTITY" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID"

APP_PATH="$ARCHIVE_PATH/Products/Applications/PlayStatus.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected archived app at $APP_PATH" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=4 "$APP_PATH"

ARCHS="$(lipo -archs "$APP_PATH/Contents/MacOS/PlayStatus")"
for required_arch in arm64 x86_64; do
  if [[ " $ARCHS " != *" $required_arch "* ]]; then
    echo "Release app is missing $required_arch; found: $ARCHS" >&2
    exit 1
  fi
done

NOTARY_ZIP="$DIST_DIR/PlayStatus-$VERSION-notary.zip"
FINAL_ZIP="$DIST_DIR/PlayStatus-$VERSION.zip"
ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"
xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

rm -f "$FINAL_ZIP"
ditto -c -k --keepParent "$APP_PATH" "$FINAL_ZIP"

VERIFY_DIR="$(mktemp -d)"
trap 'rm -rf "$VERIFY_DIR"' EXIT
ditto -x -k "$FINAL_ZIP" "$VERIFY_DIR"
VERIFY_APP="$VERIFY_DIR/PlayStatus.app"
test -d "$VERIFY_APP"
codesign --verify --deep --strict --verbose=4 "$VERIFY_APP"
spctl --assess --type execute --verbose=4 "$VERIFY_APP"

SHA256="$(shasum -a 256 "$FINAL_ZIP" | awk '{print $1}')"
echo "Built $FINAL_ZIP"
echo "SHA-256: $SHA256"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "version=$VERSION"
    echo "asset_path=$FINAL_ZIP"
    echo "sha256=$SHA256"
    echo "derived_data_path=$DERIVED_DATA_PATH"
  } >> "$GITHUB_OUTPUT"
fi
