#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
AGENTS_FILE="${ROOT_DIR}/AGENTS.md"
SKILL_FILE="${ROOT_DIR}/.agents/skills/pr-review-fix/SKILL.md"
FLOW_FILE="${ROOT_DIR}/docs/nine-standard-ai-development-flow.md"
PR_FILE="${ROOT_DIR}/.github/pull_request_template.md"
README_FILE="${ROOT_DIR}/README.md"
GUIDE_FILE="${ROOT_DIR}/docs/template-guide.md"

assert_contains() {
  local file="$1"
  local marker="$2"
  grep -Fq -- "$marker" "$file" || {
    printf 'missing review evidence contract marker in %s: %s\n' "$file" "$marker" >&2
    exit 1
  }
}

assert_absent() {
  local file="$1"
  local marker="$2"
  if grep -Fq -- "$marker" "$file"; then
    printf 'obsolete review policy marker remains in %s: %s\n' "$file" "$marker" >&2
    exit 1
  fi
}

for file in "$AGENTS_FILE" "$SKILL_FILE" "$FLOW_FILE"; do
  for marker in \
    'Review Evidence Contract' \
    'Finding ID:' \
    'Location:' \
    'Claim:' \
    'Trigger:' \
    'Expected:' \
    'Actual:' \
    'PR Causality:' \
    'Acceptance Criteria:' \
    'Reproduction:' \
    'Confidence:' \
    'Disposition:' \
    '決定的な静的根拠' \
    'Evidence不足' \
    'BLOCKING / IN-SCOPE FIX / FOLLOW-UP / DISMISS' \
    '非BLOCKING P2' \
    'Rule Promotion'; do
    assert_contains "$file" "$marker"
  done
done

for marker in \
  '- 変更目的:' \
  '- 対象ユーザー / 利用者:' \
  '- Issue受入条件:' \
  '- 禁止結果:' \
  '- 変更対象:' \
  '- 変更しない範囲:' \
  '- 主な影響先:' \
  '- 実行済みテスト:' \
  '- 特に確認する境界・失敗条件:' \
  '- 未決事項:'; do
  assert_contains "$PR_FILE" "$marker"
done

for marker in \
  'P0 / P1、および `BLOCKING` 候補のP2' \
  'Issue / 契約 / 安全条件' \
  '再現可能な問題' \
  '実行再現が困難な場合は決定的な静的根拠' \
  '非BLOCKING P2の個別人間承認をMerge条件にしない'; do
  assert_contains "$PR_FILE" "$marker"
done

for file in "$AGENTS_FILE" "$SKILL_FILE" "$FLOW_FILE" "$PR_FILE" "$README_FILE" "$GUIDE_FILE"; do
  assert_absent "$file" 'P2は原則としてMerge前に修正する。残す場合は人間が理由を確認して明示判断する。'
  assert_absent "$file" 'P2のみ残る場合は人間の理由確認と明示判断が必要である。'
  assert_absent "$file" 'P2が0件、または残置理由を人間が明示判断'
  assert_absent "$file" 'P2のみ残る場合は人間の明示判断が必要です。'
done

printf 'Review Evidence documentation contract passed\n'
