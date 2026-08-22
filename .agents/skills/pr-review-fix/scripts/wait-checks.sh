#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 5 ]]; then
  echo "Usage: $0 <repo-identity> <expected-sha> [timeout-seconds] [no-checks-grace-seconds] [stability-seconds]" >&2
  exit 2
fi

REPO_IDENTITY="$1"
EXPECTED_SHA="$2"
TIMEOUT="${3:-300}"
NO_CHECKS_GRACE="${4:-60}"
STABILITY_SECONDS="${5:-30}"
INTERVAL=5
START="$(date +%s)"
STABLE_SINCE=""
LAST_SIGNATURE=""

command -v gh >/dev/null 2>&1 || { echo "ERROR: gh not found" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 not found" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "ERROR: gh authentication is not available" >&2; exit 1; }

if [[ "$REPO_IDENTITY" != */*/* ]]; then
  echo "ERROR: repository identity must be HOST/owner/repo" >&2
  exit 1
fi
HOST="${REPO_IDENTITY%%/*}"
REPO_PATH="${REPO_IDENTITY#*/}"

TMPDIR_RUN="$(mktemp -d "${TMPDIR:-/tmp}/pr-review-checks.XXXXXX")"
trap 'rm -rf "$TMPDIR_RUN"' EXIT

while :; do
  NOW="$(date +%s)"
  ELAPSED=$((NOW - START))

  gh api --hostname "$HOST" --paginate --slurp \
    "repos/$REPO_PATH/commits/$EXPECTED_SHA/check-runs?per_page=100" \
    >"$TMPDIR_RUN/check-runs.json"
  gh api --hostname "$HOST" --paginate --slurp \
    "repos/$REPO_PATH/commits/$EXPECTED_SHA/status?per_page=100" \
    >"$TMPDIR_RUN/status.json"

  RESULT="$(python3 - "$TMPDIR_RUN/check-runs.json" "$TMPDIR_RUN/status.json" <<'PY'
import json, sys, hashlib

with open(sys.argv[1], encoding='utf-8') as f:
    check_pages = json.load(f)
with open(sys.argv[2], encoding='utf-8') as f:
    status_pages = json.load(f)

checks = []
for page in check_pages:
    if isinstance(page, dict):
        checks.extend(page.get('check_runs', []))

statuses = []
for page in status_pages:
    if isinstance(page, dict):
        statuses.extend(page.get('statuses', []))

ok_conclusions = {'success', 'neutral', 'skipped'}
failed = []
pending = []
items = []
for r in checks:
    name = r.get('name') or '<unnamed-check>'
    status = r.get('status')
    conclusion = r.get('conclusion')
    items.append(('check', str(r.get('id') or ''), name, status or '', conclusion or ''))
    if status != 'completed':
        pending.append(name)
    elif conclusion not in ok_conclusions:
        failed.append(f"{name}:{conclusion}")
for s in statuses:
    name = s.get('context') or '<unnamed-status>'
    state = s.get('state')
    items.append(('status', str(s.get('id') or ''), name, state or '', ''))
    if state == 'pending':
        pending.append(name)
    elif state != 'success':
        failed.append(f"{name}:{state}")

signature = hashlib.sha256(repr(sorted(items)).encode()).hexdigest()
print(f"COUNT={len(checks) + len(statuses)}")
print(f"PENDING={len(pending)}")
print(f"FAILED={len(failed)}")
print(f"SIGNATURE={signature}")
if pending:
    print("PENDING_NAMES=" + ",".join(sorted(pending)))
if failed:
    print("FAILED_NAMES=" + ",".join(sorted(failed)))
PY
)"

  COUNT="$(printf '%s\n' "$RESULT" | awk -F= '$1=="COUNT"{print $2}')"
  PENDING="$(printf '%s\n' "$RESULT" | awk -F= '$1=="PENDING"{print $2}')"
  FAILED="$(printf '%s\n' "$RESULT" | awk -F= '$1=="FAILED"{print $2}')"
  SIGNATURE="$(printf '%s\n' "$RESULT" | awk -F= '$1=="SIGNATURE"{print $2}')"

  if [[ "$FAILED" -gt 0 ]]; then
    printf '%s\n' "$RESULT" >&2
    echo "ERROR: CI/security check failed for $EXPECTED_SHA" >&2
    exit 1
  fi

  if [[ "$COUNT" -gt 0 && "$PENDING" -eq 0 ]]; then
    if [[ "$SIGNATURE" != "$LAST_SIGNATURE" || -z "$STABLE_SINCE" ]]; then
      LAST_SIGNATURE="$SIGNATURE"
      STABLE_SINCE="$NOW"
    fi

    STABLE_FOR=$((NOW - STABLE_SINCE))
    if [[ "$STABLE_FOR" -ge "$STABILITY_SECONDS" ]]; then
      printf '%s\n' "$RESULT"
      echo "EXPECTED_SHA=$EXPECTED_SHA"
      echo "STABLE_SECONDS=$STABLE_FOR"
      echo "STATUS=CHECKS_PASSED_STABLE"
      exit 0
    fi
  else
    STABLE_SINCE=""
    LAST_SIGNATURE="$SIGNATURE"
  fi

  if [[ "$COUNT" -eq 0 && "$ELAPSED" -ge "$NO_CHECKS_GRACE" ]]; then
    echo "EXPECTED_SHA=$EXPECTED_SHA" >&2
    echo "WAITED_SECONDS=$ELAPSED" >&2
    echo "STATUS=NO_CHECKS_OBSERVED" >&2
    echo "ERROR: no CI/security checks were observed; explicit human decision is required before continuing" >&2
    exit 4
  fi

  if [[ "$ELAPSED" -ge "$TIMEOUT" ]]; then
    printf '%s\n' "$RESULT" >&2
    echo "ERROR: timed out waiting for stable CI/security checks for $EXPECTED_SHA" >&2
    exit 1
  fi

  sleep "$INTERVAL"
done
