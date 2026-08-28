#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
doc="$repo_root/docs/acceptance-verification.md"
flow="$repo_root/docs/nine-standard-ai-development-flow.md"
deployment="$repo_root/docs/deployment-release-design.md"
guide="$repo_root/docs/template-guide.md"
parent="$repo_root/.github/ISSUE_TEMPLATE/parent-issue.md"
pr="$repo_root/.github/pull_request_template.md"

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

assert_contains "$flow" 'acceptance-verification.md'
assert_contains "$flow" 'Production Deploy後は、Health Check / Smoke Testとは別に実利用シナリオ'
assert_contains "$deployment" 'acceptance-verification.md'
assert_contains "$deployment" 'Monitoring開始 / Rollback判断'
assert_contains "$deployment" 'Monitoring / Rollbackを妨げない'
assert_contains "$guide" 'acceptance-verification.md'
assert_contains "$parent" '## 実利用検証 / 検収計画'
assert_contains "$parent" 'Product Accepted'
assert_contains "$pr" '# 実利用検証 / Product Acceptance'
assert_contains "$pr" 'ACCEPTANCE BLOCKER'

flow_line="$(grep -nF 'Production Deploy後は、Health Check / Smoke Testとは別に実利用シナリオ' "$flow" | cut -d: -f1)"
doc_line="$(grep -nF '## 4. 標準フロー' "$doc" | cut -d: -f1)"
monitor_line="$(grep -nF 'Monitoring開始 / Rollback判断' "$deployment" | cut -d: -f1)"
usage_line="$(grep -nF '↓ 実利用シナリオ検証' "$deployment" | cut -d: -f1)"
branch_line="$(grep -nF 'Merge済みIssue用branchを自動削除' "$guide" | cut -d: -f1)"
guide_usage_line="$(grep -nF 'Production Deploy後の実利用シナリオ検証' "$guide" | cut -d: -f1)"
[[ -n "$flow_line" && -n "$doc_line" && -n "$monitor_line" && -n "$usage_line" && -n "$branch_line" && -n "$guide_usage_line" ]] || {
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

printf 'acceptance verification documentation contract: ok\n'
