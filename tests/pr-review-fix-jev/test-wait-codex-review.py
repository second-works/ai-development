#!/usr/bin/env python3
"""Exercise the review waiter's final status with synthetic gh responses."""

import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
WAITER = ROOT / ".agents/skills/pr-review-fix/scripts/wait-codex-review.sh"
SHA = "a" * 40
ACTOR = {"login": "chatgpt-codex-connector[bot]", "type": "Bot"}
REQUEST = {"id": 100, "body": "@codex review", "created_at": "2026-01-01T00:00:00Z"}


def review(*, state="COMMENTED", body="No major issues", sha=SHA, rid=201, actor=ACTOR):
    return {
        "id": rid,
        "state": state,
        "body": f"{body}\n\nReviewed commit: {sha[:10]}",
        "commit_id": sha,
        "user": actor,
    }


def run_case(name, *, reviews, inline=None, threads=None, issue=None, expected_status, expected_code, extra=None, invalid_json=None, api_failure=None):
    with tempfile.TemporaryDirectory(prefix="review-wait-test-") as tmp:
        fixture = Path(tmp)
        for filename, payload in {
            "issue.json": [issue if issue is not None else [REQUEST]],
            "inline.json": [inline or []],
            "reviews.json": [reviews],
            "threads.json": threads if threads is not None else [{"data": {"repository": {"pullRequest": {"reviewThreads": {"nodes": []}}}}}],
        }.items():
            (fixture / filename).write_text(json.dumps(payload), encoding="utf-8")
        if invalid_json:
            (fixture / invalid_json).write_text("{invalid", encoding="utf-8")
        mock = fixture / "gh"
        mock.write_text("""#!/bin/sh
case " $* " in
  *' auth status '*) exit 0 ;;
  *' api graphql '*) cat "$MOCK_GH_DIR/threads.json" ;;
  *'/issues/'*'/comments?'*) cat "$MOCK_GH_DIR/issue.json" ;;
  *'/pulls/'*'/reviews?'*)
    if [ "${MOCK_API_FAILURE:-}" = reviews ]; then exit 7; fi
    cat "$MOCK_GH_DIR/reviews.json" ;;
  *'/pulls/'*'/comments?'*) cat "$MOCK_GH_DIR/inline.json" ;;
  *) echo "unexpected gh request: $*" >&2; exit 99 ;;
esac
""", encoding="utf-8")
        mock.chmod(0o755)
        env = {**os.environ, "PATH": f"{fixture}:{os.environ['PATH']}", "MOCK_GH_DIR": tmp, "MOCK_API_FAILURE": api_failure or ""}
        process = subprocess.run(
            ["bash", str(WAITER), "github.com/owner/repo", "1", SHA, "100", "200", "0"],
            text=True, capture_output=True, env=env, timeout=10,
        )
        output = process.stdout + process.stderr
        if process.returncode != expected_code or (expected_status and f"STATUS={expected_status}" not in output):
            raise AssertionError(f"{name}: code={process.returncode}, output={output}")
        for marker in extra or []:
            if marker not in output:
                raise AssertionError(f"{name}: missing {marker!r} in {output}")


run_case("clean submitted review", reviews=[review()], expected_status="REVIEW_PASSED", expected_code=0)
run_case("approved review", reviews=[review(state="APPROVED")], expected_status="REVIEW_PASSED", expected_code=0)
run_case("body P1", reviews=[review(body="[P1] security regression")], expected_status="REVIEW_CHANGES_REQUIRED", expected_code=3, extra=["AUTO_BLOCKING_COUNT=1"])
run_case("severity field P1", reviews=[review(body="**Severity:** P1\n**Finding ID:** F-1")], expected_status="REVIEW_CHANGES_REQUIRED", expected_code=3)
run_case("negated severity summary", reviews=[review(body="No P0/P1 findings and 0 P1 findings")], expected_status="REVIEW_PASSED", expected_code=0, extra=["AUTO_BLOCKING_COUNT=0"])
run_case("requested changes without severity", reviews=[review(state="CHANGES_REQUESTED")], expected_status="REVIEW_CHANGES_REQUIRED", expected_code=3)
run_case("blocking P2 body", reviews=[review(body="[P2] needs fix\nClassification: BLOCKING")], expected_status="REVIEW_CHANGES_REQUIRED", expected_code=3)
run_case("nonblocking P2 body", reviews=[review(body="[P2] suggestion")], expected_status="REVIEW_PASSED", expected_code=0, extra=["P2_NONBLOCKING_COUNT=1"])
run_case("inline P1", reviews=[review()], inline=[{"body": "P1 broken", "commit_id": SHA, "pull_request_review_id": 201, "user": ACTOR}], expected_status="REVIEW_CHANGES_REQUIRED", expected_code=3)
run_case("unresolved old-head thread", reviews=[review()], threads=[{"data": {"repository": {"pullRequest": {"reviewThreads": {"nodes": [{"id": "thread-1", "isResolved": False, "comments": {"nodes": [{"author": {"login": ACTOR["login"], "__typename": "Bot"}, "body": "P1 still broken", "outdated": False}]}}]}}}}}], expected_status="REVIEW_CHANGES_REQUIRED", expected_code=3)
for state in ("DISMISSED", "PENDING", "UNKNOWN"):
    run_case(f"{state} is not evidence", reviews=[review(state=state)], expected_status=None, expected_code=1, extra=["timed out"])
run_case("old review id", reviews=[review(rid=200)], expected_status=None, expected_code=1, extra=["timed out"])
run_case("old head", reviews=[review(sha="b" * 40)], expected_status=None, expected_code=1, extra=["timed out"])
run_case("untrusted actor", reviews=[review(actor={"login": "other", "type": "Bot"})], expected_status=None, expected_code=1, extra=["timed out"])
run_case("missing request", reviews=[review()], issue=[], expected_status=None, expected_code=4, extra=["request comment id was not found"])
run_case("malformed reviews", reviews=[review()], invalid_json="reviews.json", expected_status=None, expected_code=1)
run_case("reviews API failure", reviews=[review()], api_failure="reviews", expected_status=None, expected_code=7)
print("review waiter state and body regression cases passed")
