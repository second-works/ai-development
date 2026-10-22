#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
REVIEW_FILE="${ROOT_DIR}/docs/code-review-contract.md"
LEDGER_FILE="${ROOT_DIR}/docs/review-followups.md"

required_initial_review_markers=(
  "変更箇所の呼び出し元・利用箇所への影響"
  "類似実装・対称実装との一貫性"
  "API、データモデル、状態遷移等の既存契約との整合性"
  "固定値・特殊処理・例外処理等の設計意図が変更後も保存されているか"
  "エラー握りつぶし等によるsilent failureがないか"
  "外部API / SDK / DB / filesystem等のシステム境界仕様との整合性"
  "共通部品変更による波及先"
  "既存コード全体の改善探索へ無制限に広げず"
)

for review_file in "${REVIEW_FILE}"; do
  for marker in "${required_initial_review_markers[@]}"; do
    grep -Fq -- "${marker}" "${review_file}" || {
      printf 'missing initial review contract marker in %s: %s\n' "${review_file}" "${marker}" >&2
      exit 1
    }
  done
done

required_agents_markers=(
  "### 初回レビューの標準探索観点"
  "severityだけでMerge可否を決定せず"
  '`BLOCKING / IN-SCOPE FIX / FOLLOW-UP / DISMISS`'
  '`IN-SCOPE FIX`、`FOLLOW-UP`、`DISMISS` に分類された非BLOCKING P2は'
  "最終Merge判断は人間が行う"
)

for marker in "${required_agents_markers[@]}"; do
  grep -Fq -- "${marker}" "${REVIEW_FILE}" || {
    printf 'missing canonical review contract marker: %s\n' "${marker}" >&2
    exit 1
  }
done

# The recording fields and the steps after registration live in the ledger itself
# (checked below) and in docs/code-review-contract.md; the pr-review-fix Skill that
# repeated them was removed in #197.
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
