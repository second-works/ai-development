#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "Usage: $0 <pr-number> <expected-sha> <before-sha> [repo]" >&2
  exit 2
fi

PR="$1"
EXPECTED_SHA="$2"
BEFORE_SHA="$3"
REPO="${4:-}"

command -v git >/dev/null 2>&1 || { echo "ERROR: git not found" >&2; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "ERROR: gh not found" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 not found" >&2; exit 1; }

gh auth status >/dev/null 2>&1 || { echo "ERROR: gh authentication is not available" >&2; exit 1; }
cd "$(git rev-parse --show-toplevel)"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "ERROR: working tree is not clean" >&2
  exit 1
fi

if [[ "$EXPECTED_SHA" == "$BEFORE_SHA" ]]; then
  echo "ERROR: expected SHA is unchanged from before SHA" >&2
  echo "  before:   $BEFORE_SHA" >&2
  echo "  expected: $EXPECTED_SHA" >&2
  exit 1
fi

if [[ -z "$REPO" ]]; then
  ORIGIN_FETCH_URL="$(git remote get-url origin 2>/dev/null || true)"
  ORIGIN_PUSH_URL="$(git remote get-url --push origin 2>/dev/null || true)"
  if [[ -z "$ORIGIN_FETCH_URL" || -z "$ORIGIN_PUSH_URL" ]]; then
    echo "ERROR: repo not supplied and origin fetch/push URL unavailable" >&2
    exit 1
  fi
  repo_slug_from_url() {
    local url="$1"
    local slug
    case "$url" in
      git@*:*/*) slug="${url#*:}" ;;
      ssh://git@*/*/*) slug="${url#ssh://git@}"; slug="${slug#*/}" ;;
      http://*/*/*|https://*/*/*) slug="${url#*://}"; slug="${slug#*/}" ;;
      *) echo "ERROR: unsupported Git remote URL: $url" >&2; return 1 ;;
    esac
    slug="${slug%.git}"
    printf '%s\n' "$slug"
  }
  FETCH_REPO="$(repo_slug_from_url "$ORIGIN_FETCH_URL")"
  PUSH_REPO="$(repo_slug_from_url "$ORIGIN_PUSH_URL")"
  if [[ "$FETCH_REPO" != "$PUSH_REPO" ]]; then
    echo "ERROR: origin fetch/push repository mismatch" >&2
    exit 1
  fi
  REPO="$FETCH_REPO"
fi

PR_JSON="$(gh pr view "$PR" --repo "$REPO" --json number,state,headRefName,headRefOid,isCrossRepository,url)"
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
  GITHUB_SHA="$(gh pr view "$PR" --repo "$REPO" --json headRefOid --jq '.headRefOid')"
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
REPO=$REPO
HEAD_BRANCH=$HEAD_BRANCH
BEFORE_SHA=$BEFORE_SHA
LOCAL_SHA=$LOCAL_SHA
GITHUB_PR_HEAD_SHA=$GITHUB_SHA
EXPECTED_SHA=$EXPECTED_SHA
STATUS=VERIFIED
EOF
