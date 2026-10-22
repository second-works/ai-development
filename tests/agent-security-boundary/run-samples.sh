#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
failures=0

require_marker() {
  local file="$1"
  local marker="$2"
  if ! grep -Fq -- "$marker" "$ROOT/$file"; then
    printf 'missing marker: %s: %s\n' "$file" "$marker" >&2
    failures=1
  fi
}

require_marker "docs/ai-agent-security-boundary.md" "PUBLIC"
require_marker "docs/ai-agent-security-boundary.md" "INTERNAL"
require_marker "docs/ai-agent-security-boundary.md" "CONFIDENTIAL"
require_marker "docs/ai-agent-security-boundary.md" "MANAGED"
require_marker "docs/ai-agent-security-boundary.md" "UNMANAGED"
require_marker "docs/ai-agent-security-boundary.md" "Intake / Read"
require_marker "docs/ai-agent-security-boundary.md" "Exposure / Write"
require_marker "docs/ai-agent-security-boundary.md" "Sensitive Read Capability × External Write Capability"
require_marker "docs/ai-agent-security-boundary.md" "Least Privilege"
require_marker "docs/ai-agent-security-boundary.md" "Human Approval Boundary"
require_marker "docs/ai-agent-security-boundary.md" "Prompt Injection"
require_marker "docs/ai-agent-security-boundary.md" "Tool allowlist"
require_marker "docs/ai-agent-security-boundary.md" "Destination allowlist"
require_marker "docs/ai-agent-security-boundary.md" "git pushによるremote Repositoryへの書き込み"
require_marker "docs/ai-agent-security-boundary.md" "PUBLICだけを読むRead能力"
require_marker "docs/ai-agent-security-boundary.md" "INTERNALまたはCONFIDENTIALを読むRead能力"
require_marker "docs/ai-agent-security-boundary.md" "理由、残るリスク、代替制御、承認者"
require_marker "docs/ai-agent-security-boundary.md" "git pushによるremote Repositoryへの書き込み"
require_marker "docs/ai-agent-security-boundary.md" "適用可否"

require_marker "docs/ai-agent-security-boundary.md" "Human Approval Boundary"
require_marker "docs/ai-agent-security-boundary.md" "Sensitive Read Capability × External Write Capability"
# The PR and Issue templates and AGENTS.md are now the lightweight ones (#197). Their
# safety wording is checked in tests/lightweight-template.

require_marker "docs/github-repository-security-baseline.md" "ai-agent-security-boundary.md"
# 未保護・取得不能を成功扱いせず、設定承認と実mainの安全境界を維持する。
for marker in 'protected=false' '明示的なプラン制約と権限不足を区別' '取得不能' '期限' '追跡Issue' '期限切れ' '文書PRのmergeと保護有効化は別状態'; do
  require_marker "docs/github-repository-security-baseline.md" "$marker"
done
for marker in '人間の設定承認' 'verification' 'Security Preflight' 'github-actions' 'Do not allow bypassing the above settings' '実mainへの直接push・force push・削除で試さない'; do
  require_marker "templates/github-security/ruleset-guide.md" "$marker"
done
require_marker "docs/safe-auto-fix-auto-merge.md" "AI Agent Security Boundary"
require_marker "docs/safe-auto-fix-auto-merge.md" "Sensitive Read Capability × External Write Capability"
require_marker "SECURITY.md" "ai-agent-security-boundary.md"
require_marker "docs/template-guide.md" "AI Agent Security Boundary"
require_marker "docs/template-guide.md" "適用可否"

require_section_marker() {
  local file="$1"
  local start="$2"
  local end="$3"
  local marker="$4"
  local section
  section="$(sed -n "/^$start/,/^$end/p" "$ROOT/$file")"
  if ! grep -Fq -- "$marker" <<< "$section"; then
    printf 'missing section marker: %s (%s to %s): %s\n' "$file" "$start" "$end" "$marker" >&2
    failures=1
  fi
}
require_section_marker "docs/template-guide.md" "## 2. 新規プロジェクト開始時の使い方" "## 3. AGENTS.md" "docs/ai-agent-security-boundary.md"
require_section_marker "docs/template-guide.md" "## 15. 新規リポジトリ初期化チェックリスト" "## 16. 普段の短縮指示" "docs/ai-agent-security-boundary.md"
require_marker "docs/nine-standard-ai-development-flow.md" "AI Agent Security Boundary"

if (( failures != 0 )); then
  exit 1
fi

echo "Agent Security Boundary documentation contract: PASS"
