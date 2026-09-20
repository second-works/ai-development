#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 5 ]]; then
  echo "Usage: $0 <repo-identity> <pr-number> <head-sha> <review-comments-json> <output-jsonl>" >&2
  exit 2
fi

REPO_IDENTITY="$1"
PR_NUMBER="$2"
HEAD_SHA="$3"
REVIEW_COMMENTS_FILE="$4"
OUTPUT_JSONL="$5"

command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 not found" >&2; exit 1; }

python3 - "$REPO_IDENTITY" "$PR_NUMBER" "$HEAD_SHA" "$REVIEW_COMMENTS_FILE" "$OUTPUT_JSONL" <<'PY'
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

repo_identity, pr_number_raw, head_sha, comments_path, output_path = sys.argv[1:]

if repo_identity.count("/") < 2:
    print("JEV_STATUS=FALLBACK_INVALID_REPO")
    print("JEV_FALLBACK_REQUIRED=1")
    raise SystemExit(0)

try:
    pr_number = int(pr_number_raw)
    if pr_number <= 0:
        raise ValueError
except ValueError:
    print("JEV_STATUS=FALLBACK_INVALID_PR")
    print("JEV_FALLBACK_REQUIRED=1")
    raise SystemExit(0)

url = (os.environ.get("JEV_TRIAGE_URL") or "").strip()
token = os.environ.get("JEV_TRIAGE_TOKEN") or ""
min_conf_raw = (os.environ.get("JEV_MIN_CONFIDENCE") or "0.80").strip()

try:
    min_confidence = float(min_conf_raw)
    if not 0 <= min_confidence <= 1:
        raise ValueError
except ValueError:
    min_confidence = None

output = Path(output_path)
if output.parent != Path("."):
    output.parent.mkdir(parents=True, exist_ok=True)
output.write_text("", encoding="utf-8")

if not url or not token:
    print("JEV_STATUS=SKIPPED_UNCONFIGURED")
    print("JEV_OBSERVED_COUNT=0")
    print("JEV_FALLBACK_REQUIRED=1")
    raise SystemExit(0)

if min_confidence is None:
    print("JEV_STATUS=FALLBACK_INVALID_CONFIDENCE")
    print("JEV_OBSERVED_COUNT=0")
    print("JEV_FALLBACK_REQUIRED=1")
    raise SystemExit(0)

try:
    raw = json.loads(Path(comments_path).read_text(encoding="utf-8"))
except Exception:
    print("JEV_STATUS=FALLBACK_INVALID_REVIEW_JSON")
    print("JEV_OBSERVED_COUNT=0")
    print("JEV_FALLBACK_REQUIRED=1")
    raise SystemExit(0)

comments = []
if isinstance(raw, list):
    for item in raw:
        if isinstance(item, list):
            comments.extend(x for x in item if isinstance(x, dict))
        elif isinstance(item, dict):
            comments.append(item)
elif isinstance(raw, dict):
    comments.append(raw)

allowed_logins = {
    "chatgpt-codex-connector",
    "chatgpt-codex-connector[bot]",
}

current = []
for comment in comments:
    user = comment.get("user") or {}
    login = str(user.get("login") or "").lower()
    actor_type = str(user.get("type") or "")
    if login not in allowed_logins or actor_type != "Bot":
        continue
    if str(comment.get("commit_id") or "") != head_sha:
        continue
    body = comment.get("body")
    comment_id = comment.get("id")
    if not isinstance(body, str) or not body.strip() or not comment_id:
        continue
    current.append(comment)

if not current:
    print("JEV_STATUS=NO_CURRENT_CODEX_COMMENTS")
    print("JEV_OBSERVED_COUNT=0")
    print("JEV_FALLBACK_REQUIRED=0")
    raise SystemExit(0)

endpoint = url.rstrip("/")
if not endpoint.endswith("/triage"):
    endpoint += "/triage"

repo_path = repo_identity.split("/", 1)[1]
records = []

def candidate_for(result):
    decision = result.get("decision")
    category = result.get("category")
    priority = result.get("priority")
    auto_fixable = result.get("auto_fixable")
    high_risk = result.get("high_risk")

    if high_risk is True or category == "security" or priority in {"p0", "p1"}:
        return "BLOCKING"
    if decision == "no_action":
        return "DISMISS"
    if decision == "action_required" and priority == "p3":
        return "FOLLOW-UP"
    if decision == "action_required" and priority == "p2":
        return "IN-SCOPE FIX" if auto_fixable is True else "FOLLOW-UP"
    return None

def fallback_record(comment_id, reason, candidate=None):
    return {
        "comment_id": str(comment_id),
        "model": "typesafe/jev",
        "mode": "shadow",
        "decision": "undecided",
        "category": None,
        "priority": None,
        "auto_fixable": None,
        "high_risk": None,
        "confidence": None,
        "jev_disposition_candidate": candidate,
        "authoritative": False,
        "effective_disposition_source": "baseline",
        "fallback_required": True,
        "fallback_reason": reason,
        "latency_ms": None,
        "usage": None,
        "comparison": None,
    }

for comment in current:
    comment_id = str(comment.get("id"))
    payload = {
        "comment_id": comment_id,
        "body": comment.get("body"),
        "path": comment.get("path") if isinstance(comment.get("path"), str) else None,
        "line": comment.get("line") if isinstance(comment.get("line"), int) and comment.get("line") > 0 else None,
        "diff_hunk": comment.get("diff_hunk") if isinstance(comment.get("diff_hunk"), str) else None,
        "repository": repo_path,
        "pull_request": pr_number,
        "head_sha": head_sha,
    }

    request = urllib.request.Request(
        endpoint,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        method="POST",
        headers={
            "content-type": "application/json",
            "authorization": "Bearer " + token,
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            response_body = response.read()
        decoded = json.loads(response_body.decode("utf-8"))
        result = decoded.get("result") if isinstance(decoded, dict) else None
        if not isinstance(result, dict):
            records.append(fallback_record(comment_id, "malformed_response"))
            continue
    except urllib.error.HTTPError as exc:
        records.append(fallback_record(comment_id, "http_" + str(exc.code)))
        continue
    except Exception:
        records.append(fallback_record(comment_id, "api_failure"))
        continue

    candidate = candidate_for(result)
    confidence = result.get("confidence")
    fallback_reason = None

    if result.get("final_result") == "fallback":
        fallback_reason = result.get("fallback_reason") or "jev_fallback"
    elif result.get("mode") != "shadow":
        fallback_reason = "non_shadow_response"
    elif result.get("high_risk") is True or result.get("category") == "security" or result.get("priority") in {"p0", "p1"}:
        fallback_reason = "high_risk"
    elif not isinstance(confidence, (int, float)) or isinstance(confidence, bool) or confidence < min_confidence:
        fallback_reason = "low_confidence"
    elif result.get("decision") == "undecided" or candidate is None:
        fallback_reason = "undecided"

    records.append({
        "comment_id": comment_id,
        "model": result.get("model") if isinstance(result.get("model"), str) else "typesafe/jev",
        "mode": result.get("mode"),
        "decision": result.get("decision"),
        "category": result.get("category"),
        "priority": result.get("priority"),
        "auto_fixable": result.get("auto_fixable"),
        "high_risk": result.get("high_risk"),
        "confidence": confidence if isinstance(confidence, (int, float)) and not isinstance(confidence, bool) else None,
        "jev_disposition_candidate": candidate,
        "authoritative": False,
        "effective_disposition_source": "baseline",
        "fallback_required": fallback_reason is not None,
        "fallback_reason": fallback_reason,
        "latency_ms": result.get("latency_ms") if isinstance(result.get("latency_ms"), (int, float)) else None,
        "usage": result.get("usage") if isinstance(result.get("usage"), dict) else None,
        "comparison": result.get("comparison") if isinstance(result.get("comparison"), dict) else None,
    })

with output.open("a", encoding="utf-8") as handle:
    for record in records:
        handle.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")

counts = {
    "BLOCKING": 0,
    "IN-SCOPE FIX": 0,
    "FOLLOW-UP": 0,
    "DISMISS": 0,
}
fallback_count = 0
for record in records:
    candidate = record.get("jev_disposition_candidate")
    if candidate in counts:
        counts[candidate] += 1
    if record.get("fallback_required"):
        fallback_count += 1

print("JEV_STATUS=SHADOW_COMPLETE")
print("JEV_OBSERVED_COUNT=" + str(len(records)))
print("JEV_BLOCKING_CANDIDATE_COUNT=" + str(counts["BLOCKING"]))
print("JEV_IN_SCOPE_FIX_CANDIDATE_COUNT=" + str(counts["IN-SCOPE FIX"]))
print("JEV_FOLLOW_UP_CANDIDATE_COUNT=" + str(counts["FOLLOW-UP"]))
print("JEV_DISMISS_CANDIDATE_COUNT=" + str(counts["DISMISS"]))
print("JEV_FALLBACK_COUNT=" + str(fallback_count))
print("JEV_FALLBACK_REQUIRED=" + ("1" if fallback_count else "0"))
print("JEV_LOG=" + str(output))
PY
