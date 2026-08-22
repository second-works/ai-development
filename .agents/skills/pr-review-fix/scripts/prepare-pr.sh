#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <pr-number>" >&2
  exit 2
fi

PR="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v git >/dev/null 2>&1 || { echo "ERROR: git not found" >&2; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "ERROR: gh not found" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 not found" >&2; exit 1; }

gh auth status >/dev/null 2>&1 || { echo "ERROR: gh authentication is not available" >&2; exit 1; }

git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "ERROR: not inside a git repository" >&2; exit 1; }
cd "$(git rev-parse --show-toplevel)"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "ERROR: working tree is not clean" >&2
  exit 1
fi

# gh の default repository 設定に依存せず、push先の origin を明示的な対象repoにする。
ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
if [[ -z "$ORIGIN_URL" ]]; then
  echo "ERROR: origin remote is not configured" >&2
  exit 1
fi

repo_slug_from_url() {
  local url="$1"
  local slug
  case "$url" in
    git@*:*/*)
      slug="${url#*:}"
      ;;
    ssh://git@*/*/*)
      slug="${url#ssh://git@}"
      slug="${slug#*/}"
      ;;
    http://*/*/*|https://*/*/*)
      slug="${url#*://}"
      slug="${slug#*/}"
      ;;
    *)
      echo "ERROR: unsupported origin URL: $url" >&2
      return 1
      ;;
  esac
  slug="${slug%.git}"
  if [[ "$slug" != */* ]]; then
    echo "ERROR: could not resolve owner/repo from origin URL: $url" >&2
    return 1
  fi
  printf '%s\n' "$slug"
}

REPO="$(repo_slug_from_url "$ORIGIN_URL")"
DEFAULT_BRANCH="$(gh repo view "$REPO" --json defaultBranchRef --jq '.defaultBranchRef.name')"
PR_JSON="$(gh pr view "$PR" --repo "$REPO" --json number,state,headRefName,headRefOid,baseRefName,isCrossRepository,url)"

STATE="$(printf '%s' "$PR_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')"
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

# 古いPRのbranchへcheckoutするとrepo-local Skill自体が消える場合があるため、
# checkout前にscript一式をbranch非依存の一時ディレクトリへ退避する。
RUNTIME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pr-review-fix.${PR}.XXXXXX")"
cp -R "$SCRIPT_DIR" "$RUNTIME_DIR/scripts"

# checkout前に取得したhead SHAを修正前SHAとして固定する。
BEFORE_SHA="$HEAD_SHA"

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
  echo "Synchronize the existing PR head branch first; do not create another branch." >&2
  exit 1
fi

cat <<EOF
PR_NUMBER=$PR
PR_URL=$URL
REPO=$REPO
HEAD_BRANCH=$HEAD_BRANCH
BEFORE_SHA=$BEFORE_SHA
HEAD_SHA=$HEAD_SHA
DEFAULT_BRANCH=$DEFAULT_BRANCH
RUNTIME_DIR=$RUNTIME_DIR
VERIFY_SCRIPT=$RUNTIME_DIR/scripts/verify-pr-head.sh
STATUS=READY
EOF
