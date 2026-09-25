import contextlib
import copy
import http.client
import importlib.util
import io
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import textwrap
import threading
import time
import unittest
from unittest.mock import patch
from http.server import BaseHTTPRequestHandler, HTTPServer

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "templates/review-comment-auto-triage"))
from local_judge.contract import (FIELDS, MODEL, OPTIONS, Invalid, compare, loads,
                                 validate_decision, validate_input, validate_local)
from local_judge.providers import BaselineProvider, JevProvider, LocalJudgeProvider
from local_judge.evaluate import join, summary
from local_judge.benchmark import run as benchmark_run
from local_judge.server import Judge, backend_url, decode_probabilities, make_server
from local_judge.transport import request_json

spec = importlib.util.spec_from_file_location("runner", ROOT / ".agents/skills/pr-review-fix/scripts/triage-with-providers.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

REVIEW = {"comment_id": "153", "body": "REVIEW-PRIVATE-MARKER Fix missing check.", "diff_hunk": "DIFF-PRIVATE-MARKER"}
SECRET = "TEST-ONLY-PRIVATE-TOKEN-1234567890123456"
ENV = {"LOCAL_JUDGE_URL": "https://judge.example.invalid/triage",
       "LOCAL_JUDGE_HOST": "judge.example.invalid", "LOCAL_JUDGE_TOKEN": SECRET,
       "LOCAL_JUDGE_ACCESS_CLIENT_ID": "test-client-id", "LOCAL_JUDGE_ACCESS_CLIENT_SECRET": "test-client-secret"}
DECISION = {"needs_action": True, "category": "bug", "priority": "p2", "auto_fixable": True, "high_risk": False}


def result(decision=None):
    decision = decision or DECISION
    probabilities = {}
    for field, options in OPTIONS.items():
        probabilities[field] = {key: (0.9 if value == decision[field] else 0.1 / (len(options) - 1))
                                for key, value in options.items()}
    return {"comment_id": "153", "model": MODEL, "mode": "shadow", "authoritative": False,
            "decision": dict(decision), "probabilities": probabilities, "latency_ms": 12.5,
            "field_latency_ms": dict.fromkeys(FIELDS, 2.5), "cache_prompt": True,
            "cache_tokens": dict.fromkeys(FIELDS, 100), "probability_kind": "constrained_distribution"}


class ContractTests(unittest.TestCase):
    def test_local_schema_rejects_untrusted_values(self):
        validate_local(result(), "153")
        mutations = [
            lambda r: r.update(authoritative=True), lambda r: r.update(mode="limited_automation"),
            lambda r: r.update(model="secret-model"), lambda r: r.update(comment_id="154"),
            lambda r: r.update(extra="secret"), lambda r: r.update(latency_ms=float("nan")),
            lambda r: r["decision"].update(needs_action=1), lambda r: r["decision"].update(category=[]),
            lambda r: r["decision"].update(high_risk=None), lambda r: r["decision"].update(priority="P2"),
            lambda r: r["probabilities"]["category"].update(A=-1),
            lambda r: r["probabilities"]["category"].update(A=True),
            lambda r: r["probabilities"]["category"].update(A=float("inf")),
            lambda r: r["probabilities"]["category"].update(X=0),
            lambda r: r["probabilities"]["category"].pop("A"),
            lambda r: r["probabilities"]["category"].update(A=0.5),
            lambda r: r["decision"].update(category="docs"),
            lambda r: r["cache_tokens"].update(category=True),
            lambda r: r["field_latency_ms"].update(priority="secret"),
        ]
        for mutate in mutations:
            with self.subTest(mutation=mutate):
                raw = result()
                mutate(raw)
                with self.assertRaises((Invalid, TypeError)):
                    validate_local(raw, "153")

    def test_duplicate_json_and_nonfinite_are_rejected(self):
        for raw in ('{"a":1,"a":2}', '{"a":NaN}', '{"a":Infinity}'):
            with self.assertRaises(Invalid):
                loads(raw)

    def test_input_is_not_a_generation_proxy(self):
        validate_input(REVIEW)
        for key in ("model", "endpoint", "tools", "n_predict", "grammar", "prompt"):
            with self.assertRaises(Invalid):
                validate_input({**REVIEW, key: "untrusted"})
        for body in ("", " ", 1, "界" * 2001):
            with self.assertRaises(Invalid):
                validate_input({**REVIEW, "body": body})

    def test_probability_is_distinct_from_jev_confidence(self):
        provider = LocalJudgeProvider(ENV, transport=lambda *_a, **_k: {"result": result()})
        record = provider.observe(REVIEW)
        self.assertIsNone(record["confidence"])
        self.assertEqual(record["probabilities"], result()["probabilities"])
        self.assertFalse(record["fallback_required"])
        self.assertFalse(record["authoritative"])
        self.assertEqual(record["effective_disposition_source"], "baseline")

    def test_local_failure_never_changes_baseline(self):
        baseline = BaselineProvider({"153": DECISION}).observe(REVIEW)
        for reply in ({"result": {"body": SECRET}}, {"result": result(), "extra": SECRET}, []):
            record = LocalJudgeProvider(ENV, transport=lambda *_a, **_k: reply).observe(REVIEW)
            self.assertTrue(record["fallback_required"])
            self.assertNotIn(SECRET, json.dumps(record))
            self.assertEqual(baseline["decision"], DECISION)
            self.assertFalse(record["authoritative"])
        for reason in ("timeout", "http_error", "unavailable", "response_too_large"):
            def failed(*_a, **_k):
                raise Invalid(reason)
            self.assertEqual(LocalJudgeProvider(ENV, failed).observe(REVIEW)["fallback_reason"], reason)

    def test_disabled_provider_does_not_call_network(self):
        def forbidden(*_a, **_k):
            self.fail("network called while disabled")
        self.assertEqual(LocalJudgeProvider({}, forbidden).observe(REVIEW)["fallback_reason"], "unconfigured")
        self.assertEqual(BaselineProvider({"153": DECISION}).observe(REVIEW)["decision"], DECISION)

    def test_allowlist_rejects_credential_destinations(self):
        bad_urls = ("http://judge.example.invalid/triage", "https://evil.example/triage",
                    "https://judge.example.invalid:444/triage", "https://judge.example.invalid/completion",
                    "https://user@judge.example.invalid/triage", "https://judge.example.invalid/triage?x=1",
                    "https://judge.example.invalid/triage#x")
        for url in bad_urls:
            with self.subTest(url=url):
                def forbidden(*_a, **_k):
                    self.fail("credential destination was not rejected")
                self.assertEqual(LocalJudgeProvider({**ENV, "LOCAL_JUDGE_URL": url}, forbidden)
                                 .observe(REVIEW)["fallback_reason"], "invalid_config")
        for value in ("nan", "inf", "-1", "1.01", "garbage"):
            record = LocalJudgeProvider({**ENV, "LOCAL_JUDGE_MIN_CONFIDENCE": value}).observe(REVIEW)
            self.assertEqual(record["fallback_reason"], "invalid_config")

    def test_high_risk_and_low_confidence_are_metadata_fallbacks(self):
        for field, value in (("category", "security"), ("priority", "p0"), ("priority", "p1"), ("high_risk", True)):
            raw = result({**DECISION, field: value})
            record = LocalJudgeProvider(ENV, lambda *_a, **_k: {"result": raw}).observe(REVIEW)
            self.assertEqual(record["fallback_reason"], "high_risk")
            self.assertFalse(record["authoritative"])
        record = LocalJudgeProvider({**ENV, "LOCAL_JUDGE_MIN_CONFIDENCE": "0.95", "JEV_MIN_CONFIDENCE": "0"},
                                    lambda *_a, **_k: {"result": result()}).observe(REVIEW)
        self.assertEqual(record["fallback_reason"], "low_confidence")

    def test_comparison_tracks_false_negatives_in_all_five_fields(self):
        baseline = {**DECISION, "category": "security", "high_risk": True}
        local = {**DECISION, "needs_action": False}
        comparison = compare(local, baseline)
        self.assertTrue(comparison["false_negative"])
        self.assertTrue(comparison["blocking_false_negative"])
        self.assertTrue(comparison["security_false_negative"])
        self.assertIn("high_risk", comparison["disagreements"])
        self.assertIsNone(compare(local, None))

    def test_legacy_jev_adapts_without_model_impersonation(self):
        raw = {"comment_id": "153", "model": "typesafe/jev", "mode": "shadow",
               "decision": "action_required", **{k: v for k, v in DECISION.items() if k != "needs_action"},
               "confidence": 0.92, "latency_ms": 12, "fallback_required": False,
               "authoritative": False, "effective_disposition_source": "baseline"}
        record = JevProvider({"153": raw}).observe(REVIEW)
        self.assertEqual(record["decision"], DECISION)
        self.assertEqual(record["confidence"], 0.92)
        self.assertIsNone(record["probabilities"])
        for reason in ("credits_exhausted", "spend_limit", "rate_limited", "billing_unavailable"):
            fallback = {**raw, "decision": "undecided", "confidence": None,
                        "latency_ms": None, "fallback_required": True,
                        "fallback_reason": reason}
            adapted = JevProvider({"153": fallback}).observe(REVIEW)
            self.assertTrue(adapted["fallback_required"])
            self.assertEqual(adapted["fallback_reason"], reason)
        raw["model"] = MODEL
        self.assertTrue(JevProvider({"153": raw}).observe(REVIEW)["fallback_required"])

    def test_one_token_five_fields_fixed_parameters_and_cache(self):
        calls = []
        counter = 0
        def transport(url, data=None, **_kwargs):
            nonlocal counter
            payload = json.loads(data) if data else None
            calls.append((url, payload))
            if url.endswith("/v1/models"):
                return {"data": [{"id": MODEL}]}
            if url.endswith("/tokenize"):
                return {"tokens": [ord(payload["content"])]}
            if url.endswith("/apply-template"):
                return {"prompt": "FIXED-TEMPLATE " + payload["messages"][0]["content"]}
            field = FIELDS[counter]
            counter += 1
            probabilities = result()["probabilities"][field]
            token = max(probabilities, key=probabilities.get)
            return {"content": token, "tokens_predicted": 1, "tokens_cached": 20,
                    "completion_probabilities": [{"token": token, "top_probs": [
                        {"token": key, "prob": p} for key, p in probabilities.items()]}]}
        raw = Judge(transport=transport).triage(REVIEW)
        self.assertEqual(raw["decision"], DECISION)
        completions = [data for url, data in calls if url.endswith("/completion")]
        self.assertEqual(len(completions), 5)
        for data in completions:
            self.assertEqual(data["n_predict"], 1)
            self.assertEqual(data["temperature"], 1)
            self.assertTrue(data["post_sampling_probs"])
            self.assertTrue(data["cache_prompt"])
            self.assertNotIn("tools", data)
        self.assertNotIn("REVIEW-PRIVATE-MARKER", json.dumps(raw))
        self.assertNotIn("DIFF-PRIVATE-MARKER", json.dumps(raw))

    def test_wrong_model_or_multi_token_output_fails_closed(self):
        with self.assertRaisesRegex(Invalid, "model_mismatch"):
            Judge(transport=lambda *_a, **_k: {"data": [{"id": "another-model"}]}).triage(REVIEW)
        for value in (2, True, 0):
            with self.assertRaises(Invalid):
                decode_probabilities({"tokens_predicted": value}, "category")
        for url in ("http://example.com:8081", "http://127.0.0.1:8081/completion", "https://127.0.0.1:8081",
                    "http://user@127.0.0.1:8081", "http://127.0.0.1:8081?x=1"):
            with self.assertRaises(Invalid):
                backend_url(url)

    def test_collector_identity_filters_and_three_way_comparison(self):
        sha = "a" * 40
        comment = {"id": 153, "body": REVIEW["body"], "diff_hunk": REVIEW["diff_hunk"], "commit_id": sha,
                   "user": {"type": "Bot", "login": "chatgpt-codex-connector[bot]"}}
        self.assertEqual(runner.current_comments([[comment], [{**comment, "commit_id": "b" * 40}]], sha), [comment])
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            (path / "comments").write_text(json.dumps([comment]))
            (path / "baseline").write_text(json.dumps({"repository": "github.com/o/r", "pr_number": 1,
                                                      "head_sha": sha, "decisions": {"153": DECISION}}))
            with patch.dict(os.environ, {}, clear=True):
                records = runner.collect("github.com/o/r", "1", sha, path / "comments", path / "audit", path / "baseline")
            self.assertEqual({r["provider"] for r in records}, {"jev", "local_judge", "baseline"})
            self.assertEqual(next(r for r in records if r["provider"] == "baseline")["decision"], DECISION)
            audit = (path / "audit").read_text()
            for private in ("REVIEW-PRIVATE-MARKER", "DIFF-PRIVATE-MARKER", SECRET):
                self.assertNotIn(private, audit)
            self.assertTrue(all(r["effective_disposition_source"] == "baseline" and r["authoritative"] is False for r in records))
            with self.assertRaises(Invalid):
                runner.collect("github.com/o/r", "1", "b" * 40, path / "comments", path / "audit", path / "baseline")
            self.assertEqual((path / "audit").read_text(), "")
            original = (path / "comments").read_text()
            with self.assertRaises(Invalid):
                runner.collect("github.com/o/r", "1", sha, path / "comments", path / "comments")
            self.assertEqual((path / "comments").read_text(), original)

    def test_jev_timeout_terminates_shell_child_processes(self):
        with tempfile.TemporaryDirectory() as tmp:
            started = Path(tmp) / "child-started"
            late = Path(tmp) / "child-finished"
            program = (f"import pathlib,time; pathlib.Path({str(started)!r}).touch(); "
                       f"time.sleep(1.5); pathlib.Path({str(late)!r}).write_text('still running')")
            command = ["bash", "-c", "python3 -c " + shlex.quote(program)]
            with self.assertRaises(subprocess.TimeoutExpired):
                runner.run_jev(command, timeout=1)
            self.assertTrue(started.exists())
            time.sleep(1.6)
            self.assertFalse(late.exists(), "timed-out JEV child continued running")

    def test_offline_join_recomputes_comparison_and_rejects_stale_labels(self):
        local = LocalJudgeProvider(ENV, lambda *_a, **_k: {"result": result()}).observe(REVIEW)
        baseline = {"repository": "github.com/o/r", "pr_number": 1, "head_sha": "a" * 40,
                    "decisions": {"153": {**DECISION, "category": "security", "high_risk": True}}}
        local.update({k: baseline[k] for k in ("repository", "pr_number", "head_sha")})
        local["comparison"] = {"baseline": SECRET, "jev": SECRET}
        rows = join([local], baseline)
        report = summary(rows)["local_judge"]
        self.assertEqual(report["error_counts"]["blocking_false_negative"], 1)
        self.assertEqual(report["error_counts"]["security_false_negative"], 1)
        self.assertEqual(report["field_agreement"]["high_risk"], 0)
        self.assertNotIn(SECRET, json.dumps(report))
        self.assertEqual(report["paired_with_jev"], 0)
        with self.assertRaises(Invalid):
            join([local], {**baseline, "head_sha": "b" * 40})
        with self.assertRaises(Invalid):
            join([local, local], baseline)
        for inconsistent in (
            {**local, "fallback_reason": "unavailable"},
            {**local, "fallback_required": True},
            {**local, "fallback_required": True, "fallback_reason": "unknown_reason"},
        ):
            with self.assertRaisesRegex(Invalid, "invalid_input"):
                join([inconsistent], baseline)
        report = summary(join([local], {**baseline, "decisions": {}}))["local_judge"]
        self.assertIsNone(report["field_agreement"]["needs_action"])
        self.assertEqual(report["paired_with_baseline"], 0)

    def test_benchmark_does_not_store_review_or_treat_failure_as_agreement(self):
        class Fake:
            def triage(self, _review):
                return result()
        cases = [{"review": REVIEW, "expected": DECISION}]
        rows = benchmark_run(cases, Fake())
        self.assertEqual(summary(rows)["local_judge"]["paired_with_baseline"], 1)
        self.assertNotIn("REVIEW-PRIVATE-MARKER", json.dumps(rows))
        class Failed:
            def triage(self, _review):
                raise RuntimeError(SECRET)
        rows = benchmark_run(cases, Failed())
        self.assertEqual(summary(rows)["local_judge"]["paired_with_baseline"], 0)
        self.assertIsNone(summary(rows)["local_judge"]["field_agreement"]["category"])
        self.assertNotIn(SECRET, json.dumps(rows))

    def test_candidates_must_cover_the_whole_distribution(self):
        raw = {"tokens_predicted": 1, "content": "A", "completion_probabilities": [{"token": "A",
               "top_probs": [{"token": "A", "prob": 0.978}, {"token": "Option", "prob": 0.007}]}]}
        with self.assertRaises(Invalid):
            decode_probabilities(raw, "needs_action")

    def test_workflow_rejects_untrusted_dispatch_before_secrets(self):
        import re
        import subprocess
        workflow = (ROOT / ".github/workflows/decision-shadow.yml").read_text()
        body = re.search(r'- name: Validate trusted dispatch.*?run: \|\n(.*?)(?=\n      - name:)', workflow, re.S)[1]
        script = textwrap.dedent(body)
        env = {**os.environ, "PR_NUMBER": "1", "HEAD_SHA": "a" * 40,
               "WORKFLOW_REF": "main", "DEFAULT_BRANCH": "main"}
        self.assertEqual(subprocess.run(["bash", "-c", script], env=env).returncode, 0)
        for update in ({"WORKFLOW_REF": "feat/untrusted"}, {"PR_NUMBER": "1;true"},
                       {"PR_NUMBER": "0"}, {"HEAD_SHA": "abc"}):
            self.assertNotEqual(subprocess.run(["bash", "-c", script], env={**env, **update}).returncode, 0)
        self.assertIn("ref: ${{ github.event.repository.default_branch }}", workflow)
        self.assertIn("persist-credentials: false", workflow)
        self.assertIn("environment: local-judge-shadow", workflow)
        self.assertNotIn("pull_request_target:", workflow)
        self.assertNotIn(": write", workflow)
        self.assertEqual(workflow.count("--jq '.head.sha'"), 3)
        self.assertIn("path: ${{ runner.temp }}/shadow-audit.jsonl", workflow)


class HttpTests(unittest.TestCase):
    @contextlib.contextmanager
    def serve(self, server):
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            yield server.server_address[1]
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_api_auth_size_and_parameter_boundary(self):
        class FakeJudge:
            calls = 0
            def triage(self, _review):
                self.calls += 1
                return result()
        judge = FakeJudge()
        with self.serve(make_server(judge, SECRET, port=0)) as port:
            for endpoint, auth, payload, expected in (
                ("/triage", "", REVIEW, 401),
                ("/completion", SECRET, REVIEW, 404),
                ("/triage?prompt=secret", SECRET, REVIEW, 404),
                ("/triage", SECRET, {**REVIEW, "n_predict": 999}, 400),
                ("/triage", SECRET, {**REVIEW, "body": "x" * 17000}, 413),
                ("/triage", SECRET, REVIEW, 200),
            ):
                conn = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
                conn.request("POST", endpoint, json.dumps(payload), {"Content-Type": "application/json", "Authorization": "Bearer " + auth})
                response = conn.getresponse()
                self.assertEqual(response.status, expected)
                text = response.read().decode()
                self.assertNotIn(SECRET, text)
                self.assertNotIn("REVIEW-PRIVATE-MARKER", text)
                conn.close()
        self.assertEqual(judge.calls, 1)

    def test_redirect_never_forwards_any_credential(self):
        observed = []
        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                observed.append((self.path, dict(self.headers)))
                self.send_response(302)
                self.send_header("Location", f"http://127.0.0.1:{self.server.server_address[1]}/stolen")
                self.end_headers()
            def do_GET(self):
                observed.append((self.path, dict(self.headers)))
                self.send_response(200)
                self.end_headers()
            def log_message(self, *_args):
                pass
        with self.serve(HTTPServer(("127.0.0.1", 0), Handler)) as port:
            with self.assertRaisesRegex(Invalid, "http_error"):
                request_json(f"http://127.0.0.1:{port}/triage", data=b"{}", headers={
                    "Authorization": SECRET, "CF-Access-Client-Id": "test-id", "CF-Access-Client-Secret": "test-secret"})
        self.assertEqual(len(observed), 1)
        self.assertEqual(observed[0][0], "/triage")

    def test_response_limit_and_timeout(self):
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path == "/json":
                    self.send_response(200)
                    self.send_header("Content-Length", "2")
                    self.end_headers()
                    self.wfile.write(b"{}")
                    return
                if self.path == "/truncated":
                    self.send_response(200)
                    self.send_header("Content-Length", "200")
                    self.end_headers()
                    self.wfile.write(b"{}")
                    return
                if self.path == "/slow":
                    time.sleep(0.15)
                self.send_response(200)
                self.end_headers()
                try:
                    self.wfile.write(b'"' + b"x" * 10000 + b'"')
                except BrokenPipeError:
                    pass
            def log_message(self, *_args):
                pass
        with self.serve(HTTPServer(("127.0.0.1", 0), Handler)) as port:
            self.assertEqual(request_json(f"http://127.0.0.1:{port}/json"), {})
            with self.assertRaisesRegex(Invalid, "malformed_response"):
                request_json(f"http://127.0.0.1:{port}/truncated")
            with self.assertRaisesRegex(Invalid, "response_too_large"):
                request_json(f"http://127.0.0.1:{port}/large", limit=100)
            with self.assertRaisesRegex(Invalid, "timeout"):
                request_json(f"http://127.0.0.1:{port}/slow", timeout=0.02)


if __name__ == "__main__":
    unittest.main()
