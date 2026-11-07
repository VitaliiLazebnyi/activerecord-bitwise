#!/usr/bin/env bash
# Fails when the log of any other job of the current workflow run contains a warning or a deprecation notice.
# Run by the "Warning gate" job of every workflow; the repository tolerates no warnings (see CONTRIBUTING.md).
#
# Needs GH_TOKEN (actions: read), GITHUB_REPOSITORY, GITHUB_RUN_ID and GATE_JOB_NAME (the name of the gate job
# itself, whose own log quotes the pattern).
set -euo pipefail

repository=${GITHUB_REPOSITORY:?}
run_id=${GITHUB_RUN_ID:?}
gate_job=${GATE_JOB_NAME:?}
token=${GH_TOKEN:?}

warning='[Ww]arning:|WARNING:|##\[warning\]|\[warn\]:'
deprecation='DEPRECATION|DEPRECATED|is deprecated|will be deprecated|Node\.js [0-9]+ actions are deprecated'
pattern="${warning}|${deprecation}"
# The two kinds of matching line that are not warnings, each skipped only where it occurs:
# - CodeQL prints the JSON schema of its extractor options, whose "title" and "description" fields document a
#   deprecated option ("DEPRECATED - Whether to use buildless ...").
# - The Scorecard action prints the event that triggered the run, whose "message" fields are the commit
#   messages of the push (text written by people, which may mention a warning).
documentation='^[0-9TZ:.-]+ +"(title|description)" : "'
event_payload='^[0-9TZ:.-]+ +"message": "'

jobs=$(gh api --paginate "repos/${repository}/actions/runs/${run_id}/jobs?per_page=100" \
  --jq ".jobs[] | select(.name != \"${gate_job}\" and .conclusion != \"skipped\") | \"\(.id)\t\(.name)\"")

status=0
while IFS=$'\t' read -r id name; do
  [[ -n ${id} ]] || continue
  skipped=${documentation}
  [[ ${name} != 'Scorecard analysis' ]] || skipped="${documentation}|${event_payload}"
  # Downloaded with curl: depending on its version, gh refuses to print a log that contains terminal escape
  # sequences (colored tool output), and older versions do not know the flag that allows them.
  log=$(curl --fail --silent --show-error --location \
    --header "Authorization: Bearer ${token}" --header 'Accept: application/vnd.github+json' \
    "${GITHUB_API_URL:-https://api.github.com}/repos/${repository}/actions/jobs/${id}/logs")
  hits=$(printf '%s\n' "${log}" | grep -nE -e "${pattern}" | sed -E 's/^[0-9]+://' | grep -vE -e "${skipped}" || true)
  if [[ -n ${hits} ]]; then
    printf '::error::Warnings in the log of job "%s"\n%s\n\n' "${name}" "${hits}"
    status=1
  else
    printf 'No warnings in the log of job "%s"\n' "${name}"
  fi
done <<<"${jobs}"

exit "${status}"
