#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

node --check templates/review-comment-auto-triage/src/decision-layer.mjs
node --check templates/review-comment-auto-triage/src/index.mjs
node --test tests/review-comment-auto-triage/test.mjs

grep -Fq 'typesafe/jev' templates/review-comment-auto-triage/src/decision-layer.mjs
grep -Fq 'routed_to: mode === "shadow" ? "record_only"' templates/review-comment-auto-triage/src/decision-layer.mjs
grep -Fq 'neuron_usage: { status: "unavailable"' templates/review-comment-auto-triage/src/decision-layer.mjs
grep -Fq 'MAX_REQUEST_BYTES = 64 * 1024' templates/review-comment-auto-triage/src/index.mjs
grep -Fq '"additionalProperties": false' templates/review-comment-auto-triage/decision-result.schema.json

printf '%s\n' 'review-comment-auto-triage samples: PASS'
