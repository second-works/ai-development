#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
PARENT="${ROOT_DIR}/.github/ISSUE_TEMPLATE/parent-issue.md"
CHILD="${ROOT_DIR}/.github/ISSUE_TEMPLATE/child-issue.md"
STANDARD="${ROOT_DIR}/docs/product-ui-standard.md"
DESIGN_TEMPLATE="${ROOT_DIR}/templates/app/docs/design.md"
UI_REFERENCE="${ROOT_DIR}/docs/product-ui-standard.md"

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
  ' "$UI_REFERENCE")"
  boundary_line="$(grep -F 'Framework Decision、UI Level、標準Design Rules、案件 `docs/design.md` のいずれかが欠落・矛盾・判断不能で' <<< "$section" || true)"
  boundary_line="${boundary_line#- }"
  if [[ "$boundary_line" != 'Framework Decision、UI Level、標準Design Rules、案件 `docs/design.md` のいずれかが欠落・矛盾・判断不能で、重要UX判断を確定できない場合は推測で補完せず `NEEDS_DECISION` として既存のDesign Decisionへ接続し、実装を停止する。component / library固有docsは採用する場合に参照し、採用を決めたdocsが取得できない場合だけ同じ停止条件を適用する。' ]]; then
    printf 'reference stop boundary changed or missing\n' >&2
    exit 1
  fi
}

assert_exact_line "$UI_REFERENCE" '## AI / Codex Reference Contract'
assert_reference_stop_boundary
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
  assert_contains "$UI_REFERENCE" "$needle"
done
assert_order "$UI_REFERENCE" '1. Framework Decision結果と正本文書（Frameworkを再選定しない）' '2. UI Level Decisionと適用対象'
assert_order "$UI_REFERENCE" '2. UI Level Decisionと適用対象' '3. Nine PRODUCT UI Standard / `Component Decision Rules`'
assert_order "$UI_REFERENCE" '3. Nine PRODUCT UI Standard / `Component Decision Rules`' '4. 案件 `docs/design.md`'
assert_order "$UI_REFERENCE" '4. 案件 `docs/design.md`' '5. component / library固有docs（存在する場合）'

# Issueは専門本文を複製せず、条件表からUI正本と案件設計へ到達する。
for file in "$PARENT" "$CHILD"; do
  assert_exact_line "$file" '# Context'
  assert_exact_line "$file" '# Scope / Boundaries'
  assert_contains "$file" '../blob/main/docs/minimal-development-contract.md#条件付き参照'
  assert_contains "$file" '重要判断がNEEDS_DECISION'
  if grep -Eq '^# (UI Level|AI / Codex Reference)' "$file"; then
    printf 'non-applicable UI sections must not be prefilled\n' >&2
    exit 1
  fi
done
CONTRACT="${ROOT_DIR}/docs/minimal-development-contract.md"
assert_contains "$CONTRACT" '[PRODUCT UI](product-ui-standard.md)'
assert_contains "$CONTRACT" 'Framework Decision → UI Level → PRODUCT UI Standard / Component Decision Rules → 案件 `docs/design.md` → 採用component / library固有docs'
assert_contains "$CONTRACT" '非UIにNONE記入を強制せず'
assert_contains "$STANDARD" 'Nine PRODUCT UI Standard v1'
assert_contains "$DESIGN_TEMPLATE" '# Product Design'


assert_contains "${ROOT_DIR}/AGENTS.md" 'Framework Decision → UI Level → docs/product-ui-standard.md / Component Decision Rules → 案件 docs/design.md → 採用component / library固有docs'

printf 'Issue template UI Level contract: ok\n'
