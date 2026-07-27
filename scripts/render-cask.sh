#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 VERSION BUILD_NUMBER SHA256" >&2
  exit 1
fi

version="$1"
build_number="$2"
sha256="$3"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$build_number" =~ ^[0-9]+$ || ! "$sha256" =~ ^[a-f0-9]{64}$ ]]; then
  echo "Version, build number, or SHA-256 is invalid" >&2
  exit 1
fi

sed \
  -e "s/__VERSION__/$version/g" \
  -e "s/__BUILD_NUMBER__/$build_number/g" \
  -e "s/__SHA256__/$sha256/g" \
  distribution/homebrew/Casks/playstatus.rb.template
