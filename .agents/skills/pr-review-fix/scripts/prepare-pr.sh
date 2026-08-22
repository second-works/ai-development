#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <pr-number>" >&2
  exit 2
fi

PR="$1"

command -v git >/dev/null 2>&1 || { echo "ERROR: git not found" >&2; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "ERROR: gh not found" >&2; exit 1; }

gh auth status >/dev/null 2>&1 || { echo "ERROR: gh authentication is not available" >&2; exit 1; }

git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "ERROR: not inside a git repository" >&2; exit 1; }
cd "$(git rev-parse --show-toplevel)"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "ERROR: working tree is not clean" >&2
  exit 1
fi

DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')"

PR_JSON="$(gh pr view "$PR" --json number,state,headRefName,headRefOid,baseRefName,isCrossRepository,url)"
STATE="$(printf '%s' "$PR_JSON" | gh api --method POST /graphql -f query='query($v:String!){__typename}' -f v=x >/dev/null 2>&1; printf '%s' "$PR_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')"
HEAD_BRANCH="$(printf '%s' "$PR_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["headRefName"])')"
HEAD_SHA="$(printf '%s' "$PR_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["headRefOid"])')"
CROSS_REPO="$(printf '%s' "$PR_JSON" | python3 -c 'import json,sys; print(str(json.load(sys.stdin)["isCrossRepository"]).lower())')"
URL="$(printf '%s' "$PR_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["url"])')"

if [[ "$STATE" != "OPEN" ]]; then
  echo "ERROR: PR #$PR is not open (state=$STATE)" >&2
  exit 1
fi

if [[ "$CROSS_REPO" == "true" ]]; then
  echo "ERROR: cross-repository PR is not supported by this skill" >&2
  exit 1
fi

if [[ -z "$HEAD_BRANCH" || -z "$HEAD_SHA" ]]; then
  echo "ERROR: could not resolve PR head branch/SHA" >&2
  exit 1
fi

if [[ "$HEAD_BRANCH" == "$DEFAULT_BRANCH" ]]; then
  echo "ERROR: PR head branch is the default branch ($DEFAULT_BRANCH)" >&2
  exit 1
fi

git fetch origin "$HEAD_BRANCH"

if git show-ref --verify --quiet "refs/heads/$HEAD_BRANCH"; then
  git checkout "$HEAD_BRANCH"
else
  git checkout --track -b "$HEAD_BRANCH" "origin/$HEAD_BRANCH"
fi

CURRENT_BRANCH="$(git branch --show-current)"
if [[ "$CURRENT_BRANCH" != "$HEAD_BRANCH" ]]; then
  echo "ERROR: checkout mismatch: current=$CURRENT_BRANCH expected=$HEAD_BRANCH" >&2
  exit 1
fi

LOCAL_SHA="$(git rev-parse HEAD)"
if [[ "$LOCAL_SHA" != "$HEAD_SHA" ]]; then
  echo "ERROR: local HEAD does not match GitHub PR head SHA" >&2
  echo "  local:  $LOCAL_SHA" >&2
  echo "  github: $HEAD_SHA" >&2
  echo "Update/synchronize the existing PR head branch first; do not create another branch." >&2
  exit 1
fi

cat <<EOF
PR_NUMBER=$PR
PR_URL=$URL
HEAD_BRANCH=$HEAD_BRANCH
HEAD_SHA=$HEAD_SHA
DEFAULT_BRANCH=$DEFAULT_BRANCH
STATUS=READY
EOF
