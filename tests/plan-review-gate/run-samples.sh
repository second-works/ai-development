#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
doc="$repo_root/docs/plan-review-gate.md"
flow="$repo_root/docs/nine-standard-ai-development-flow.md"
guide="$repo_root/docs/template-guide.md"
agents="$repo_root/AGENTS.md"
parent="$repo_root/.github/ISSUE_TEMPLATE/parent-issue.md"
child="$repo_root/.github/ISSUE_TEMPLATE/child-issue.md"
design="$repo_root/templates/app/docs/design.md"
readme="$repo_root/README.md"
authoring="$repo_root/docs/plan-authoring.md"
sample="$repo_root/templates/planning/web-todo-app-plan.sample.md"

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    printf 'missing plan review contract: %s in %s\n' "$needle" "$file" >&2
    exit 1
  fi
}

for needle in \
    'Plan Review Gate' \
    'PASS' \
    'NEEDS_DECISION' \
    'NOT_APPLICABLE' \
    '親Issue / 子Issue化および実装開始へ進まない' \
    'Design Decision' \
    'Design Decision Escalation' \
    'deployment-release-design.md' \
    'acceptance-verification.md' \
    'Issue #30' \
    '一問一答形式を固定しない' \
    '反証レビュー（既存Plan Reviewの一部）' \
    'この計画が失敗するとしたら、主な原因は何か。' \
    '同じ目的を、より単純な代替案で達成できないか。' \
    '採用案に不利な証拠、比較対象、既存手法を見落としていないか。' \
    '期待する結果を先取りしていないか' \
    '関連する過去のPlan vs Reality記録:' \
    '今回計画へ反映した教訓:' \
    'UI Level Decision' \
    'Framework Decision' \
    'UI Level: `NONE / UTILITY / PRODUCT / NEEDS_DECISION`' \
    'UI適用対象: UIなし / UTILITY / PRODUCT' \
    'PRODUCT UI completeness: `COMPLETE / INCOMPLETE / NOT_APPLICABLE`' \
    'PRODUCT未決定事項:' \
    'Primary screen structure:' \
    'Destructive action behavior:' \
    'Major Design Direction:' \
    'Design Decisionへ送るUI項目:'; do
  assert_contains "$doc" "$needle"
done

assert_contains "$flow" 'Plan Review Gate（Grilling）'
assert_contains "$flow" '## 2.0 Framework Decision（技術選定）'
assert_contains "$flow" '## 2.1 UI Level Decision（案件分類）'
assert_contains "$flow" '## 2.2 Plan Review Gate（計画書Grilling）'
assert_contains "$flow" 'Consultation → Framework Decision → UI Level Decision → PRODUCT前提整理 → Plan Review Gate'
assert_contains "$flow" 'NONE / UTILITY: PRODUCT用チェックを必須化しない'
assert_contains "$flow" 'PRODUCT UI completenessが `INCOMPLETE` の場合'
assert_contains "$guide" 'Plan Review Gate（Grilling）'
assert_contains "$guide" '- [ ] `docs/plan-review-gate.md` を配置'
assert_contains "$guide" 'Plan Review正本文書（`docs/plan-review-gate.md`）を配置'
assert_contains "$flow" 'PASSまたは理由付きNOT_APPLICABLEの場合だけIssue化へ進み'
assert_contains "$guide" 'NEEDS_DECISION → Design Decision → 計画書更新 → 再Review'
assert_contains "$guide" 'Issue化前にPlan Review（Grilling）を実施'
assert_contains "$agents" 'docs/minimal-development-contract.md'
assert_contains "$doc" 'plan-review-gate.md'
assert_contains "$doc" 'PASSまたは理由付きNOT_APPLICABLEの場合だけIssue化へ進み'
for template in "$parent" "$child"; do
  assert_contains "$template" '# Context'
  assert_contains "$template" 'Plan Reviewの判定（PASS / NOT_APPLICABLE）、理由'
  assert_contains "$template" '../blob/main/docs/plan-review-gate.md'
  assert_contains "$template" '重要判断がNEEDS_DECISION'
done
assert_contains "$doc" 'Framework依存の未決定事項 / 停止範囲:'
assert_contains "$design" '## Framework Decision Boundary'
assert_contains "$design" 'このファイルはFrameworkを再選定せず'
assert_contains "$readme" 'docs/plan-review-gate.md'
assert_contains "$readme" 'docs/architecture/framework-decision.md'
assert_contains "$readme" 'docs/plan-authoring.md'
assert_contains "$readme" 'ChatGPTで要件整理・計画書作成（手順は [`docs/plan-authoring.md`](docs/plan-authoring.md)）'
assert_contains "$authoring" '会話で決まっていない欄は推測で埋めないでください。'
assert_contains "$authoring" 'README には手順の全文を置かない'
assert_contains "$authoring" 'Framework Decision'
assert_contains "$authoring" 'UI Level Decision / PRODUCT前提整理'
assert_contains "$authoring" 'NEEDS_DECISION → 確認して計画を更新 → 再判定。Framework依存のIssue化は停止'
assert_contains "$sample" '| { tag: LOADED, list: EMPTY | NONEMPTY, form: IDLE | INVALID | SUBMITTING }'
assert_contains "$sample" '`LOADING` や `LOAD_FAILED` のときに `list` と `form` を持たない。'
assert_contains "$sample" '`title === title.trim()`'
assert_contains "$sample" '読込時に値を暗黙にtrimして別のTodoへ変換しない'
assert_contains "$guide" '## 4.4 計画書の作り方（会話）'
assert_contains "$guide" '[計画書の作り方](plan-authoring.md)'
assert_contains "$flow" '[計画書の作り方](plan-authoring.md)'
assert_contains "$doc" '[計画書の作り方](plan-authoring.md)'
assert_contains "$guide" '- [ ] `docs/architecture/framework-decision.md` を配置'

guide_setup_line="$(grep -nF 'Plan Review正本文書（`docs/plan-review-gate.md`）を配置' "$guide" | cut -d: -f1)"
guide_after_setup_line="$(grep -nF '設定後、計画書を親Issue・子Issueへ変換' "$guide" | cut -d: -f1)"
[[ -n "$guide_setup_line" && -n "$guide_after_setup_line" && "$guide_setup_line" -lt "$guide_after_setup_line" ]] || {
  printf 'Plan Review source must be listed before issue conversion\n' >&2
  exit 1
}

guide_plan_line="$(grep -nF 'Plan Review Gate（Grilling）' "$guide" | tail -1 | cut -d: -f1)"
guide_parent_line="$(grep -nF '    ├─ PASS → 親Issue' "$guide" | cut -d: -f1)"
[[ -n "$guide_plan_line" && -n "$guide_parent_line" && "$guide_plan_line" -lt "$guide_parent_line" ]] || {
  printf 'Plan Review Gate must precede parent Issue conversion in template guide\\n' >&2
  exit 1
}


framework_line="$(grep -nF '## 2.0 Framework Decision（技術選定）' "$flow" | cut -d: -f1)"
ui_level_line="$(grep -nF '## 2.1 UI Level Decision（案件分類）' "$flow" | cut -d: -f1)"
plan_line="$(grep -nF '## 2.2 Plan Review Gate（計画書Grilling）' "$flow" | cut -d: -f1)"
parent_line="$(grep -nF '## 3. 親Issue' "$flow" | cut -d: -f1)"
[[ -n "$framework_line" && -n "$ui_level_line" && -n "$plan_line" && -n "$parent_line" && "$framework_line" -lt "$ui_level_line" && "$ui_level_line" -lt "$plan_line" && "$plan_line" -lt "$parent_line" ]] || {
  printf 'Framework Decision must precede UI Level Decision, Plan Review Gate, and parent Issue conversion\n' >&2
  exit 1
}

# 条件付き参照先でFramework → UI → Plan Reviewの順序を保持する。
skill="$repo_root/.agents/skills/plan-to-issues/SKILL.md"
framework=$(grep -nF 'Framework Decision（適用時）' "$skill" | head -1 | cut -d: -f1)
ui=$(grep -nF 'UI Level Decision（UI適用を確認し、UIがある場合だけ記録）' "$skill" | head -1 | cut -d: -f1)
plan=$(grep -nFx 'Plan Review Gate' "$skill" | head -1 | cut -d: -f1)
[[ "$framework" -lt "$ui" && "$ui" -lt "$plan" ]] || exit 1

printf 'plan review gate documentation contract: ok\n'
