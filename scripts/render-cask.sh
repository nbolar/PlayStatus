#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 VERSION SHA256" >&2
  exit 1
fi

version="$1"
sha256="$2"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$sha256" =~ ^[a-f0-9]{64}$ ]]; then
  echo "Version or SHA-256 is invalid" >&2
  exit 1
fi

sed \
  -e "s/__VERSION__/$version/g" \
  -e "s/__SHA256__/$sha256/g" \
  distribution/homebrew/Casks/playstatus.rb.template
