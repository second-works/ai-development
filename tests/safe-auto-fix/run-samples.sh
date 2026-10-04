#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
doc="$repo_root/docs/safe-auto-fix-auto-merge.md"
agents="$repo_root/AGENTS.md"
flow="$repo_root/docs/nine-standard-ai-development-flow.md"
guide="$repo_root/docs/template-guide.md"
pr="$repo_root/.github/pull_request_template.md"

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    printf 'missing safe auto-fix contract: %s in %s\n' "$needle" "$file" >&2
    exit 1
  fi
}

assert_contains "$doc" 'IN-SCOPE FIX'
assert_contains "$doc" 'BLOCKING'
assert_contains "$doc" '公開API、既存インターフェース、データ契約を変更しない'
assert_contains "$doc" 'DB schema、migration、永続データ形式を変更しない'
assert_contains "$doc" '認証、認可、権限、アクセス制御を変更しない'
assert_contains "$doc" 'secrets、credential、Security policy、監査設定を変更しない'
assert_contains "$doc" 'テスト削除、skip、品質ゲート緩和'
assert_contains "$doc" '自動修正後に標準検証、CI、利用可能なSecurity、Codex再Review'
assert_contains "$doc" 'SECURITY_STATUS=SECURITY_PASSED'
assert_contains "$doc" 'SECURITY_STATUS=SECURITY_FAILED'
assert_contains "$doc" 'SECURITY_STATUS=SECURITY_UNAVAILABLE'
assert_contains "$doc" 'SECURITY_STATUS=SECURITY_NOT_APPLICABLE'
assert_contains "$doc" 'templates/security/security-preflight.sh'
assert_contains "$doc" '自動修正コミットSHA、全検証対象SHA、PR head SHAが一致する'
assert_contains "$doc" '原則1ラウンドだけ実行する'
assert_contains "$doc" '追加AUTO-FIXへ戻らず、分類・記録後もAuto-Mergeせず通常レーンへ戻す'
assert_contains "$doc" '自動修正後の再レビューで新しいP2が1件でも発生した場合は、追加AUTO-FIXへ戻らず、分類・記録後もAuto-Mergeせず通常レーンへ戻す'
assert_contains "$doc" 'AI / automationによるAuto-Merge'

assert_contains "$agents" 'docs/safe-auto-fix-auto-merge.md の全Safety Gate'
assert_contains "$agents" '新規採用は別承認'
assert_contains "$flow" 'Safe Auto-Fix / Auto-Merge'
assert_contains "$guide" 'safe-auto-fix-auto-merge.md'
assert_contains "$pr" 'Safe Auto-Fix / Auto-Merge'

gate_line="$(grep -nF '次のすべてを満たさない限りAuto-Mergeしない。' "$doc" | cut -d: -f1)"
security_line="$(grep -nF '利用可能なSecurity / Code Scanning' "$doc" | cut -d: -f1)"
review_line="$(grep -nF 'Codex Code Review再実行' "$doc" | cut -d: -f1)"
sha_line="$(grep -nF 'Auto-Merge直前のPR head SHA再確認' "$doc" | cut -d: -f1)"
[[ -n "$gate_line" && -n "$security_line" && -n "$review_line" && -n "$sha_line" ]] || {
  printf 'safe auto-fix gate anchors are missing\n' >&2
  exit 1
}
(( security_line < review_line && review_line < sha_line )) || {
  printf 'security, review, and final SHA verification order is invalid\n' >&2
  exit 1
}

printf 'safe auto-fix and auto-merge documentation contract: ok\n'
