#!/usr/bin/env bash
set -euo pipefail

require_value() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required environment variable: ${name}" >&2
    exit 1
  fi
}

require_value VERSION
require_value RELEASE_ARCHIVE
require_value RELEASE_NOTES
require_value DERIVED_DATA_PATH
require_value SPARKLE_ED25519_PRIVATE_KEY
require_value SPARKLE_S3_URI
require_value SPARKLE_PUBLIC_BASE_URL

if [[ ! -f "$RELEASE_ARCHIVE" || ! -f "$RELEASE_NOTES" ]]; then
  echo "Release archive and matching HTML release notes must exist" >&2
  exit 1
fi

GENERATE_APPCAST="$(find "$DERIVED_DATA_PATH/SourcePackages/artifacts/sparkle" -type f -name generate_appcast -perm -u+x -print -quit)"
if [[ -z "$GENERATE_APPCAST" ]]; then
  echo "Sparkle generate_appcast was not resolved by the archive build" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# Keep historical archives locally: Sparkle uses them to preserve history and
# generate delta updates. Never use --delete against the production bucket.
aws s3 sync "$SPARKLE_S3_URI" "$WORK_DIR" --exclude "old_updates/*"
cp "$RELEASE_ARCHIVE" "$WORK_DIR/PlayStatus-$VERSION.zip"
cp "$RELEASE_NOTES" "$WORK_DIR/PlayStatus-$VERSION.html"

printf '%s' "$SPARKLE_ED25519_PRIVATE_KEY" |
  "$GENERATE_APPCAST" \
    --ed-key-file - \
    --download-url-prefix "$SPARKLE_PUBLIC_BASE_URL" \
    --release-notes-url-prefix "$SPARKLE_PUBLIC_BASE_URL" \
    --maximum-versions 0 \
    -o "$WORK_DIR/appcast.xml" \
    "$WORK_DIR"

# Upload payloads and deltas before appcast.xml, so clients never receive a
# feed entry that points to an unavailable update.
aws s3 sync "$WORK_DIR" "$SPARKLE_S3_URI" \
  --exclude "appcast.xml" \
  --exclude "old_updates/*" \
  --acl public-read \
  --cache-control "public,max-age=31536000,immutable"
# `aws s3 sync` leaves an unchanged object's ACL untouched. Reapply public
# readability to the current release lineage so a feed repair fixes existing
# immutable ZIP and release-note objects as well as newly uploaded files.
aws s3 cp "$WORK_DIR/PlayStatus-$VERSION.zip" "$SPARKLE_S3_URI/PlayStatus-$VERSION.zip" \
  --acl public-read \
  --cache-control "public,max-age=31536000,immutable"
aws s3 cp "$WORK_DIR/PlayStatus-$VERSION.html" "$SPARKLE_S3_URI/PlayStatus-$VERSION.html" \
  --acl public-read \
  --content-type "text/html" \
  --cache-control "public,max-age=31536000,immutable"
aws s3 cp "$WORK_DIR/appcast.xml" "$SPARKLE_S3_URI/appcast.xml" \
  --acl public-read \
  --content-type "application/xml" \
  --cache-control "no-cache"

PUBLIC_APPCAST_URL="${SPARKLE_PUBLIC_BASE_URL%/}/appcast.xml"
curl --fail --silent --show-error --retry 3 --retry-all-errors "$PUBLIC_APPCAST_URL" >/dev/null
