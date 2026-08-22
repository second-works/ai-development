#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <pr-number> [expected-sha]" >&2
  exit 2
fi

PR="$1"
EXPECTED_SHA="${2:-$(git rev-parse HEAD)}"

command -v git >/dev/null 2>&1 || { echo "ERROR: git not found" >&2; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "ERROR: gh not found" >&2; exit 1; }

gh auth status >/dev/null 2>&1 || { echo "ERROR: gh authentication is not available" >&2; exit 1; }

cd "$(git rev-parse --show-toplevel)"

PR_JSON="$(gh pr view "$PR" --json number,state,headRefName,headRefOid,isCrossRepository,url)"
STATE="$(printf '%s' "$PR_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')"
HEAD_BRANCH="$(printf '%s' "$PR_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["headRefName"])')"
GITHUB_SHA="$(printf '%s' "$PR_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["headRefOid"])')"
CROSS_REPO="$(printf '%s' "$PR_JSON" | python3 -c 'import json,sys; print(str(json.load(sys.stdin)["isCrossRepository"]).lower())')"
CURRENT_BRANCH="$(git branch --show-current)"
LOCAL_SHA="$(git rev-parse HEAD)"

if [[ "$STATE" != "OPEN" ]]; then
  echo "ERROR: PR #$PR is not open (state=$STATE)" >&2
  exit 1
fi

if [[ "$CROSS_REPO" == "true" ]]; then
  echo "ERROR: cross-repository PR is not supported by this skill" >&2
  exit 1
fi

if [[ "$CURRENT_BRANCH" != "$HEAD_BRANCH" ]]; then
  echo "ERROR: branch mismatch" >&2
  echo "  current: $CURRENT_BRANCH" >&2
  echo "  PR head: $HEAD_BRANCH" >&2
  exit 1
fi

if [[ "$LOCAL_SHA" != "$EXPECTED_SHA" ]]; then
  echo "ERROR: local HEAD differs from expected pushed SHA" >&2
  echo "  local:    $LOCAL_SHA" >&2
  echo "  expected: $EXPECTED_SHA" >&2
  exit 1
fi

# GitHub側への反映に短い遅延がある場合だけ待つ。最大約15秒。
for _ in 1 2 3 4 5; do
  GITHUB_SHA="$(gh pr view "$PR" --json headRefOid --jq '.headRefOid')"
  [[ "$GITHUB_SHA" == "$EXPECTED_SHA" ]] && break
  sleep 3
done

if [[ "$GITHUB_SHA" != "$EXPECTED_SHA" ]]; then
  echo "ERROR: GitHub PR head SHA does not match pushed commit SHA" >&2
  echo "  github:   $GITHUB_SHA" >&2
  echo "  expected: $EXPECTED_SHA" >&2
  echo "Do not re-test or re-review. Fix the existing PR head branch first." >&2
  exit 1
fi

cat <<EOF
PR_NUMBER=$PR
HEAD_BRANCH=$HEAD_BRANCH
LOCAL_SHA=$LOCAL_SHA
GITHUB_PR_HEAD_SHA=$GITHUB_SHA
EXPECTED_SHA=$EXPECTED_SHA
STATUS=VERIFIED
EOF
