#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
agents="$ROOT/AGENTS.md"
skill="$ROOT/.agents/skills/plan-to-issues/SKILL.md"
inventory="$ROOT/docs/instruction-architecture-inventory.md"
harness="$ROOT/docs/ai-development-harness-inventory.md"

require() {
  local file="$1"
  local needle="$2"
  grep -Fq -- "$needle" "$file" || {
    printf 'missing plan-to-issues contract: %s: %s\n' "$file" "$needle" >&2
    exit 1
  }
}

[[ -f "$skill" ]] || {
  printf 'plan-to-issues Skill is missing: %s\n' "$skill" >&2
  exit 1
}

for path in \
  docs/plan-review-gate.md \
  docs/issue-quality-check.md \
  docs/adaptive-development-flow.md \
  docs/architecture/framework-decision.md \
  .github/ISSUE_TEMPLATE/parent-issue.md \
  .github/ISSUE_TEMPLATE/child-issue.md; do
  [[ -e "$ROOT/$path" ]] || {
    printf 'plan-to-issues canonical source is missing: %s\n' "$path" >&2
    exit 1
  }
done

require "$agents" '### Plan to Issues Routing'
require "$agents" '.agents/skills/plan-to-issues/SKILL.md'
require "$agents" '「この方向でIssue化して」'
require "$agents" '「親Issueと子Issueに分けて」'
require "$agents" '既存Issueの実装・レビュー・コメント確認'
require "$agents" 'Plan ReviewまたはChild Issue Quality Gateの停止条件'

require "$skill" 'name: plan-to-issues'
require "$skill" 'Framework Decision（適用時）'
require "$skill" 'Plan Review Gate'
require "$skill" 'Risk Tier'
require "$skill" 'Child Issue Quality Gate'
require "$skill" '`NEEDS_DECISION` の場合はIssue登録へ進まない'
require "$skill" '1子Issue = 1 PR'
require "$skill" '1 PRで完結する場合'
require "$skill" '空の親Issueを作ること自体を目的にしない'
require "$skill" '.github/ISSUE_TEMPLATE/parent-issue.md'
require "$skill" '.github/ISSUE_TEMPLATE/child-issue.md'
require "$skill" 'MUST不足'
require "$skill" 'GitHubが返したIssue番号やURLを使用し、番号を推測しない'
require "$skill" 'Issue登録が完了したら、このSkillの作業は終了する'
require "$skill" 'Issueの実装を開始しない'
require "$skill" '同じ詳細をSkill本文へ複製して独自基準を作らない'

require "$inventory" '`Plan Review Gate > Plan to Issues Routing` | `ENTRYPOINT` | `KEEP`'
require "$inventory" '.agents/skills/plan-to-issues/SKILL.md'
require "$inventory" '`plan-to-issues` は合意済み計画からGitHub Issueへの変換に限定'
require "$harness" '#148'
require "$harness" '.agents/skills/plan-to-issues/SKILL.md'

printf 'Plan to Issues Skill contract: PASS\n'
