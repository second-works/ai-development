#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
DOC="${ROOT_DIR}/docs/acceptance-verification.md"
FLOW="${ROOT_DIR}/docs/nine-standard-ai-development-flow.md"
INVENTORY="${ROOT_DIR}/docs/ai-development-harness-inventory.md"

assert_contains() {
  local file="$1"
  local marker="$2"
  grep -Fq -- "$marker" "$file" || {
    printf 'missing verification evidence marker in %s: %s\n' "$file" "$marker" >&2
    exit 1
  }
}

for marker in \
  'Verification Evidence Contract' \
  'Requirement / acceptance condition' \
  'Risk being checked' \
  'Test / verification method' \
  'VERIFIED' \
  'FAILED' \
  'NOT_VERIFIED' \
  'BLOCKED' \
  'SKIPPED' \
  'テストコマンドの実行成功はEvidenceの一部にすぎず' \
  '未実行のまま成功した工程として' \
  'Residual Risk Summary' \
  'Known Remaining Risk' \
  'Human Decision Required' \
  'Quality Rule Promotion' \
  'human decision'; do
  assert_contains "$DOC" "$marker"
done

# The PR template and AGENTS.md are now the lightweight ones (#197). Their safety
# wording is checked in tests/lightweight-template.

assert_contains "$FLOW" 'Requirement → Risk → Test → Result → Evidence'
assert_contains "$FLOW" 'Verification Evidence Contract / Residual Risk Summary'
assert_contains "${ROOT_DIR}/docs/code-review-contract.md" 'Review Evidence Contractはレビュー指摘の成立条件とPR因果を記録する契約'
assert_contains "${ROOT_DIR}/docs/code-review-contract.md" 'Verification Evidence Contract / Residual Risk Summary'
assert_contains "$INVENTORY" 'テスト実行をRequirement検証と混同すること'
assert_contains "$INVENTORY" 'Residual Risk Summary'
assert_contains "$INVENTORY" '#119'

doc_line="$(grep -nF '## 5. Verification Evidence Contract / Residual Risk Summary' "$DOC" | cut -d: -f1)"
record_line="$(grep -nF '## 6. 検収記録' "$DOC" | cut -d: -f1)"
[[ -n "$doc_line" && -n "$record_line" && "$doc_line" -lt "$record_line" ]] || {
  printf 'verification evidence contract must precede the acceptance record\n' >&2
  exit 1
}

printf 'verification evidence contract: PASS\n'
