#!/usr/bin/env bash
# Checks the lightweight candidate (#194) in temporary repositories only.
# Nothing here talks to GitHub or pushes anywhere.

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
CAND="$ROOT/templates/lightweight"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { printf 'lightweight-template: %s\n' "$1" >&2; exit 1; }
expect_status() { # <expected> <actual> <label>
  [[ $2 -eq $1 ]] || fail "$3: expected exit $1, got $2"
}

new_repo() { # <dir> [branch]
  mkdir -p "$1"
  git -C "$1" init -q -b "${2:-feature/issue-1-sample}"
  git -C "$1" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
}

# --- 1. Content of the candidate -------------------------------------------
agents="$CAND/AGENTS.md"
[[ $(wc -l <"$agents") -le 45 ]] || fail "AGENTS.md is longer than 45 lines"
[[ $(wc -c <"$agents") -le 4500 ]] || fail "AGENTS.md is larger than 4.5 KB"
for banned in nine-standard-ai-development-flow pr-review-fix minimal-development-contract; do
  ! grep -q "$banned" "$agents" || fail "AGENTS.md still points to $banned"
done
for kept in 'mainへ直接pushしない' 'force pushしない' 'Secrets' '全件skip' '古い結果を使わない' '人間の承認' '未確認のものを完了と報告しない'; do
  grep -q "$kept" "$agents" || fail "AGENTS.md lost the rule: $kept"
done
steward="$CAND/.claude/skills/steward/SKILL.md"
for banned in pr-review-fix JEV 'IN-SCOPE FIX' 'Local Judge'; do
  ! grep -q "$banned" "$steward" || fail "steward copied $banned from pr-review-fix"
done
[[ $(head -1 "$CAND/CLAUDE.md") == '@AGENTS.md' ]] || fail "CLAUDE.md does not import AGENTS.md"
jq -e . "$CAND/.claude/settings.json" >/dev/null || fail "settings.json is not valid JSON"

# --- 2. Placement -------------------------------------------------------------
proj="$WORK/project"
new_repo "$proj"
out="$("$CAND/place.sh" --dry-run "$proj")"
[[ $(grep -c '^would create: ' <<<"$out") -eq 12 ]] || fail "dry-run did not list 12 files"
[[ -z $(find "$proj" -path "$proj/.git" -prune -o -type f -print) ]] || fail "dry-run wrote files"

"$CAND/place.sh" "$proj" >/dev/null
for f in AGENTS.md CLAUDE.md .agents/skills/plan-to-issues/SKILL.md .claude/skills/steward/SKILL.md \
  .claude/settings.json .claude/hooks/guard-git-push.sh .github/ISSUE_TEMPLATE/child-issue.md \
  .github/ISSUE_TEMPLATE/parent-issue.md .github/pull_request_template.md \
  scripts/verify.sh scripts/security-preflight.sh scripts/check-pr-head.sh; do
  [[ -f $proj/$f ]] || fail "placement did not create $f"
done
for f in .claude/hooks/guard-git-push.sh scripts/verify.sh scripts/security-preflight.sh scripts/check-pr-head.sh; do
  [[ -x $proj/$f ]] || fail "$f is not executable after placement"
done
cmp -s "$ROOT/templates/verification/verify.sh" "$proj/scripts/verify.sh" || fail "verify.sh is not the existing original"

before="$(cd "$proj" && find . -path ./.git -prune -o -type f -print | sort | xargs shasum)"
set +e; "$CAND/place.sh" "$proj" >/dev/null 2>"$WORK/err"; status=$?; set -e
expect_status 1 "$status" "re-running placement"
grep -q 'Nothing was written' "$WORK/err" || fail "re-run did not explain that nothing was written"
[[ $before == "$(cd "$proj" && find . -path ./.git -prune -o -type f -print | sort | xargs shasum)" ]] ||
  fail "re-run changed existing files"

conflict="$WORK/conflict"
new_repo "$conflict"
printf 'own rules\n' >"$conflict/CLAUDE.md"
set +e; "$CAND/place.sh" "$conflict" >/dev/null 2>"$WORK/err"; status=$?; set -e
expect_status 1 "$status" "placement over an existing CLAUDE.md"
grep -q 'conflict: CLAUDE.md' "$WORK/err" || fail "conflict was not reported"
[[ ! -e $conflict/AGENTS.md && $(<"$conflict/CLAUDE.md") == 'own rules' ]] || fail "placement wrote despite a conflict"

partial="$WORK/partial"
new_repo "$partial"
printf 'not a directory\n' >"$partial/.github"
set +e; "$CAND/place.sh" "$partial" >/dev/null 2>"$WORK/err"; status=$?; set -e
expect_status 1 "$status" "placement that fails part way"
grep -q 'removed the' "$WORK/err" || fail "partial failure did not roll back"
[[ ! -e $partial/AGENTS.md && ! -e $partial/.claude/settings.json ]] || fail "rollback left files from this run"
[[ $(<"$partial/.github") == 'not a directory' ]] || fail "rollback touched a file it did not create"

# Generated projects may run these scripts with macOS Bash 3.2.
if [[ -x /bin/bash ]] && /bin/bash -c '((BASH_VERSINFO[0] < 5))'; then
  old="$WORK/bash32"
  new_repo "$old"
  /bin/bash "$CAND/place.sh" "$old" >/dev/null || fail "placement failed under Bash 3.2"
  set +e; /bin/bash "$CAND/place.sh" "$old" >/dev/null 2>&1; status=$?; set -e
  expect_status 1 "$status" "re-running placement under Bash 3.2"
  for c in 'git push origin main' 'git push -f'; do
    set +e
    /bin/bash "$old/.claude/hooks/guard-git-push.sh" <<<"$(jq -n --arg c "$c" --arg d "$old" '{tool_input: {command: $c}, cwd: $d}')" >/dev/null 2>&1
    status=$?
    set -e
    expect_status 2 "$status" "hook under Bash 3.2 for '$c'"
  done
fi

# --- 3. Standard verification and Security in the placed project ---------------
for stage in lint typecheck test build; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$proj/scripts/$stage.sh"
  chmod +x "$proj/scripts/$stage.sh"
done
(cd "$proj" && VERIFY_STACK=generic ./scripts/verify.sh >/dev/null) || fail "verify.sh failed in the placed project"
printf '#!/usr/bin/env bash\nexit 17\n' >"$proj/scripts/lint.sh"
set +e; (cd "$proj" && VERIFY_STACK=generic ./scripts/verify.sh >/dev/null 2>&1); status=$?; set -e
expect_status 17 "$status" "verify.sh with a failing lint stage"
git -C "$proj" add -A
sec="$(cd "$proj" && bash scripts/security-preflight.sh .)" || fail "Security Preflight did not pass in the placed project"
grep -q '^SECURITY_STATUS=SECURITY_PASSED$' <<<"$sec" || fail "Security Preflight did not report SECURITY_PASSED"

# --- 4. Push guard hook -------------------------------------------------------------
hook="$proj/.claude/hooks/guard-git-push.sh"
main_repo="$WORK/on-main"
new_repo "$main_repo" main
run_hook() { # <command> [cwd] -> exit status
  local payload
  payload="$(jq -n --arg c "$1" --arg d "${2:-$proj}" '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d}')"
  set +e; "$hook" <<<"$payload" >/dev/null 2>&1; local s=$?; set -e
  return "$s"
}
check_hook() { # <expected> <command> [cwd]
  local s=0
  run_hook "$2" "${3:-$proj}" || s=$?
  expect_status "$1" "$s" "hook for '$2'"
}
check_hook 0 'ls -la'
check_hook 0 'git push -u origin feature/issue-1-sample'
check_hook 0 'git push origin feature/main-fix'
check_hook 2 'git push origin main'
check_hook 2 'git push origin HEAD:main'
check_hook 2 'git push origin HEAD:refs/heads/master'
check_hook 2 'git status && git push origin main'
check_hook 2 'git push --force origin feature/issue-1-sample'
check_hook 2 'git push -f'
check_hook 2 'git push --force-with-lease'
check_hook 2 'git push origin +feature/issue-1-sample'
check_hook 2 'git push' "$main_repo"
set +e; "$hook" <<<'{"tool_input": git push origin main' >/dev/null 2>&1; status=$?; set -e
expect_status 2 "$status" "hook with unreadable input"
nojq="$WORK/nojq"
mkdir -p "$nojq"
for tool in bash cat tr git env; do ln -s "$(command -v "$tool")" "$nojq/$tool"; done
set +e
env PATH="$nojq" bash "$hook" <<<'{"tool_input":{"command":"git push origin feature/x"}}' >/dev/null 2>&1
status=$?
set -e
expect_status 2 "$status" "hook without jq"

# --- 5. Final-head check with synthetic GitHub data -----------------------------------
gate="$proj/scripts/check-pr-head.sh"
fake="$WORK/fake"
mkdir -p "$fake/bin"
cat >"$fake/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "pr view 7 --json headRefOid,url,state") f=pr.json ;;
  "pr view 7 --json comments") f=comments.json ;;
  api\ repos/*/check-runs*) f=checks.json ;;
  api\ graphql*) f=threads.json ;;
  *) exit 1 ;;
esac
[[ -f "$FAKE_GH/$f" ]] || exit 1
cat "$FAKE_GH/$f"
EOF
chmod +x "$fake/bin/gh"
head_sha="$(git -C "$proj" rev-parse HEAD)"
old_sha="$(printf 'old' | shasum | cut -c1-40)"
set_data() { # <pr-head> <checks> <review-sha> <review-status> <unresolved> <open-threads>
  local d="$fake/data"
  rm -rf "$d"; mkdir -p "$d"
  jq -n --arg h "$1" '{headRefOid: $h, url: "https://github.com/acme/app/pull/7", state: "OPEN"}' >"$d/pr.json"
  printf '%s' "$2" >"$d/checks.json"
  if [[ -n $3 ]]; then
    jq -n --arg s "$3" --arg st "$4" --argjson u "$5" '{comments: [{author: {login: "chatgpt-codex-connector"},
      body: ("<!-- codex-review-state:v1 " + ({code_review: {commit_sha: $s, status: $st, has_unresolved_findings: $u}} | tojson) + " -->")}]}' >"$d/comments.json"
  else
    printf '{"comments": []}' >"$d/comments.json"
  fi
  jq -n --argjson n "$6" '{data: {repository: {pullRequest: {reviewThreads: {nodes: ([range(0; $n)] | map({isResolved: false}) + [{isResolved: true}])}}}}}' >"$d/threads.json"
}
ok_checks='{"check_runs":[{"name":"verification","status":"completed","conclusion":"success"},{"name":"Security Preflight","status":"completed","conclusion":"success"}]}'
check_gate() { # <expected-status> <label>
  local out s=0
  out="$(cd "$proj" && FAKE_GH="$fake/data" PATH="$fake/bin:$PATH" "$gate" 7 2>&1)" || s=$?
  grep -q "^PR_GATE_STATUS=$1$" <<<"$out" || fail "$2: expected $1, got: $out"
  if [[ $1 == READY ]]; then expect_status 0 "$s" "$2"; else expect_status 1 "$s" "$2"; fi
}
set_data "$head_sha" "$ok_checks" "$head_sha" completed false 0
check_gate READY "all clear"
set_data "$old_sha" "$ok_checks" "$old_sha" completed false 0
check_gate STALE_HEAD "local HEAD differs from the PR head"
set_data "$head_sha" '{"check_runs":[{"name":"verification","status":"completed","conclusion":"success"}]}' "$head_sha" completed false 0
check_gate CHECK_UNAVAILABLE "Security check missing"
set_data "$head_sha" '{"check_runs":[{"name":"verification","status":"completed","conclusion":"success"},{"name":"Security Preflight","status":"completed","conclusion":"skipped"}]}' "$head_sha" completed false 0
check_gate CHECK_UNAVAILABLE "Security check skipped"
set_data "$head_sha" '{"check_runs":[{"name":"verification","status":"completed","conclusion":"failure"},{"name":"Security Preflight","status":"completed","conclusion":"success"}]}' "$head_sha" completed false 0
check_gate CHECK_FAILED "CI failed"
set_data "$head_sha" '{"check_runs":[{"name":"verification","status":"in_progress","conclusion":null},{"name":"Security Preflight","status":"completed","conclusion":"success"}]}' "$head_sha" completed false 0
check_gate CHECK_PENDING "CI still running"
set_data "$head_sha" "$ok_checks" "$old_sha" completed false 0
check_gate REVIEW_PENDING "review only for an older head"
set_data "$head_sha" "$ok_checks" "$head_sha" running null 0
check_gate REVIEW_PENDING "review still running"
set_data "$head_sha" "$ok_checks" "$head_sha" completed true 0
check_gate REVIEW_FINDINGS "review has findings"
set_data "$head_sha" "$ok_checks" "" completed false 0
check_gate REVIEW_UNAVAILABLE "no review state"
set_data "$head_sha" "$ok_checks" "$head_sha" completed false 2
check_gate UNRESOLVED_THREADS "unresolved threads"
rm -f "$fake/data/pr.json"
check_gate UNAVAILABLE "PR cannot be read"

echo "lightweight-template: all checks passed"
