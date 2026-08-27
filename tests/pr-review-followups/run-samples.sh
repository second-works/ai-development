#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_FILE="${ROOT_DIR}/.agents/skills/pr-review-fix/SKILL.md"
LEDGER_FILE="${ROOT_DIR}/docs/review-followups.md"

required_skill_markers=(
  "## FOLLOW-UPの記録・参照"
  "発生元Issue / PR"
  "対象機能・領域"
  "FOLLOW-UPとした理由"
  "今回後回しにしてもマージ可能と判断した根拠"
  "想定される将来の症状 / 不具合"
  "関連ファイル・モジュール等の調査入口"
  '推奨扱い: `ISSUE` または `NOTE`'
  "../../../docs/review-followups.md"
  '`ISSUE` として台帳へ登録'
  'FOLLOW-UPかつ `ISSUE` の台帳登録後'
  "台帳登録commit"
  "EXPECTED_SHA"
  "台帳登録後の新しいSHA"
  "標準検証入口"
  "security"
  '`@codex review`'
  "open"
  "resolved"
  "superseded"
)

for marker in "${required_skill_markers[@]}"; do
  grep -Fq -- "${marker}" "${SKILL_FILE}" || {
    printf 'missing FOLLOW-UP Skill marker: %s\n' "${marker}" >&2
    exit 1
  }
done

required_ledger_markers=(
  "# Review Follow-ups"
  "Follow-up ID"
  "発生元Issue / PR"
  "対象領域"
  "後回し可能とした根拠"
  "想定症状"
  "関連ファイル / 機能"
  "優先度"
  "状態"
  "解決Issue / PR"
  "open / resolved / superseded"
  '原因候補から外れただけなら `open` を維持する'
  'リスクを解消した場合だけ解決Issue / PRを追記して `resolved` へ'
  '設計変更で不要になった場合だけ置換理由を追記して `superseded` へ'
  "症状"
  "エラー文"
  "機能名"
  "モジュール名"
  "NOTE"
  "台帳登録後の検証対象SHA"
  "登録commit"
  "同じPRのhead branch"
  "検証結果が同じ新しいSHA"
  "人間へ戻す"
)

for marker in "${required_ledger_markers[@]}"; do
  grep -Fq -- "${marker}" "${LEDGER_FILE}" || {
    printf 'missing FOLLOW-UP ledger marker: %s\n' "${marker}" >&2
    exit 1
  }
done

printf 'FOLLOW-UP documentation contract passed\n'
