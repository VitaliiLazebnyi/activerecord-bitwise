#!/usr/bin/env bash
# Validates the release tag and requires it to match the committed version.rb, then exports VERSION for the
# next steps of the release job (.github/workflows/release.yml). The version file is the single source of
# truth; a mistyped tag (the cause of the accidental 0.10.0 release) fails loudly instead of publishing.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

tag_name=${GITHUB_REF_NAME:?}
if [[ ! ${tag_name} =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "::error::Tag '${tag_name}' does not match the required vX.Y.Z format." >&2
  exit 1
fi
version=${tag_name#v}
file_version=$(ruby -r ./lib/active_record/bitwise/version -e 'puts ActiveRecord::Bitwise::VERSION')
if [[ ${version} != "${file_version}" ]]; then
  echo "::error::Tag version '${version}' does not match lib/active_record/bitwise/version.rb ('${file_version}')." >&2
  exit 1
fi
echo "VERSION=${version}" >>"${GITHUB_ENV:?}"
