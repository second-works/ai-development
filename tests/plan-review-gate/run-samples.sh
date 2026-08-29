#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
doc="$repo_root/docs/plan-review-gate.md"
flow="$repo_root/docs/nine-standard-ai-development-flow.md"
guide="$repo_root/docs/template-guide.md"
agents="$repo_root/AGENTS.md"
parent="$repo_root/.github/ISSUE_TEMPLATE/parent-issue.md"
readme="$repo_root/README.md"

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    printf 'missing plan review contract: %s in %s\n' "$needle" "$file" >&2
    exit 1
  fi
}

for needle in \
  'Plan Review Gate' \
  'PASS' \
  'NEEDS_DECISION' \
  'NOT_APPLICABLE' \
  '親Issue / 子Issue化および実装開始へ進まない' \
  'Design Decision' \
  'Design Decision Escalation' \
  'deployment-release-design.md' \
  'acceptance-verification.md' \
  'Issue #30' \
  '一問一答形式を固定しない'; do
  assert_contains "$doc" "$needle"
done

assert_contains "$flow" 'Plan Review Gate（Grilling）'
assert_contains "$guide" 'Plan Review Gate（Grilling）'
assert_contains "$agents" 'docs/plan-review-gate.md'
assert_contains "$parent" '# Plan Review Gate'
assert_contains "$parent" '判定: `PASS / NEEDS_DECISION / NOT_APPLICABLE`'
assert_contains "$readme" 'docs/plan-review-gate.md'

plan_line="$(grep -nF '## 2.1 Plan Review Gate（計画書Grilling）' "$flow" | cut -d: -f1)"
parent_line="$(grep -nF '## 3. 親Issue' "$flow" | cut -d: -f1)"
[[ -n "$plan_line" && -n "$parent_line" && "$plan_line" -lt "$parent_line" ]] || {
  printf 'Plan Review Gate must precede parent Issue conversion\n' >&2
  exit 1
}

printf 'plan review gate documentation contract: ok\n'
