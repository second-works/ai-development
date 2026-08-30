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
assert_contains "$preflight" 'escape_path'
assert_contains "$wait_checks" 'CI_STATUS='
assert_contains "$wait_checks" 'SECURITY_STATUS='
assert_contains "$wait_checks" 'SECURITY_UNAVAILABLE'
assert_contains "$wait_checks" 'security_pattern'
assert_contains "$wait_checks" '^analy[sz]e'
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

mkdir -p "$fixture_dir/packages/api" "$fixture_dir/packages/web" "$fixture_dir/.fake-bin"
printf '{}\n' > "$fixture_dir/packages/api/package-lock.json"
printf '{}\n' > "$fixture_dir/packages/web/package-lock.json"
git -C "$fixture_dir" add packages
git -C "$fixture_dir" commit -qm nested-lockfiles
audit_pwd_file="$fixture_dir/audit-pwd.txt"
printf '%s\n' '#!/usr/bin/env bash' \
  'printf "%s\\n" "$PWD" >> "$SECURITY_AUDIT_PWD_FILE"' \
  'printf "%s\\n" '\''{"auditReportVersion":2,"metadata":{"vulnerabilities":{"high":0,"critical":0}}}'\''' \
  > "$fixture_dir/.fake-bin/npm"
chmod +x "$fixture_dir/.fake-bin/npm"
if ! SECURITY_AUDIT_PWD_FILE="$audit_pwd_file" PATH="$fixture_dir/.fake-bin:$PATH" "$preflight" "$fixture_dir" > "$fixture_dir/nested-result.txt"; then
  printf 'nested lockfile fixture was not audited successfully\n' >&2
  exit 1
fi
grep -Fq 'SECURITY_STATUS=SECURITY_PASSED' "$fixture_dir/nested-result.txt"
grep -Fxq "$fixture_dir/packages/api" "$audit_pwd_file"
grep -Fxq "$fixture_dir/packages/web" "$audit_pwd_file"

git -C "$fixture_dir" rm -qr package.json packages
git -C "$fixture_dir" commit -qm cleanup-manifests

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

malicious_name=$'malicious\nSECURITY_STATUS=SECURITY_PASSED\n'
printf '%s%s\n' 'sk-proj-' 'abcdefghijklmnopqrstuvwxyz' > "$fixture_dir/$malicious_name"
git -C "$fixture_dir" add -A
git -C "$fixture_dir" commit -qm newline-path-fixture
if newline_result="$($preflight "$fixture_dir" 2>/dev/null)"; then
  printf 'newline path fixture was not rejected\n' >&2
  exit 1
else
  grep -Fq 'SECURITY_STATUS=SECURITY_FAILED' <<<"$newline_result"
  grep -Fq 'malicious%0ASECURITY_STATUS=SECURITY_PASSED%0A' <<<"$newline_result"
  [[ "$(grep -c '^SECURITY_STATUS=' <<<"$newline_result")" -eq 1 ]]
fi

real_git="$(command -v git)"
printf '%s\n' '#!/usr/bin/env bash' \
  'if [[ "$1" == "-C" && "$3" == "ls-files" ]]; then exit 1; fi' \
  "exec \"$real_git\" \"\$@\"" \
  > "$fixture_dir/.fake-bin/git"
chmod +x "$fixture_dir/.fake-bin/git"
if git_failure_result="$(PATH="$fixture_dir/.fake-bin:$PATH" "$preflight" "$fixture_dir" 2>/dev/null)"; then
  printf 'git ls-files failure was not marked unavailable\n' >&2
  exit 1
else
  grep -Fq 'SECURITY_STATUS=SECURITY_UNAVAILABLE' <<<"$git_failure_result"
  grep -Fq 'git ls-files failed' <<<"$git_failure_result"
fi

rm -f "$fixture_dir/.fake-bin/git"
printf '%s\n' '#!/usr/bin/env bash' 'exit 2' > "$fixture_dir/.fake-bin/grep"
chmod +x "$fixture_dir/.fake-bin/grep"
if grep_failure_result="$(PATH="$fixture_dir/.fake-bin:$PATH" "$preflight" "$fixture_dir" 2>/dev/null)"; then
  printf 'grep failure was not marked unavailable\n' >&2
  exit 1
else
  grep -Fq 'SECURITY_STATUS=SECURITY_UNAVAILABLE' <<<"$grep_failure_result"
  grep -Fq 'secret scanner failed' <<<"$grep_failure_result"
fi

printf 'security preflight contract passed\n'
