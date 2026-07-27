#!/usr/bin/env bash
set -euo pipefail

RELEASE_TAG="${1:-${RELEASE_TAG:-}}"
if [[ -z "$RELEASE_TAG" ]]; then
  echo "Missing release tag" >&2
  exit 1
fi

if ! git rev-parse --verify --quiet "refs/tags/$RELEASE_TAG^{tag}" >/dev/null; then
  echo "Release tags must be annotated tags: $RELEASE_TAG" >&2
  exit 1
fi

BUILD_NUMBER="$(
  git show "$RELEASE_TAG:PlayStatus.xcodeproj/project.pbxproj" |
    sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION = \([^;]*\);/\1/p' |
    sort -u
)"

if [[ "$(printf '%s\n' "$BUILD_NUMBER" | sed '/^$/d' | wc -l | tr -d ' ')" != "1" || ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Expected one numeric CURRENT_PROJECT_VERSION in $RELEASE_TAG; found: $BUILD_NUMBER" >&2
  exit 1
fi

printf '%s\n' "$BUILD_NUMBER"
