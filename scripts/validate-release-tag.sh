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
  git show "$RELEASE_TAG:PlayStatus.xcodeproj/project.pbxproj" |
    sed -n 's/^[[:space:]]*MARKETING_VERSION = \([^;]*\);/\1/p' |
    sort -u
)"

if [[ "$(printf '%s\n' "$MARKETING_VERSION" | sed '/^$/d' | wc -l | tr -d ' ')" != "1" ]]; then
  echo "Expected one MARKETING_VERSION in $RELEASE_TAG; found: $MARKETING_VERSION" >&2
  exit 1
fi

if [[ "$MARKETING_VERSION" != "$VERSION" ]]; then
  echo "Tag $RELEASE_TAG does not match MARKETING_VERSION $MARKETING_VERSION" >&2
  exit 1
fi

printf '%s\n' "$VERSION"
