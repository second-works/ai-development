#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
failures=0

require() {
  if ! grep -Fq -- "$2" "$ROOT/$1"; then
    printf 'missing template simplification contract: %s: %s\n' "$1" "$2" >&2
    failures=1
  fi
}

reject() {
  if grep -Fq -- "$2" "$ROOT/$1"; then
    printf 'legacy duplicated template content remains: %s: %s\n' "$1" "$2" >&2
    failures=1
  fi
}

require .github/ISSUE_TEMPLATE/parent-issue.md "Plan Reviewの判定"
require .github/ISSUE_TEMPLATE/parent-issue.md "AI Agent Security Boundary"
require .github/ISSUE_TEMPLATE/parent-issue.md "Acceptance Verification"
require .github/ISSUE_TEMPLATE/child-issue.md "1子Issue = 1 PR"
require .github/ISSUE_TEMPLATE/child-issue.md "Issue Quality Check"
require .github/ISSUE_TEMPLATE/child-issue.md "安全境界と停止条件"
require .github/ISSUE_TEMPLATE/child-issue.md "Harness Minimalism台帳"
require .github/pull_request_template.md "検証とGitHub観測"
require .github/pull_request_template.md "Review Evidence Contract"
require .github/pull_request_template.md "最終Mergeは人間が判断する"
reject .github/ISSUE_TEMPLATE/child-issue.md "## エスカレーション時の標準出力"
reject .github/pull_request_template.md "## 修正時のPR / head branch記録"
require docs/template-guide.md "## 2.2 テンプレートに記入する値"
require docs/template-guide.md "| LOW |"
require docs/template-guide.md "| MEDIUM |"
require docs/template-guide.md "| HIGH |"
require docs/nine-standard-ai-development-flow.md "テンプレートは今回値"
require README.md "テンプレートは今回値"
require docs/ai-development-harness-inventory.md "C-01"

(( failures == 0 )) || exit 1
echo "Template simplification contract: PASS"
