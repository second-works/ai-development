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

require docs/nine-standard-ai-development-flow.md '## AI生成ドキュメント原則'
require docs/nine-standard-ai-development-flow.md '**Decision First**'
require docs/nine-standard-ai-development-flow.md '**Non-goals**'
require docs/nine-standard-ai-development-flow.md '**Minimum Documentation**'
require docs/nine-standard-ai-development-flow.md '安全境界、停止条件、承認、検証、Acceptanceなど既存Gateが要求する今回値は省略しない'
require docs/nine-standard-ai-development-flow.md '案 / 却下理由'
require docs/nine-standard-ai-development-flow.md '変更ファイル一覧を再掲しない'
require docs/nine-standard-ai-development-flow.md '重複説明、意思決定に不要な章、同じ理由の言い換え、根拠のない将来可能性を削除'
require docs/plan-authoring.md '## Decision'
require docs/plan-authoring.md '## Non-goals'
require docs/plan-authoring.md '推測で埋めない'

for template in \
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

require .github/ISSUE_TEMPLATE/child-issue.md '# Context'
require .github/ISSUE_TEMPLATE/child-issue.md '# Non-goals'
require .github/pull_request_template.md '# 差分・判断・レビュー上の注意点'
require .github/pull_request_template.md 'GitHubから確認できる変更ファイル一覧は再掲しない'
require docs/template-guide.md 'Design Decisionの最小構成'
require docs/template-guide.md '意思決定の理解に必要な場合のみ記載'

# 最小入力から条件表と安全正本へ到達し、非該当の巨大節を再導入しない。
for template in parent child; do
  file=".github/ISSUE_TEMPLATE/$template-issue.md"
  require "$file" '# Scope / Boundaries'
  require "$file" '# Verification'
  require "$file" '../blob/main/docs/minimal-development-contract.md#条件付き参照'
  require "$file" '../blob/main/docs/ai-agent-security-boundary.md'
  if grep -Eq '^# (Framework Decision|Agent Security Boundary|Current State|Harness|Alternatives)' "$ROOT/$file"; then
    printf 'non-applicable specialist sections remain: %s\n' "$file" >&2
    failures=1
  fi
done
require .github/ISSUE_TEMPLATE/parent-issue.md 'Acceptance Verification'
require .github/pull_request_template.md '# 検証とGitHub観測'
require .github/pull_request_template.md '# レビュー収束'
require templates/app/docs/framework-decision.md '## Completion Checklist'
require templates/app/docs/design.md '## Component Decision Rules'
require templates/app/docs/design.md '## Accessibility'

require AGENTS.md 'docs/nine-standard-ai-development-flow.md'

(( failures == 0 )) || exit 1
echo 'Document concision contract: PASS'
