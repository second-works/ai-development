import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { deriveRoute, runDecisionLayer } from "../../templates/review-comment-auto-triage/src/decision-layer.mjs";
import worker from "../../templates/review-comment-auto-triage/src/index.mjs";

const input = {
  comment_id: "review-1",
  body: "This branch can return an incorrect state after the retry.",
  path: "src/retry.js",
  line: 42,
  diff_hunk: "@@ -40,3 +40,3 @@",
  repository: "second-works/example",
  pull_request: 12,
  head_sha: "abc123",
  existing_decision: {
    decision: "action_required",
    category: "style",
    priority: "p2",
    auto_fixable: true,
  },
};

function response(overrides = {}) {
  return {
    model: "jev-test",
    answers: {
      needs_action: { type: "noul", noul: 0.95 },
      category: { type: "choice", choice: "bug", confidence: 0.9 },
      priority: { type: "choice", choice: "p2", confidence: 0.9 },
      auto_fixable: { type: "noul", noul: 0.9 },
      high_risk: { type: "noul", noul: 0.05 },
      ...overrides,
    },
    usage: { input_tokens: 426, output_tokens: 73 },
  };
}

const clock = { now: (() => { let value = 10; return () => (value += 7); })() };

test("shadow mode records a decision without routing to Codex", async () => {
  const result = await runDecisionLayer({
    env: { AI: { run: async () => response() } },
    input,
    clock,
  });

  assert.equal(result.mode, "shadow");
  assert.equal(result.routed_to, "record_only");
  assert.equal(result.suggested_route, "record_only");
  assert.equal(result.final_result, "shadow_observation");
  assert.deepEqual(result.usage, { input_tokens: 426, output_tokens: 73 });
  assert.equal(result.neuron_usage.status, "unavailable");
  assert.deepEqual(result.comparison.disagreements, ["category"]);
});

test("token usage outside the schema contract is normalized to null", async () => {
  const aiResponse = response();
  aiResponse.usage = { input_tokens: -1, output_tokens: 1.5 };
  const result = await runDecisionLayer({
    env: { AI: { run: async () => aiResponse } },
    input,
    clock,
  });

  assert.deepEqual(result.usage, { input_tokens: null, output_tokens: null });
});

test("limited automation routes only safe, confident, auto-fixable work", async () => {
  const result = await runDecisionLayer({
    env: { AI: { run: async () => response() } },
    input: { ...input, existing_decision: null },
    mode: "limited_automation",
    minConfidence: 0.8,
    clock,
  });

  assert.equal(result.routed_to, "codex");
  assert.equal(result.final_result, "routed");
});

test("neutral auto-fixability routes to a human fallback", async () => {
  const result = await runDecisionLayer({
    env: { AI: { run: async () => response({ auto_fixable: { type: "noul", noul: 0.5 } }) } },
    input: { ...input, existing_decision: null },
    mode: "limited_automation",
    minConfidence: 0.5,
  });
  assert.equal(result.decision, "action_required");
  assert.equal(result.auto_fixable, null);
  assert.equal(result.routed_to, "human");
});

test("high-risk comments always route to a human", async () => {
  const result = await runDecisionLayer({
    env: { AI: { run: async () => response({ category: { type: "choice", choice: "security", confidence: 0.99 } }) } },
    input: { ...input, existing_decision: null },
    mode: "limited_automation",
    minConfidence: 0.1,
    clock,
  });

  assert.equal(result.routed_to, "human");
  assert.equal(result.suggested_route, "human");
  assert.equal(result.fallback_reason, "high_risk");
});

test("high-risk noul output routes to a human even when other fields look safe", async () => {
  const result = await runDecisionLayer({
    env: {
      AI: {
        run: async () => response({
          high_risk: { type: "noul", noul: 0.99 },
        }),
      },
    },
    input: { ...input, existing_decision: null },
    mode: "limited_automation",
    minConfidence: 0.1,
    clock,
  });

  assert.equal(result.high_risk, true);
  assert.equal(result.routed_to, "human");
  assert.equal(result.fallback_reason, "high_risk");
});

test("undecided comments route to a human fallback", async () => {
  const result = await runDecisionLayer({
    env: {
      AI: {
        run: async () => response({
          needs_action: { type: "noul", noul: 0.5 },
        }),
      },
    },
    input: { ...input, existing_decision: null },
    mode: "limited_automation",
    minConfidence: 0.1,
    clock,
  });

  assert.equal(result.decision, "undecided");
  assert.equal(result.routed_to, "human");
  assert.equal(result.fallback_reason, "low_confidence");
});

test("high-risk no-action comments route to a human before no-action recording", async () => {
  const result = await runDecisionLayer({
    env: {
      AI: {
        run: async () => response({
          needs_action: { type: "noul", noul: 0.1 },
          high_risk: { type: "noul", noul: 0.99 },
        }),
      },
    },
    input: { ...input, existing_decision: null },
    mode: "limited_automation",
    minConfidence: 0.1,
    clock,
  });

  assert.equal(result.decision, "no_action");
  assert.equal(result.high_risk, true);
  assert.equal(result.routed_to, "human");
  assert.equal(result.fallback_reason, "high_risk");
});

test("low confidence is an explicit fallback in limited automation", async () => {
  const result = await runDecisionLayer({
    env: {
      AI: {
        run: async () => response({
          needs_action: { type: "noul", noul: 0.6 },
          category: { type: "choice", choice: "bug", confidence: 0.6 },
          priority: { type: "choice", choice: "p2", confidence: 0.6 },
          auto_fixable: { type: "noul", noul: 0.6 },
          high_risk: { type: "noul", noul: 0.1 },
        }),
      },
    },
    input: { ...input, existing_decision: null },
    mode: "limited_automation",
    minConfidence: 0.8,
    clock,
  });

  assert.equal(result.routed_to, "human");
  assert.equal(result.fallback_reason, "low_confidence");
});

test("API failure falls back without exposing the comment body", async () => {
  const result = await runDecisionLayer({
    env: { AI: { run: async () => { throw new Error("upstream failure"); } } },
    input,
    clock,
  });

  assert.equal(result.final_result, "fallback");
  assert.equal(result.fallback_reason, "api_failure");
  assert.equal(result.routed_to, "human");
  assert.equal(JSON.stringify(result).includes(input.body), false);
});

test("invalid route configuration fails closed", async () => {
  const result = await runDecisionLayer({
    env: { AI: { run: async () => response() } },
    input,
    mode: "limited_automation",
    minConfidence: null,
    clock,
  });

  assert.equal(result.final_result, "fallback");
  assert.equal(result.fallback_reason, "invalid_route_config");
});

test("non-finite route configuration fails closed", async () => {
  const result = await runDecisionLayer({
    env: { AI: { run: async () => response() } },
    input,
    mode: "limited_automation",
    minConfidence: Number.NaN,
    clock,
  });

  assert.equal(result.final_result, "fallback");
  assert.equal(result.fallback_reason, "invalid_route_config");
});

test("invalid input preserves the active execution mode in the fallback", async () => {
  const result = await runDecisionLayer({
    env: { AI: { run: async () => response() } },
    input: { body: "missing comment id" },
    mode: "limited_automation",
    minConfidence: 0.1,
    clock,
  });

  assert.equal(result.mode, "limited_automation");
  assert.equal(result.final_result, "fallback");
  assert.equal(result.fallback_reason, "invalid_comment_id");
});

test("invalid choice output falls back as an unparseable response", async () => {
  const result = await runDecisionLayer({
    env: {
      AI: {
        run: async () => response({
          category: { type: "choice", choice: "garbage", confidence: 0.99 },
        }),
      },
    },
    input,
    mode: "limited_automation",
    minConfidence: 0.1,
    clock,
  });

  assert.equal(result.final_result, "fallback");
  assert.equal(result.fallback_reason, "unparseable_response");
  assert.equal(result.routed_to, "human");
});

test("route derivation never auto-routes security or high priority comments", () => {
  assert.equal(deriveRoute({
    decision: "action_required",
    category: "security",
    priority: "p3",
    autoFixable: true,
    confidence: 1,
    minConfidence: 0.1,
  }), "human");
  assert.equal(deriveRoute({
    decision: "action_required",
    category: "bug",
    priority: "p1",
    autoFixable: true,
    confidence: 1,
    minConfidence: 0.1,
  }), "human");
  assert.equal(deriveRoute({
    decision: "action_required",
    category: "bug",
    priority: "p2",
    autoFixable: true,
    highRisk: true,
    confidence: 1,
    minConfidence: 0.1,
  }), "human");
  assert.equal(deriveRoute({
    decision: "undecided",
    category: "bug",
    priority: "p2",
    autoFixable: true,
    highRisk: false,
    confidence: 1,
    minConfidence: 0.1,
  }), "human");
  assert.equal(deriveRoute({
    decision: "no_action",
    category: "bug",
    priority: "p2",
    autoFixable: true,
    highRisk: true,
    confidence: 1,
    minConfidence: 0.1,
  }), "human");
  assert.equal(deriveRoute({
    decision: "no_action",
    category: "bug",
    priority: "p2",
    autoFixable: true,
    highRisk: false,
    confidence: 0.5,
    minConfidence: 0.8,
  }), "human");
  assert.equal(deriveRoute({
    decision: "action_required",
    category: "bug",
    priority: "p2",
    autoFixable: true,
    highRisk: false,
    confidence: 1,
    minConfidence: Number.NaN,
  }), "human");
});

test("decision result schema declares the complete audit contract", () => {
  const schema = JSON.parse(readFileSync("templates/review-comment-auto-triage/decision-result.schema.json", "utf8"));
  assert.equal(schema.additionalProperties, false);
  for (const field of ["comment_id", "decision", "confidence", "latency_ms", "usage", "neuron_usage", "comparison"]) {
    assert.equal(schema.required.includes(field), true, field);
  }
  assert.deepEqual(schema.properties.mode.enum, ["shadow", "limited_automation"]);
});

test("worker endpoint accepts a bounded comment and keeps Shadow Mode", async () => {
  const request = new Request("https://example.test/triage", {
    method: "POST",
    body: JSON.stringify(input),
    headers: { "content-type": "application/json" },
  });
  const responseFromWorker = await worker.fetch(request, {
    AI: { run: async () => response() },
  });
  const body = await responseFromWorker.json();

  assert.equal(responseFromWorker.status, 200);
  assert.equal(body.result.routed_to, "record_only");
});

test("worker endpoint rejects an oversized request before inference", async () => {
  const request = new Request("https://example.test/triage", {
    method: "POST",
    body: JSON.stringify({ comment_id: "large", body: "x".repeat(65 * 1024) }),
  });
  const responseFromWorker = await worker.fetch(request, { AI: { run: async () => response() } });

  assert.equal(responseFromWorker.status, 400);
  assert.deepEqual(await responseFromWorker.json(), { error: "request_too_large" });
});

test("worker endpoint rejects a blank limited-automation confidence threshold", async () => {
  let inferenceCalled = false;
  const request = new Request("https://example.test/triage", {
    method: "POST",
    body: JSON.stringify(input),
    headers: { "content-type": "application/json" },
  });
  const responseFromWorker = await worker.fetch(request, {
    TRIAGE_MODE: "limited_automation",
    MIN_CONFIDENCE: " ",
    AI: { run: async () => { inferenceCalled = true; return response(); } },
  });
  const body = await responseFromWorker.json();

  assert.equal(responseFromWorker.status, 502);
  assert.equal(body.result.fallback_reason, "invalid_route_config");
  assert.equal(inferenceCalled, false);
});
