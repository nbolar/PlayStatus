#!/usr/bin/env bash
set -euo pipefail

RELEASE_TAG="${1:-${RELEASE_TAG:-}}"
if [[ -z "$RELEASE_TAG" ]]; then
  echo "Missing release tag" >&2
  exit 1
fi

if [[ ! "$RELEASE_TAG" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "RELEASE_TAG must use the vX.Y.Z format; got: $RELEASE_TAG" >&2
  exit 1
fi

if ! git rev-parse --verify --quiet "refs/tags/$RELEASE_TAG^{tag}" >/dev/null; then
  echo "Release tags must be annotated tags: $RELEASE_TAG" >&2
  exit 1
fi

VERSION="${RELEASE_TAG#v}"
MARKETING_VERSION="$(
  xcodebuild -project PlayStatus.xcodeproj -scheme PlayStatus -configuration Release -showBuildSettings |
    awk -F ' = ' '$1 ~ /MARKETING_VERSION$/ { print $2; exit }'
)"

if [[ "$MARKETING_VERSION" != "$VERSION" ]]; then
  echo "Tag $RELEASE_TAG does not match MARKETING_VERSION $MARKETING_VERSION" >&2
  exit 1
fi

printf '%s\n' "$VERSION"
