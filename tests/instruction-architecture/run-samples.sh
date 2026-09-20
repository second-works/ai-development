#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
inventory="$ROOT/docs/instruction-architecture-inventory.md"
agents="$ROOT/AGENTS.md"
git_bin="$(command -v git)"
if ! "$git_bin" --version >/dev/null 2>&1; then
  for candidate in /usr/bin/git /bin/git; do
    if [[ -x "$candidate" ]] && "$candidate" --version >/dev/null 2>&1; then
      git_bin="$candidate"
      break
    fi
  done
fi
"$git_bin" --version >/dev/null 2>&1 || {
  printf 'a working Git executable is required for the read-only smoke test\n' >&2
  exit 1
}

tar_bin="$(command -v tar)"
[[ -n "$tar_bin" ]] || {
  printf 'a working tar executable is required for the read-only smoke test\n' >&2
  exit 1
}

digest_stream() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    printf 'a SHA-256 executable is required for the read-only smoke test\n' >&2
    return 1
  fi
}

before_head="$("$git_bin" -C "$ROOT" rev-parse --verify HEAD)"
before_branch="$("$git_bin" -C "$ROOT" symbolic-ref --quiet --short HEAD || printf '<detached>')"
before_refs="$("$git_bin" -C "$ROOT" for-each-ref --format='%(refname) %(objectname) %(symref)')"
before_status="$("$git_bin" -C "$ROOT" status --porcelain=v1)"
# --stage records index entries, and -v includes assume-unchanged / skip-worktree flags.
before_index="$("$git_bin" -C "$ROOT" ls-files --stage -v -z | digest_stream)"
before_worktree="$("$tar_bin" -C "$ROOT" --exclude=.git -cf - . | digest_stream)"

[[ -f "$inventory" ]] || {
  printf 'instruction architecture inventory is missing: %s\n' "$inventory" >&2
  exit 1
}

require() {
  local file="$1"
  local needle="$2"
  grep -Fq -- "$needle" "$ROOT/$file" || {
    printf 'missing instruction architecture contract: %s: %s\n' "$file" "$needle" >&2
    exit 1
  }
}

require "AGENTS.md" 'docs/instruction-architecture-inventory.md'
require "docs/instruction-architecture-inventory.md" '## Decision First'
require "docs/instruction-architecture-inventory.md" '変更前の `AGENTS.md`: **47,136 bytes**'
require "docs/instruction-architecture-inventory.md" '変更後 `AGENTS.md`: 47,438 bytes（`+302 bytes`）'
require "docs/instruction-architecture-inventory.md" '現行35セクションをすべて列挙する'
require "docs/instruction-architecture-inventory.md" '## Overlap, contradiction, and source-of-truth ledger'
require "docs/instruction-architecture-inventory.md" 'IA-01'
require "docs/instruction-architecture-inventory.md" 'IA-02'
require "docs/instruction-architecture-inventory.md" '### IA-02 Review Evidence layer map'
require "docs/instruction-architecture-inventory.md" '`README.md`'
require "docs/instruction-architecture-inventory.md" '`docs/template-guide.md`'
require "docs/instruction-architecture-inventory.md" '`docs/ai-development-harness-inventory.md#V-02`'
require "docs/instruction-architecture-inventory.md" '`docs/ai-execution-state.md`'
require "docs/instruction-architecture-inventory.md" '`docs/nine-standard-ai-development-flow.md`'
require "docs/instruction-architecture-inventory.md" '`.agents/skills/pr-review-fix/SKILL.md`'
require "docs/instruction-architecture-inventory.md" '正本競合は未解消として記録する'
require "docs/instruction-architecture-inventory.md" 'docs側とSkill側を正本参照入口へ短縮'
require "docs/instruction-architecture-inventory.md" '`Parent Issue Completion` | `ENTRYPOINT` | `KEEP`'
require "docs/instruction-architecture-inventory.md" '## Agent-executed protocol'
require "docs/instruction-architecture-inventory.md" '### Execution record'
require "docs/instruction-architecture-inventory.md" '## Read-only smoke test'
require "docs/instruction-architecture-inventory.md" 'branch、commit、push、PR、Issueコメントを作成しない'
require "docs/instruction-architecture-inventory.md" 'index entryと`assume-unchanged` / `skip-worktree` flag'
require "docs/instruction-architecture-inventory.md" 'symbolic refの参照先'
require "docs/instruction-architecture-inventory.md" '`AGENTS.md`、`docs/`、`.agents/skills/`、`.github/`、`tests/`'
require "docs/instruction-architecture-inventory.md" '`docs/architecture/rag-design.md` はRAG採用プロジェクトの案件固有記録'

while IFS= read -r section; do
  [[ -n "$section" ]] || continue
  row="$(grep -F -- "| \`$section\` |" "$inventory" || true)"
  [[ -n "$row" ]] || {
    printf 'AGENTS section is not recorded in inventory: %s\n' "$section" >&2
    exit 1
  }
  case "$row" in
    *'| `KEEP` |'*|*'| `SHORTEN+REFERENCE` |'*|*'| `MOVE` |'*|*'| `MERGE` |'*) ;;
    *)
      printf 'AGENTS section has no relocation candidate: %s\n' "$section" >&2
      exit 1
      ;;
  esac
done < <(sed -n 's/^## \(.*\)$/\1/p' "$agents")

for path in \
  docs/adaptive-development-flow.md \
  docs/ai-agent-security-boundary.md \
  docs/ai-development-harness-inventory.md \
  docs/ai-execution-state.md \
  docs/architecture/framework-decision.md \
  docs/architecture/rag-guidelines.md \
  docs/acceptance-verification.md \
  docs/deployment-release-design.md \
  docs/github-repository-security-baseline.md \
  docs/issue-quality-check.md \
  docs/plan-review-gate.md \
  docs/safe-auto-fix-auto-merge.md \
  docs/nine-standard-ai-development-flow.md \
  templates/verification/verify.sh \
  templates/security/security-preflight.sh \
  .agents/skills/pr-review-fix/SKILL.md \
  .github/workflows/ci.yml \
  .github/workflows/security.yml; do
  [[ -e "$ROOT/$path" ]] || {
    printf 'instruction architecture source is missing: %s\n' "$path" >&2
    exit 1
  }
done

grep -Fq -- '## Read-only smoke test' "$inventory"
grep -Fq -- '## Deferred decisions and follow-up boundary' "$inventory"
grep -Fq -- '## Overlap, contradiction, and source-of-truth ledger' "$inventory"
grep -Fq -- '## Agent-executed protocol' "$inventory"
after_head="$("$git_bin" -C "$ROOT" rev-parse --verify HEAD)"
after_branch="$("$git_bin" -C "$ROOT" symbolic-ref --quiet --short HEAD || printf '<detached>')"
after_refs="$("$git_bin" -C "$ROOT" for-each-ref --format='%(refname) %(objectname) %(symref)')"
after_status="$("$git_bin" -C "$ROOT" status --porcelain=v1)"
after_index="$("$git_bin" -C "$ROOT" ls-files --stage -v -z | digest_stream)"
after_worktree="$("$tar_bin" -C "$ROOT" --exclude=.git -cf - . | digest_stream)"
[[ "$before_head" == "$after_head" && "$before_branch" == "$after_branch" && "$before_refs" == "$after_refs" && "$before_status" == "$after_status" && "$before_index" == "$after_index" && "$before_worktree" == "$after_worktree" ]] || {
  printf 'read-only smoke test changed HEAD, branch, refs or symbolic ref targets, index entries or flags, or worktree contents\n' >&2
  exit 1
}

printf 'Instruction architecture and read-only smoke test contract: PASS\n'
