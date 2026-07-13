#!/usr/bin/env bash
set -euo pipefail

TAP_REPOSITORY="nbolar/homebrew-playstatus"

gh auth status -h github.com
if gh repo view "$TAP_REPOSITORY" >/dev/null 2>&1; then
  echo "$TAP_REPOSITORY already exists; refusing to overwrite it" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
TAP_DIRECTORY="$WORK_DIR/homebrew-playstatus"
mkdir -p "$TAP_DIRECTORY/Casks" "$TAP_DIRECTORY/.github/workflows"
cp distribution/homebrew/README.md "$TAP_DIRECTORY/README.md"
cp distribution/homebrew/cask-ci.yml "$TAP_DIRECTORY/.github/workflows/cask.yml"

git init --initial-branch=main "$TAP_DIRECTORY"
git -C "$TAP_DIRECTORY" add README.md .github/workflows/cask.yml
git -C "$TAP_DIRECTORY" -c user.name="nbolar" -c user.email="nbolar@users.noreply.github.com" \
  commit -m "Initialize PlayStatus Homebrew tap"
gh repo create "$TAP_REPOSITORY" --public --source "$TAP_DIRECTORY" --push \
  --description "Official Homebrew Cask tap for PlayStatus"

echo "Created $TAP_REPOSITORY. The first tagged release will open a PR with Casks/playstatus.rb."
