#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DOC="${ROOT}/docs/ai-execution-state.md"
SKILL="${ROOT}/.agents/skills/pr-review-fix/SKILL.md"
AGENTS="${ROOT}/AGENTS.md"
FLOW="${ROOT}/docs/nine-standard-ai-development-flow.md"
CHILD_TEMPLATE="${ROOT}/.github/ISSUE_TEMPLATE/child-issue.md"
PR_TEMPLATE="${ROOT}/.github/pull_request_template.md"
INVENTORY="${ROOT}/docs/ai-development-harness-inventory.md"

require_marker() {
  local file="$1"
  local marker="$2"
  grep -Fq -- "$marker" "$file" || {
    printf 'missing marker: %s: %s\n' "$file" "$marker" >&2
    exit 1
  }
}

require_marker "$DOC" "# Structured Current State"
require_marker "$DOC" "schema_version: 1"
require_marker "$DOC" "execution:"
require_marker "$DOC" "pr:"
require_marker "$DOC" "verification:"
require_marker "$DOC" "review:"
require_marker "$DOC" "updated_at:"
require_marker "$DOC" "PLAN_READY"
require_marker "$DOC" "READY_FOR_HUMAN_MERGE"
require_marker "$DOC" "DESIGN_DECISION"
require_marker "$DOC" "SHA_MISMATCH"
require_marker "$DOC" "FIX_BLOCKING"
require_marker "$DOC" 'P2分類（`BLOCKING` / `IN-SCOPE FIX` / `FOLLOW-UP` / `DISMISS`）'
require_marker "$DOC" "merge_allowed"
require_marker "$DOC" "最新観測を確認してStateを更新"
require_marker "$DOC" "旧SHAに紐付くlocal / CI / security / review"
require_marker "$DOC" "chain-of-thought、推論全文、全会話ログ、秘密情報はCurrent Stateへ保存しない"

if grep -Eq '^[[:space:]]*merge_allowed:' "$DOC"; then
  printf 'merge_allowed must not be persisted as a State field\n' >&2
  exit 1
fi

yaml_block="$(sed -n '/^```yaml$/,/^```$/p' "$DOC")"
if grep -Fq -- "chain-of-thought" <<< "$yaml_block"; then
  printf 'Current State YAML must not contain chain-of-thought\n' >&2
  exit 1
fi

require_marker "$SKILL" "## Structured Current State"
require_marker "$SKILL" "head SHAが変わったら旧結果を再利用せず"
require_marker "$SKILL" "merge_allowed"
require_marker "$AGENTS" "## Structured Current State"
require_marker "$FLOW" "### 4.3 Structured Current State"
require_marker "$CHILD_TEMPLATE" "# Current State"
require_marker "$PR_TEMPLATE" "# Current State"
require_marker "$INVENTORY" "| S-04 | Structured Current State契約 | S | STRENGTHEN |"

printf 'Structured Current State contract: PASS\n'
