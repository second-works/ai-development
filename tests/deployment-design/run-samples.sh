#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
doc="$repo_root/docs/deployment-release-design.md"
flow="$repo_root/docs/nine-standard-ai-development-flow.md"
guide="$repo_root/docs/template-guide.md"
acceptance="$repo_root/docs/acceptance-verification.md"
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
assert_contains "$doc" "## 4. Full-System Security Audit"
assert_contains "$doc" 'RC静的監査'
assert_contains "$doc" 'Staging上の確認'
assert_contains "$doc" '認証、認可、権限境界'
assert_contains "$doc" 'Dependencyとsupply chain'
assert_contains "$doc" 'CodeQL等の静的解析'
assert_contains "$doc" 'API、DB、外部サービス間のtrust boundary'
assert_contains "$doc" 'Production / Deployment設定'
assert_contains "$doc" '`PASS`：'
assert_contains "$doc" '`FAIL`：'
assert_contains "$doc" '`NOT_APPLICABLE`：'
assert_contains "$doc" 'LOWだけを理由に監査を省略しない'
assert_contains "$doc" '古い`PASS`を再利用せず'
assert_contains "$doc" 'Release Candidateとのidentity不一致'
assert_contains "$doc" '理由と適格性を確認した`NOT_APPLICABLE`'
assert_contains "$doc" "Backup / migration"
assert_contains "$doc" "Post-deploy Health Check"
assert_contains "$doc" "Monitoring / Rollback"
assert_contains "$doc" "GitHub Environments"
assert_contains "$doc" "macOS固有アプリ"
assert_contains "$doc" "一律に強制しない"
assert_contains "$flow" "docs/deployment-release-design.md"
assert_contains "$flow" 'Full-System Security Audit判定'
assert_contains "$flow" 'PR単位Security Checkを置き換えない'
assert_contains "$acceptance" 'Full-System Security Audit判定'
assert_contains "$acceptance" '理由と適格性を確認した`NOT_APPLICABLE`'
assert_contains "$doc" '### Full-System Security Audit'
assert_contains "$doc" 'identity不一致ではRelease判定とProduction Deployへ進まない'
assert_contains "$guide" "docs/deployment-release-design.md"
assert_contains "$guide" 'Full-System Security Auditの`PASS`または理由と適格性を確認した`NOT_APPLICABLE`'
assert_contains "$preflight" "secret_pattern"

security_result="$($preflight "$repo_root")"
grep -Fq 'SECURITY_STATUS=SECURITY_PASSED' <<<"$security_result" || {
  printf 'security preflight did not pass for the repository\n' >&2
  exit 1
}

# The PR and Issue templates and AGENTS.md are now the lightweight ones (#197). Their
# safety wording is checked in tests/lightweight-template.
assert_contains "$doc" 'Release Candidate SHA / artifact identity、RC静的監査・Staging確認、Full-System Security Auditの結果・理由'

printf 'deployment design documentation contract: ok\n'
