#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
RENDER="$ROOT/scripts/render-status-report.py"
FIXTURES="$ROOT/tests/html-status-report/fixtures"

before="$(shasum -a 256 "$FIXTURES/complete.json" | awk '{print $1}')"
python3 "$RENDER" "$FIXTURES/complete.json" --output "$WORK/report.html"
after="$(shasum -a 256 "$FIXTURES/complete.json" | awk '{print $1}')"
[[ "$before" == "$after" ]]
grep -Fq 'GitHub Status Report' "$WORK/report.html"
grep -Fq 'rel="icon" href="data:,"' "$WORK/report.html"
grep -Fq 'complete.json' "$WORK/report.html"
grep -Fq '2026-09-08T00:00:00Z' "$WORK/report.html"
grep -Fq '0123456789012345678901234567890123456789' "$WORK/report.html"
grep -Fq '日本語' "$WORK/report.html"
grep -Fq 'deliberately long fixture text' "$WORK/report.html"

python3 "$RENDER" "$FIXTURES/dangerous.json" --output "$WORK/dangerous.html"
grep -Fq '&lt;script&gt;alert(1)&lt;/script&gt;' "$WORK/dangerous.html"
if grep -Fq '<script>alert(1)</script>' "$WORK/dangerous.html"; then
  exit 1
fi
if grep -Fq 'href="javascript:' "$WORK/dangerous.html"; then
  exit 1
fi
if python3 "$RENDER" "$FIXTURES/complete.json" --output "$FIXTURES/complete.json"; then
  exit 1
fi
printf '{invalid' > "$WORK/invalid.json"
if python3 "$RENDER" "$WORK/invalid.json" --output "$WORK/invalid.html"; then
  exit 1
fi
printf '{"collection":{"status":"COMPLETE"}}' > "$WORK/invalid-schema.json"
if python3 "$RENDER" "$WORK/invalid-schema.json" --output "$WORK/invalid-schema.html"; then
  exit 1
fi
python3 - "$FIXTURES/complete.json" "$WORK/boolean-schema.json" <<'PY'
import json
import sys

source, destination = sys.argv[1:]
payload = json.load(open(source, encoding="utf-8"))
payload["observer_schema_version"] = True
payload["issue"]["number"] = False
json.dump(payload, open(destination, "w", encoding="utf-8"))
PY
if python3 "$RENDER" "$WORK/boolean-schema.json" --output "$WORK/boolean-schema.html"; then
  exit 1
fi
if python3 "$RENDER" "$FIXTURES/complete.json" --output "$WORK/report.html"; then
  exit 1
fi
printf 'html-status-report samples: ok\n'
