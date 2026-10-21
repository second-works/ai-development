#!/usr/bin/env bash
# Claude Code PreToolUse hook for Bash.
# Blocks `git push` to main/master, force pushes, and any push from main/master.
# It reads the command text only. Aliases, scripts, variables and other tools
# are not covered; server-side branch protection is the real guarantee.
# Exit 2 blocks the tool call and shows the message to Claude.

block() {
  printf 'guard-git-push: %s\n' "$1" >&2
  exit 2
}

input="$(cat)"

# Fast path: anything that cannot be a git push is allowed untouched.
case "$input" in
  *git*push*) ;;
  *) exit 0 ;;
esac

command -v jq >/dev/null 2>&1 || block "jq is not installed, so the push could not be checked"
cmd="$(printf '%s' "$input" | jq -er '.tool_input.command' 2>/dev/null)" ||
  block "could not read the command from the hook input"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"

push_re='(^|[[:space:]])git([[:space:]].*)?[[:space:]]push([[:space:]]|$)'
force_re='[[:space:]](--force|--force-with-lease|--force-if-includes|--mirror|-[a-zA-Z]*f[a-zA-Z]*)([[:space:]=]|$)'
plus_re='[[:space:]]\+[^[:space:]]'
main_re='([[:space:]:]|refs/heads/)(main|master)([[:space:]]|$)'

found_push=0
while IFS= read -r segment; do
  [[ $segment =~ $push_re ]] || continue
  found_push=1
  [[ $segment =~ $force_re || $segment =~ $plus_re ]] && block "force push is not allowed: $segment"
  [[ $segment =~ $main_re ]] && block "push to main/master is not allowed: $segment"
done < <(printf '%s\n' "$cmd" | tr ';&|' '\n\n\n')

if [[ $found_push -eq 1 ]]; then
  branch="$(git -C "${cwd:-.}" symbolic-ref --short -q HEAD 2>/dev/null || true)"
  case "$branch" in
    main | master) block "push from the $branch branch is not allowed; use an Issue branch" ;;
  esac
fi

exit 0
