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
require "docs/instruction-architecture-inventory.md" '## Read-only smoke test'
require "docs/instruction-architecture-inventory.md" 'branch、commit、push、PR、Issueコメントを作成しない'
require "docs/instruction-architecture-inventory.md" '`AGENTS.md`、`docs/`、`.agents/skills/`、`.github/`、`tests/`'
require "docs/instruction-architecture-inventory.md" '`docs/architecture/rag-design.md` はRAG採用プロジェクトの案件固有記録'

while IFS= read -r section; do
  [[ -n "$section" ]] || continue
  grep -Fq -- "| \`$section\` |" "$inventory" || {
    printf 'AGENTS section is not recorded in inventory: %s\n' "$section" >&2
    exit 1
  }
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

before="$("$git_bin" -C "$ROOT" status --porcelain=v1)"
grep -Fq -- '## Read-only smoke test' "$inventory"
grep -Fq -- '## Deferred decisions and follow-up boundary' "$inventory"
after="$("$git_bin" -C "$ROOT" status --porcelain=v1)"
[[ "$before" == "$after" ]] || {
  printf 'read-only smoke test changed the Git working tree\n' >&2
  exit 1
}

printf 'Instruction architecture and read-only smoke test contract: PASS\n'
