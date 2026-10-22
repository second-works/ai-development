#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
doc="$repo_root/docs/acceptance-verification.md"
flow="$repo_root/docs/nine-standard-ai-development-flow.md"
deployment="$repo_root/docs/deployment-release-design.md"
guide="$repo_root/docs/template-guide.md"

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    printf 'missing acceptance contract: %s in %s\n' "$needle" "$file" >&2
    exit 1
  fi
}

assert_contains "$doc" 'Implementation Done'
assert_contains "$doc" 'Deployed'
assert_contains "$doc" 'Product Accepted'
assert_contains "$doc" 'PRODUCT UI Visual / UI Acceptance'
assert_contains "$doc" 'UI LevelがPRODUCTの場合'
assert_contains "$doc" 'Screenshot / Render'
assert_contains "$doc" 'Visual Review'
assert_contains "$doc" 'UI Acceptance'
assert_contains "$doc" 'Product Acceptance'
assert_contains "$doc" 'Primary user flow'
assert_contains "$doc" 'Primary Action clarity'
assert_contains "$doc" 'Navigation'
assert_contains "$doc" 'Loading状態'
assert_contains "$doc" 'Empty状態'
assert_contains "$doc" 'Error + Recovery'
assert_contains "$doc" 'Success/feedback'
assert_contains "$doc" 'Responsive'
assert_contains "$doc" 'Accessibility minimum'
assert_contains "$doc" 'Design consistency'
assert_contains "$doc" 'docs/design.md'
assert_contains "$doc" 'UNKNOWN'
assert_contains "$doc" 'UNKNOWN` != `ERROR'
assert_contains "$doc" 'EMPTY` != `ERROR'
assert_contains "$doc" 'UNAVAILABLE` != `FAILED'
assert_contains "$doc" '色だけで表現せず'
assert_contains "$doc" 'Implementation Done` != `UI Accepted` != `Product Accepted'
assert_contains "$doc" 'Accepted'
assert_contains "$doc" 'Not Accepted'
assert_contains "$doc" 'Conditional'
assert_contains "$doc" '解決したい課題 / 利用目的:'
assert_contains "$doc" '対象ユーザー / 利用者:'
assert_contains "$doc" '実利用シナリオ（開始条件から完了まで）:'
assert_contains "$doc" '成功条件（利用者が達成できること、測定方法）:'
assert_contains "$doc" '失敗条件（検収不可とする条件）:'
assert_contains "$doc" '検証環境（Production、Staging、ローカル等）:'
assert_contains "$doc" '必要な実データ / fixtureとデータ準備方法:'
assert_contains "$doc" '人間確認が必要な項目'
assert_contains "$doc" 'Accepted'
assert_contains "$doc" 'Not Accepted'
assert_contains "$doc" 'Conditional'
assert_contains "$doc" 'ACCEPTANCE BLOCKER'
assert_contains "$doc" 'DEFECT'
assert_contains "$doc" 'IMPROVEMENT'
assert_contains "$doc" 'FUTURE'
assert_contains "$doc" 'Design Decision Escalation'
assert_contains "$doc" '設計判断の失敗仮説:'
assert_contains "$doc" '設計判断が誤りと判断する観測:'
assert_contains "$doc" '機能が動いても選択した設計 / 設定に価値がない条件:'
assert_contains "$doc" 'Plan vs Reality'
assert_contains "$doc" '失敗した前提:'
assert_contains "$doc" '不要または過剰だった設計:'
assert_contains "$doc" '次の計画へ反映する教訓:'
assert_contains "$doc" '失敗観測または価値なし条件が実利用で成立した場合'

assert_contains "$flow" 'acceptance-verification.md'
assert_contains "$flow" 'Production Deploy後は、Health Check / Smoke Testとは別に実利用シナリオ'
assert_contains "$flow" 'Plan Reviewで整理した主要予測・失敗仮説'
assert_contains "$deployment" 'acceptance-verification.md'
assert_contains "$deployment" 'Monitoring開始 / Rollback判断'
assert_contains "$deployment" 'Monitoring / Rollbackを妨げない'
assert_contains "$guide" 'acceptance-verification.md'
# The PR and Issue templates and AGENTS.md are now the lightweight ones (#197). Their
# safety wording is checked in tests/lightweight-template.
assert_contains "$guide" '次Issue着手と、Deploy後の実利用検証・検収は独立した工程'

flow_line="$(grep -nF 'Production Deploy後は、Health Check / Smoke Testとは別に実利用シナリオ' "$flow" | cut -d: -f1)"
doc_line="$(grep -nF '## 4. 標準フロー' "$doc" | cut -d: -f1)"
monitor_line="$(grep -nF 'Monitoring開始 / Rollback判断' "$deployment" | cut -d: -f1)"
usage_line="$(grep -nF '↓ 実利用シナリオ検証' "$deployment" | cut -d: -f1)"
branch_line="$(grep -nF 'Merge済みIssue用branchを自動削除' "$guide" | cut -d: -f1)"
guide_usage_line="$(grep -nF 'Production Deploy後の実利用シナリオ検証' "$guide" | cut -d: -f1)"
parallel_line="$(grep -nF '次Issue着手と、Deploy後の実利用検証・検収は独立した工程' "$guide" | cut -d: -f1)"
[[ -n "$flow_line" && -n "$doc_line" && -n "$monitor_line" && -n "$usage_line" && -n "$branch_line" && -n "$guide_usage_line" && -n "$parallel_line" ]] || {
  printf 'acceptance flow anchors are missing\n' >&2
  exit 1
}
(( monitor_line < usage_line )) || {
  printf 'monitoring / rollback must precede real-use verification\n' >&2
  exit 1
}
(( branch_line < guide_usage_line )) || {
  printf 'merged branch cleanup must precede real-use verification\n' >&2
  exit 1
}


render_line="$(grep -nF 'Screenshot / Render' "$doc" | head -n1 | cut -d: -f1)"
visual_line="$(grep -nF '↓ Visual Review' "$doc" | head -n1 | cut -d: -f1)"
ui_acceptance_line="$(grep -nF '↓ UI Acceptance' "$doc" | head -n1 | cut -d: -f1)"
product_acceptance_line="$(grep -nF '↓ Product Acceptance' "$doc" | head -n1 | cut -d: -f1)"
[[ -n "$render_line" && -n "$visual_line" && -n "$ui_acceptance_line" && -n "$product_acceptance_line" ]] || {
  printf 'PRODUCT UI acceptance flow anchors are missing\n' >&2
  exit 1
}
(( render_line < visual_line && visual_line < ui_acceptance_line && ui_acceptance_line < product_acceptance_line )) || {
  printf 'PRODUCT UI acceptance flow order is invalid\n' >&2
  exit 1
}

printf 'acceptance verification documentation contract: ok\n'
