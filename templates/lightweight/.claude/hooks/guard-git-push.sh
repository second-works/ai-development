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

# A segment is a push only when git starts it and push is git's subcommand:
# optional "(" or "{", VAR=value prefixes, "env", a path such as /usr/bin/git,
# and git's own options (-C <dir>, -c <key=value>, --no-pager ...) may come first.
# Words like "push" inside a commit message or a PR body therefore do not count.
# Quotes and backslashes are removed first, as the shell would remove them.
push_re='^[[:space:]({]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*(env[[:space:]]+)?([^[:space:]]*/)?git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+|[[:space:]]+-[^[:space:]]+)*[[:space:]]+push([[:space:]]|$)'
force_re='[[:space:]](--force|--force-with-lease|--force-if-includes|--mirror|-[a-zA-Z]*f[a-zA-Z]*)([=)}[:space:]]|$)'
plus_re='[[:space:]:]\+[^[:space:]]'
main_re='([[:space:]:]|refs/heads/)(main|master)([)}[:space:]]|$)'

found_push=0
while IFS= read -r raw; do
  segment="$(printf '%s' "$raw" | tr -d "'\"\\")"
  [[ $segment =~ $push_re ]] || continue
  found_push=1
  case "$raw" in
    *'$'* | *'`'*) block "a push built from variables or command substitution cannot be checked; write the branch name literally: $raw" ;;
  esac
  [[ $segment =~ $force_re || $segment =~ $plus_re ]] && block "force push is not allowed: $raw"
  [[ $segment =~ $main_re ]] && block "push to main/master is not allowed: $raw"
done < <(printf '%s\n' "$cmd" | tr ';&|' '\n\n\n')

if [[ $found_push -eq 1 ]]; then
  dir="${cwd:-.}"
  branch="$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null || true)"
  case "$branch" in
    main | master) block "push from the $branch branch is not allowed; use an Issue branch" ;;
  esac
  # Without a refspec on the command line, git takes the destination from config.
  if git -C "$dir" config --get-regexp '^remote\..*\.push$' 2>/dev/null | grep -Eq '([[:space:]:]|refs/heads/)(main|master)$'; then
    block "a remote.<name>.push setting sends pushes to main/master"
  fi
  case "$(git -C "$dir" config --get push.default 2>/dev/null)" in
    upstream | tracking)
      case "$(git -C "$dir" config --get "branch.$branch.merge" 2>/dev/null)" in
        refs/heads/main | refs/heads/master) block "push.default=upstream would push $branch to its upstream main/master" ;;
      esac
      ;;
  esac
fi

exit 0
