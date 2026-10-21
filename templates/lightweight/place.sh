#!/usr/bin/env bash
# Place the lightweight candidate into a project without losing what is already there.
#
#   place.sh [--dry-run] [--ref <commit>] [--keep <path>]... <project-root>
#   place.sh --check [--ref <commit>] <project-root>
#   place.sh --restore <project-root>
#
# The candidate is read from one commit of this repository (HEAD by default, which
# must have no uncommitted changes in the candidate files), and that full SHA is
# recorded in the project's .ai/lightweight-placement.tsv.
#
# Every destination is prepared in a temporary directory first. Nothing is written
# if any destination conflicts:
#   - AGENTS.md and CLAUDE.md get a managed block; text outside it is kept as is.
#   - .claude/settings.json is merged: existing settings, deny rules and hooks are
#     kept, and only the missing deny rules and the push guard hook are added.
#   - Other files are created when missing, and updated only when they still match
#     what this script placed last time. A different existing file is a conflict;
#     keep the project's own file with --keep <path>.
#   - A symlinked destination or parent directory is a conflict.
# Before writing, the previous content is saved under the project's .git directory.
# A failed or interrupted run puts back what it changed. --restore puts back the
# latest run's changes, and stops without changing anything if a file was edited
# after that run. Placing files does not mean they are active or verified: Claude
# Code loads hooks in a new session, and ./scripts/verify.sh, CI and Security run
# separately.
#
# Exit status: 0 success (including nothing to change), 1 conflict, failure or a
# --check that found problems, 2 usage error.

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"

BEGIN_MARK='<!-- lightweight:begin (managed by templates/lightweight/place.sh; edit outside this block) -->'
END_MARK='<!-- lightweight:end -->'
STATE_REL='.ai/lightweight-placement.tsv'
GUARD_COMMAND='"$CLAUDE_PROJECT_DIR"/.claude/hooks/guard-git-push.sh'

usage() {
  echo "usage: place.sh [--dry-run] [--ref <commit>] [--keep <path>]... <project-root>" >&2
  echo "       place.sh --check [--ref <commit>] <project-root>" >&2
  echo "       place.sh --restore <project-root>" >&2
  exit 2
}
die() { echo "error: $2" >&2; exit "$1"; }

mode=apply ref='' keeps=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) mode=dry-run ;;
    --check) mode=check ;;
    --restore) mode=restore ;;
    --ref) [[ $# -ge 2 ]] || usage; ref="$2"; shift ;;
    --keep) [[ $# -ge 2 ]] || usage; keeps+=("$2"); shift ;;
    --*) usage ;;
    *) break ;;
  esac
  shift
done
[[ $# -eq 1 ]] || usage
target="$1"
[[ -d $target ]] || die 2 "$target is not a directory"
target="$(cd "$target" && pwd -P)"
git_dir="$(git -C "$target" rev-parse --absolute-git-dir 2>/dev/null)" ||
  die 2 "$target is not a git repository (the backup for --restore is kept in .git)"
# The backup lives in the repository's git directory, so one repository has one
# placement: its root. A subdirectory would share the backup with other targets.
toplevel="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)" && toplevel="$(cd "$toplevel" && pwd -P)"
[[ $toplevel == "$target" ]] || die 2 "$target is not the root of its git repository ($toplevel); place into the root"
backup_root="$git_dir/lightweight-placement"

sha_of() { # <file>: sha256 of the file, or - when it does not exist
  if [[ ! -e $1 ]]; then echo -; return; fi
  if command -v sha256sum >/dev/null 2>&1; then sha256sum <"$1" | cut -d' ' -f1; else shasum -a 256 <"$1" | cut -d' ' -f1; fi
}
reverse_lines() { awk '{ line[NR] = $0 } END { for (i = NR; i > 0; i--) print line[i] }' "$1"; }
has_symlink_on_path() { # <rel>: true when the destination or a parent directory is a symlink
  local p="$1"
  while [[ $p != . ]]; do
    [[ -L $target/$p ]] && { echo "$p"; return 0; }
    p="$(dirname "$p")"
  done
  return 1
}

# A run that was killed before it finished leaves its backup in the "applying" state.
unfinished_backup() {
  local d
  [[ -d $backup_root ]] || return 1
  for d in "$backup_root"/*/; do
    [[ -f ${d}status && $(<"${d}status") == applying ]] && { echo "${d%/}"; return 0; }
  done
  return 1
}

# --- Restore ---------------------------------------------------------------------
# Journal lines: <created|modified|dir> TAB <path> TAB <sha before> TAB <sha after>.
# Each line is written before the change it describes, so an interrupted run can
# also be put back.
restore_backup() { # <backup dir> <status to record>
  local bk="$1" final="$2" kind rel before after now link problems=0
  while IFS=$'\t' read -r kind rel before after; do
    # A symlink swapped in after the placement would make restore delete or
    # overwrite files outside the project.
    if link="$(has_symlink_on_path "$rel")"; then
      echo "conflict: $link is now a symlink, so restoring $rel would reach outside the project" >&2
      problems=$((problems + 1))
      continue
    fi
    [[ $kind == dir ]] && continue
    now="$(sha_of "$target/$rel")"
    # Already as it was before the run, or exactly as the run left it: safe either way.
    [[ $now == "$after" || $now == "$before" ]] && continue
    echo "conflict: $rel was changed after the placement; restore it by hand from $bk/before/$rel" >&2
    problems=$((problems + 1))
  done <"$bk/journal"
  if [[ $problems -gt 0 ]]; then
    echo "stopped: $problems file(s) changed since the placement. Nothing was restored." >&2
    return 1
  fi
  local count=0 interrupted=0
  [[ $(<"$bk/status") == applying ]] && interrupted=1
  while IFS=$'\t' read -r kind rel before after; do
    # Only an unfinished run can have left its own temporary file behind.
    # Directories never get one, so a file named like that next to them is not ours.
    [[ $interrupted -eq 1 && $kind != dir ]] && rm -f -- "$target/$rel.lightweight-tmp"
    case "$kind" in
      created)
        if [[ $(sha_of "$target/$rel") == "$after" ]]; then rm -f -- "$target/$rel" || return 1; count=$((count + 1)); fi ;;
      modified)
        # cp -p also puts back the mode when only the mode changed (chmod +x).
        if [[ $(sha_of "$target/$rel") == "$after" ]]; then
          cp -p -- "$bk/before/$rel" "$target/$rel" || return 1
          count=$((count + 1))
        fi ;;
      dir) rmdir -- "$target/$rel" 2>/dev/null || true ;;
    esac
  done < <(reverse_lines "$bk/journal")
  echo "$final" >"$bk/status"
  echo "restored $count file(s) changed by the placement in $bk" >&2
}

if [[ $mode == restore ]]; then
  latest=''
  if [[ -d $backup_root ]]; then
    for d in "$backup_root"/*/; do
      [[ -f ${d}status ]] || continue
      case "$(<"${d}status")" in done | applying) latest="${d%/}" ;; esac
    done
  fi
  [[ -n $latest ]] || die 1 "no placement to restore in $target"
  restore_backup "$latest" restored || exit 1
  exit 0
fi

# --- Source ------------------------------------------------------------------------
# source (relative to this repo) | destination (relative to the project)
pairs=(
  "templates/lightweight/AGENTS.md|AGENTS.md"
  "templates/lightweight/CLAUDE.md|CLAUDE.md"
  "templates/lightweight/.agents/skills/plan-to-issues/SKILL.md|.agents/skills/plan-to-issues/SKILL.md"
  "templates/lightweight/.claude/skills/steward/SKILL.md|.claude/skills/steward/SKILL.md"
  "templates/lightweight/.claude/skills/steward/scripts/check-pr-head.sh|scripts/check-pr-head.sh"
  "templates/lightweight/.claude/settings.json|.claude/settings.json"
  "templates/lightweight/.claude/hooks/guard-git-push.sh|.claude/hooks/guard-git-push.sh"
  "templates/lightweight/.github/ISSUE_TEMPLATE/parent-issue.md|.github/ISSUE_TEMPLATE/parent-issue.md"
  "templates/lightweight/.github/ISSUE_TEMPLATE/child-issue.md|.github/ISSUE_TEMPLATE/child-issue.md"
  "templates/lightweight/.github/pull_request_template.md|.github/pull_request_template.md"
  "templates/verification/verify.sh|scripts/verify.sh"
  "templates/security/security-preflight.sh|scripts/security-preflight.sh"
)

for k in ${keeps[@]+"${keeps[@]}"}; do
  known=0
  for pair in "${pairs[@]}"; do [[ ${pair#*|} == "$k" ]] && known=1; done
  [[ $known -eq 1 ]] || die 2 "--keep $k is not one of the placed files"
done

if [[ -n $ref ]]; then
  commit="$(git -C "$repo_root" rev-parse --verify --quiet "$ref^{commit}")" || die 2 "unknown commit: $ref"
else
  commit="$(git -C "$repo_root" rev-parse --verify --quiet HEAD)" || die 2 "$repo_root is not a git checkout"
  sources=()
  for pair in "${pairs[@]}"; do sources+=("${pair%%|*}"); done
  dirty="$(git -C "$repo_root" status --porcelain -- "${sources[@]}")"
  if [[ -n $dirty ]]; then
    echo "$dirty" >&2
    die 1 "the candidate has uncommitted changes, so no commit describes it. Commit them, or pass --ref <commit>."
  fi
fi

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

state_file="$target/$STATE_REL"
recorded() { # <path>: "<kind> <sha>" from the previous placement, if any
  [[ -f $state_file && ! -L $state_file ]] || return 0
  awk -F'\t' -v p="$1" '$1 != "source" && $1 !~ /^#/ && $2 == p { print $1 " " $3; exit }' "$state_file"
}
wants_keep() { # <path>
  local k
  for k in ${keeps[@]+"${keeps[@]}"}; do [[ $k == "$1" ]] && return 0; done
  [[ $(recorded "$1") == "kept "* ]]
}

# Managed block helpers. The block is the lines between the two marker lines.
marker_count() { grep -cxF -- "$1" "$2" 2>/dev/null || true; }
block_inside() { awk -v b="$BEGIN_MARK" -v e="$END_MARK" '$0 == e { s = 0 } s { print } $0 == b { s = 1 }' "$1"; }
block_outside() { awk -v b="$BEGIN_MARK" -v e="$END_MARK" '$0 == b { s = 1; next } $0 == e { s = 0; next } !s { print }' "$1"; }

conflicts=0
conflict() { echo "conflict: $1" >&2; conflicts=$((conflicts + 1)); }

# Builds the new content of a block file in $stage/new/<rel> and its block body in
# $stage/body/<rel>. Runs in this shell (not $(...)) so that conflicts are counted.
stage_block() { # <rel> <candidate file>
  local rel="$1" cand="$2" dst="$target/$1" new="$stage/new/$1" body="$stage/body/$1"
  mkdir -p "$(dirname "$new")" "$(dirname "$body")"
  local begins ends
  begins="$(marker_count "$BEGIN_MARK" "$dst")" ends="$(marker_count "$END_MARK" "$dst")"
  if [[ $rel == CLAUDE.md && -f $dst ]] && block_outside "$dst" | grep -qxF '@AGENTS.md'; then
    # The project already imports AGENTS.md; do not import it twice.
    awk 'NR == 1 && $0 == "@AGENTS.md" { skip = 1; next } skip && $0 == "" { skip = 0; next } { skip = 0; print }' "$cand" >"$body"
  else
    awk 1 "$cand" >"$body"
  fi
  if [[ ! -e $dst ]]; then
    { echo "$BEGIN_MARK"; cat "$body"; echo "$END_MARK"; } >"$new"
  elif [[ ${begins:-0} -eq 0 && ${ends:-0} -eq 0 ]]; then
    { awk 1 "$dst"; [[ -s $dst ]] && echo; echo "$BEGIN_MARK"; cat "$body"; echo "$END_MARK"; } >"$new"
  elif [[ $begins -eq 1 && $ends -eq 1 ]] &&
    [[ $(grep -nxF -- "$BEGIN_MARK" "$dst" | cut -d: -f1) -lt $(grep -nxF -- "$END_MARK" "$dst" | cut -d: -f1) ]]; then
    local inside_sha previous
    inside_sha="$(block_inside "$dst" | { cat >"$stage/inside"; sha_of "$stage/inside"; })"
    previous="$(recorded "$rel")"
    if [[ $inside_sha != "$(sha_of "$body")" && $previous != "block $inside_sha" ]]; then
      conflict "$rel: the managed block was edited by hand; move the edits outside the block or pass --keep $rel"
      return 1
    fi
    awk -v b="$BEGIN_MARK" -v e="$END_MARK" -v f="$body" '
      $0 == b { print; while ((getline line < f) > 0) print line; s = 1; next }
      $0 == e { s = 0 }
      !s { print }' "$dst" >"$new"
  else
    conflict "$rel: the lightweight block markers are broken (they must appear once each, begin first)"
    return 1
  fi
}

# Merges the candidate settings into the project's settings in $stage/new/<rel>.
stage_settings() { # <rel> <candidate file>
  local rel="$1" cand="$2" dst="$target/$1" new="$stage/new/$1"
  mkdir -p "$(dirname "$new")"
  if ! command -v jq >/dev/null 2>&1; then
    conflict "$rel: jq is required to merge settings safely"
    return 1
  fi
  if [[ ! -e $dst ]]; then
    jq . "$cand" >"$new" || { conflict "$rel: the candidate settings are not valid JSON"; return 1; }
    return 0
  fi
  # An empty file or several JSON documents give jq nothing or too much to merge.
  if ! jq -e -s 'length == 1 and (.[0] | type == "object")' "$dst" >/dev/null 2>&1; then
    conflict "$rel: cannot be merged safely (it is not a single JSON object)"
    return 1
  fi
  if ! jq --slurpfile cand "$cand" --arg guard "$GUARD_COMMAND" '
      def need($t; $p): if (getpath($p) == null) or ((getpath($p) | type) == $t) then . else error("\($p | join(".")) is not an \($t)") end;
      $cand[0] as $c
      | if type != "object" then error("the top level is not an object") else . end
      | need("object"; ["permissions"]) | need("array"; ["permissions", "deny"])
      | need("object"; ["hooks"]) | need("array"; ["hooks", "PreToolUse"])
      | (.permissions.deny // []) as $deny
      | .permissions.deny = $deny + [$c.permissions.deny[] | select(. as $x | any($deny[]; . == $x) | not)]
      | (.hooks.PreToolUse // []) as $pre
      # The guard counts as present only under a matcher that covers Bash.
      | .hooks.PreToolUse = (if any($pre[] | select((.matcher // "") | . == "Bash" or . == "*" or . == "")
          | (.hooks // [])[]?; .command? == $guard) then $pre
          else $pre + $c.hooks.PreToolUse end)
    ' "$dst" >"$new" 2>"$stage/jq-error"; then
    conflict "$rel: cannot be merged safely ($(tr '\n' ' ' <"$stage/jq-error"))"
    return 1
  fi
  # Keep the project's own formatting when nothing needs to be added.
  if [[ $(jq -S . "$dst") == "$(jq -S . "$new")" ]]; then cp -p -- "$dst" "$new"; fi
}

# --- Plan ----------------------------------------------------------------------------
# plan_sha is the destination's sha when it was planned; apply stops if it changed since.
plan_rel=() plan_action=() plan_sha=()
add_plan() { plan_rel+=("$1"); plan_action+=("$2"); plan_sha+=("$(sha_of "$target/$1")"); }
decide() { # <rel>: create, unchanged or update for a staged file
  local rel="$1" dst="$target/$1" new="$stage/new/$1"
  if [[ -e $dst.lightweight-tmp || -L $dst.lightweight-tmp ]]; then
    conflict "$rel: $rel.lightweight-tmp already exists, and this script writes through that name"
    return
  fi
  if [[ ! -e $dst ]]; then add_plan "$rel" create; return; fi
  if cmp -s "$new" "$dst" && { [[ $rel != *.sh ]] || [[ -x $dst ]]; }; then add_plan "$rel" unchanged; return; fi
  add_plan "$rel" update
}

state_new="$stage/new/$STATE_REL"
mkdir -p "$(dirname "$state_new")"
{
  echo "# Written by templates/lightweight/place.sh. It uses this file to update and check the placement."
  printf 'source\t%s\n' "$commit"
} >"$state_new"

for pair in "${pairs[@]}"; do
  src="${pair%%|*}" rel="${pair#*|}"
  cand="$stage/candidate/$rel"
  mkdir -p "$(dirname "$cand")"
  git -C "$repo_root" show "$commit:$src" >"$cand" 2>/dev/null || die 1 "cannot read $src at $commit"
  if link="$(has_symlink_on_path "$rel")"; then
    conflict "$rel: $link is a symlink, so the file would be written outside the project"
    continue
  fi
  dst="$target/$rel"
  if [[ -e $dst && ! -f $dst ]]; then
    conflict "$rel: exists but is not a regular file"
    continue
  fi
  if [[ -e $dst ]] && wants_keep "$rel"; then
    add_plan "$rel" keep
    printf 'kept\t%s\t-\n' "$rel" >>"$state_new"
    continue
  fi
  case "$rel" in
    AGENTS.md | CLAUDE.md)
      stage_block "$rel" "$cand" || continue
      printf 'block\t%s\t%s\n' "$rel" "$(sha_of "$stage/body/$rel")" >>"$state_new" ;;
    .claude/settings.json)
      stage_settings "$rel" "$cand" || continue
      printf 'settings\t%s\t-\n' "$rel" >>"$state_new" ;;
    *)
      mkdir -p "$(dirname "$stage/new/$rel")"
      cp -- "$cand" "$stage/new/$rel"
      if [[ -e $dst ]] && ! cmp -s "$cand" "$dst" && [[ $(recorded "$rel") != "file $(sha_of "$dst")" ]]; then
        conflict "$rel: already exists with different content that this script did not place; merge it by hand or pass --keep $rel"
        continue
      fi
      printf 'file\t%s\t%s\n' "$rel" "$(sha_of "$cand")" >>"$state_new" ;;
  esac
  decide "$rel"
done
if link="$(has_symlink_on_path "$STATE_REL")"; then
  conflict "$STATE_REL: $link is a symlink, so the file would be written outside the project"
else
  decide "$STATE_REL"
fi

# Guards that this script leaves to their own owners.
if [[ -f $target/.ai/GIT_RULES.md ]] && grep -q '直接コミットしてよい' "$target/.ai/GIT_RULES.md"; then
  echo "warning: .ai/GIT_RULES.md allows committing documents directly to main / master, but the placed AGENTS.md forbids pushing to main. Follow AGENTS.md; this script does not edit .ai/GIT_RULES.md (it belongs to ai-project-bootstrap)." >&2
fi
if pending="$(unfinished_backup)"; then
  echo "warning: a previous placement did not finish ($pending). Run place.sh --restore $target first." >&2
  [[ $mode == apply ]] && exit 1
fi

# --- Check -------------------------------------------------------------------------------
if [[ $mode == check ]]; then
  problems=$conflicts
  for i in "${!plan_rel[@]}"; do
    case "${plan_action[i]}" in
      unchanged) echo "placed: ${plan_rel[i]}" ;;
      keep) echo "kept: ${plan_rel[i]} (the project's own file, not the candidate)" ;;
      create) echo "missing: ${plan_rel[i]}"; problems=$((problems + 1)) ;;
      update) echo "outdated: ${plan_rel[i]} (differs from the candidate at $commit)"; problems=$((problems + 1)) ;;
    esac
  done
  for guard in .git/hooks/pre-commit .ai/GIT_RULES.md; do
    if [[ $guard == .git/hooks/pre-commit ]]; then p="$git_dir/hooks/pre-commit"; else p="$target/$guard"; fi
    if [[ -e $p ]]; then echo "left as it was: $guard"; fi
  done
  echo "not checked here: whether Claude Code has loaded the hook (start a new session), ./scripts/verify.sh, CI, Security and review."
  if [[ $problems -gt 0 ]]; then
    echo "check: $problems problem(s) against the candidate at $commit" >&2
    exit 1
  fi
  echo "check: placed from $commit"
  exit 0
fi

if [[ $conflicts -gt 0 ]]; then
  echo "stopped: $conflicts conflict(s). Nothing was written." >&2
  exit 1
fi

changes=0
for i in "${!plan_rel[@]}"; do
  case "${plan_action[i]}" in create | update) changes=$((changes + 1)) ;; esac
done

# --- Dry run ---------------------------------------------------------------------------------
if [[ $mode == dry-run ]]; then
  echo "source: $commit"
  for i in "${!plan_rel[@]}"; do
    case "${plan_action[i]}" in
      create) echo "would create: ${plan_rel[i]}" ;;
      update) echo "would update: ${plan_rel[i]}" ;;
      unchanged) echo "unchanged: ${plan_rel[i]}" ;;
      keep) echo "kept: ${plan_rel[i]}" ;;
    esac
  done
  for i in "${!plan_rel[@]}"; do
    rel="${plan_rel[i]}"
    case "${plan_action[i]}" in
      create) diff -u -L /dev/null -L "b/$rel" /dev/null "$stage/new/$rel" ;;
      update) diff -u -L "a/$rel" -L "b/$rel" "$target/$rel" "$stage/new/$rel" ;;
    esac
  done
  exit 0
fi

# --- Apply ---------------------------------------------------------------------------------------
if [[ $changes -eq 0 ]]; then
  echo "nothing to change: the candidate at $commit is already placed"
  exit 0
fi

mkdir -p "$backup_root" || die 1 "cannot create $backup_root"
# Name backups by a sequence number, so that --restore finds the latest one even if
# the clock moves backwards. The UTC time is only for people reading the name.
n=0
for d in "$backup_root"/*/; do
  d="${d%/}" d="${d##*/}"
  [[ $d =~ ^[0-9]{6}- ]] && ((10#${d:0:6} > n)) && n=$((10#${d:0:6}))
done
bk="$backup_root/$(printf '%06d' $((n + 1)))-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir "$bk" && mkdir "$bk/before" || die 1 "cannot create $bk"
echo applying >"$bk/status"
: >"$bk/journal"
echo "$commit" >"$bk/source"

rollback() {
  trap - HUP INT TERM
  if restore_backup "$bk" rolled-back; then
    echo "failed: put back the files changed by this run" >&2
  else
    echo "failed: could not put everything back; see $bk and run place.sh --restore $target" >&2
  fi
  exit 1
}
trap rollback HUP INT TERM

make_parent() { # <rel dir>: create missing directories and journal each one
  local d="$1" missing=()
  while [[ $d != . && ! -e $target/$d ]]; do missing=("$d" ${missing[@]+"${missing[@]}"}); d="$(dirname "$d")"; done
  for d in ${missing[@]+"${missing[@]}"}; do
    printf 'dir\t%s\t-\t-\n' "$d" >>"$bk/journal" || return 1
    mkdir -- "$target/$d" || return 1
  done
}

for i in "${!plan_rel[@]}"; do
  rel="${plan_rel[i]}" action="${plan_action[i]}"
  [[ $action == create || $action == update ]] || continue
  dst="$target/$rel" new="$stage/new/$rel" tmp="$target/$rel.lightweight-tmp"
  after="$(sha_of "$new")"
  if [[ $(sha_of "$dst") != "${plan_sha[i]}" ]]; then
    echo "conflict: $rel changed while placing; nothing of it was written" >&2
    rollback
  fi
  if [[ $action == update ]]; then
    mkdir -p "$(dirname "$bk/before/$rel")" && cp -p -- "$dst" "$bk/before/$rel" || rollback
    printf 'modified\t%s\t%s\t%s\n' "$rel" "$(sha_of "$dst")" "$after" >>"$bk/journal" || rollback
    cp -p -- "$dst" "$tmp" && cat -- "$new" >"$tmp" || rollback
  else
    make_parent "$(dirname "$rel")" || rollback
    printf 'created\t%s\t-\t%s\n' "$rel" "$after" >>"$bk/journal" || rollback
    cp -- "$new" "$tmp" || rollback
  fi
  case "$rel" in *.sh) chmod +x "$tmp" || rollback ;; esac
  mv -f -- "$tmp" "$dst" || rollback
  if [[ $action == update ]]; then echo "updated: $rel"; else echo "created: $rel"; fi
done
echo done >"$bk/status"
trap - HUP INT TERM
echo "placed $changes file(s) from $commit. To undo: place.sh --restore $target"
echo "not verified yet: start a new Claude Code session to load the hook, write the build and test steps in README.md, and run ./scripts/verify.sh."
