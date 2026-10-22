#!/usr/bin/env bash
# Standard verification for this repository: run every tests/*/run-samples.sh with
# Bash 5 or later. Any failure, or finding no suite at all, is not success.

set -u

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root" || exit 2

bash5=''
for candidate in "${VERIFY_BASH:-}" /opt/homebrew/bin/bash /usr/local/bin/bash bash; do
  [[ -n $candidate ]] || continue
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c '((BASH_VERSINFO[0] >= 5))' 2>/dev/null; then
    bash5="$candidate"
    break
  fi
done
[[ -n $bash5 ]] || { echo "[verify] Bash 5 or later was not found (set VERIFY_BASH)" >&2; exit 2; }

suites=(tests/*/run-samples.sh)
[[ -f ${suites[0]} ]] || { echo "[verify] no tests/*/run-samples.sh was found" >&2; exit 1; }

failed=0
for suite in "${suites[@]}"; do
  if "$bash5" "$suite" >/dev/null 2>"${TMPDIR:-/tmp}/verify-$$.err"; then
    echo "[verify] passed $suite"
  else
    failed=$((failed + 1))
    echo "[verify] FAILED $suite" >&2
    tail -5 "${TMPDIR:-/tmp}/verify-$$.err" >&2
  fi
done
rm -f "${TMPDIR:-/tmp}/verify-$$.err"
echo "[verify] ${#suites[@]} suite(s), $failed failed"
[[ $failed -eq 0 ]]
