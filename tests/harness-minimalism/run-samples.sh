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

require_ledger_fields() {
  local id="$1"
  local section
  local marker
  local markers=(
    "ETCSLV分類"
    "解決する失敗モード"
    "発火条件"
    "入力 / Context"
    "出力 / State変更"
    "決定論的判定可能か"
    "実行コスト / 運用負荷"
    "重複する仕組み"
    "安全上必須か"
    "判定"
    "削除・再評価条件"
    "関連Issue / 正本文書"
  )

  section="$(awk -v id="$id" '
    index($0, "### " id " ") == 1 { found=1; next }
    found && /^### / { exit }
    found && /^## / { exit }
    found { print }
  ' "$ROOT/docs/ai-development-harness-inventory.md")"

  if [[ -z "$section" ]]; then
    printf 'missing ledger section: %s\\n' "$id" >&2
    failures=1
    return
  fi

  for marker in "${markers[@]}"; do
    local prefix="- **${marker}**："
    local field_line
    local field_value
    field_line="$(grep -F -- "$prefix" <<< "$section" | head -n 1 || true)"
    field_value="${field_line#"$prefix"}"
    if [[ -z "$field_line" ]] || ! grep -q '[^[:space:]]' <<< "$field_value"; then
      printf 'missing or empty ledger field: %s: %s\\n' "$id" "$marker" >&2
      failures=1
    fi
  done

  if ! grep -F -- "- **関連Issue / 正本文書**：" <<< "$section" | grep -Eq "#[0-9]+"; then
    printf 'missing ledger Issue reference: %s: #<number>\\n' "$id" >&2
    failures=1
  fi
}

require_marker "docs/ai-development-harness-inventory.md" "## Harness Minimalism"
require_marker "docs/ai-development-harness-inventory.md" "ETCSLV"
ledger_ids=()
while IFS= read -r id; do
  [[ -n "$id" ]] && ledger_ids+=("$id")
done < <(awk '
  /^## 台帳$/ { in_ledger=1; next }
  in_ledger && /^## / { exit }
  in_ledger && /^### [^ ]+ / { print $2 }
' "$ROOT/docs/ai-development-harness-inventory.md")

if (( ${#ledger_ids[@]} == 0 )); then
  printf 'no ledger records found\\n' >&2
  failures=1
else
  duplicate_ids="$(printf '%s\n' "${ledger_ids[@]}" | sort | uniq -d)"
  if [[ -n "$duplicate_ids" ]]; then
    printf 'duplicate ledger IDs: %s\\n' "$duplicate_ids" >&2
    failures=1
  fi

  for id in "${ledger_ids[@]}"; do
    require_ledger_fields "$id"
  done
fi
require_marker "docs/ai-development-harness-inventory.md" "解決する失敗モード"
require_marker "docs/ai-development-harness-inventory.md" "発火条件"
require_marker "docs/ai-development-harness-inventory.md" "入力 / Context"
require_marker "docs/ai-development-harness-inventory.md" "出力 / State変更"
require_marker "docs/ai-development-harness-inventory.md" "決定論的判定可能か"
require_marker "docs/ai-development-harness-inventory.md" "実行コスト / 運用負荷"
require_marker "docs/ai-development-harness-inventory.md" "重複する仕組み"
if grep -Fq -- "上記の実行コスト / 運用負荷欄に記載した比較対象" "$ROOT/docs/ai-development-harness-inventory.md"; then
  printf 'generic overlap record remains\n' >&2
  failures=1
fi
require_marker "docs/ai-development-harness-inventory.md" "安全上必須か"
require_marker "docs/ai-development-harness-inventory.md" "KEEP / STRENGTHEN / SIMPLIFY / REMOVE_CANDIDATE"
require_marker "docs/ai-development-harness-inventory.md" "削除・再評価条件"
require_marker "docs/ai-development-harness-inventory.md" "## 削除候補と簡素化候補"
require_marker "docs/ai-development-harness-inventory.md" "## モデル更新時の再評価"
require_marker "docs/ai-development-harness-inventory.md" "Security Boundary"
require_marker "docs/ai-development-harness-inventory.md" "Human Approval Boundary"

require_marker "AGENTS.md" "docs/ai-development-harness-inventory.md"
require_marker "AGENTS.md" "失敗モードを示せない新規ハーネス"
require_marker "AGENTS.md" "削除・再評価条件"

require_section_marker "docs/template-guide.md" "## 2. 新規プロジェクト開始時の使い方" "## 3. AGENTS.md" "docs/ai-development-harness-inventory.md"
require_section_marker "docs/template-guide.md" "## 15. 新規リポジトリ初期化チェックリスト" "## 16. 普段の短縮指示" "docs/ai-development-harness-inventory.md"
require_marker "docs/template-guide.md" "## 12.2 Harness MinimalismとETCSLV台帳"
require_marker "docs/nine-standard-ai-development-flow.md" "## 4.2 Harness Minimalism確認"

require_marker ".github/ISSUE_TEMPLATE/parent-issue.md" "# Harness Minimalism / ETCSLV"
require_marker ".github/ISSUE_TEMPLATE/parent-issue.md" "解決する失敗モード:"
require_marker ".github/ISSUE_TEMPLATE/parent-issue.md" "削除・再評価条件:"
require_marker ".github/ISSUE_TEMPLATE/child-issue.md" "# Harness Minimalism / ETCSLV"
require_marker ".github/ISSUE_TEMPLATE/child-issue.md" "判定（KEEP / STRENGTHEN / SIMPLIFY / REMOVE_CANDIDATE）:"
require_marker ".github/pull_request_template.md" "# Harness Minimalism / ETCSLV"
require_marker ".github/pull_request_template.md" "対象ハーネス / 台帳ID:"
require_marker ".github/pull_request_template.md" "削除・再評価条件:"

if (( failures != 0 )); then
  exit 1
fi

echo "Harness Minimalism documentation contract: PASS"
