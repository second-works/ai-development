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

before_head="$("$git_bin" -C "$ROOT" rev-parse --verify HEAD)"
before_branch="$("$git_bin" -C "$ROOT" symbolic-ref --quiet --short HEAD || printf '<detached>')"
before_refs="$("$git_bin" -C "$ROOT" for-each-ref --format='%(refname) %(objectname)')"
before_status="$("$git_bin" -C "$ROOT" status --porcelain=v1)"

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
require "docs/instruction-architecture-inventory.md" '正本競合を解消済み'
require "docs/instruction-architecture-inventory.md" '## Agent-executed protocol'
require "docs/instruction-architecture-inventory.md" '### Execution record'
require "docs/instruction-architecture-inventory.md" '## Read-only smoke test'
require "docs/instruction-architecture-inventory.md" 'branch、commit、push、PR、Issueコメントを作成しない'
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
after_refs="$("$git_bin" -C "$ROOT" for-each-ref --format='%(refname) %(objectname)')"
after_status="$("$git_bin" -C "$ROOT" status --porcelain=v1)"
[[ "$before_head" == "$after_head" && "$before_branch" == "$after_branch" && "$before_refs" == "$after_refs" && "$before_status" == "$after_status" ]] || {
  printf 'read-only smoke test changed HEAD, branch, refs, or the Git working tree\n' >&2
  exit 1
}

printf 'Instruction architecture and read-only smoke test contract: PASS\n'
