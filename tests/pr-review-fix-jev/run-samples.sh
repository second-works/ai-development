#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
SCRIPT="$ROOT_DIR/.agents/skills/pr-review-fix/scripts/triage-with-jev.sh"
TMP_DIR="$(mktemp -d)"
SERVER_PID=""

cleanup() {
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

COMMENTS="$TMP_DIR/review-comments.json"
LOG="$TMP_DIR/jev.jsonl"
PORT_FILE="$TMP_DIR/port"

cat >"$COMMENTS" <<'JSON'
[
  [
    {
      "id": 101,
      "body": "Safe P2 fix. SECRET-MARKER must never be logged.",
      "path": "src/a.js",
      "line": 10,
      "diff_hunk": "@@ secret-diff-marker @@",
      "commit_id": "abc123",
      "user": {"login": "chatgpt-codex-connector[bot]", "type": "Bot"}
    },
    {
      "id": 102,
      "body": "No action.",
      "path": "src/b.js",
      "line": 20,
      "commit_id": "abc123",
      "user": {"login": "chatgpt-codex-connector", "type": "Bot"}
    },
    {
      "id": 103,
      "body": "P3 suggestion.",
      "path": "src/c.js",
      "line": 30,
      "commit_id": "abc123",
      "user": {"login": "chatgpt-codex-connector[bot]", "type": "Bot"}
    },
    {
      "id": 104,
      "body": "Security boundary.",
      "path": "src/d.js",
      "line": 40,
      "commit_id": "abc123",
      "user": {"login": "chatgpt-codex-connector[bot]", "type": "Bot"}
    },
    {
      "id": 105,
      "body": "Low confidence.",
      "path": "src/e.js",
      "line": 50,
      "commit_id": "abc123",
      "user": {"login": "chatgpt-codex-connector[bot]", "type": "Bot"}
    },
    {
      "id": 106,
      "body": "P0 blocker.",
      "path": "src/f.js",
      "line": 60,
      "commit_id": "abc123",
      "user": {"login": "chatgpt-codex-connector[bot]", "type": "Bot"}
    },
    {
      "id": 107,
      "body": "Unexpected active routing.",
      "path": "src/g.js",
      "line": 70,
      "commit_id": "abc123",
      "user": {"login": "chatgpt-codex-connector[bot]", "type": "Bot"}
    },
    {
      "id": 108,
      "body": "Upstream failure.",
      "path": "src/h.js",
      "line": 80,
      "commit_id": "abc123",
      "user": {"login": "chatgpt-codex-connector[bot]", "type": "Bot"}
    },
    {
      "id": 109,
      "body": "Malformed response.",
      "path": "src/i.js",
      "line": 90,
      "commit_id": "abc123",
      "user": {"login": "chatgpt-codex-connector[bot]", "type": "Bot"}
    },
    {
      "id": 110,
      "body": "Malicious usage payload.",
      "path": "src/j.js",
      "line": 100,
      "commit_id": "abc123",
      "user": {"login": "chatgpt-codex-connector[bot]", "type": "Bot"}
    },
    {
      "id": 111,
      "body": "Malicious comparison payload.",
      "path": "src/k.js",
      "line": 110,
      "commit_id": "abc123",
      "user": {"login": "chatgpt-codex-connector[bot]", "type": "Bot"}
    },
    {
      "id": 112,
      "body": "Mismatched comment id.",
      "path": "src/l.js",
      "line": 120,
      "commit_id": "abc123",
      "user": {"login": "chatgpt-codex-connector[bot]", "type": "Bot"}
    },
    {
      "id": 113,
      "body": "Credits exhausted.",
      "path": "src/m.js",
      "line": 130,
      "commit_id": "abc123",
      "user": {"login": "chatgpt-codex-connector[bot]", "type": "Bot"}
    },
    {
      "id": 114,
      "body": "Spend limit reached.",
      "path": "src/n.js",
      "line": 140,
      "commit_id": "abc123",
      "user": {"login": "chatgpt-codex-connector[bot]", "type": "Bot"}
    },
    {
      "id": 115,
      "body": "Rate limited.",
      "path": "src/o.js",
      "line": 150,
      "commit_id": "abc123",
      "user": {"login": "chatgpt-codex-connector[bot]", "type": "Bot"}
    },
    {
      "id": 116,
      "body": "Billing unavailable.",
      "path": "src/p.js",
      "line": 160,
      "commit_id": "abc123",
      "user": {"login": "chatgpt-codex-connector[bot]", "type": "Bot"}
    },
    {
      "id": 117,
      "body": "429 with a non-fallback JEV body must still use baseline.",
      "path": "src/q.js",
      "line": 170,
      "commit_id": "abc123",
      "user": {"login": "chatgpt-codex-connector[bot]", "type": "Bot"}
    },
    {
      "id": 118,
      "body": "Truncated HTTP error bodies must not abort triage.",
      "path": "src/r.js",
      "line": 180,
      "commit_id": "abc123",
      "user": {"login": "chatgpt-codex-connector[bot]", "type": "Bot"}
    },
    {
      "id": 119,
      "body": "Redirects must not receive the Bearer token.",
      "path": "src/s.js",
      "line": 190,
      "commit_id": "abc123",
      "user": {"login": "chatgpt-codex-connector[bot]", "type": "Bot"}
    },
    {
      "id": 999,
      "body": "Old commit must be ignored.",
      "path": "src/old.js",
      "commit_id": "oldsha",
      "user": {"login": "chatgpt-codex-connector[bot]", "type": "Bot"}
    }
  ]
]
JSON

python3 - "$PORT_FILE" <<'PY' &
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

port_file = sys.argv[1]

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        if self.path != "/triage":
            self.send_response(404)
            self.end_headers()
            return
        if self.headers.get("authorization") != "Bearer test-secret":
            self.send_response(401)
            self.end_headers()
            return
        if self.headers.get("user-agent") != "ai-development-jev-triage/1.0":
            self.send_response(403)
            self.end_headers()
            return
        length = int(self.headers.get("content-length") or "0")
        data = json.loads(self.rfile.read(length))
        cid = str(data["comment_id"])

        if cid == "108":
            self.send_response(503)
            self.end_headers()
            return
        result = {
            "comment_id": cid,
            "model": "typesafe/jev",
            "mode": "shadow",
            "decision": "action_required",
            "category": "bug",
            "priority": "p2",
            "auto_fixable": True,
            "high_risk": False,
            "confidence": 0.95,
            "suggested_route": "record_only",
            "routed_to": "record_only",
            "final_result": "shadow_observation",
            "fallback_reason": None,
            "latency_ms": 12,
            "usage": {"input_tokens": 10, "output_tokens": 5},
            "neuron_usage": {
                "status": "unavailable",
                "reason": "AI.run response exposes token usage, not Neurons",
            },
            "comparison": None,
        }

        if cid == "110":
            result["usage"] = {
                "input_tokens": 10,
                "output_tokens": 5,
                "secret": "SECRET-MARKER-USAGE",
            }
        elif cid == "111":
            result["comparison"] = {
                "baseline_present": True,
                "disagreement_count": 0,
                "disagreements": [],
                "secret": "SECRET-MARKER-COMPARISON",
            }
        elif cid == "112":
            result["comment_id"] = "other-comment"

        if cid in {"113", "114", "115", "116"}:
            reason = {
                "113": "credits_exhausted",
                "114": "spend_limit",
                "115": "rate_limited",
                "116": "billing_unavailable",
            }[cid]
            result.update({
                "decision": "undecided",
                "category": None,
                "priority": None,
                "auto_fixable": None,
                "high_risk": None,
                "confidence": None,
                "suggested_route": "human",
                "routed_to": "human",
                "final_result": "fallback",
                "fallback_reason": reason,
                "usage": None,
                "comparison": None,
            })
            body = json.dumps({"result": result}).encode()
            self.send_response(429 if cid in {"114", "115"} else 502)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if cid == "117":
            # Valid schema, but not an explicit fallback: non-2xx must still
            # force the local HTTP fallback and Codex baseline.
            body = json.dumps({"result": result}).encode()
            self.send_response(429)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if cid == "118":
            # Declare a larger body than is actually sent, then close the
            # connection so HTTPError.read() raises IncompleteRead.
            body = b'{"result":'
            self.send_response(502)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", "9999")
            self.end_headers()
            self.wfile.write(body)
            self.wfile.flush()
            self.close_connection = True
            return

        if cid == "119":
            self.send_response(302)
            self.send_header("location", "http://127.0.0.1:1/should-not-follow")
            self.end_headers()
            return

        if cid == "102":
            result["decision"] = "no_action"
            result["auto_fixable"] = False
        elif cid == "103":
            result["priority"] = "p3"
        elif cid == "104":
            result["category"] = "security"
            result["high_risk"] = True
        elif cid == "105":
            result["confidence"] = 0.40
        elif cid == "106":
            result["priority"] = "p0"
        elif cid == "107":
            result["mode"] = "limited_automation"

        if cid == "109":
            body = json.dumps({"result": result}).replace(
                '"latency_ms": 12',
                '"latency_ms": 1e400',
            ).encode()
            self.send_response(200)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        body = json.dumps({"result": result}).encode()
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

server = HTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w", encoding="utf-8") as f:
    f.write(str(server.server_port))
server.serve_forever()
PY
SERVER_PID=$!

for _ in $(seq 1 50); do
  [[ -s "$PORT_FILE" ]] && break
  sleep 0.05
done
[[ -s "$PORT_FILE" ]] || { echo "mock server failed to start" >&2; exit 1; }

PORT="$(cat "$PORT_FILE")"
export JEV_TRIAGE_URL="http://127.0.0.1:$PORT"
export JEV_TRIAGE_TOKEN="test-secret"
export JEV_MIN_CONFIDENCE="0.80"

OUTPUT="$(bash "$SCRIPT" "github.com/second-works/ai-development" 123 abc123 "$COMMENTS" "$LOG")"
grep -Fq "JEV_STATUS=SHADOW_COMPLETE" <<<"$OUTPUT"
grep -Fq "JEV_OBSERVED_COUNT=19" <<<"$OUTPUT"
grep -Fq "JEV_BLOCKING_CANDIDATE_COUNT=2" <<<"$OUTPUT"
grep -Fq "JEV_IN_SCOPE_FIX_CANDIDATE_COUNT=3" <<<"$OUTPUT"
grep -Fq "JEV_FOLLOW_UP_CANDIDATE_COUNT=1" <<<"$OUTPUT"
grep -Fq "JEV_DISMISS_CANDIDATE_COUNT=1" <<<"$OUTPUT"
grep -Fq "JEV_FALLBACK_COUNT=16" <<<"$OUTPUT"
grep -Fq "JEV_CREDITS_EXHAUSTED_COUNT=1" <<<"$OUTPUT"
grep -Fq "JEV_SPEND_LIMIT_COUNT=1" <<<"$OUTPUT"
grep -Fq "JEV_RATE_LIMITED_COUNT=1" <<<"$OUTPUT"
grep -Fq "JEV_BILLING_UNAVAILABLE_COUNT=1" <<<"$OUTPUT"
grep -Fq "credits_exhausted:1" <<<"$OUTPUT"
grep -Fq "spend_limit:1" <<<"$OUTPUT"
grep -Fq "http_429:1" <<<"$OUTPUT"
grep -Fq "http_502:1" <<<"$OUTPUT"
grep -Fq "http_302:1" <<<"$OUTPUT"

python3 - "$LOG" <<'PY'
import json
import sys

path = sys.argv[1]
records = [json.loads(line) for line in open(path, encoding="utf-8") if line.strip()]
by_id = {r["comment_id"]: r for r in records}

assert len(records) == 19
assert by_id["101"]["jev_disposition_candidate"] == "IN-SCOPE FIX"
assert by_id["101"]["fallback_required"] is False
assert by_id["102"]["jev_disposition_candidate"] == "DISMISS"
assert by_id["103"]["jev_disposition_candidate"] == "FOLLOW-UP"
assert by_id["104"]["jev_disposition_candidate"] == "BLOCKING"
assert by_id["104"]["fallback_reason"] == "high_risk"
assert by_id["105"]["fallback_reason"] == "low_confidence"
assert by_id["106"]["jev_disposition_candidate"] == "BLOCKING"
assert by_id["106"]["fallback_reason"] == "high_risk"
assert by_id["107"]["fallback_reason"] == "non_shadow_response"
assert by_id["108"]["fallback_reason"] == "http_503"
assert by_id["109"]["fallback_reason"] == "malformed_response"
assert by_id["110"]["fallback_reason"] == "malformed_response"
assert by_id["111"]["fallback_reason"] == "malformed_response"
assert by_id["112"]["fallback_reason"] == "malformed_response"
assert by_id["113"]["fallback_reason"] == "credits_exhausted"
assert by_id["114"]["fallback_reason"] == "spend_limit"
assert by_id["115"]["fallback_reason"] == "rate_limited"
assert by_id["116"]["fallback_reason"] == "billing_unavailable"
assert by_id["117"]["fallback_reason"] == "http_429"
assert by_id["117"]["fallback_required"] is True
assert by_id["117"]["jev_disposition_candidate"] is None
assert by_id["118"]["fallback_reason"] == "http_502"
assert by_id["118"]["fallback_required"] is True
assert by_id["118"]["jev_disposition_candidate"] is None
assert by_id["119"]["fallback_reason"] == "http_302"
assert by_id["119"]["fallback_required"] is True
assert by_id["119"]["jev_disposition_candidate"] is None
assert all(by_id[cid]["effective_disposition_source"] == "baseline" for cid in ["113", "114", "115", "116", "117", "118", "119"])
assert by_id["110"]["usage"] is None
assert by_id["111"]["comparison"] is None
assert all(r["authoritative"] is False for r in records)
assert all(r["effective_disposition_source"] == "baseline" for r in records)

text = open(path, encoding="utf-8").read()
for forbidden in [
    "SECRET-MARKER",
    "SECRET-MARKER-USAGE",
    "SECRET-MARKER-COMPARISON",
    "secret-diff-marker",
    "test-secret",
    "authorization",
    "Infinity",
]:
    assert forbidden not in text
PY

unset JEV_TRIAGE_URL
unset JEV_TRIAGE_TOKEN
EMPTY_LOG="$TMP_DIR/unconfigured.jsonl"
UNCONFIGURED="$(bash "$SCRIPT" "github.com/second-works/ai-development" 123 abc123 "$COMMENTS" "$EMPTY_LOG")"
grep -Fq "JEV_STATUS=SKIPPED_UNCONFIGURED" <<<"$UNCONFIGURED"
grep -Fq "JEV_FALLBACK_REQUIRED=1" <<<"$UNCONFIGURED"
[[ ! -s "$EMPTY_LOG" ]]

export JEV_TRIAGE_URL="http://127.0.0.1:$PORT"
export JEV_TRIAGE_TOKEN="test-secret"
export JEV_MIN_CONFIDENCE="not-a-number"
INVALID_CONF="$(bash "$SCRIPT" "github.com/second-works/ai-development" 123 abc123 "$COMMENTS" "$TMP_DIR/invalid-conf.jsonl")"
grep -Fq "JEV_STATUS=FALLBACK_INVALID_CONFIDENCE" <<<"$INVALID_CONF"
grep -Fq "JEV_FALLBACK_REQUIRED=1" <<<"$INVALID_CONF"


SKILL_FILE="$ROOT_DIR/.agents/skills/pr-review-fix/SKILL.md"
for marker in \
  "## JEV Decision Layer" \
  "JEV_TRIAGE_URL" \
  "JEV_TRIAGE_TOKEN" \
  "JEV_MIN_CONFIDENCE" \
  "JEV_FALLBACK_REASONS" \
  "authoritative=false" \
  "effective_disposition_source=baseline" \
  "triage-with-jev.sh" \
  "Shadow Mode" \
  "JEV候補だけを根拠にBLOCKING確定"; do
  grep -Fq -- "$marker" "$SKILL_FILE" || {
    printf 'missing JEV Skill contract marker: %s\n' "$marker" >&2
    exit 1
  }
done

printf 'pr-review-fix JEV shadow integration contract passed\n'

# urllib transport contract
grep -Fq 'USER_AGENT = "ai-development-jev-triage/1.0"' "$SCRIPT"
grep -Fq 'class NoRedirect(urllib.request.HTTPRedirectHandler):' "$SCRIPT"
grep -Fq 'HTTP_OPENER = urllib.request.build_opener(NoRedirect)' "$SCRIPT"
grep -Fq '"user-agent": USER_AGENT' "$SCRIPT"
grep -Fq 'with HTTP_OPENER.open(request, timeout=20) as response:' "$SCRIPT"
if grep -Fq 'urllib.request.urlopen(request' "$SCRIPT"; then
  echo "JEV transport must not use redirect-following urllib.request.urlopen" >&2
  exit 1
fi
