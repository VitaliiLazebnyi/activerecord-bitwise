#!/usr/bin/env bash
# Fails when a tracked file silences a linter, scanner, type checker, warning or test, or weakens typing.
# Inline suppressions are forbidden everywhere in this repository (see CONTRIBUTING.md): fix the cause.
# Markdown files are skipped because they document the rules.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# This script and the CI workflow files that call it name the patterns, so they are not scanned for them.
files=$(git ls-files -z -- . ':(exclude)*.md' ':(exclude)script/forbidden_suppressions.sh' ':(exclude)sorbet/rbi/gems' \
  | tr '\0' '\n')

status=0
check() {
  local description=$1 pattern=$2 scope=${3:-.}
  local hits
  hits=$(printf '%s\n' "$files" | grep -E "^${scope}" | xargs -r grep -nEH -e "$pattern" -- || true)
  if [ -n "$hits" ]; then
    printf 'Forbidden (%s):\n%s\n\n' "$description" "$hits"
    status=1
  fi
}

check 'RuboCop directive' 'rubocop:(disable|enable|todo)'
check 'Reek suppression' ':reek:'
check 'SimpleCov exclusion' ':nocov:'
check 'mutant suppression' 'mutant:disable'
check 'gitleaks allow' 'gitleaks:allow'
check 'zizmor ignore' 'zizmor: ?ignore'
check 'shellcheck disable' 'shellcheck +disable'
check 'LGTM/CodeQL suppression' 'lgtm\[|codeql\[|codeql-disable|lgtm: ?ignore'
check 'nosec' 'nosec'
check 'warning silencing' '\$VERBOSE *= *nil|Warning\.ignore|silence_warnings|\$stderr *= *File::NULL'
check 'skipped or focused test' '^[[:space:]]*(xit|xdescribe|xcontext|fit|fdescribe|fcontext|skip|pending)([[:space:]]|\()|focus: *true|, *:focus|, *(skip|pending): ' '(spec|script)/'
check 'Sorbet escape hatch' 'T\.(unsafe|cast|bind)\b|typed: *(false|ignore)' 'lib/'

exit "$status"
