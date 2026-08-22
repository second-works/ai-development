#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "Usage: $0 <repo-identity> <pr-number> <expected-sha> [timeout-seconds]" >&2
  exit 2
fi

REPO_IDENTITY="$1"
PR="$2"
EXPECTED_SHA="$3"
TIMEOUT="${4:-300}"
INTERVAL=5
START="$(date +%s)"
SHORT10="${EXPECTED_SHA:0:10}"

command -v gh >/dev/null 2>&1 || { echo "ERROR: gh not found" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 not found" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "ERROR: gh authentication is not available" >&2; exit 1; }

if [[ "$REPO_IDENTITY" != */*/* ]]; then
  echo "ERROR: repository identity must be HOST/owner/repo" >&2
  exit 1
fi
HOST="${REPO_IDENTITY%%/*}"
REPO_PATH="${REPO_IDENTITY#*/}"

TMPDIR_RUN="$(mktemp -d "${TMPDIR:-/tmp}/pr-review-codex.XXXXXX")"
trap 'rm -rf "$TMPDIR_RUN"' EXIT

while :; do
  NOW="$(date +%s)"
  ELAPSED=$((NOW - START))

  gh api --hostname "$HOST" --paginate --slurp \
    "repos/$REPO_PATH/issues/$PR/comments?per_page=100" \
    >"$TMPDIR_RUN/issue-comments.json"
  gh api --hostname "$HOST" --paginate --slurp \
    "repos/$REPO_PATH/pulls/$PR/comments?per_page=100" \
    >"$TMPDIR_RUN/review-comments.json"

  RESULT="$(python3 - "$TMPDIR_RUN/issue-comments.json" "$TMPDIR_RUN/review-comments.json" "$EXPECTED_SHA" "$SHORT10" <<'PY'
import json, re, sys
issue_path, review_path, sha, short10 = sys.argv[1:]

def flatten_pages(path):
    with open(path, encoding='utf-8') as f:
        pages = json.load(f)
    out = []
    for page in pages:
        if isinstance(page, list):
            out.extend(page)
        elif isinstance(page, dict):
            out.append(page)
    return out

issue_comments = flatten_pages(issue_path)
review_comments = flatten_pages(review_path)

review_seen = False
for c in issue_comments:
    login = ((c.get('user') or {}).get('login') or '').lower()
    body = c.get('body') or ''
    if 'codex' in login and 'Reviewed commit:' in body and (short10 in body or sha in body):
        review_seen = True

severities = []
for c in review_comments:
    login = ((c.get('user') or {}).get('login') or '').lower()
    body = c.get('body') or ''
    commit_id = c.get('commit_id') or ''
    if 'codex' not in login:
        continue
    if commit_id != sha:
        continue
    for sev in ('P0', 'P1', 'P2'):
        if re.search(rf'\b{sev}\b', body):
            severities.append(sev)

print(f"REVIEW_SEEN={1 if review_seen else 0}")
print(f"BLOCKING_COUNT={len(severities)}")
if severities:
    print("BLOCKING_SEVERITIES=" + ','.join(sorted(set(severities))))
PY
)"

  REVIEW_SEEN="$(printf '%s\n' "$RESULT" | awk -F= '$1=="REVIEW_SEEN"{print $2}')"
  BLOCKING_COUNT="$(printf '%s\n' "$RESULT" | awk -F= '$1=="BLOCKING_COUNT"{print $2}')"

  if [[ "$REVIEW_SEEN" -eq 1 ]]; then
    printf '%s\n' "$RESULT"
    echo "EXPECTED_SHA=$EXPECTED_SHA"
    if [[ "$BLOCKING_COUNT" -gt 0 ]]; then
      echo "STATUS=REVIEW_CHANGES_REQUIRED"
      exit 3
    fi
    echo "STATUS=REVIEW_PASSED"
    exit 0
  fi

  if [[ "$ELAPSED" -ge "$TIMEOUT" ]]; then
    echo "ERROR: timed out waiting for Codex review of $EXPECTED_SHA" >&2
    exit 1
  fi

  sleep "$INTERVAL"
done
