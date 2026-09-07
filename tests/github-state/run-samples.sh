#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SCRIPT="$ROOT/scripts/collect-github-state.py"
FIXTURES="$ROOT/tests/github-state/fixtures"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

python3 -m py_compile "$SCRIPT"

happy_output="$WORK_DIR/happy.json"
GITHUB_TOKEN=not-a-real-token python3 "$SCRIPT" \
  --repository example/demo \
  --issue 64 \
  --pr 12 \
  --fixture-dir "$FIXTURES/happy" \
  --observed-at 2026-09-07T00:00:00Z \
  --output "$happy_output"

python3 -c '
import json
import os
import stat
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["observer_schema_version"] == 1
assert data["observed_at"] == "2026-09-07T00:00:00Z"
assert data["collection"] == {"status": "COMPLETE", "usable_for_state_update": True, "errors": []}
assert data["head_consistency"]["status"] == "MATCH"
assert data["head_consistency"]["initial_head_sha"] == "a" * 40
assert data["head_consistency"]["initial_source_url"] == "fixture://pr-initial.json"
assert data["head_consistency"]["final_source_url"] == "fixture://pr-final.json"
assert data["pull_request"]["state"] == "closed"
assert data["pull_request"]["merged"] is True
assert data["pull_request"]["source_url"] == "fixture://pr-final.json"
assert stat.S_IMODE(os.stat(sys.argv[1]).st_mode) == 0o600
assert len(data["workflow_runs"]["source_urls"]) == 2
assert [run["id"] for run in data["workflow_runs"]["other_runs"]] == [101, 103]
assert data["workflow_runs"]["other_runs"][1]["conclusion"] == "startup_failure"
assert [run["id"] for run in data["workflow_runs"]["security_named_runs"]] == [102]
assert data["workflow_runs"]["nonmatching_head_runs"] == []
assert data["workflow_runs"]["target_head_evidence_status"] == "OBSERVED"
assert [review["id"] for review in data["reviews"]["same_head"]] == [201]
assert [review["id"] for review in data["reviews"]["other_head"]] == [202]
assert data["reviews"]["target_head_evidence_status"] == "OBSERVED"
assert [comment["id"] for comment in data["review_comments"]["same_head"]] == [301]
assert [comment["id"] for comment in data["review_comments"]["other_head"]] == [302]
assert data["review_comments"]["target_head_evidence_status"] == "OBSERVED"
assert "body" not in data["review_comments"]["same_head"][0]
assert "not-a-real-token" not in open(sys.argv[1], encoding="utf-8").read()
' "$happy_output"

set +e
python3 "$SCRIPT" \
  --repository example/demo \
  --issue 64 \
  --pr 12 \
  --fixture-dir "$FIXTURES/happy" \
  --observed-at 2026-09-07T00:00:00Z \
  --output "$happy_output" >/dev/null 2>&1
existing_output_status=$?
set -e
[[ "$existing_output_status" -eq 4 ]] || {
  printf 'existing output must produce exit 4, got %s\n' "$existing_output_status" >&2
  exit 1
}

head_changed_output="$WORK_DIR/head-changed.json"
set +e
python3 "$SCRIPT" \
  --repository example/demo \
  --issue 64 \
  --pr 12 \
  --fixture-dir "$FIXTURES/head-changed" \
  --observed-at 2026-09-07T00:00:00Z \
  --output "$head_changed_output"
head_changed_status=$?
set -e
[[ "$head_changed_status" -eq 3 ]] || {
  printf 'head change must produce exit 3, got %s\n' "$head_changed_status" >&2
  exit 1
}
python3 -c '
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["collection"]["status"] == "UNAVAILABLE"
assert data["collection"]["usable_for_state_update"] is False
assert data["head_consistency"]["status"] == "MISMATCH"
assert data["head_consistency"]["initial_head_sha"] == "a" * 40
assert data["head_consistency"]["final_head_sha"] == "d" * 40
assert data["head_consistency"]["initial_source_url"] == "fixture://pr-initial.json"
assert data["head_consistency"]["final_source_url"] == "fixture://pr-final.json"
assert data["collection"]["errors"][0]["kind"] == "HEAD_CHANGED_DURING_COLLECTION"
' "$head_changed_output"

no_pr_output="$WORK_DIR/no-pr.json"
python3 "$SCRIPT" \
  --repository example/demo \
  --issue 64 \
  --fixture-dir "$FIXTURES/no-pr" \
  --observed-at 2026-09-07T00:00:00Z \
  --output "$no_pr_output"
python3 -c '
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["collection"]["status"] == "COMPLETE"
assert data["collection"]["usable_for_state_update"] is True
assert data["pull_request"] is None
assert data["head_consistency"]["status"] == "NOT_APPLICABLE"
assert data["workflow_runs"]["security_named_runs"] == []
assert data["workflow_runs"]["target_head_evidence_status"] == "NOT_APPLICABLE"
' "$no_pr_output"

no_evidence_output="$WORK_DIR/no-evidence.json"
python3 "$SCRIPT" \
  --repository example/demo \
  --issue 64 \
  --pr 12 \
  --fixture-dir "$FIXTURES/no-evidence" \
  --observed-at 2026-09-07T00:00:00Z \
  --output "$no_evidence_output"
python3 -c '
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["collection"]["status"] == "COMPLETE"
assert data["head_consistency"]["status"] == "MATCH"
assert data["workflow_runs"]["target_head_evidence_status"] == "NOT_OBSERVED"
assert data["reviews"]["target_head_evidence_status"] == "NOT_OBSERVED"
assert data["review_comments"]["target_head_evidence_status"] == "NOT_OBSERVED"
assert len(data["workflow_runs"]["source_urls"]) == 1
assert len(data["reviews"]["source_urls"]) == 1
assert len(data["review_comments"]["source_urls"]) == 1
' "$no_evidence_output"

for fixture in http-error invalid-json; do
  error_output="$WORK_DIR/$fixture.json"
  set +e
  python3 "$SCRIPT" \
    --repository example/demo \
    --issue 64 \
    --fixture-dir "$FIXTURES/$fixture" \
    --observed-at 2026-09-07T00:00:00Z \
    --output "$error_output"
  status=$?
  set -e
  [[ "$status" -eq 3 ]] || {
    printf '%s fixture must produce exit 3, got %s\n' "$fixture" "$status" >&2
    exit 1
  }
  python3 -c '
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["collection"] ["status"] == "UNAVAILABLE"
assert data["collection"]["usable_for_state_update"] is False
assert data["collection"]["errors"]
' "$error_output"
done

unknown_enum_output="$WORK_DIR/unknown-enum.json"
set +e
python3 "$SCRIPT" \
  --repository example/demo \
  --issue 64 \
  --fixture-dir "$FIXTURES/unknown-enum" \
  --observed-at 2026-09-07T00:00:00Z \
  --output "$unknown_enum_output"
unknown_enum_status=$?
set -e
[[ "$unknown_enum_status" -eq 3 ]] || {
  printf 'unknown enum must produce exit 3, got %s\n' "$unknown_enum_status" >&2
  exit 1
}
python3 -c '
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["collection"]["status"] == "UNAVAILABLE"
assert data["collection"]["errors"] == [{
    "operation": "issue",
    "kind": "UNKNOWN_ENUM",
    "detail": "state was not a supported value",
}]
' "$unknown_enum_output"

invalid_argument_output="$WORK_DIR/invalid-argument.json"
set +e
python3 "$SCRIPT" \
  --repository example/demo \
  --issue 0 \
  --fixture-dir "$FIXTURES/no-pr" \
  --output "$invalid_argument_output" >/dev/null 2>&1
invalid_argument_status=$?
set -e
[[ "$invalid_argument_status" -eq 2 ]] || {
  printf 'zero Issue number must be rejected, got %s\n' "$invalid_argument_status" >&2
  exit 1
}

live_observed_at_output="$WORK_DIR/live-observed-at.json"
set +e
python3 "$SCRIPT" \
  --repository example/demo \
  --issue 64 \
  --observed-at 2026-09-07T00:00:00Z \
  --output "$live_observed_at_output" >/dev/null 2>&1
live_observed_at_status=$?
set -e
[[ "$live_observed_at_status" -eq 2 ]] || {
  printf 'live --observed-at must be rejected, got %s\n' "$live_observed_at_status" >&2
  exit 1
}
[[ ! -e "$live_observed_at_output" ]] || {
  printf 'live --observed-at must fail before creating an artifact\n' >&2
  exit 1
}

echo "GitHub State observation samples: PASS"
