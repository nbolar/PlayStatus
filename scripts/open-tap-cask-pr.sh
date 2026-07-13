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
require_value SHA256
require_value TAP_REPOSITORY
require_value TAP_TOKEN

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
BRANCH="playstatus-$VERSION"

git clone "https://x-access-token:$TAP_TOKEN@github.com/$TAP_REPOSITORY.git" "$WORK_DIR/tap"
mkdir -p "$WORK_DIR/tap/Casks"
scripts/render-cask.sh "$VERSION" "$SHA256" > "$WORK_DIR/tap/Casks/playstatus.rb"

git -C "$WORK_DIR/tap" checkout -B "$BRANCH"
git -C "$WORK_DIR/tap" add Casks/playstatus.rb
if git -C "$WORK_DIR/tap" diff --cached --quiet; then
  echo "Cask already matches $VERSION; no pull request needed."
  exit 0
fi
git -C "$WORK_DIR/tap" -c user.name="playstatus-release[bot]" -c user.email="playstatus-release[bot]@users.noreply.github.com" \
  commit -m "playstatus $VERSION"
git -C "$WORK_DIR/tap" push --force-with-lease origin "$BRANCH"

EXISTING_PR="$(GH_TOKEN="$TAP_TOKEN" gh pr list \
  --repo "$TAP_REPOSITORY" \
  --base main \
  --head "$BRANCH" \
  --state open \
  --json url \
  --jq '.[0].url')"
if [[ -n "$EXISTING_PR" ]]; then
  echo "Updated existing cask pull request: $EXISTING_PR"
  exit 0
fi

GH_TOKEN="$TAP_TOKEN" gh pr create \
  --repo "$TAP_REPOSITORY" \
  --base main \
  --head "$BRANCH" \
  --title "playstatus $VERSION" \
  --body "Automated cask update for PlayStatus $VERSION.\n\nSHA-256: \`$SHA256\`"
