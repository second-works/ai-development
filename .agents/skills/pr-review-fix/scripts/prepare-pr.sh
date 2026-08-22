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

repo_identity_from_url() {
  local url="$1"
  local host path identity

  case "$url" in
    git@*:*/*)
      host="${url#git@}"
      host="${host%%:*}"
      path="${url#*:}"
      ;;
    ssh://git@*/*/*)
      local rest
      rest="${url#ssh://git@}"
      host="${rest%%/*}"
      path="${rest#*/}"
      # gh --repo does not encode a custom SSH port in repository identity.
      if [[ "$host" == *:* ]]; then
        echo "ERROR: SSH URL with explicit port is not supported safely: $url" >&2
        return 1
      fi
      ;;
    http://*/*/*|https://*/*/*)
      local rest
      rest="${url#*://}"
      host="${rest%%/*}"
      path="${rest#*/}"
      ;;
    *)
      echo "ERROR: unsupported Git remote URL: $url" >&2
      return 1
      ;;
  esac

  path="${path%.git}"
  if [[ -z "$host" || "$path" != */* || "$path" == */*/* ]]; then
    echo "ERROR: could not resolve HOST/owner/repo from remote URL: $url" >&2
    return 1
  fi

  identity="${host}/${path}"
  # GitHub repository identity is case-insensitive; normalize before comparison.
  printf '%s\n' "$identity" | tr '[:upper:]' '[:lower:]'
}

# origin のfetch先と、実際に push される全 pushurl を事前検証する。
ORIGIN_FETCH_URL="$(git remote get-url origin 2>/dev/null || true)"
if [[ -z "$ORIGIN_FETCH_URL" ]]; then
  echo "ERROR: origin fetch URL is not configured" >&2
  exit 1
fi

mapfile -t ORIGIN_PUSH_URLS < <(git remote get-url --push --all origin 2>/dev/null || true)
if [[ ${#ORIGIN_PUSH_URLS[@]} -eq 0 ]]; then
  echo "ERROR: origin push URL is not configured" >&2
  exit 1
fi

REPO="$(repo_identity_from_url "$ORIGIN_FETCH_URL")"
for push_url in "${ORIGIN_PUSH_URLS[@]}"; do
  PUSH_REPO="$(repo_identity_from_url "$push_url")"
  if [[ "$PUSH_REPO" != "$REPO" ]]; then
    echo "ERROR: origin push repository differs from fetch/GitHub repository" >&2
    echo "  fetch identity: $REPO" >&2
    echo "  push URL:       $push_url" >&2
    echo "  push identity:  $PUSH_REPO" >&2
    echo "Do not push until every origin push URL targets the same GitHub repository." >&2
    exit 1
  fi
done

# HOST/owner/repo を明示して gh の既定host/repository設定に依存しない。
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

# sourceだけのfetchではremote-tracking refが更新されない場合があるため、destinationを明示する。
git fetch origin "+refs/heads/$HEAD_BRANCH:refs/remotes/origin/$HEAD_BRANCH"

if git show-ref --verify --quiet "refs/heads/$HEAD_BRANCH"; then
  git checkout "$HEAD_BRANCH"
  # 既存local branchが古い場合に勝手にresetせず、SHA不一致として安全に停止させる。
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
ORIGIN_FETCH_URL=$ORIGIN_FETCH_URL
ORIGIN_PUSH_URL_COUNT=${#ORIGIN_PUSH_URLS[@]}
RUNTIME_DIR=$RUNTIME_DIR
VERIFY_SCRIPT=$RUNTIME_DIR/scripts/verify-pr-head.sh
STATUS=READY
EOF
