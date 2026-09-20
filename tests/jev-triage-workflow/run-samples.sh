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

# summary quoting contract
grep -Fq "printf -- '- Repository: \`%s\`\\n' \"\$GITHUB_REPOSITORY\"" "$WORKFLOW"
grep -Fq "printf -- '- Head SHA: \`%s\`\\n' \"\$HEAD_SHA\"" "$WORKFLOW"
if grep -Eq 'echo ".*\`\$[A-Z_]+\`"' "$WORKFLOW"; then
  echo "summary must not use shell command substitution for Markdown backticks" >&2
  exit 1
fi

# ingress diagnostic contract
grep -Fq 'JEV_PROBE_UNAUTH_STATUS=' "$WORKFLOW"
grep -Fq 'JEV_PROBE_AUTH_STATUS=' "$WORKFLOW"
[[ "$(grep -Fc -- '--output /dev/null' "$WORKFLOW")" -eq 2 ]]
[[ "$(grep -Fc -- "--write-out '%{http_code}'" "$WORKFLOW")" -eq 2 ]]
[[ "$(grep -Fc -- '--data '"'"'{}'"'"'' "$WORKFLOW")" -eq 2 ]]
grep -Fq -- '--header "authorization: Bearer ${JEV_TRIAGE_TOKEN}"' "$WORKFLOW"

unauth_probe="$(
  awk '/JEV_PROBE_UNAUTH_STATUS="\$\(/,/^          \)"/ { print }' "$WORKFLOW"
)"
auth_probe="$(
  awk '/JEV_PROBE_AUTH_STATUS="\$\(/,/^          \)"/ { print }' "$WORKFLOW"
)"

printf '%s\n' "$unauth_probe" | grep -Fq -- '--output /dev/null'
printf '%s\n' "$auth_probe" | grep -Fq -- '--output /dev/null'
printf '%s\n' "$unauth_probe" | grep -Fq -- "--write-out '%{http_code}'"
printf '%s\n' "$auth_probe" | grep -Fq -- "--write-out '%{http_code}'"
printf '%s\n' "$auth_probe" | grep -Fq -- '--header "authorization: Bearer ${JEV_TRIAGE_TOKEN}"'
if printf '%s\n' "$unauth_probe" | grep -Fq -- '--header "authorization: Bearer ${JEV_TRIAGE_TOKEN}"'; then
  echo "unauthenticated diagnostic probe must not send the Bearer token" >&2
  exit 1
fi
[[ "$(grep -Fc -- '--header "authorization: Bearer ${JEV_TRIAGE_TOKEN}"' "$WORKFLOW")" -eq 1 ]]

if grep -Eq 'curl .*--verbose|curl .* -v( |$)' "$WORKFLOW"; then
  echo "diagnostic curl must not enable verbose output" >&2
  exit 1
fi

if grep -Fq '/tmp/jev-probe' "$WORKFLOW"; then
  echo "diagnostic response bodies must not be written to files" >&2
  exit 1
fi

# urllib ingress comparison contract
grep -Fq 'JEV_PROBE_URLLIB_AUTH_STATUS=' "$WORKFLOW"
grep -Fq 'import urllib.request' "$WORKFLOW"
grep -Fq 'import urllib.error' "$WORKFLOW"
grep -Fq 'data=b"{}"' "$WORKFLOW"
grep -Fq '"authorization": "Bearer " + token' "$WORKFLOW"
grep -Fq 'print(exc.code)' "$WORKFLOW"
grep -Fq 'print(response.status)' "$WORKFLOW"
grep -Fq 'class NoRedirect(urllib.request.HTTPRedirectHandler):' "$WORKFLOW"
grep -Fq 'return None' "$WORKFLOW"
grep -Fq 'urllib.request.build_opener(NoRedirect)' "$WORKFLOW"

urllib_probe="$(
  awk '/JEV_PROBE_URLLIB_AUTH_STATUS="\$\(/,/^          \)"/ { print }' "$WORKFLOW"
)"
printf '%s\n' "$urllib_probe" | grep -Fq 'urllib.request.Request('
printf '%s\n' "$urllib_probe" | grep -Fq 'data=b"{}"'
printf '%s\n' "$urllib_probe" | grep -Fq '"authorization": "Bearer " + token'
printf '%s\n' "$urllib_probe" | grep -Fq 'urllib.request.build_opener(NoRedirect)'
printf '%s\n' "$urllib_probe" | grep -Fq 'with opener.open(request, timeout=20) as response:'
if printf '%s\n' "$urllib_probe" | grep -Fq 'urllib.request.urlopen('; then
  echo "urllib diagnostic probe must not use redirect-following urlopen" >&2
  exit 1
fi
if printf '%s\n' "$urllib_probe" | grep -Fq '.read('; then
  echo "urllib diagnostic probe must not read or log the response body" >&2
  exit 1
fi
