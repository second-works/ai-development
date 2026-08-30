#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
doc="$repo_root/docs/deployment-release-design.md"
parent="$repo_root/.github/ISSUE_TEMPLATE/parent-issue.md"
flow="$repo_root/docs/nine-standard-ai-development-flow.md"
guide="$repo_root/docs/template-guide.md"
preflight="$repo_root/templates/security/security-preflight.sh"

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
assert_contains "$doc" "Release Candidate / artifact identity"
assert_contains "$doc" "image digest"
assert_contains "$doc" "Backup / migration"
assert_contains "$doc" "Post-deploy Health Check"
assert_contains "$doc" "Monitoring / Rollback"
assert_contains "$doc" "GitHub Environments"
assert_contains "$doc" "macOS固有アプリ"
assert_contains "$doc" "一律に強制しない"
assert_contains "$parent" "## デプロイ設計 / Release・Production計画"
assert_contains "$parent" "Production runtime:"
assert_contains "$parent" "Containerの要否と理由:"
assert_contains "$parent" "Persistent dataの保存先・再作成後の生存方法:"
assert_contains "$parent" "Deployment method・実行主体・権限:"
assert_contains "$parent" "Release Candidate / artifact identity（commit SHA・artifact ID・image digest）:"
assert_contains "$parent" "Secrets / 環境変数 / 外部サービス（値は記録しない）:"
assert_contains "$parent" "backup・DB/schema/vector migration・失敗時の復旧:"
assert_contains "$parent" "Stagingの要否と理由:"
assert_contains "$parent" "E2E / Smoke Test・Release判定:"
assert_contains "$parent" "Production Deploy後のHealth Check・Monitoring:"
assert_contains "$parent" "Rollback単位・永続データ互換性:"
assert_contains "$parent" "MergeからProduction Deployまでの承認境界:"
assert_contains "$flow" "docs/deployment-release-design.md"
assert_contains "$guide" "docs/deployment-release-design.md"
assert_contains "$preflight" "secret_pattern"

security_result="$($preflight "$repo_root")"
grep -Fq 'SECURITY_STATUS=SECURITY_PASSED' <<<"$security_result" || {
  printf 'security preflight did not pass for the repository\n' >&2
  exit 1
}

printf 'deployment design documentation contract: ok\n'
