#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
doc="$repo_root/docs/deployment-release-design.md"
parent="$repo_root/.github/ISSUE_TEMPLATE/parent-issue.md"
flow="$repo_root/docs/nine-standard-ai-development-flow.md"
guide="$repo_root/docs/template-guide.md"

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    printf 'missing contract: %s in %s\n' "$needle" "$file" >&2
    exit 1
  fi
}

assert_contains "$doc" "GitHub上の実装完了と、本番投入可能な状態を分けて"
assert_contains "$doc" "Production runtime"
assert_contains "$doc" "Persistent data"
assert_contains "$doc" "Deployment method"
assert_contains "$doc" "Backup / migration"
assert_contains "$doc" "Post-deploy Health Check"
assert_contains "$doc" "Monitoring / Rollback"
assert_contains "$doc" "GitHub Environments"
assert_contains "$doc" "macOS固有アプリ"
assert_contains "$doc" "一律に強制しない"
assert_contains "$parent" "## デプロイ設計 / Release・Production計画"
assert_contains "$flow" "docs/deployment-release-design.md"
assert_contains "$guide" "docs/deployment-release-design.md"

if grep -Eiq 'ghp_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}' "$doc" "$parent" "$flow" "$guide"; then
  printf 'possible secret-like value found in deployment documentation\n' >&2
  exit 1
fi

printf 'deployment design documentation contract: ok\n'
