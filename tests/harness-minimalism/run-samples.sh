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

extract_field_value() {
  local section="$1"
  local prefix="$2"
  awk -v prefix="$prefix" '
    {
      line=$0
      sub(/^[[:space:]]+/, "", line)
      if (index(line, prefix) == 1) {
        value=substr(line, length(prefix) + 1)
        sub(/[[:space:]]+$/, "", value)
        print value
        exit
      }
    }
  ' <<< "$section"
}

count_field_occurrences() {
  local section="$1"
  local prefix="$2"
  awk -v prefix="$prefix" '
    {
      line=$0
      sub(/^[[:space:]]+/, "", line)
      if (index(line, prefix) == 1) {
        count++
      }
    }
    END { print count + 0 }
  ' <<< "$section"
}

extract_ledger_section() {
  local id="$1"
  awk -v id="$id" '
    function normalize_atx(line) {
      if (line ~ /^(### | ### |  ### |   ### |## | ## |  ## |   ## )/) {
        sub(/^ */, "", line)
        return line
      }
      return ""
    }
    {
      line=normalize_atx($0)
      if (index(line, "### " id " ") == 1) { found=1; next }
      if (found && line ~ /^### /) { exit }
      if (found && line ~ /^## /) { exit }
      if (found) { print }
    }
  ' "$ROOT/docs/ai-development-harness-inventory.md"
}

require_ledger_fields() {
  local id="$1"
  local section
  local marker
  local field_value
  local normalized_value
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

  section="$(extract_ledger_section "$id")"

  if [[ -z "$section" ]]; then
    printf 'missing ledger section: %s\n' "$id" >&2
    failures=1
    return
  fi

  for marker in "${markers[@]}"; do
    field_prefix="- **${marker}**："
    field_count="$(count_field_occurrences "$section" "$field_prefix")"
    if [[ "$field_count" -ne 1 ]]; then
      printf 'ledger field must appear exactly once: %s: %s (found %s)\n' "$id" "$marker" "$field_count" >&2
      failures=1
      continue
    fi

    field_value="$(extract_field_value "$section" "$field_prefix")"
    if [[ -z "$field_value" ]] || ! grep -q '[^[:space:]]' <<< "$field_value"; then
      printf 'missing or empty ledger field: %s: %s\n' "$id" "$marker" >&2
      failures=1
      continue
    fi

    case "$marker" in
      "ETCSLV分類")
        case "$field_value" in
          Execution|Tools|Context|State|"Lifecycle Hooks"|Verification) ;;
          *)
            printf 'invalid ETCSLV classification: %s: %s\n' "$id" "$field_value" >&2
            failures=1
            ;;
        esac
        ;;
      "判定")
        normalized_value="${field_value%。}"
        case "$normalized_value" in
          KEEP|STRENGTHEN|SIMPLIFY|REMOVE_CANDIDATE) ;;
          *)
            printf 'invalid ledger judgment: %s: %s\n' "$id" "$field_value" >&2
            failures=1
            ;;
        esac
        ;;
    esac
  done

  field_value="$(extract_field_value "$section" "- **関連Issue / 正本文書**：")"
  if ! grep -Eq '#[0-9]+' <<< "$field_value"; then
    printf 'missing ledger Issue reference: %s: #<number>\n' "$id" >&2
    failures=1
  fi
}

require_marker "docs/ai-development-harness-inventory.md" "## Harness Minimalism"
require_marker "docs/ai-development-harness-inventory.md" "ETCSLV"
require_marker "docs/ai-development-harness-inventory.md" "schema v3に従ったphase"
require_marker "docs/ai-development-harness-inventory.md" "Acceptance対象artifact"
require_marker "docs/ai-development-harness-inventory.md" "現行Deploy target"
ledger_headings=()
while IFS= read -r heading; do
  ledger_headings+=("$heading")
done < <(awk '
  function normalize_atx(line) {
    if (line ~ /^(### | ### |  ### |   ### |## | ## |  ## |   ## )/) {
      sub(/^ */, "", line)
      return line
    }
    return ""
  }
  {
    line=normalize_atx($0)
    if (line == "## 台帳") { in_ledger=1; next }
    if (in_ledger && line ~ /^## /) { exit }
    if (in_ledger && line ~ /^### /) { print substr(line, 5) }
  }
' "$ROOT/docs/ai-development-harness-inventory.md")

if (( ${#ledger_headings[@]} == 0 )); then
  printf 'no ledger records found\n' >&2
  failures=1
else
  ledger_ids=()
  for heading in "${ledger_headings[@]}"; do
    id="${heading%% *}"
    name="${heading#* }"
    name="${name#"${name%%[![:space:]]*}"}"
    name="${name%"${name##*[![:space:]]}"}"
    if [[ -z "$heading" || "$heading" == "$id" || -z "$id" || -z "$name" ]]; then
      printf 'ledger heading must include an ID and name: ### %s\n' "$heading" >&2
      failures=1
      continue
    fi
    if [[ ! "$id" =~ ^[A-Z]+-[0-9]+[a-z]*$ ]]; then
      printf 'invalid ledger ID: %s\n' "$id" >&2
      failures=1
    fi
    ledger_ids+=("$id")
  done

  duplicate_ids="$(printf '%s\n' "${ledger_ids[@]}" | sort | uniq -d)"
  if [[ -n "$duplicate_ids" ]]; then
    printf 'duplicate ledger IDs: %s\n' "$duplicate_ids" >&2
    failures=1
  fi

  for id in "${ledger_ids[@]}"; do
    require_ledger_fields "$id"
  done
fi

summary_rows=()
while IFS=$'\t' read -r summary_id summary_class summary_judgment; do
  summary_rows+=("$summary_id"$'\t'"$summary_class"$'\t'"$summary_judgment")
done < <(awk -F'|' '
  function trim(value) {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
    return value
  }
  /^## 主要ハーネスの判定$/ { in_summary=1; next }
  in_summary && /^## / { exit }
  in_summary && /^\|/ {
    id=trim($2)
    classification=trim($4)
    judgment=trim($5)
    if (id != "" && id != "ID" && id !~ /^-+$/) {
      print id "\t" classification "\t" judgment
    }
  }
' "$ROOT/docs/ai-development-harness-inventory.md")

if (( ${#summary_rows[@]} == 0 )); then
  printf 'no summary table records found\n' >&2
  failures=1
else
  summary_ids=()
  for row in "${summary_rows[@]}"; do
    IFS=$'\t' read -r summary_id summary_class summary_judgment <<< "$row"
    summary_ids+=("$summary_id")
    detail_section="$(extract_ledger_section "$summary_id")"
    detail_class="$(extract_field_value "$detail_section" "- **ETCSLV分類**：")"
    detail_judgment="$(extract_field_value "$detail_section" "- **判定**：")"

    case "$summary_class" in
      E) expected_class="Execution" ;;
      T) expected_class="Tools" ;;
      C) expected_class="Context" ;;
      S) expected_class="State" ;;
      L) expected_class="Lifecycle Hooks" ;;
      V) expected_class="Verification" ;;
      *) expected_class="$summary_class" ;;
    esac
    normalized_detail_judgment="${detail_judgment%。}"
    normalized_summary_judgment="${summary_judgment%。}"

    if [[ -z "$detail_section" || "$detail_class" != "$expected_class" || "$normalized_detail_judgment" != "$normalized_summary_judgment" ]]; then
      printf 'summary/detail mismatch: %s: summary=%s/%s detail=%s/%s\n' "$summary_id" "$summary_class" "$summary_judgment" "$detail_class" "$detail_judgment" >&2
      failures=1
    fi
  done

  duplicate_summary_ids="$(printf '%s\n' "${summary_ids[@]}" | sort | uniq -d)"
  if [[ -n "$duplicate_summary_ids" ]]; then
    printf 'duplicate summary IDs: %s\n' "$duplicate_summary_ids" >&2
    failures=1
  fi

  summary_set="$(printf '%s\n' "${summary_ids[@]}" | sed '/^$/d' | sort -u)"
  ledger_set="$(printf '%s\n' "${ledger_ids[@]}" | sed '/^$/d' | sort -u)"
  if [[ "$summary_set" != "$ledger_set" ]]; then
    printf 'summary/detail ID sets differ\nsummary:\n%s\ndetail:\n%s\n' "$summary_set" "$ledger_set" >&2
    failures=1
  fi
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

bash "$ROOT/tests/current-state/run-samples.sh" "$ROOT"
bash "$ROOT/tests/adaptive-development-flow/run-samples.sh" "$ROOT"

if (( failures != 0 )); then
  exit 1
fi

echo "Harness Minimalism documentation contract: PASS"
