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
# steward must not merge on its own: the parent #192 keeps the human merge.
for banned in pr-review-fix JEV 'IN-SCOPE FIX' 'Local Judge' 'gh pr merge'; do
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
[[ ! -e $partial/AGENTS.md && ! -e $partial/.claude && ! -e $partial/.agents ]] || fail "rollback left files or directories from this run"
[[ $(<"$partial/.github") == 'not a directory' ]] || fail "rollback touched a file it did not create"

interrupted="$WORK/interrupted"
new_repo "$interrupted"
shim="$WORK/slow-cp"
mkdir -p "$shim"
cat >"$shim/cp" <<EOF
#!/usr/bin/env bash
n=\$(( \$(cat "$shim/count" 2>/dev/null || echo 0) + 1 )); echo "\$n" >"$shim/count"
[[ \$n -eq 3 ]] && { touch "$shim/paused"; sleep 2; }
exec "$(command -v cp)" "\$@"
EOF
chmod +x "$shim/cp"
PATH="$shim:$PATH" "$CAND/place.sh" "$interrupted" >/dev/null 2>"$WORK/err" &
place_pid=$!
for _ in $(seq 50); do [[ -e $shim/paused ]] && break; sleep 0.1; done
[[ -e $shim/paused ]] || fail "interrupt test did not reach the third copy"
kill -TERM "$place_pid"
set +e; wait "$place_pid"; status=$?; set -e
expect_status 1 "$status" "interrupted placement"
grep -q 'removed the' "$WORK/err" || fail "interrupted placement did not roll back"
[[ -z $(find "$interrupted" -path "$interrupted/.git" -prune -o -mindepth 1 -print) ]] ||
  fail "interrupted placement left files or directories"

linked="$WORK/linked"
new_repo "$linked"
mkdir -p "$WORK/outside"
ln -s "$WORK/outside" "$linked/.claude"
set +e; "$CAND/place.sh" "$linked" >/dev/null 2>"$WORK/err"; status=$?; set -e
expect_status 1 "$status" "placement through a symlinked .claude"
grep -q 'conflict: .claude is a symlink' "$WORK/err" || fail "symlinked parent was not reported"
[[ -z $(ls -A "$WORK/outside") && ! -e $linked/AGENTS.md ]] || fail "placement wrote through a symlinked parent"

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
  set +e; ${HOOK_SH:-} "$hook" <<<"$payload" >/dev/null 2>&1; local s=$?; set -e
  return "$s"
}
check_hook() { # <expected> <command> [cwd]
  local s=0
  run_hook "$2" "${3:-$proj}" || s=$?
  expect_status "$1" "$s" "hook${HOOK_SH:+ under $HOOK_SH} for '$2'"
}
hook_cases() {
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
check_hook 0 'git commit -m "block push to main and more"'
check_hook 0 'git commit -m "push -f guard"'
check_hook 0 'gh pr comment 1 --body "use git push origin main carefully"'
check_hook 0 'git -C ../other push origin feature/a'
check_hook 2 'git push origin "main"'
check_hook 2 "git push origin 'HEAD:main'"
check_hook 2 '/usr/bin/git push origin main'
check_hook 2 '(git push --force)'
check_hook 2 'git -c core.x=1 push origin main'
check_hook 2 'FOO=1 git push -f'
check_hook 2 "git push origin '+feature/issue-1-sample'"
check_hook 2 "git push '--force' origin feature/issue-1-sample"
check_hook 2 "git push origin HEAD:'main'"
check_hook 2 'git push origin "$BRANCH"'
check_hook 0 'git push origin'
git -C "$proj" config remote.origin.push HEAD:refs/heads/main
check_hook 2 'git push origin'
git -C "$proj" config --unset remote.origin.push
git -C "$proj" config push.default upstream
git -C "$proj" config branch.feature/issue-1-sample.merge refs/heads/main
check_hook 2 'git push'
git -C "$proj" config branch.feature/issue-1-sample.merge refs/heads/feature/issue-1-sample
check_hook 0 'git push'
git -C "$proj" config --unset push.default
# Line continuations, shell keywords and wrappers before git.
check_hook 2 $'git push origin \\\n  main'
check_hook 2 $'git push \\\n  --force origin feature/issue-1-sample'
check_hook 2 'if true; then git push origin main; fi'
check_hook 2 'for i in 1; do git push --force origin feature/x; done'
check_hook 2 'time git push origin main'
check_hook 2 'command git push origin main'
check_hook 2 '! git push origin main'
check_hook 2 'env -i git push origin main'
check_hook 2 'xargs git push origin main'
check_hook 2 'git -C "/path/with space" push origin main'
check_hook 2 'git --git-dir .git push origin main'
# Pushes that select several branches.
check_hook 2 'git push --all origin'
check_hook 2 'git push origin :'
check_hook 2 "git push origin 'refs/heads/*:refs/heads/*'"
# Quoting or a variable that builds git or push.
check_hook 2 "g'it' p\"ush\" origin main"
check_hook 2 'SUB=push; git "$SUB" origin main'
# Free text in push options and other git commands are not pushes.
check_hook 0 'git push -o "ci +1" origin feature/issue-1-sample'
check_hook 0 'git commit -m "$(printf "push to main")"'
check_hook 0 'git status'
# A push inside command substitution, and wrappers that take values.
check_hook 2 'out=$(git push origin main)'
check_hook 2 'out=$(git push origin main 2>&1)'
check_hook 2 'echo "$(git push --force origin feature/x)"'
check_hook 2 'echo `git push origin main`'
check_hook 2 'timeout 60 git push origin main'
check_hook 2 'nice git push origin main'
check_hook 2 'sudo -u me git push origin main'
check_hook 2 'git push origin main>/tmp/push.log'
check_hook 2 'git push origin main 2>/tmp/push.log'
check_hook 2 'git push --force>/tmp/push.log'
check_hook 2 'git push --all>/tmp/push.log'
check_hook 0 'git push origin feature/issue-1-sample>/tmp/push.log'
check_hook 0 'out=$(git push origin feature/issue-1-sample 2>&1)'
check_hook 0 'out=`git push origin feature/issue-1-sample`'
check_hook 2 'out=$(git push origin "$BRANCH" 2>&1)'
check_hook 2 'out=$(git push origin $(echo main))'
check_hook 2 'out=`git push origin $B`'
git -C "$proj" config push.default matching
check_hook 2 'git push origin'
git -C "$proj" config --unset push.default
git -C "$proj" config remote.origin.push 'refs/heads/*:refs/heads/*'
check_hook 2 'git push origin'
git -C "$proj" config remote.origin.push HEAD:refs/heads/feature/issue-1-sample
check_hook 0 'git push origin'
git -C "$proj" config --unset remote.origin.push
}
hook_cases
if [[ -x /bin/bash ]] && /bin/bash -c '((BASH_VERSINFO[0] < 5))'; then HOOK_SH=/bin/bash hook_cases; fi
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
  "pr view 7 --json headRefOid,url,state,mergeable,reviewDecision,reviews")
    n=$(( $(cat "$FAKE_GH/pr-calls" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$FAKE_GH/pr-calls"
    f=pr.json; [[ $n -gt 1 && -f "$FAKE_GH/pr-later.json" ]] && f=pr-later.json ;;
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
set_data() { # <pr-head> <checks> <review-sha> <review-status> <unresolved> <open-threads> [mergeable] [more-threads] [decision]
  local d="$fake/data"
  rm -rf "$d"; mkdir -p "$d"
  jq -n --arg h "$1" --arg m "${7:-MERGEABLE}" --arg r "${9:-}" '{headRefOid: $h, url: "https://github.com/acme/app/pull/7", state: "OPEN", mergeable: $m, reviewDecision: $r}' >"$d/pr.json"
  printf '%s' "$2" >"$d/checks.json"
  if [[ -n $3 ]]; then
    jq -n --arg s "$3" --arg st "$4" --argjson u "$5" '{comments: [{author: {login: "chatgpt-codex-connector"},
      body: ("<!-- codex-review-state:v1 " + ({code_review: {commit_sha: $s, status: $st, has_unresolved_findings: $u}} | tojson) + " -->")}]}' >"$d/comments.json"
  else
    printf '{"comments": []}' >"$d/comments.json"
  fi
  jq -n --argjson n "$6" --argjson more "${8:-false}" '{data: {repository: {pullRequest: {reviewThreads: {pageInfo: {hasNextPage: $more},
    nodes: ([range(0; $n)] | map({isResolved: false}) + [{isResolved: true}])}}}}}' >"$d/threads.json"
}
ok_checks='{"check_runs":[{"name":"verification","status":"completed","conclusion":"success"},{"name":"Security Preflight","status":"completed","conclusion":"success"}]}'
check_gate() { # <expected-status> <label> [shell]
  local out s=0
  out="$(cd "$proj" && FAKE_GH="$fake/data" PATH="$fake/bin:$PATH" ${3:-bash} "$gate" 7 2>&1)" || s=$?
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
set_data "$head_sha" "$ok_checks" "$head_sha" completed false 0
jq --arg h "$old_sha" '.headRefOid = $h' "$fake/data/pr.json" >"$fake/data/pr-later.json"
check_gate STALE_HEAD "PR head changed during the check"
set_data "$head_sha" "$ok_checks" "$head_sha" completed false 0 false true
check_gate REVIEW_UNAVAILABLE "more than 100 review threads"
set_data "$head_sha" "$ok_checks" "$head_sha" completed false 0 CONFLICTING
check_gate CONFLICT "conflict with the base branch"
set_data "$head_sha" "$ok_checks" "$head_sha" completed false 0 UNKNOWN
check_gate MERGE_STATE_PENDING "conflict check not finished"
set_data "$head_sha" "$ok_checks" "$head_sha" completed false 0 MERGEABLE false CHANGES_REQUESTED
check_gate CHANGES_REQUESTED "a reviewer requested changes"
set_data "$head_sha" "$ok_checks" "$head_sha" completed false 0
jq '.mergeable = "CONFLICTING"' "$fake/data/pr.json" >"$fake/data/pr-later.json"
check_gate CONFLICT "base branch moved during the check"
set_data "$head_sha" "$ok_checks" "$head_sha" completed false 0
jq '.reviewDecision = "CHANGES_REQUESTED"' "$fake/data/pr.json" >"$fake/data/pr-later.json"
check_gate CHANGES_REQUESTED "changes requested during the check"
# Without required reviews GitHub leaves reviewDecision empty; the reviews themselves decide.
set_data "$head_sha" "$ok_checks" "$head_sha" completed false 0
jq '.reviews = [{author: {login: "pat"}, state: "CHANGES_REQUESTED", submittedAt: "2026-01-01T00:00:00Z"},
  {author: {login: "pat"}, state: "COMMENTED", submittedAt: "2026-01-02T00:00:00Z"}]' "$fake/data/pr.json" >"$fake/data/x" && mv "$fake/data/x" "$fake/data/pr.json"
check_gate CHANGES_REQUESTED "changes requested with an empty reviewDecision"
set_data "$head_sha" "$ok_checks" "$head_sha" completed false 0
jq '.reviews = [{author: {login: "pat"}, state: "CHANGES_REQUESTED", submittedAt: "2026-01-01T00:00:00Z"},
  {author: {login: "pat"}, state: "APPROVED", submittedAt: "2026-01-02T00:00:00Z"}]' "$fake/data/pr.json" >"$fake/data/x" && mv "$fake/data/x" "$fake/data/pr.json"
check_gate READY "changes requested, then approved by the same reviewer"
if [[ -x /bin/bash ]] && /bin/bash -c '((BASH_VERSINFO[0] < 5))'; then
  set_data "$head_sha" "$ok_checks" "$head_sha" completed false 0
  check_gate READY "all clear under Bash 3.2" /bin/bash
  set_data "$head_sha" '{"check_runs":[{"name":"verification","status":"completed","conclusion":"success"}]}' "$head_sha" completed false 0
  check_gate CHECK_UNAVAILABLE "Security check missing under Bash 3.2" /bin/bash
fi
rm -f "$fake/data/pr.json"
check_gate UNAVAILABLE "PR cannot be read"

echo "lightweight-template: all checks passed"
