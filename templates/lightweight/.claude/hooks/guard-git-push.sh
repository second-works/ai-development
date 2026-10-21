#!/usr/bin/env bash
# Claude Code PreToolUse hook for Bash.
# Blocks `git push` to main/master, force pushes, and any push from main/master.
# It reads the command text only and is not a shell parser: aliases, scripts,
# bash -c, quoted separators and other tools are not fully covered. Server-side
# branch protection is the real guarantee.
# Exit 2 blocks the tool call and shows the message to Claude.

block() {
  printf 'guard-git-push: %s\n' "$1" >&2
  exit 2
}

input="$(cat)"

# Fast path: anything that cannot be a git push is allowed untouched.
# Quotes and backslashes are removed first, so g'it' p"ush" is not missed.
flat="$(printf '%s' "$input" | tr -d "'\"\\")"
case "$flat" in
  *git*) ;;
  *) exit 0 ;;
esac
case "$flat" in
  *push* | *'$'* | *'`'*) ;;
  *) exit 0 ;;
esac

command -v jq >/dev/null 2>&1 || block "jq is not installed, so the push could not be checked"
cmd="$(printf '%s' "$input" | jq -er '.tool_input.command' 2>/dev/null)" ||
  block "could not read the command from the hook input"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"

# Join "\<newline>" continuations so a destination on the next line is not lost.
nl=$'\n'
cmd="${cmd//\\$nl/ }"

# A segment is a git command when git starts it. Allowed before git: "(", "{", "!",
# shell keywords and wrappers (then, do, time, command, env -i, xargs ...),
# VAR=value prefixes, and a path such as /usr/bin/git. git's own options may come
# next; -C, -c, --git-dir, --work-tree and --namespace take a separate value.
lead='^[[:space:]({!]*((if|then|do|else|elif|while|until|time|command|exec|nohup|xargs|sudo|env)([[:space:]]+-[^[:space:]]+)*[[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+|![[:space:]]+)*([^[:space:]]*/)?git'
opts="([[:space:]]+(-C|-c|--git-dir|--work-tree|--namespace|--config-env)[[:space:]]+(\"[^\"]*\"|'[^']*'|[^[:space:]]+)|[[:space:]]+-[^[:space:]]+)*"
push_re="${lead}${opts}[[:space:]]+push([[:space:]]|\$)"
# git followed by a subcommand built from a variable or substitution.
dynamic_re="${lead}${opts}[[:space:]]+[^[:space:]-][^[:space:]]*[\$\`]"
force_re='[[:space:]](--force|--force-with-lease|--force-if-includes|--mirror|-[a-zA-Z]*f[a-zA-Z]*)([=)}[:space:]]|$)'
plus_re='[[:space:]:]\+[^[:space:]]'
main_re='([[:space:]:]|refs/heads/)(main|master)([)}[:space:]]|$)'
# Pushes that select many branches, which can include main/master.
many_re='[[:space:]](--all|--branches)([=)}[:space:]]|$)|[[:space:]]:([)}[:space:]]|$)|\*'

found_push=0
while IFS= read -r raw; do
  # Push options carry free text (for example -o "ci +1"); drop them before checking.
  plain="$(printf '%s' "$raw" | sed -E "s/(^|[[:space:]])(-o|--push-option)(=|[[:space:]]+)(\"[^\"]*\"|'[^']*'|[^[:space:]]+)/\\1/g" | tr -d "'\"\\")"
  if [[ ! $raw =~ $push_re && ! $plain =~ $push_re ]]; then
    [[ $raw =~ $dynamic_re ]] && block "a git subcommand built from a variable cannot be checked; write it literally: $raw"
    continue
  fi
  found_push=1
  case "$raw" in
    *'$'* | *'`'*) block "a push built from variables or command substitution cannot be checked; write the branch name literally: $raw" ;;
  esac
  [[ $plain =~ $force_re || $plain =~ $plus_re ]] && block "force push is not allowed: $raw"
  [[ $plain =~ $main_re ]] && block "push to main/master is not allowed: $raw"
  [[ $plain =~ $many_re ]] && block "a push of several branches (--all, :, *) can include main/master: $raw"
done < <(printf '%s\n' "$cmd" | tr ';&|' '\n\n\n')

if [[ $found_push -eq 1 ]]; then
  dir="${cwd:-.}"
  branch="$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null || true)"
  case "$branch" in
    main | master) block "push from the $branch branch is not allowed; use an Issue branch" ;;
  esac
  # Without a refspec on the command line, git takes the destination from config.
  if git -C "$dir" config --get-regexp '^remote\..*\.push$' 2>/dev/null |
    grep -Eq '([[:space:]:]|refs/heads/)(main|master)$|\*|[[:space:]]:$'; then
    block "a remote.<name>.push setting can send pushes to main/master"
  fi
  case "$(git -C "$dir" config --get push.default 2>/dev/null)" in
    matching) block "push.default=matching pushes every branch with the same name, including main/master" ;;
    upstream | tracking)
      case "$(git -C "$dir" config --get "branch.$branch.merge" 2>/dev/null)" in
        refs/heads/main | refs/heads/master) block "push.default=upstream would push $branch to its upstream main/master" ;;
      esac
      ;;
  esac
fi

exit 0
