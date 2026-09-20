#!/usr/bin/env bash
set -euo pipefail

WORKFLOW=".github/workflows/jev-triage.yml"

[[ -f "$WORKFLOW" ]]

grep -Fq 'ref: ${{ github.event.repository.default_branch }}' "$WORKFLOW"
grep -Fq '"github.com/${GITHUB_REPOSITORY}"' "$WORKFLOW"
grep -Fq 'PR head SHA changed before JEV call; refusing stale revision' "$WORKFLOW"

secret_refs="$(grep -Fc 'JEV_TRIAGE_TOKEN: ${{ secrets.JEV_TRIAGE_TOKEN }}' "$WORKFLOW")"
[[ "$secret_refs" -eq 1 ]]

run_line="$(grep -n '^      - name: Run JEV Shadow Triage$' "$WORKFLOW" | cut -d: -f1)"
secret_line="$(grep -nF 'JEV_TRIAGE_TOKEN: ${{ secrets.JEV_TRIAGE_TOKEN }}' "$WORKFLOW" | cut -d: -f1)"
upload_line="$(grep -n '^      - name: Upload sanitized JEV result$' "$WORKFLOW" | cut -d: -f1)"
checkout_line="$(grep -n '^      - name: Checkout trusted default branch$' "$WORKFLOW" | cut -d: -f1)"

[[ "$secret_line" -gt "$run_line" ]]
[[ "$secret_line" -lt "$upload_line" ]]
[[ "$secret_line" -gt "$checkout_line" ]]

first_verify="$(grep -n 'ACTUAL_HEAD_SHA=.*gh api' "$WORKFLOW" | sed -n '1p' | cut -d: -f1)"
second_verify="$(grep -n 'ACTUAL_HEAD_SHA=.*gh api' "$WORKFLOW" | sed -n '2p' | cut -d: -f1)"
triage_call="$(grep -n 'triage-with-jev.sh' "$WORKFLOW" | tail -1 | cut -d: -f1)"

[[ -n "$first_verify" ]]
[[ -n "$second_verify" ]]
[[ "$second_verify" -lt "$triage_call" ]]



grep -Fq 'BLOCKING_CANDIDATE_COUNT' "$WORKFLOW"
grep -Fq 'IN_SCOPE_FIX_CANDIDATE_COUNT' "$WORKFLOW"
grep -Fq 'FOLLOW_UP_CANDIDATE_COUNT' "$WORKFLOW"
grep -Fq 'DISMISS_CANDIDATE_COUNT' "$WORKFLOW"

if grep -Eq 'BLOCKING_CANDIDATES|IN_SCOPE_FIX_CANDIDATES|FOLLOW_UP_CANDIDATES|DISMISS_CANDIDATES' "$WORKFLOW"; then
  echo "legacy candidate keys must not be used" >&2
  exit 1
fi

# review comment pagination contract
grep -Fq -- '--paginate' "$WORKFLOW"
grep -Fq -- '--slurp' "$WORKFLOW"
grep -Fq "jq 'add' /tmp/review-comment-pages.json > /tmp/review-comments.json" "$WORKFLOW"

echo "JEV triage workflow contract: PASS"

# environment secret boundary contract
grep -Fq 'environment: jev-triage-production' "$WORKFLOW"
grep -Fq 'WORKFLOW_REF: ${{ github.ref_name }}' "$WORKFLOW"
grep -Fq 'DEFAULT_BRANCH: ${{ github.event.repository.default_branch }}' "$WORKFLOW"
grep -Fq 'JEV Triage must be dispatched from the repository default branch' "$WORKFLOW"

# gh api must not combine --slurp with its own --jq formatter.
# Normalize shell line continuations first so multi-line logical commands are tested.
normalized_workflow="$(sed ':a;N;$!ba;s/\\\n/ /g' "$WORKFLOW")"
if printf '%s\n' "$normalized_workflow" \
  | grep -Eq 'gh api.*--slurp.*--jq|gh api.*--jq.*--slurp'; then
  echo "slurp must not be combined with gh api --jq" >&2
  exit 1
fi
