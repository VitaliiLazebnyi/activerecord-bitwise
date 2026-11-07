#!/usr/bin/env bash
# Writes the gem signing key (the GEM_PRIVATE_KEY secret) to ~/.gem/gem-private_key.pem, where
# activerecord-bitwise.gemspec looks for it, and refuses to go on without it: the release job
# (.github/workflows/release.yml) never publishes an unsigned gem.
set -euo pipefail

key=${GEM_PRIVATE_KEY:-}
if [[ -z ${key} ]]; then
  echo "::error::GEM_PRIVATE_KEY secret is missing or empty; refusing to publish an unsigned gem." >&2
  exit 1
fi
mkdir -p ~/.gem
(
  umask 077
  printf '%s\n' "${key}" >~/.gem/gem-private_key.pem
)
