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
  "推奨扱い: `ISSUE` または `NOTE`"
  "docs/review-followups.md"
  "`ISSUE` として台帳へ登録"
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
  "症状"
  "エラー文"
  "機能名"
  "モジュール名"
  "NOTE"
)

for marker in "${required_ledger_markers[@]}"; do
  grep -Fq -- "${marker}" "${LEDGER_FILE}" || {
    printf 'missing FOLLOW-UP ledger marker: %s\n' "${marker}" >&2
    exit 1
  }
done

printf 'FOLLOW-UP documentation contract passed\n'
