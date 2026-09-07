#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
failures=0
require() {
  if ! grep -Fq -- "$2" "$ROOT/$1"; then
    printf 'missing Adaptive Flow contract: %s: %s\n' "$1" "$2" >&2
    failures=1
  fi
}

doc=docs/adaptive-development-flow.md
require "$doc" '既定値は `MEDIUM`'
require "$doc" '安全影響不明をMEDIUMのまま進めない'
require "$doc" 'LOW / MEDIUM / HIGH'
require "$doc" 'HIGH > MEDIUM > LOW'
require "$doc" '未知値は判定済みとして使わず'
require "$doc" '実行動作・API・依存関係・workflow・安全ルールを変えない'
require "$doc" '安全規則の変更はMarkdownだけでもHIGH'
require "$doc" 'Issue化前'
require "$doc" '実装開始時とPR提出前'
require "$doc" '修正で範囲・依存・権限・実行動作が変わった場合も再判定'
require "$doc" 'Gate未実施や失敗を解消するための降格は禁止'
require "$doc" '既に承認された設計範囲の作業は進め'

# Gate一覧の節だけを検査し、単なる他節での名前出現を成功としない。
gates="$(sed -n '/^## 全Tierで維持するGate$/,/^## 記入例とPlan vs Reality$/p' "$ROOT/$doc")"
for gate in '標準検証' 'CI' 'Security' 'Codex Review' 'Human Merge' 'Acceptance'; do
  if ! grep -Fq -- "- $gate:" <<< "$gates"; then
    printf 'missing mandatory gate: %s\n' "$gate" >&2
    failures=1
  fi
done
require "$doc" 'LOWから適用資格を推定しない'
require "$doc" 'Tierから自動設定しない'
require "$doc" '未承認の重要設計'

# 文書の判定例を期待Tierと照合する。意味分類を自動化したとは扱わない。
for pair in '文言のみ:LOW' '通常機能:MEDIUM' '高リスク:HIGH' '混在:HIGH' '不明:HIGH' '今回 #63:HIGH'; do
  name="${pair%:*}"
  tier="${pair##*:}"
  if ! awk -F'|' -v name="$name" -v tier="$tier" '
    { label=$2; gsub(/^ +| +$/, "", label) }
    label==name { count++; value=$4; gsub(/^ +| +$/, "", value); if (index(value, tier "。") == 1) matched++ }
    END { exit !(count==1 && matched==1) }
  ' "$ROOT/$doc"; then
    printf 'invalid scenario Tier: %s expected %s\n' "$name" "$tier" >&2
    failures=1
  fi
done
require "$doc" '本番利用の成果やGitHub Gate成功の証拠ではない'

for file in AGENTS.md README.md docs/template-guide.md docs/nine-standard-ai-development-flow.md .github/ISSUE_TEMPLATE/child-issue.md .github/pull_request_template.md; do
  require "$file" 'adaptive-development-flow.md'
  require "$file" 'LOW / MEDIUM / HIGH'
done
for file in .github/ISSUE_TEMPLATE/child-issue.md .github/pull_request_template.md; do
  require "$file" '# Risk Tier'
  require "$file" '判定理由・影響範囲:'
  require "$file" '再判定（実装開始 / PR提出 / 影響変更時）:'
done
require docs/ai-development-harness-inventory.md '### C-03 Adaptive Development Flow'
require docs/ai-development-harness-inventory.md '| C-03 | Adaptive Development Flow | C | SIMPLIFY |'

# 正本文書が参照する相対Markdownリンクの存在を確認する。
while IFS= read -r target; do
  if [[ ! -f "$ROOT/docs/$target" ]]; then
    printf 'broken Adaptive Flow reference: %s\n' "$target" >&2
    failures=1
  fi
done < <(sed -nE 's/.*\]\(([^)#]+\.md)\).*/\1/p' "$ROOT/$doc")

(( failures == 0 )) || exit 1
echo 'Adaptive Development Flow documentation contract: PASS'
