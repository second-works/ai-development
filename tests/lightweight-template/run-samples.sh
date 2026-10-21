#!/usr/bin/env bash
# Checks the lightweight candidate (#194) and its placement (#195) in temporary repositories only.
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
# place.sh reads the candidate from a commit. Copy the working tree into a temporary
# source repository, so that this test checks the candidate files as they are now.
SRC="$WORK/source"
mkdir -p "$SRC/templates/verification" "$SRC/templates/security"
cp -R "$CAND" "$SRC/templates/lightweight"
cp -p "$ROOT/templates/verification/verify.sh" "$SRC/templates/verification/"
cp -p "$ROOT/templates/security/security-preflight.sh" "$SRC/templates/security/"
git -C "$SRC" init -q -b main
git -C "$SRC" add -A
git -C "$SRC" -c user.name=t -c user.email=t@example.invalid commit -q -m candidate
SRC_SHA="$(git -C "$SRC" rev-parse HEAD)"
PLACE="$SRC/templates/lightweight/place.sh"
STEWARD=templates/lightweight/.claude/skills/steward/SKILL.md

run_place() { # <args...>: sets status, out and err
  set +e
  "$PLACE" "$@" >"$WORK/out" 2>"$WORK/err"
  status=$?
  set -e
}
snapshot() { # <dir>: path, executable bit and checksum of every file outside .git
  (cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do
    if [[ -x $f ]]; then x=x; else x=-; fi
    printf '%s %s %s\n' "$f" "$x" "$(cksum <"$f")"
  done)
}
backups() { find "$1/.git/lightweight-placement" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' '; }
last_backup_status() { cat "$(find "$1/.git/lightweight-placement" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort | tail -1)/status"; }

# Fresh project: dry-run shows the source and the diff and writes nothing.
proj="$WORK/project"
new_repo "$proj"
run_place --dry-run "$proj"
expect_status 0 "$status" "dry-run"
[[ $(grep -c '^would create: ' "$WORK/out") -eq 13 ]] || fail "dry-run did not list 13 files"
grep -qx "source: $SRC_SHA" "$WORK/out" || fail "dry-run did not show the full source SHA"
grep -q '^+++ b/AGENTS.md' "$WORK/out" || fail "dry-run did not show the diff"
[[ -z $(find "$proj" -path "$proj/.git" -prune -o -type f -print) && $(backups "$proj") -eq 0 ]] || fail "dry-run wrote files"

run_place "$proj"
expect_status 0 "$status" "placement"
for f in AGENTS.md CLAUDE.md .agents/skills/plan-to-issues/SKILL.md .claude/skills/steward/SKILL.md \
  .claude/settings.json .claude/hooks/guard-git-push.sh .github/ISSUE_TEMPLATE/child-issue.md \
  .github/ISSUE_TEMPLATE/parent-issue.md .github/pull_request_template.md \
  scripts/verify.sh scripts/security-preflight.sh scripts/check-pr-head.sh .ai/lightweight-placement.tsv; do
  [[ -f $proj/$f ]] || fail "placement did not create $f"
done
for f in .claude/hooks/guard-git-push.sh scripts/verify.sh scripts/security-preflight.sh scripts/check-pr-head.sh; do
  [[ -x $proj/$f ]] || fail "$f is not executable after placement"
done
cmp -s "$ROOT/templates/verification/verify.sh" "$proj/scripts/verify.sh" || fail "verify.sh is not the existing original"
grep -qxF "$(printf 'source\t%s' "$SRC_SHA")" "$proj/.ai/lightweight-placement.tsv" || fail "the full source SHA was not recorded"
grep -q 'not verified yet' "$WORK/out" || fail "placement did not say that it is not verified yet"

# Re-running changes nothing and makes no new backup.
before="$(snapshot "$proj")"
run_place "$proj"
expect_status 0 "$status" "re-running placement"
grep -q 'nothing to change' "$WORK/out" || fail "re-run did not say that nothing changed"
[[ $before == "$(snapshot "$proj")" && $(backups "$proj") -eq 1 ]] || fail "re-run changed files or made a backup"

run_place --check "$proj"
expect_status 0 "$status" "check of a placed project"
grep -qx "check: placed from $SRC_SHA" "$WORK/out" || fail "check did not confirm the placement"
grep -q '^not checked here: whether Claude Code has loaded the hook' "$WORK/out" || fail "check did not separate placement from activation and verification"
[[ $before == "$(snapshot "$proj")" ]] || fail "check wrote files"

unplaced="$WORK/unplaced"
new_repo "$unplaced"
run_place --check "$unplaced"
expect_status 1 "$status" "check of an unplaced project"
grep -qx 'missing: AGENTS.md' "$WORK/out" || fail "check did not report missing files"

# Existing settings, rules, hooks and uncommitted edits are kept, and --restore puts them back.
own="$WORK/own"
new_repo "$own"
printf '# Own rules\n\n- keep me\n' >"$own/AGENTS.md"
git -C "$own" add AGENTS.md
git -C "$own" -c user.name=t -c user.email=t@example.invalid commit -q -m rules
printf -- '- uncommitted edit\n' >>"$own/AGENTS.md"
printf '@AGENTS.md\n\nown claude notes\n' >"$own/CLAUDE.md"
mkdir -p "$own/.claude" "$own/.ai"
cat >"$own/.claude/settings.json" <<'EOF'
{"model": "own", "permissions": {"allow": ["Read"], "deny": ["Read(./secrets/**)", "Bash(git push -f:*)"]},
 "hooks": {"PreToolUse": [{"matcher": "Edit", "hooks": [{"type": "command", "command": "own-hook.sh"}]}],
           "Stop": [{"hooks": [{"type": "command", "command": "stop.sh"}]}]}}
EOF
printf '# rules\n- 文書だけの変更は main へ直接コミットしてよい\n' >"$own/.ai/GIT_RULES.md"
printf '#!/bin/sh\nexit 0\n' >"$own/.git/hooks/pre-commit"
chmod +x "$own/.git/hooks/pre-commit"
own_before="$(snapshot "$own")"
hook_before="$(cksum <"$own/.git/hooks/pre-commit")"
run_place "$own"
expect_status 0 "$status" "placement over existing settings"
grep -q '^warning: .ai/GIT_RULES.md allows committing documents directly' "$WORK/err" || fail "the GIT_RULES contradiction was not reported"
grep -qx -- '- keep me' "$own/AGENTS.md" && grep -qx -- '- uncommitted edit' "$own/AGENTS.md" || fail "AGENTS.md lost the project's own text"
grep -q 'mainへ直接pushしない' "$own/AGENTS.md" || fail "AGENTS.md did not get the lightweight block"
[[ $(grep -cx '@AGENTS.md' "$own/CLAUDE.md") -eq 1 ]] && grep -qx 'own claude notes' "$own/CLAUDE.md" || fail "CLAUDE.md was not merged once"
jq -e '.model == "own" and .permissions.allow == ["Read"]
  and (.permissions.deny | index("Read(./secrets/**)") != null and index("Read(./.env)") != null and index("Bash(git push --force:*)") != null)
  and (.permissions.deny | map(select(. == "Bash(git push -f:*)")) | length == 1)
  and ([.hooks.PreToolUse[].hooks[].command] | index("own-hook.sh") != null and (map(select(test("guard-git-push"))) | length == 1))
  and .hooks.Stop[0].hooks[0].command == "stop.sh"' "$own/.claude/settings.json" >/dev/null ||
  fail "settings.json lost existing values or did not get the guard"
[[ $(<"$own/.ai/GIT_RULES.md") == *直接コミットしてよい* && $hook_before == "$(cksum <"$own/.git/hooks/pre-commit")" ]] ||
  fail "placement touched .ai/GIT_RULES.md or the pre-commit hook"
run_place "$own"
expect_status 0 "$status" "re-running placement over merged files"
grep -q 'nothing to change' "$WORK/out" || fail "merged files changed on re-run"
run_place --restore "$own"
expect_status 0 "$status" "restore"
[[ $own_before == "$(snapshot "$own")" && $hook_before == "$(cksum <"$own/.git/hooks/pre-commit")" ]] || fail "restore did not put the project back exactly"
[[ $(last_backup_status "$own") == restored ]] || fail "restore did not record its result"

# A file that cannot be merged stops everything; --keep keeps the project's own file.
conf="$WORK/conflict"
new_repo "$conf"
mkdir -p "$conf/scripts"
printf 'own verify\n' >"$conf/scripts/verify.sh"
conf_before="$(snapshot "$conf")"
run_place "$conf"
expect_status 1 "$status" "placement over an existing verify.sh"
grep -q '^conflict: scripts/verify.sh' "$WORK/err" && grep -q 'Nothing was written' "$WORK/err" || fail "conflict was not reported"
[[ $conf_before == "$(snapshot "$conf")" && $(backups "$conf") -eq 0 ]] || fail "placement wrote despite a conflict"
run_place --check "$conf"
expect_status 1 "$status" "check with a conflict"
grep -q '^conflict: scripts/verify.sh' "$WORK/err" || fail "check did not report the conflict"
run_place --keep scripts/verify.sh "$conf"
expect_status 0 "$status" "placement with --keep"
[[ $(<"$conf/scripts/verify.sh") == 'own verify' ]] || fail "--keep did not keep the project's file"
run_place --check "$conf"
expect_status 0 "$status" "check with a kept file"
grep -q '^kept: scripts/verify.sh' "$WORK/out" || fail "check did not report the kept file"
run_place "$conf"
expect_status 0 "$status" "re-running without --keep"

n_bad=0
for bad in '{"permissions": {"deny": "Read(./.env)"}}' 'not json'; do
  badset="$WORK/badset-$((++n_bad))"
  new_repo "$badset"
  mkdir -p "$badset/.claude"
  printf '%s\n' "$bad" >"$badset/.claude/settings.json"
  bad_before="$(snapshot "$badset")"
  run_place "$badset"
  expect_status 1 "$status" "placement over settings: $bad"
  grep -q '^conflict: .claude/settings.json: cannot be merged safely' "$WORK/err" || fail "unmergeable settings were not reported: $bad"
  [[ $bad_before == "$(snapshot "$badset")" ]] || fail "placement wrote over unmergeable settings"
done

broken="$WORK/broken"
new_repo "$broken"
printf '%s\nhalf a block\n' '<!-- lightweight:begin (managed by templates/lightweight/place.sh; edit outside this block) -->' >"$broken/AGENTS.md"
run_place "$broken"
expect_status 1 "$status" "placement with a broken block"
grep -q '^conflict: AGENTS.md: the lightweight block markers are broken' "$WORK/err" || fail "broken markers were not reported"

# Update to a newer candidate, pinning with --ref, and edits that block an update.
upd="$WORK/update"
new_repo "$upd"
run_place "$upd"
expect_status 0 "$status" "placement before an update"
edited="$WORK/edited"
new_repo "$edited"
run_place "$edited"
printf -- '- edited by hand\n' >>"$edited/.claude/skills/steward/SKILL.md"
inblock="$WORK/inblock"
new_repo "$inblock"
run_place "$inblock"
sed 's/^## 作業境界$/## 作業境界（手で変更）/' "$inblock/AGENTS.md" >"$WORK/agents" && cat "$WORK/agents" >"$inblock/AGENTS.md"
printf -- '- new step\n' >>"$SRC/$STEWARD"
git -C "$SRC" -c user.name=t -c user.email=t@example.invalid commit -q -am "newer candidate"
NEW_SHA="$(git -C "$SRC" rev-parse HEAD)"
run_place --check "$upd"
expect_status 1 "$status" "check against a newer candidate"
grep -qx 'outdated: .claude/skills/steward/SKILL.md (differs from the candidate at '"$NEW_SHA"')' "$WORK/out" || fail "check did not report the outdated file"
run_place --ref "$SRC_SHA" --check "$upd"
expect_status 0 "$status" "check pinned to the placed commit"
run_place "$upd"
expect_status 0 "$status" "update"
grep -qx 'updated: .claude/skills/steward/SKILL.md' "$WORK/out" || fail "update did not update the changed file"
grep -qx -- '- new step' "$upd/.claude/skills/steward/SKILL.md" || fail "update did not write the newer candidate"
grep -qxF "$(printf 'source\t%s' "$NEW_SHA")" "$upd/.ai/lightweight-placement.tsv" || fail "update did not record the new source"
run_place --restore "$upd"
expect_status 0 "$status" "restore after an update"
! grep -qx -- '- new step' "$upd/.claude/skills/steward/SKILL.md" || fail "restore did not undo only the update"
grep -qxF "$(printf 'source\t%s' "$SRC_SHA")" "$upd/.ai/lightweight-placement.tsv" || fail "restore did not put back the earlier record"
run_place "$edited"
expect_status 1 "$status" "update over a hand-edited file"
grep -q '^conflict: .claude/skills/steward/SKILL.md' "$WORK/err" || fail "hand-edited file was not protected"
run_place "$inblock"
expect_status 1 "$status" "update over a hand-edited block"
grep -q '^conflict: AGENTS.md: the managed block was edited by hand' "$WORK/err" || fail "hand-edited block was not protected"

# Uncommitted candidate changes: no commit describes them, so stop unless --ref is given.
printf -- '- uncommitted\n' >>"$SRC/$STEWARD"
dirty="$WORK/dirty"
new_repo "$dirty"
run_place "$dirty"
expect_status 1 "$status" "placement from an uncommitted candidate"
grep -q 'uncommitted changes' "$WORK/err" || fail "uncommitted candidate was not reported"
[[ -z $(find "$dirty" -path "$dirty/.git" -prune -o -type f -print) ]] || fail "placement wrote from an uncommitted candidate"
run_place --ref HEAD "$dirty"
expect_status 0 "$status" "placement pinned with --ref"
! grep -qx -- '- uncommitted' "$dirty/.claude/skills/steward/SKILL.md" || fail "--ref placed uncommitted content"
git -C "$SRC" checkout -q -- "$STEWARD"

# A failure part way puts back what the run changed and leaves the rest alone.
partial="$WORK/partial"
new_repo "$partial"
printf '# Own rules\n' >"$partial/AGENTS.md"
printf 'not a directory\n' >"$partial/.github"
partial_before="$(snapshot "$partial")"
run_place "$partial"
expect_status 1 "$status" "placement that fails part way"
grep -q 'put back the files changed by this run' "$WORK/err" || fail "partial failure did not roll back"
[[ $partial_before == "$(snapshot "$partial")" && ! -e $partial/.claude && ! -e $partial/.agents ]] || fail "rollback left changes from this run"
[[ $(last_backup_status "$partial") == rolled-back ]] || fail "rollback did not record its result"

# Interruptions. The cp shim waits on the third copy into the project until told to go.
shim="$WORK/slow-cp"
mkdir -p "$shim"
cat >"$shim/cp" <<EOF
#!/usr/bin/env bash
for last; do :; done
if [[ \$last == *.lightweight-tmp ]]; then
  n=\$(( \$(cat "$shim/count" 2>/dev/null || echo 0) + 1 )); echo "\$n" >"$shim/count"
  if [[ \$n -eq 3 ]]; then
    echo \$\$ >"$shim/pid"; touch "$shim/paused"
    while [[ ! -e "$shim/go" ]]; do sleep 0.1; done
  fi
fi
exec "$(command -v cp)" "\$@"
EOF
chmod +x "$shim/cp"
start_paused() { # <project>: start placement in the background and wait for the pause
  rm -f "$shim/count" "$shim/paused" "$shim/go" "$shim/pid"
  PATH="$shim:$PATH" "$PLACE" "$1" >/dev/null 2>"$WORK/err" &
  place_pid=$!
  for _ in $(seq 100); do [[ -e $shim/paused ]] && break; sleep 0.1; done
  [[ -e $shim/paused ]] || fail "interrupt test did not reach the third copy"
}

interrupted="$WORK/interrupted"
new_repo "$interrupted"
start_paused "$interrupted"
kill -TERM "$place_pid"
touch "$shim/go"
set +e; wait "$place_pid"; status=$?; set -e
expect_status 1 "$status" "interrupted placement"
grep -q 'put back the files changed by this run' "$WORK/err" || fail "interrupted placement did not roll back"
[[ -z $(find "$interrupted" -path "$interrupted/.git" -prune -o -mindepth 1 -print) ]] ||
  fail "interrupted placement left files or directories"

killed="$WORK/killed"
new_repo "$killed"
start_paused "$killed"
# The braces keep the shell's "Killed" job message out of the log.
{ kill -KILL "$place_pid"; wait "$place_pid"; } 2>/dev/null || true
touch "$shim/go"
for _ in $(seq 100); do kill -0 "$(cat "$shim/pid")" 2>/dev/null || break; sleep 0.1; done
run_place "$killed"
expect_status 1 "$status" "placement after a killed run"
grep -q 'did not finish' "$WORK/err" || fail "a killed run was not reported"
run_place --restore "$killed"
expect_status 0 "$status" "restore after a killed run"
[[ -z $(find "$killed" -path "$killed/.git" -prune -o -mindepth 1 -print) ]] || fail "restore after a killed run left files"
run_place "$killed"
expect_status 0 "$status" "placement after restoring a killed run"

# --restore does not undo a run whose files were edited afterwards.
later="$WORK/later"
new_repo "$later"
run_place "$later"
printf '# edited after placement\n' >>"$later/scripts/check-pr-head.sh"
later_before="$(snapshot "$later")"
run_place --restore "$later"
expect_status 1 "$status" "restore after a later edit"
grep -q '^conflict: scripts/check-pr-head.sh was changed after the placement' "$WORK/err" && grep -q 'Nothing was restored' "$WORK/err" ||
  fail "restore did not stop on a later edit"
[[ $later_before == "$(snapshot "$later")" ]] || fail "restore changed files despite a later edit"

linked="$WORK/linked"
new_repo "$linked"
mkdir -p "$WORK/outside"
ln -s "$WORK/outside" "$linked/.claude"
run_place "$linked"
expect_status 1 "$status" "placement through a symlinked .claude"
grep -q 'conflict: .claude/.*: .claude is a symlink' "$WORK/err" || fail "symlinked parent was not reported"
[[ -z $(ls -A "$WORK/outside") && ! -e $linked/AGENTS.md ]] || fail "placement wrote through a symlinked parent"

mkdir -p "$WORK/not-git"
run_place "$WORK/not-git"
expect_status 2 "$status" "placement outside a git repository"
run_place --keep README.md "$proj"
expect_status 2 "$status" "--keep with a path that is not placed"

dironly="$WORK/dironly"
new_repo "$dironly"
mkdir -p "$dironly/AGENTS.md"
run_place "$dironly"
expect_status 1 "$status" "placement over a directory named AGENTS.md"
grep -q '^conflict: AGENTS.md: exists but is not a regular file' "$WORK/err" || fail "a directory in place of a file was not reported"

# A file named like the temporary file is the project's, so it is a conflict.
tmpname="$WORK/tmpname"
new_repo "$tmpname"
printf 'own\n' >"$tmpname/AGENTS.md"
printf 'precious\n' >"$tmpname/AGENTS.md.lightweight-tmp"
tmpname_before="$(snapshot "$tmpname")"
run_place "$tmpname"
expect_status 1 "$status" "placement next to an existing .lightweight-tmp"
grep -q '^conflict: AGENTS.md: AGENTS.md.lightweight-tmp already exists' "$WORK/err" || fail "an existing temporary name was not reported"
[[ $tmpname_before == "$(snapshot "$tmpname")" ]] || fail "placement overwrote an existing .lightweight-tmp"

# The guard under a matcher that does not cover Bash does not count as placed.
matcher="$WORK/matcher"
new_repo "$matcher"
mkdir -p "$matcher/.claude"
jq -n --arg c '"$CLAUDE_PROJECT_DIR"/.claude/hooks/guard-git-push.sh' \
  '{hooks: {PreToolUse: [{matcher: "Edit", hooks: [{type: "command", command: $c}]}]}}' >"$matcher/.claude/settings.json"
run_place "$matcher"
expect_status 0 "$status" "placement with the guard under another matcher"
jq -e '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].command | select(test("guard-git-push"))] | length == 1' \
  "$matcher/.claude/settings.json" >/dev/null || fail "the guard was not added under the Bash matcher"

# A file changed between planning and writing is not overwritten.
raced="$WORK/raced"
new_repo "$raced"
printf 'own\n' >"$raced/AGENTS.md"
race="$WORK/race-mkdir"
mkdir -p "$race"
cat >"$race/mkdir" <<EOF
#!/usr/bin/env bash
for last; do :; done
[[ \$last == */before ]] && printf 'added while placing\n' >>"$raced/AGENTS.md"
exec "$(command -v mkdir)" "\$@"
EOF
chmod +x "$race/mkdir"
set +e; PATH="$race:$PATH" "$PLACE" "$raced" >/dev/null 2>"$WORK/err"; status=$?; set -e
expect_status 1 "$status" "placement over a file changed while placing"
grep -q '^conflict: AGENTS.md changed while placing' "$WORK/err" || fail "a change while placing was not reported"
[[ $(<"$raced/AGENTS.md") == $'own\nadded while placing' && ! -e $raced/CLAUDE.md && ! -e $raced/.claude ]] ||
  fail "placement overwrote a file changed while placing, or left files"

# Backups are numbered, so the latest one does not depend on the clock.
names="$(find "$upd/.git/lightweight-placement" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | LC_ALL=C sort | cut -c1-7 | tr '\n' ' ')"
[[ $names == '000001- 000002- ' ]] || fail "backups are not numbered in order: $names"

# Generated projects may run these scripts with macOS Bash 3.2.
if [[ -x /bin/bash ]] && /bin/bash -c '((BASH_VERSINFO[0] < 5))'; then
  old="$WORK/bash32"
  new_repo "$old"
  printf '{"permissions": {"deny": ["Read(./secrets/**)"]}}\n' >"$WORK/bash32-settings"
  mkdir -p "$old/.claude" && cp "$WORK/bash32-settings" "$old/.claude/settings.json"
  /bin/bash "$PLACE" "$old" >/dev/null 2>&1 || fail "placement failed under Bash 3.2"
  /bin/bash "$PLACE" "$old" >/dev/null 2>&1 || fail "re-running placement failed under Bash 3.2"
  /bin/bash "$PLACE" --check "$old" >/dev/null 2>&1 || fail "check failed under Bash 3.2"
  for c in 'git push origin main' 'git push -f'; do
    set +e
    /bin/bash "$old/.claude/hooks/guard-git-push.sh" <<<"$(jq -n --arg c "$c" --arg d "$old" '{tool_input: {command: $c}, cwd: $d}')" >/dev/null 2>&1
    status=$?
    set -e
    expect_status 2 "$status" "hook under Bash 3.2 for '$c'"
  done
  /bin/bash "$PLACE" --restore "$old" >/dev/null 2>&1 || fail "restore failed under Bash 3.2"
  cmp -s "$WORK/bash32-settings" "$old/.claude/settings.json" || fail "restore under Bash 3.2 did not put back settings.json"
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
check_hook 2 $'git push origin ma\\\nin'
check_hook 2 $'git push --for\\\nce origin feature/x'
check_hook 0 $'git push origin \\\n  feature/issue-1-sample'
check_hook 2 $'git pu\\\nsh origin main'
check_hook 2 $'gi\\\nt push origin main'
check_hook 2 $'echo a\\\\\ngit push origin main'
check_hook 0 $'echo a\\\\\ngit push origin feature/issue-1-sample'
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
check_hook 2 'git push>/tmp/push.log origin main'
check_hook 2 'git push>/tmp/push.log --force origin feature/x'
check_hook 2 'git push 2>&1 origin main'
check_hook 2 'git push</dev/null origin main'
check_hook 0 'git push>/tmp/push.log origin feature/issue-1-sample'
check_hook 2 'git>/tmp/push.log push origin main'
check_hook 2 'git 2>/tmp/push.log push --force origin feature/x'
check_hook 2 'git -C . 2>/dev/null push origin main'
check_hook 2 'git >>/tmp/push.log push origin main'
check_hook 0 'git 2>/dev/null push origin feature/issue-1-sample'
check_hook 2 'git >"/tmp/push log" push origin main'
check_hook 2 'git 2>"/tmp/push log" push --force origin feature/x'
check_hook 2 "git >'/tmp/push log' push origin main"
check_hook 0 'git >"/tmp/push log" push origin feature/issue-1-sample'
check_hook 2 'git push -o "note >" origin "main"'
check_hook 2 "git push -o 'note >' origin 'main'"
check_hook 2 'git push -o "note >" --force origin "feature/x"'
check_hook 0 'git push -o "note >" origin "feature/issue-1-sample"'
check_hook 2 'xargs -o git push origin main'
check_hook 2 'xargs -o git push --force origin feature/x'
check_hook 2 'stdbuf -o L git push origin main'
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
