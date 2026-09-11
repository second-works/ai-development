#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
STANDARD="${ROOT_DIR}/docs/product-ui-standard.md"
DESIGN_TEMPLATE="${ROOT_DIR}/templates/app/docs/design.md"
README="${ROOT_DIR}/README.md"

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "${needle}" "${file}"; then
    printf 'missing PRODUCT UI contract: %s in %s\n' "${needle}" "${file}" >&2
    exit 1
  fi
}

for needle in \
  'Nine PRODUCT UI Standard v1' \
  '`NONE`' \
  '`UTILITY`' \
  '`PRODUCT`' \
  '`NEEDS_DECISION`' \
  'User Goal First' \
  'Current State is Visible' \
  'Next Action is Clear' \
  'Invalid States are Prevented Structurally' \
  'Implementation Done != UI Accepted' \
  '## PRODUCT UI Specification' \
  '## Design Profile' \
  'Use:' \
  'Do NOT copy:' \
  'UNKNOWN != ERROR' \
  'EMPTY != ERROR' \
  'UNAVAILABLE != FAILED' \
  '## Responsive Design' \
  '## Accessibility Minimum' \
  '## AI / Codex Design Boundary' \
  '## Visual Review / UI Acceptance' \
  'Plan Review Gate' \
  'Acceptance Verification' \
  'Harness Minimalism / ETCSLV'; do
  assert_contains "${STANDARD}" "${needle}"
done

for needle in \
  '# Product Design' \
  '## Product' \
  '## UI Level' \
  '## Target User / Primary Goal' \
  '## Device Priority' \
  '## Design Direction' \
  '## Visual References' \
  '## Design System' \
  '## Typography' \
  '## Layout' \
  '## Spacing' \
  '## Color Semantics' \
  '## Components' \
  '## UI States' \
  '## Responsive Rules' \
  '## Accessibility' \
  '## Do' \
  "## Don't" \
  '## Open Design Decisions'; do
  assert_contains "${DESIGN_TEMPLATE}" "${needle}"
done

assert_contains "${README}" 'docs/product-ui-standard.md'
assert_contains "${README}" 'templates/app/docs/design.md'

printf 'PRODUCT UI standard contract: ok\n'
