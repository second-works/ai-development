import { runDecisionLayer } from "./decision-layer.mjs";

const MAX_REQUEST_BYTES = 64 * 1024;

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

async function readBoundedJson(request) {
  const reader = request.body?.getReader();
  if (!reader) throw new Error("missing_body");

  const chunks = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > MAX_REQUEST_BYTES) throw new Error("request_too_large");
    chunks.push(value);
  }

  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return JSON.parse(new TextDecoder().decode(bytes));
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method !== "POST" || url.pathname !== "/triage") {
      return json({ error: "not_found" }, 404);
    }

    let input;
    try {
      input = await readBoundedJson(request);
    } catch (error) {
      const reason = error instanceof SyntaxError ? "invalid_json" : error.message;
      return json({ error: reason || "invalid_request" }, 400);
    }

    const mode = env.TRIAGE_MODE === "limited_automation" ? "limited_automation" : "shadow";
    const rawMinConfidence = env.MIN_CONFIDENCE;
    const minConfidence = rawMinConfidence === undefined
      ? null
      : typeof rawMinConfidence === "string" && rawMinConfidence.trim() === ""
        ? Number.NaN
        : Number(rawMinConfidence);
    const result = await runDecisionLayer({ env, input, mode, minConfidence });
    return json({ result }, result.final_result === "fallback" ? 502 : 200);
  },
};
