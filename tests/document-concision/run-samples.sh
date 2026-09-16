#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
failures=0

require() {
  if ! grep -Fq -- "$2" "$ROOT/$1"; then
    printf 'missing document concision contract: %s: %s\n' "$1" "$2" >&2
    failures=1
  fi
}

require AGENTS.md '## AI生成ドキュメント原則'
require AGENTS.md '**Decision First**'
require AGENTS.md '**Non-goals**'
require AGENTS.md '**Minimum Documentation**'
require AGENTS.md '安全境界、停止条件、承認、検証、Acceptanceなど既存Gateが要求する今回値は省略しない'
require AGENTS.md '案 / 却下理由'
require AGENTS.md '変更ファイル一覧を再掲しない'
require AGENTS.md '重複説明、意思決定に不要な章、同じ理由の言い換え、根拠のない将来可能性を削除'

for template in \
  .github/ISSUE_TEMPLATE/parent-issue.md \
  templates/app/docs/framework-decision.md \
  templates/app/docs/design.md; do
  require "$template" 'Decision Summary'
  require "$template" 'Alternatives'
  require "$template" 'Non-goals'
done

require templates/app/docs/framework-decision.md '## 4. Framework Alternatives'
require templates/app/docs/framework-decision.md '候補の採否と主要理由はこの表だけに記録する'
if grep -Fq -- 'Rejected candidates and reasons:' "$ROOT/templates/app/docs/framework-decision.md"; then
  printf 'duplicated framework rejection field remains\n' >&2
  failures=1
fi

require .github/ISSUE_TEMPLATE/child-issue.md 'Decision Summary'
require .github/ISSUE_TEMPLATE/child-issue.md 'Non-goals（今回扱わないこと）'
require .github/pull_request_template.md '# 差分・判断・レビュー上の注意点'
require .github/pull_request_template.md 'GitHubから確認できる変更ファイル一覧は再掲しない'
require docs/template-guide.md 'Design Decisionの最小構成'
require docs/template-guide.md '意思決定の理解に必要な場合のみ記載'

# 簡潔化後も既存Gateの情報がテンプレートに残ることを確認する。
require .github/ISSUE_TEMPLATE/parent-issue.md '# Framework Decision'
require .github/ISSUE_TEMPLATE/parent-issue.md '# Agent Security Boundary とリリース判断'
require .github/ISSUE_TEMPLATE/parent-issue.md '# 検収計画'
require .github/ISSUE_TEMPLATE/child-issue.md '# テストと受入条件'
require .github/ISSUE_TEMPLATE/child-issue.md '# Agent Security Boundary（安全境界と停止条件）'
require .github/ISSUE_TEMPLATE/child-issue.md '# Current State'
require .github/pull_request_template.md '# 検証とGitHub観測'
require .github/pull_request_template.md '# レビュー収束'
require templates/app/docs/framework-decision.md '## Completion Checklist'
require templates/app/docs/design.md '## Component Decision Rules'
require templates/app/docs/design.md '## Accessibility'

(( failures == 0 )) || exit 1
echo 'Document concision contract: PASS'
