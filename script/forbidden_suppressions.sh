#!/usr/bin/env bash
# Fails when a tracked file silences a linter, scanner, type checker, warning or test, or weakens typing,
# and when a suppression or todo file of one of the tools exists.
# Inline suppressions are forbidden everywhere in this repository (see CONTRIBUTING.md): fix the cause.
# Markdown files are skipped because they document the rules.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# This script names the patterns, so it is not scanned for them. The committed central-repository RBI
# annotations (sorbet/rbi/annotations) are third-party type information, not code of this repository.
files=$(git ls-files -z -- . ':(exclude)*.md' ':(exclude)script/forbidden_suppressions.sh' \
  ':(exclude)sorbet/rbi/annotations' | tr '\0' '\n')

# The extended regular expression that matches any of the arguments.
any() {
  local IFS='|'
  printf '%s' "$*"
}

status=0
check() {
  local description=$1 pattern=$2 scope=${3:-.}
  local hits
  hits=$(printf '%s\n' "${files}" | grep -E "^${scope}" | xargs -r grep -nEH -e "${pattern}" -- || true)
  if [[ -n ${hits} ]]; then
    printf 'Forbidden (%s):\n%s\n\n' "${description}" "${hits}"
    status=1
  fi
}

check 'RuboCop directive' 'rubocop:(disable|enable|todo)'
check 'Reek suppression' ':reek:'
check 'SimpleCov exclusion' ':nocov:|nocov_token|SimpleCov\.nocov'
check 'mutant suppression' 'mutant:disable'
check 'gitleaks allow' 'gitleaks:allow'
check 'zizmor ignore' 'zizmor: ?ignore'
check 'shellcheck disable' 'shellcheck +disable'
check 'actionlint ignore' 'actionlint +(ignore|disable)'
check 'markdownlint/rumdl suppression' '(markdownlint|rumdl)-(disable|capture|configure-file)'
check 'typos suppression' 'typos: ?(ignore|off)|spellchecker: ?disable'
check 'LGTM/CodeQL suppression' 'lgtm\[|codeql\[|codeql-disable|lgtm: ?ignore'
check 'nosec' 'nosec|NOLINT'
check 'yamllint directive' 'yamllint (disable|enable)'
check 'editorconfig-checker directive' 'editorconfig-checker-(disable|enable)'
warnings=$(any '[$]VERBOSE *= *(nil|false)' 'Warning\.ignore' 'silence_warnings' '[$]stderr *= *File::NULL' \
  'Warning\[:[a-z]+\] *= *false' '-W0' '--no-warnings')
check 'warning silencing' "${warnings}"
deprecations=$(any 'ActiveSupport::Deprecation\.(silence|behavior *= *:silence)' \
  'deprecation *= *:(silence|log|notify)' 'report_deprecations *= *false')
check 'deprecation silencing' "${deprecations}"
skipping=$(any xit xspecify xexample xdescribe xcontext fit fspecify fexample fdescribe fcontext skip pending)
focus=$(any "^[[:space:]]*(${skipping})([[:space:]]|\()" 'focus: *true' ', *:focus' ', *(skip|pending): ')
check 'skipped or focused test' "${focus}" '(spec|script)/'
check 'Sorbet escape hatch' 'T\.(unsafe|cast|bind)\b' '(lib|spec|script)/.*\.rb$'
check 'untyped value outside lib/' 'T\.untyped\b' '(spec|script)/.*\.rb$'
check 'weak Sorbet sigil' 'typed: *(false|ignore|true)\b' '(lib|script)/'
check 'Sorbet sigil off' 'typed: *ignore\b'

# Suppression and todo files of the tools: findings are fixed, never parked in a file.
for forbidden in .rubocop_todo.yml sorbet/rbi/todo.rbi .reek.yml .gitleaksignore .gitleaks.toml \
  .markdownlintignore .rumdlignore .typos-ignore .yamllint-ignore .ecrc .editorconfig-checker.json \
  .github/zizmor.yml zizmor.yml .mutant-ignore .simplecov; do
  if [[ -e ${forbidden} ]]; then
    printf 'Forbidden (suppression or todo file): %s\n\n' "${forbidden}"
    status=1
  fi
done

exit "${status}"
