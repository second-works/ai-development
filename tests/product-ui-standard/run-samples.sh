#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
STANDARD="${ROOT_DIR}/docs/product-ui-standard.md"
DESIGN_TEMPLATE="${ROOT_DIR}/templates/app/docs/design.md"
README="${ROOT_DIR}/README.md"
AGENTS="${ROOT_DIR}/AGENTS.md"
CI_WORKFLOW="${ROOT_DIR}/.github/workflows/ci.yml"

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

assert_rule_contract() {
  local heading="$1"
  local rule_id="$2"
  local section
  section="$(awk -v heading="### ${heading}" '
    $0 == heading { found=1; next }
    found && /^### / { exit }
    found { print }
  ' "$STANDARD")"
  if [[ -z "$section" ]]; then
    printf 'missing PRODUCT UI rule section: %s\n' "$heading" >&2
    exit 1
  fi
  for needle in \
    "- Rule ID: \`${rule_id}\`" \
    '- Condition:' \
    '- Decision:' \
    '- Candidate pattern/component:' \
    '- Verification:' \
    '- Fallback:'; do
    if ! grep -Fq -- "$needle" <<< "$section"; then
      printf 'missing PRODUCT UI rule field: %s in %s\n' "$needle" "$heading" >&2
      exit 1
    fi
  done
  local previous=0
  for needle in \
    "- Rule ID: \`${rule_id}\`" \
    '- Condition:' \
    '- Decision:' \
    '- Candidate pattern/component:' \
    '- Verification:' \
    '- Fallback:'; do
    local line
    line="$(grep -nF -- "$needle" <<< "$section" | head -n 1 | cut -d: -f1)"
    if [[ -z "$line" || "$line" -le "$previous" ]]; then
      printf 'invalid PRODUCT UI rule field order: %s in %s\n' "$needle" "$heading" >&2
      exit 1
    fi
    previous="$line"
  done
  if ! grep -Eq -- '^- Fallback:.*NEEDS_DECISION' <<< "$section"; then
    printf 'missing PRODUCT UI rule fallback decision in Fallback field: %s\n' "$heading" >&2
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
assert_order "$AGENTS" '1. Framework Decision結果と正本文書（Frameworkを再選定しない）' '2. UI Level Decisionと適用対象'
assert_order "$AGENTS" '2. UI Level Decisionと適用対象' '3. Nine PRODUCT UI Standard / `Component Decision Rules`'
assert_order "$AGENTS" '3. Nine PRODUCT UI Standard / `Component Decision Rules`' '4. 案件 `docs/design.md`'
assert_order "$AGENTS" '4. 案件 `docs/design.md`' '5. component / library固有docs（存在する場合）'

assert_exact_heading "$STANDARD" '## Component Decision Rules'
assert_exact_heading "$STANDARD" '### Rule Record Contract'
assert_order "$STANDARD" '## Component Decision Rules' '## 10. Visual Review / UI Acceptance'
assert_order "$STANDARD" '### State Mapping' '### Responsive Priority'
assert_order "$STANDARD" '### State Mapping' 'Event -> Current State -> Transition -> Resulting State'
for rule in \
  'Primary Action|PRIMARY_ACTION' \
  'Selection Pattern|SELECTION_PATTERN' \
  'Destructive Action|DESTRUCTIVE_ACTION' \
  'Async Feedback|ASYNC_FEEDBACK' \
  'Form Validation|FORM_VALIDATION' \
  'State Mapping|STATE_MAPPING' \
  'Responsive Priority|RESPONSIVE_PRIORITY' \
  'Accessibility|ACCESSIBILITY'; do
  IFS='|' read -r heading rule_id <<< "$rule"
  assert_rule_contract "$heading" "$rule_id"
done
state_transition_section="$(awk -v heading='### State Ownership / Transition' '
  $0 == heading { found=1; next }
  found && /^## / { exit }
  found { print }
' "$DESIGN_TEMPLATE")"
if [[ -z "$state_transition_section" ]]; then
  printf 'missing design template state ownership section\n' >&2
  exit 1
fi
for needle in \
  '- State / domain:' \
  '- Owner / source of truth:' \
  '- Allowed events/actions:' \
  '- Allowed transitions:' \
  '- Invalid transition handling:' \
  '- Concurrent / async handling:' \
  '- Verification:'; do
  if ! grep -Fq -- "$needle" <<< "$state_transition_section"; then
    printf 'missing state transition field: %s\n' "$needle" >&2
    exit 1
  fi
done
for needle in \
  'state owner / source of truth' \
  'event/actionと裁定境界' \
  'Event -> Current State -> Transition -> Resulting State' \
  'stale response' \
  'rapid repeated input' \
  'component間で互いの内部状態を直接変更せず' \
  '特定のpattern、ライブラリ、frameworkを標準として強制しない'; do
  assert_contains "$STANDARD" "$needle"
done
for needle in \
  '### Conflict and Scope Boundary' \
  '標準ruleと案件設計が重要UXについて矛盾する、候補componentがない、または判断材料が不足する場合は暗黙PASSせず `NEEDS_DECISION` とする。' \
  'この契約は `NONE` / `UTILITY` にPRODUCT UIの必須条件を過剰適用せず'; do
  assert_contains "$STANDARD" "$needle"
done
assert_exact_heading "$DESIGN_TEMPLATE" '## Component Decision Rules'
design_rules_section="$(awk -v heading='## Component Decision Rules' '
  $0 == heading { found=1; next }
  found && /^## / { exit }
  found { print }
' "$DESIGN_TEMPLATE")"
if [[ -z "$design_rules_section" ]]; then
  printf 'missing design template component decision rules section\n' >&2
  exit 1
fi
project_specific_section="$(awk -v heading='### Project-specific Decision' '
  $0 == heading { found=1; next }
  found && /^### / { exit }
  found { print }
' <<< "$design_rules_section")"
if [[ -z "$project_specific_section" ]]; then
  printf 'missing design template project-specific decision section\n' >&2
  exit 1
fi
for needle in \
  '案件側ではvisual、brand、tokens、採用component、例外を具体化するが、標準のUX原則とAccessibility最低条件を暗黙に弱めない。' \
  '### Project-specific Decision' \
  '- Rule ID:' \
  '- Condition:' \
  '- Decision:' \
  '- Candidate pattern/component:' \
  '- Verification:' \
  '- Fallback: 重要な判断を確定できない場合は `NEEDS_DECISION` として停止する。'; do
  if ! grep -Fq -- "$needle" <<< "$design_rules_section"; then
    printf 'missing design template decision rule contract: %s\n' "$needle" >&2
    exit 1
  fi
done
for needle in \
  '- Selected rule / Rule ID:' \
  '- Project context:' \
  '- Adopted pattern/component:' \
  '- Reason and evidence:' \
  '- Exception or conflict:' \
  '- Design Decision / Issue reference:'; do
  if ! grep -Fq -- "$needle" <<< "$project_specific_section"; then
    printf 'missing design template decision rule contract: %s\n' "$needle" >&2
    exit 1
  fi
done
assert_contains "$CI_WORKFLOW" 'bash tests/product-ui-standard/run-samples.sh'
assert_contains "$CI_WORKFLOW" 'bash tests/issue-template-ui/run-samples.sh'

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
  '### State Ownership / Transition' \
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
