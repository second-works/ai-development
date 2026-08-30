#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
preflight="$repo_root/templates/security/security-preflight.sh"
wait_checks="$repo_root/.agents/skills/pr-review-fix/scripts/wait-checks.sh"

assert_contains() {
  local file="$1"
  local needle="$2"
  grep -Fq -- "$needle" "$file" || {
    printf 'missing security preflight contract: %s in %s\n' "$needle" "$file" >&2
    exit 1
  }
}

[[ -x "$preflight" ]] || {
  printf 'security preflight is not executable: %s\n' "$preflight" >&2
  exit 1
}

for state in SECURITY_PASSED SECURITY_FAILED SECURITY_NOT_APPLICABLE SECURITY_UNAVAILABLE; do
  assert_contains "$preflight" "$state"
done
assert_contains "$preflight" 'npm audit --json --audit-level=high --package-lock-only'
assert_contains "$wait_checks" 'CI_STATUS='
assert_contains "$wait_checks" 'SECURITY_STATUS='
assert_contains "$wait_checks" 'SECURITY_UNAVAILABLE'
assert_contains "$wait_checks" 'security_pattern'
assert_contains "$wait_checks" 'SECURITY_FAILED'
assert_contains "$wait_checks" 'security-preflight.sh'
assert_contains "$repo_root/AGENTS.md" 'CIの成功をSecurityの成功として扱わない'
assert_contains "$repo_root/AGENTS.md" 'SECURITY_NOT_APPLICABLE'
assert_contains "$repo_root/docs/nine-standard-ai-development-flow.md" 'Security Preflight'
assert_contains "$repo_root/docs/template-guide.md" 'SECURITY_UNAVAILABLE'
assert_contains "$repo_root/.github/pull_request_template.md" 'Security Preflight判定'

fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT
git -C "$fixture_dir" init -q
git -C "$fixture_dir" config user.email test@example.invalid
git -C "$fixture_dir" config user.name security-preflight-test
printf 'safe fixture\n' > "$fixture_dir/safe.txt"
git -C "$fixture_dir" add safe.txt
git -C "$fixture_dir" commit -qm initial

safe_result="$($preflight "$fixture_dir")"
grep -Fq 'SECURITY_STATUS=SECURITY_PASSED' <<<"$safe_result"
grep -Fq 'DEPENDENCY_STATUS=SECURITY_NOT_APPLICABLE' <<<"$safe_result"

printf '{"name":"fixture","dependencies":{}}\n' > "$fixture_dir/package.json"
git -C "$fixture_dir" add package.json
git -C "$fixture_dir" commit -qm package-manifest
if manifest_result="$($preflight "$fixture_dir" 2>/dev/null)"; then
  printf 'package manifest without lockfile was not marked unavailable\n' >&2
  exit 1
else
  grep -Fq 'SECURITY_STATUS=SECURITY_UNAVAILABLE' <<<"$manifest_result"
  grep -Fq 'DEPENDENCY_STATUS=SECURITY_UNAVAILABLE' <<<"$manifest_result"
fi

printf '%s%s\n' 'sk-proj-' 'abcdefghijklmnopqrstuvwxyz' > "$fixture_dir/secret.txt"
git -C "$fixture_dir" add secret.txt
git -C "$fixture_dir" commit -qm secret-fixture
if secret_result="$($preflight "$fixture_dir" 2>/dev/null)"; then
  printf 'secret fixture was not rejected\n' >&2
  exit 1
else
  grep -Fq 'SECURITY_STATUS=SECURITY_FAILED' <<<"$secret_result"
fi

git -C "$fixture_dir" rm -q secret.txt
link_target="$(printf '%s%s' 'github_pat_' 'abcdefghijklmnopqrstuvwxyz')"
ln -s "$link_target" "$fixture_dir/secret-link"
git -C "$fixture_dir" add -A
git -C "$fixture_dir" commit -qm symlink-fixture
if link_result="$($preflight "$fixture_dir" 2>/dev/null)"; then
  printf 'secret symlink fixture was not rejected\n' >&2
  exit 1
else
  grep -Fq 'SECURITY_STATUS=SECURITY_FAILED' <<<"$link_result"
fi

printf 'security preflight contract passed\n'
