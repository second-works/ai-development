#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
STANDARD="${ROOT_DIR}/docs/product-ui-standard.md"
DESIGN_TEMPLATE="${ROOT_DIR}/templates/app/docs/design.md"
README="${ROOT_DIR}/README.md"
AGENTS="${ROOT_DIR}/AGENTS.md"

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "${needle}" "${file}"; then
    printf 'missing PRODUCT UI contract: %s in %s\n' "${needle}" "${file}" >&2
    exit 1
  fi
}

assert_exact_heading() {
  local file="$1"
  local heading="$2"
  if ! grep -Fxq -- "$heading" "$file"; then
    printf 'missing exact PRODUCT UI heading: %s in %s\\n' "$heading" "$file" >&2
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
    printf 'invalid PRODUCT UI contract order: %s before %s in %s\n' "$first" "$second" "$file" >&2
    exit 1
  fi
}

assert_exact_heading "$AGENTS" '## AI / Codex Reference Contract'
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

for needle in \
  'Nine PRODUCT UI Standard v1' \
  '`NONE`' \
  '`UTILITY`' \
  '`PRODUCT`' \
  '`NEEDS_DECISION`' \
  'User Goal First' \
  'Current State is Visible' \
  'Next Action is Clear' \
  'Invalid States are Prevented Structurally' \
  'Implementation Done != UI Accepted' \
  'PRODUCT UI Specification' \
  'Design Profile' \
  'Use:' \
  'Do NOT copy:' \
  'UNKNOWN != ERROR' \
  'EMPTY != ERROR' \
  'UNAVAILABLE != FAILED' \
  'Responsive Design' \
  'Accessibility Minimum' \
  'AI / Codex Design Boundary' \
  'Visual Review / UI Acceptance' \
  'Plan Review Gate' \
  'Acceptance Verification' \
  'Harness Minimalism / ETCSLV'; do
  assert_contains "${STANDARD}" "${needle}"
done

for needle in \
  '# Product Design' \
  '## Product' \
  '## UI Level' \
  '## Target User / Primary Goal' \
  '## Device Priority' \
  '## Design Direction' \
  '## Visual References' \
  '## Design System' \
  '## Typography' \
  '## Layout' \
  '## Spacing' \
  '## Color Semantics' \
  '## Components' \
  '## UI States' \
  '## Responsive Rules' \
  '## Accessibility' \
  '## Open Design Decisions'; do
  assert_contains "${DESIGN_TEMPLATE}" "${needle}"
done

assert_exact_heading "${DESIGN_TEMPLATE}" '## Do'
assert_exact_heading "${DESIGN_TEMPLATE}" "## Don't"
assert_contains "${README}" 'docs/product-ui-standard.md'
assert_contains "${README}" 'templates/app/docs/design.md'

printf 'PRODUCT UI standard contract: ok\n'
