#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
PARENT="${ROOT_DIR}/.github/ISSUE_TEMPLATE/parent-issue.md"
CHILD="${ROOT_DIR}/.github/ISSUE_TEMPLATE/child-issue.md"
STANDARD="${ROOT_DIR}/docs/product-ui-standard.md"
DESIGN_TEMPLATE="${ROOT_DIR}/templates/app/docs/design.md"

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    printf 'missing Issue template UI contract: %s in %s\n' "$needle" "$file" >&2
    exit 1
  fi
}

assert_exact_line() {
  local file="$1"
  local line="$2"
  if ! grep -Fxq -- "$line" "$file"; then
    printf 'missing exact Issue template UI contract: %s in %s\n' "$line" "$file" >&2
    exit 1
  fi
}

assert_exact_line "$PARENT" '# UI Level / PRODUCT UI'
assert_exact_line "$CHILD" '# UI Level / PRODUCT UI 引き継ぎ'

for file in "$PARENT" "$CHILD"; do
  assert_exact_line "$file" '- UI Level: `NONE / UTILITY / PRODUCT / NEEDS_DECISION`' || true
done

assert_contains "$PARENT" '- 分類理由:'
assert_contains "$PARENT" '- PRODUCT時の適用仕様: [Nine PRODUCT UI Standard v1](../blob/main/docs/product-ui-standard.md)'
assert_contains "$PARENT" '- PRODUCT時のDesign Profile / docs/design.md: [Design Profile / design.md雛形](../blob/main/templates/app/docs/design.md)'
assert_contains "$PARENT" '- UI LevelがNEEDS_DECISIONの場合の未決定事項・決定期限:'
assert_contains "$PARENT" 'AI/Codexが分類や重要UX判断を推測せず、子Issue化・実装開始を停止する'
assert_contains "$PARENT" 'PRODUCT以外ではPRODUCT用の必須欄やVisual/UI Acceptanceを強制しない'

assert_contains "$CHILD" '- 親IssueのUI Level: `NONE / UTILITY / PRODUCT / NEEDS_DECISION`'
assert_contains "$CHILD" '- UI対象範囲:'
assert_contains "$CHILD" '- 分類理由 / 親Issue参照:'
assert_contains "$CHILD" '- PRODUCT時の設計参照: [Nine PRODUCT UI Standard v1](../blob/main/docs/product-ui-standard.md)、[Design Profile / docs/design.md雛形](../blob/main/templates/app/docs/design.md)'
assert_contains "$CHILD" '- UI受入対象外の理由（NONE/UTILITYでPRODUCT項目を適用しない場合）:'
assert_contains "$CHILD" '- NEEDS_DECISIONの未決定事項 / 決定期限:'
assert_contains "$CHILD" 'UI Levelが `NEEDS_DECISION` の場合、AI/Codexは推測で子Issue化・実装開始せず、決定まで停止する'
assert_contains "$CHILD" 'PRODUCT以外ではPRODUCT用の仕様・Design Profile・Visual/UI Acceptanceを必須化しない'

assert_contains "$STANDARD" 'Nine PRODUCT UI Standard v1'
assert_contains "$DESIGN_TEMPLATE" '# Product Design'
assert_contains "$PARENT" 'docs/product-ui-standard.md'
assert_contains "$PARENT" 'templates/app/docs/design.md'
assert_contains "$CHILD" 'docs/product-ui-standard.md'
assert_contains "$CHILD" 'templates/app/docs/design.md'

printf 'Issue template UI Level contract: ok\n'
