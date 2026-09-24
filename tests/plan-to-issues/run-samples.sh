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
require "$skill" 'UI Level Decision（全案件。非UIは NONE + 理由）'
require "$skill" 'UI Levelは全案件で `NONE / UTILITY / PRODUCT / NEEDS_DECISION` のいずれかを明示する'
require "$skill" 'Plan Review Gate'
require "$skill" 'Risk Tier'
require "$skill" 'Child Issue Quality Gate'
require "$skill" '`NEEDS_DECISION` の場合はIssue登録へ進まない'
require "$skill" '1子Issue = 1 PR'
require "$skill" '1 PRで完結する場合'
require "$skill" '空の親Issueを作ること自体を目的にしない'
require "$skill" '.github/ISSUE_TEMPLATE/parent-issue.md'
require "$skill" '.github/ISSUE_TEMPLATE/child-issue.md'
require "$skill" 'Plan Review結果（`PASS / NOT_APPLICABLE`）、理由、正本参照'
require "$skill" '単一Issueでも、Plan Reviewの判定・理由・正本参照'
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

require "$ROOT/.github/ISSUE_TEMPLATE/child-issue.md" '# Plan Review / Design Decision 引き継ぎ'
require "$ROOT/.github/ISSUE_TEMPLATE/child-issue.md" '- Plan Review: `PASS / NEEDS_DECISION / NOT_APPLICABLE`'
require "$ROOT/.github/ISSUE_TEMPLATE/child-issue.md" '単一IssueでもPlan Reviewの判定・理由・正本参照をこのIssue本文へ保存する'
require "$ROOT/.github/ISSUE_TEMPLATE/child-issue.md" '- UI Level: `NONE / UTILITY / PRODUCT / NEEDS_DECISION`'
require "$ROOT/.github/ISSUE_TEMPLATE/child-issue.md" '非UIは `NONE` と対象外理由を必ず記録'
require "$ROOT/.github/ISSUE_TEMPLATE/child-issue.md" 'UIを持たないCLI・library・文書案件も省略せず `NONE` と対象外理由を記録する'

printf 'Plan to Issues Skill contract: PASS\n'
