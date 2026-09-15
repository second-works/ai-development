#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
PARENT="${ROOT_DIR}/.github/ISSUE_TEMPLATE/parent-issue.md"
CHILD="${ROOT_DIR}/.github/ISSUE_TEMPLATE/child-issue.md"
STANDARD="${ROOT_DIR}/docs/product-ui-standard.md"
DESIGN_TEMPLATE="${ROOT_DIR}/templates/app/docs/design.md"
AGENTS="${ROOT_DIR}/AGENTS.md"

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

assert_order() {
  local file="$1"
  local first="$2"
  local second="$3"
  local first_line second_line
  first_line="$(grep -nF -- "$first" "$file" | head -n 1 | cut -d: -f1)"
  second_line="$(grep -nF -- "$second" "$file" | head -n 1 | cut -d: -f1)"
  if [[ -z "$first_line" || -z "$second_line" || "$first_line" -ge "$second_line" ]]; then
    printf 'invalid Issue template contract order: %s before %s in %s\n' "$first" "$second" "$file" >&2
    exit 1
  fi
}

assert_reference_stop_boundary() {
  local section boundary_line
  section="$(awk -v heading='## AI / Codex Reference Contract' '
    $0 == heading { found=1; next }
    found && /^## / { exit }
    found { print }
  ' "$AGENTS")"
  boundary_line="$(grep -F 'Framework Decision、UI Level、標準Design Rules、案件 `docs/design.md` のいずれかが欠落・矛盾・判断不能で' <<< "$section" || true)"
  boundary_line="${boundary_line#- }"
  if [[ "$boundary_line" != 'Framework Decision、UI Level、標準Design Rules、案件 `docs/design.md` のいずれかが欠落・矛盾・判断不能で、重要UX判断を確定できない場合は推測で補完せず `NEEDS_DECISION` として既存のDesign Decisionへ接続し、実装を停止する。component / library固有docsは採用する場合に参照し、採用を決めたdocsが取得できない場合だけ同じ停止条件を適用する。' ]]; then
    printf 'reference stop boundary changed or missing\n' >&2
    exit 1
  fi
}

assert_exact_line "$AGENTS" '## AI / Codex Reference Contract'
assert_reference_stop_boundary
assert_order "$AGENTS" '## Framework Decision' '## AI / Codex Reference Contract'
assert_order "$AGENTS" '## AI / Codex Reference Contract' '## Child Issue Quality Gate'
for needle in \
  '1. Framework Decision結果と正本文書（Frameworkを再選定しない）' \
  '2. UI Level Decisionと適用対象' \
  '3. Nine PRODUCT UI Standard / `Component Decision Rules`' \
  '4. 案件 `docs/design.md`' \
  '5. component / library固有docs（存在する場合）' \
  '参照順序、適用対象、案件固有の例外と根拠をIssueまたはPRで追跡できる状態にする。' \
  '推測で補完せず `NEEDS_DECISION` として既存のDesign Decisionへ接続し、実装を停止する' \
  '案件 `docs/design.md` の決定は、標準Design RulesのUX原則とAccessibility最低条件を満たす範囲で尊重する。標準側と案件側の責務を暗黙に入れ替えない。' \
  '`NONE` / `UTILITY` の案件にはPRODUCT UI用の必須欄やVisual/UI Acceptanceを過剰適用しない'; do
  assert_contains "$AGENTS" "$needle"
done
assert_order "$AGENTS" '1. Framework Decision結果と正本文書（Frameworkを再選定しない）' '2. UI Level Decisionと適用対象'
assert_order "$AGENTS" '2. UI Level Decisionと適用対象' '3. Nine PRODUCT UI Standard / `Component Decision Rules`'
assert_order "$AGENTS" '3. Nine PRODUCT UI Standard / `Component Decision Rules`' '4. 案件 `docs/design.md`'
assert_order "$AGENTS" '4. 案件 `docs/design.md`' '5. component / library固有docs（存在する場合）'

assert_exact_line "$PARENT" '# UI Level / PRODUCT UI'
assert_exact_line "$CHILD" '# UI Level / PRODUCT UI 引き継ぎ'

assert_exact_line "$PARENT" '# AI / Codex Reference Contract（PRODUCT UI実装時）'
assert_exact_line "$CHILD" '# AI / Codex Reference Contract（PRODUCT UI実装時）'
assert_order "$PARENT" '# UI Level / PRODUCT UI' '# AI / Codex Reference Contract（PRODUCT UI実装時）'
assert_order "$PARENT" '# AI / Codex Reference Contract（PRODUCT UI実装時）' '# 今回の範囲'
assert_order "$CHILD" '# UI Level / PRODUCT UI 引き継ぎ' '# AI / Codex Reference Contract（PRODUCT UI実装時）'
assert_order "$CHILD" '# AI / Codex Reference Contract（PRODUCT UI実装時）' '# 今回の変更'

assert_exact_line "$PARENT" '- UI Level: `NONE / UTILITY / PRODUCT / NEEDS_DECISION`'
assert_exact_line "$CHILD" '- 親IssueのUI Level: `NONE / UTILITY / PRODUCT / NEEDS_DECISION`'

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

for file in "$PARENT" "$CHILD"; do
  assert_contains "$file" '参照順序: Framework Decision結果 → UI Level → Nine PRODUCT UI Standard / `Component Decision Rules` → 案件 `docs/design.md` → component / library固有docs（存在時）'
  assert_contains "$file" 'Standard Design Rules: [Component Decision Rules](../blob/main/docs/product-ui-standard.md#component-decision-rules)'
  assert_contains "$file" '案件固有のvisual、brand、tokens、採用component、例外、根拠:'
  assert_contains "$file" '推測で補完せず `NEEDS_DECISION` としてDesign Decisionへ接続し、実装を停止する'
done
assert_contains "$PARENT" '未決定事項・矛盾・候補不足・Design Decision参照:'
assert_contains "$CHILD" '親Issue・前Issueから引き継ぐ未決定事項・矛盾・Design Decision参照:'

assert_contains "$STANDARD" 'Nine PRODUCT UI Standard v1'
assert_contains "$DESIGN_TEMPLATE" '# Product Design'
assert_contains "$PARENT" 'docs/product-ui-standard.md'
assert_contains "$PARENT" 'templates/app/docs/design.md'
assert_contains "$CHILD" 'docs/product-ui-standard.md'
assert_contains "$CHILD" 'templates/app/docs/design.md'

printf 'Issue template UI Level contract: ok\n'
