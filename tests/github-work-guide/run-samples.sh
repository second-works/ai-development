#!/usr/bin/env bash
# Python tests of the GitHub work guide (scripts/github_work_guide, scripts/report_github_work_guide.py).
# Standard verification (scripts/verify.sh) runs this file like every tests/*/run-samples.sh.
# No network and no model: GitHub is replaced by synthetic transports and saved PUBLIC fixtures.
set -Eeuo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
PYTHON="${VERIFY_PYTHON:-python3}"

command -v "$PYTHON" >/dev/null 2>&1 || { echo "[github-work-guide] $PYTHON was not found" >&2; exit 1; }
# A missing or old Python is a failure, never a skip.
"$PYTHON" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' ||
  { echo "[github-work-guide] Python 3.10 or later is required" >&2; exit 1; }

log="$(mktemp)"
trap 'rm -f "$log"' EXIT
# -I ignores PYTHON* variables and user site-packages; -B writes no bytecode into the checkout.
if ! (cd "$ROOT/tests/github-work-guide" && "$PYTHON" -I -B -m unittest discover -s . -p 'test_*.py' -t .) >"$log" 2>&1; then
  cat "$log" >&2
  exit 1
fi
cat "$log" >&2
# unittest reports skips as "OK (skipped=N)". No test may be skipped.
if grep -Eq 'skipped=[0-9]+' "$log"; then
  echo "[github-work-guide] some tests were skipped, which is not success" >&2
  exit 1
fi
grep -Eq '^OK$' "$log" || { echo "[github-work-guide] unittest did not report OK" >&2; exit 1; }
