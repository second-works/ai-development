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

secret_pattern='ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9-]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'

scan_file() {
  local file="$1"
  if [[ -L "$file" ]]; then
    readlink "$file" | grep -Eiq -- "$secret_pattern"
    return $?
  fi
  [[ -f "$file" ]] && grep -Eiq -- "$secret_pattern" "$file"
}

scan_tracked_files() {
  local path
  while IFS= read -r -d '' path; do
    if scan_file "$repo_root/$path"; then
      return 0
    fi
  done < <(git -C "$repo_root" ls-files -z)
  return 1
}

if ! git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf 'repository is not a git worktree\n' >&2
  exit 1
fi

if scan_tracked_files; then
  printf 'possible secret-like value found in repository\n' >&2
  exit 1
fi

fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT
printf '%s%s\n' 'sk-proj-' 'abcdefghijklmnopqrstuvwxyz' > "$fixture_dir/secret-fixture.txt"
if ! scan_file "$fixture_dir/secret-fixture.txt"; then
  printf 'secret scanner did not detect sk-proj fixture\n' >&2
  exit 1
fi

link_target="$(printf '%s%s' 'github_pat_' 'abcdefghijklmnopqrstuvwxyz')"
ln -s "$link_target" "$fixture_dir/secret-link"
if ! scan_file "$fixture_dir/secret-link"; then
  printf 'secret scanner did not detect token-like symlink content\n' >&2
  exit 1
fi

printf 'deployment design documentation contract: ok\n'
