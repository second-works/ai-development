#!/usr/bin/env bash
# Place the lightweight candidate into a project without overwriting anything.
#
#   place.sh [--dry-run] <project-root>
#
# Every destination is checked first. If any already exists, nothing is written
# and the conflicts are listed (exit 1). A symlinked parent directory counts as a
# conflict. If a copy fails part way or is interrupted, only the files and empty
# directories created by this run are removed (exit 1). verify.sh and the Security Preflight
# are copied from their existing originals in this repository, not duplicated.

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"

dry_run=0
if [[ ${1:-} == --dry-run ]]; then dry_run=1; shift; fi
[[ $# -eq 1 ]] || { echo "usage: place.sh [--dry-run] <project-root>" >&2; exit 2; }
target="$1"
[[ -d $target ]] || { echo "error: $target is not a directory" >&2; exit 2; }
target="$(cd "$target" && pwd -P)"

# source (relative to this repo) -> destination (relative to the project)
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

conflicts=0
for pair in "${pairs[@]}"; do
  src="$repo_root/${pair%%|*}" dst="$target/${pair#*|}"
  [[ -f $src ]] || { echo "error: source is missing: ${pair%%|*}" >&2; exit 1; }
  if [[ -e $dst || -L $dst ]]; then
    echo "conflict: ${pair#*|} already exists" >&2
    conflicts=$((conflicts + 1))
  fi
  # A symlinked parent (for example .claude -> ~/.claude) would write outside the project.
  parent="$(dirname "${pair#*|}")"
  while [[ $parent != . ]]; do
    if [[ -L $target/$parent ]]; then
      echo "conflict: $parent is a symlink, so ${pair#*|} would be written outside the project" >&2
      conflicts=$((conflicts + 1))
      break
    fi
    parent="$(dirname "$parent")"
  done
done
if [[ $conflicts -gt 0 ]]; then
  echo "stopped: $conflicts file(s) already exist. Nothing was written. Merge them by hand." >&2
  exit 1
fi

if [[ $dry_run -eq 1 ]]; then
  for pair in "${pairs[@]}"; do echo "would create: ${pair#*|}"; done
  exit 0
fi

created=()
made_dirs=()
rollback() {
  trap - HUP INT TERM
  local f i
  for f in ${created[@]+"${created[@]}"}; do rm -f -- "$target/$f"; done
  # Remove only the directories this run made, deepest first, and only if empty.
  for ((i = ${#made_dirs[@]} - 1; i >= 0; i--)); do rmdir -- "${made_dirs[i]}" 2>/dev/null || true; done
  echo "failed: removed the ${#created[@]} file(s) created by this run" >&2
  exit 1
}
trap rollback HUP INT TERM

make_parent() { # <dir>: mkdir -p that remembers which directories it created
  local d="$1" missing=()
  while [[ ! -e $d && $d != "$target" ]]; do missing=("$d" ${missing[@]+"${missing[@]}"}); d="$(dirname "$d")"; done
  for d in ${missing[@]+"${missing[@]}"}; do
    mkdir -- "$d" || return 1
    made_dirs+=("$d")
  done
}

for pair in "${pairs[@]}"; do
  src="$repo_root/${pair%%|*}" rel="${pair#*|}"
  make_parent "$(dirname "$target/$rel")" || rollback
  # Record before copying: an interrupt during cp must still remove this file.
  # Every destination was checked to be absent above, so removing it is safe.
  created+=("$rel")
  cp -p "$src" "$target/$rel" || rollback
  case "$rel" in *.sh) chmod +x "$target/$rel" || rollback ;; esac
  echo "created: $rel"
done
echo "placed ${#created[@]} file(s). Write project-specific build and test steps in README.md."
