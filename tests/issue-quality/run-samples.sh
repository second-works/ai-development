#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
failures=0
require() {
  if ! grep -Fq -- "$2" "$ROOT/$1"; then
    printf 'missing Issue Quality contract: %s: %s\n' "$1" "$2" >&2
    failures=1
  fi
}

for marker in '目的' '変更範囲' '独立検証' '1 PR' '依存関係' '安全境界'; do
  require docs/issue-quality-check.md "$marker"
done
require docs/issue-quality-check.md 'ScoreにかかわらずGitHub登録・実装開始を停止'
require docs/issue-quality-check.md 'SHOULDだけの不足は改善候補として継続できる'
require docs/issue-quality-check.md '許容値は0、1、2だけ'
require docs/issue-quality-check.md '合計範囲は0〜12点'
require docs/issue-quality-check.md 'Scoreが高くてもMUST不足は登録・実装開始を許可しない'
require AGENTS.md 'MUSTが1つでも欠落した場合はScoreにかかわらず登録・実装開始を停止'
require AGENTS.md 'SHOULDのみの不足は改善候補として継続できる'
require docs/template-guide.md '高ScoreでもMUST不足を打ち消さない'
require README.md '子Issue品質はMUSTを先に確認'
require docs/nine-standard-ai-development-flow.md 'Scoreは補助表示であり、MUST不足を打ち消さない'
require docs/ai-development-harness-inventory.md 'MUST不足時の停止'
require docs/ai-development-harness-inventory.md 'SHOULD不足時の改善候補'

(( failures == 0 )) || exit 1
echo 'Issue Quality MUST/SHOULD contract: PASS'
