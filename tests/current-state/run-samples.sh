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
require_marker "$DOC" "schema_version: 2"
require_marker "$DOC" "Versioning and migration"
require_marker "$DOC" "execution:"
require_marker "$DOC" "acceptance:"
require_marker "$DOC" "result: NOT_RUN"
require_marker "$DOC" 'acceptance.result'
require_marker "$DOC" 'acceptance.conditions'
require_marker "$DOC" 'acceptance.due_at'
require_marker "$DOC" 'acceptance.follow_up_issue'
require_marker "$DOC" 'acceptance.blockers'
require_marker "$DOC" 'ACCEPTED'
require_marker "$DOC" 'NOT_ACCEPTED'
require_marker "$DOC" 'CONDITIONAL'
require_marker "$DOC" 'ACCEPTANCE_CONDITION_UNRESOLVED'
require_marker "$DOC" "pr:"
require_marker "$DOC" "verification:"
require_marker "$DOC" "review:"
require_marker "$DOC" "updated_at:"
require_marker "$DOC" "security_exception: NOT_APPLICABLE"
require_marker "$DOC" "approval.security_exception"
require_marker "$DOC" "evidence:"
require_marker "$DOC" "evidence.issue_url"
require_marker "$DOC" "人間の明示判断後だけ"
require_marker "$DOC" "security=FAILED"
require_marker "$DOC" '`UNAVAILABLE`かつ`approval.security_exception=APPROVED`でもない'
require_marker "$DOC" "stop_reason=SECURITY_FAILED"
require_marker "$DOC" "PLAN_READY"
require_marker "$DOC" "READY_FOR_HUMAN_MERGE"
require_marker "$DOC" "COMPLETED"
require_marker "$DOC" "COMPLETE"
require_marker "$DOC" "ACCEPTANCE_NOT_ACCEPTED"
require_marker "$DOC" 'issue.acceptance_status=SATISFIED'
require_marker "$DOC" "DESIGN_DECISION"
require_marker "$DOC" "SHA_MISMATCH"
require_marker "$DOC" "FIX_BLOCKING"
require_marker "$DOC" 'P2分類（`BLOCKING` / `IN-SCOPE FIX` / `FOLLOW-UP` / `DISMISS`）'
require_marker "$DOC" "merge_allowed"
require_marker "$DOC" "最新観測を確認してStateを更新"
require_marker "$DOC" "旧SHAに紐付くlocal / CI / security / review"
require_marker "$DOC" "chain-of-thoughtや推論全文、全会話ログはCurrent Stateへ保存しない"

if ! grep -Fq -- 'READY_FOR_HUMAN_MERGE' "$DOC" || ! grep -Fq -- 'issue.acceptance_status=SATISFIED' "$DOC"; then
  printf 'READY_FOR_HUMAN_MERGE must require SATISFIED acceptance status\n' >&2
  exit 1
fi

if ! grep -Fq -- 'ACCEPTED' "$DOC" || ! grep -Fq -- 'CONDITIONAL' "$DOC" || ! grep -Fq -- 'next_action=COMPLETE' "$DOC"; then
  printf 'completed Acceptance must have a result and terminal action\n' >&2
  exit 1
fi

if ! grep -Fq -- 'issue.acceptance_status=SATISFIED' "$DOC" || ! grep -Fq -- 'conditions`が1件以上' "$DOC" || ! grep -Fq -- 'due_at`と`follow_up_issue`が設定済み' "$DOC" || ! grep -Fq -- 'blockers`が空' "$DOC"; then
  printf 'Conditional completion must require conditions, deadline, follow-up, and no blockers\\n' >&2
  exit 1
fi

if grep -Fq -- 'schema_version: 1' "$DOC"; then
  printf 'Current State schema must be version 2 after adding acceptance fields\\n' >&2
  exit 1
fi

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
require_marker "$CHILD_TEMPLATE" "Issue acceptance status:"
require_marker "$CHILD_TEMPLATE" "Product Acceptance result:"
require_marker "$PR_TEMPLATE" "# Current State"
require_marker "$PR_TEMPLATE" "Issue acceptance status:"
require_marker "$PR_TEMPLATE" "Product Acceptance result:"
require_marker "$INVENTORY" "| S-04 | Structured Current State契約 | S | STRENGTHEN |"

printf 'Structured Current State contract: PASS\n'
