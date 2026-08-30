#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [repository-root]" >&2
  exit 2
fi

repo_root="$(cd "${1:-.}" && pwd)"

command -v git >/dev/null 2>&1 || {
  echo 'SECURITY_STATUS=SECURITY_UNAVAILABLE'
  echo 'SECURITY_REASON=git is not installed'
  exit 4
}

git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo 'SECURITY_STATUS=SECURITY_UNAVAILABLE'
  echo 'SECURITY_REASON=repository root is not a git worktree'
  exit 4
}

secret_pattern='ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9-]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'

scan_file() {
  local file="$1"
  if [[ -L "$file" ]]; then
    readlink "$file" | grep -Eiq -- "$secret_pattern"
    return $?
  fi
  [[ -f "$file" ]] && grep -Eiq -- "$secret_pattern" "$file"
}

secret_status='SECURITY_PASSED'
secret_reason='tracked files and symlink targets contained no known secret patterns'
while IFS= read -r -d '' path; do
  if scan_file "$repo_root/$path"; then
    secret_status='SECURITY_FAILED'
    secret_reason="secret-like value detected in $path"
    break
  fi
done < <(git -C "$repo_root" ls-files -z)

manifest_paths=()
while IFS= read -r -d '' path; do
  case "$path" in
    package.json|package-lock.json|npm-shrinkwrap.json|pnpm-lock.yaml|yarn.lock|requirements.txt|requirements-*.txt|pyproject.toml|poetry.lock|Pipfile.lock|uv.lock)
      manifest_paths+=("$path")
      ;;
  esac
done < <(git -C "$repo_root" ls-files -z)

dependency_status='SECURITY_NOT_APPLICABLE'
dependency_reason='no supported dependency manifest is present'
dependency_manifest=''

for path in "${manifest_paths[@]}"; do
  case "$path" in
    package-lock.json|npm-shrinkwrap.json|pnpm-lock.yaml|yarn.lock)
      dependency_manifest="$path"
      break
      ;;
  esac
done

if [[ -n "$dependency_manifest" ]]; then
  if ! command -v npm >/dev/null 2>&1; then
    dependency_status='SECURITY_UNAVAILABLE'
    dependency_reason="npm is unavailable for $dependency_manifest"
  else
    audit_output="$(mktemp "${TMPDIR:-/tmp}/security-preflight-audit.XXXXXX")"
    trap 'rm -f "$audit_output"' EXIT
    if npm audit --json --audit-level=high --package-lock-only >"$audit_output" 2>&1; then
      dependency_status='SECURITY_PASSED'
      dependency_reason="npm audit reported no high or critical vulnerabilities for $dependency_manifest"
    elif python3 - "$audit_output" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        payload = json.load(handle)
except (OSError, json.JSONDecodeError):
    raise SystemExit(2)

vulnerabilities = payload.get("metadata", {}).get("vulnerabilities", {})
if "auditReportVersion" not in payload or not isinstance(vulnerabilities, dict):
    raise SystemExit(2)
high = int(vulnerabilities.get("high", 0) or 0)
critical = int(vulnerabilities.get("critical", 0) or 0)
raise SystemExit(0 if high or critical else 1)
PY
    then
      dependency_status='SECURITY_FAILED'
      dependency_reason="npm audit reported high or critical vulnerabilities for $dependency_manifest"
    else
      audit_parse_status=$?
      if [[ "$audit_parse_status" -eq 1 ]]; then
        dependency_status='SECURITY_PASSED'
        dependency_reason="npm audit reported no high or critical vulnerabilities for $dependency_manifest"
      else
        dependency_status='SECURITY_UNAVAILABLE'
        dependency_reason="npm audit could not produce a machine-readable result for $dependency_manifest"
      fi
    fi
  fi
else
  for path in "${manifest_paths[@]}"; do
    if [[ "$path" == 'package.json' ]]; then
      dependency_status='SECURITY_UNAVAILABLE'
      dependency_reason='package.json is present but no supported npm lockfile is available'
      dependency_manifest="$path"
      break
    fi
  done
  for path in "${manifest_paths[@]}"; do
    [[ "$dependency_status" == 'SECURITY_NOT_APPLICABLE' ]] || break
    case "$path" in
      requirements.txt|requirements-*.txt|pyproject.toml|poetry.lock|Pipfile.lock|uv.lock)
        dependency_status='SECURITY_UNAVAILABLE'
        dependency_reason="no supported dependency scanner is defined for $path"
        dependency_manifest="$path"
        break
        ;;
    esac
  done
fi

overall_status='SECURITY_PASSED'
overall_reason="$secret_reason; dependency check: $dependency_reason"
if [[ "$secret_status" == 'SECURITY_FAILED' || "$dependency_status" == 'SECURITY_FAILED' ]]; then
  overall_status='SECURITY_FAILED'
elif [[ "$dependency_status" == 'SECURITY_UNAVAILABLE' ]]; then
  overall_status='SECURITY_UNAVAILABLE'
fi

printf 'SECURITY_STATUS=%s\n' "$overall_status"
printf 'SECURITY_REASON=%s\n' "$overall_reason"
printf 'SECRET_STATUS=%s\n' "$secret_status"
printf 'DEPENDENCY_STATUS=%s\n' "$dependency_status"
printf 'DEPENDENCY_MANIFEST=%s\n' "$dependency_manifest"

case "$overall_status" in
  SECURITY_FAILED)
    exit 1
    ;;
  SECURITY_UNAVAILABLE)
    exit 4
    ;;
  SECURITY_PASSED|SECURITY_NOT_APPLICABLE)
    exit 0
    ;;
esac
