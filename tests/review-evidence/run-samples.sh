#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
REVIEW_FILE="${ROOT_DIR}/docs/code-review-contract.md"
SKILL_FILE="${ROOT_DIR}/.agents/skills/pr-review-fix/SKILL.md"
FLOW_FILE="${ROOT_DIR}/docs/nine-standard-ai-development-flow.md"
README_FILE="${ROOT_DIR}/README.md"
GUIDE_FILE="${ROOT_DIR}/docs/template-guide.md"

assert_contains() {
  local file="$1"
  local marker="$2"
  grep -Fq -- "$marker" "$file" || {
    printf 'missing review evidence contract marker in %s: %s\n' "$file" "$marker" >&2
    exit 1
  }
}

assert_absent() {
  local file="$1"
  local marker="$2"
  if grep -Fq -- "$marker" "$file"; then
    printf 'obsolete review policy marker remains in %s: %s\n' "$file" "$marker" >&2
    exit 1
  fi
}

for file in "$REVIEW_FILE" "$SKILL_FILE"; do
  for marker in \
    'Review Evidence Contract' \
    'Finding ID:' \
    'Location:' \
    'Claim:' \
    'Trigger:' \
    'Expected:' \
    'Actual:' \
    'PR Causality:' \
    'Acceptance Criteria:' \
    'Reproduction:' \
    'Confidence:' \
    'Disposition:' \
    '決定的な静的根拠' \
    'Evidence不足' \
    'BLOCKING / IN-SCOPE FIX / FOLLOW-UP / DISMISS' \
    '非BLOCKING P2' \
    'Rule Promotion'; do
    assert_contains "$file" "$marker"
  done
done

for marker in \
  'Review Evidence Contract' \
  '`BLOCKING` 判定には' \
  'Evidence不足の指摘をSeverityだけでBLOCKING扱いにしない' \
  '決定的な静的根拠' \
  '非BLOCKING P2の残置に個別の人間承認を要求しない'; do
  assert_contains "$FLOW_FILE" "$marker"
done

# The PR template and AGENTS.md are now the lightweight ones (#197). Their safety
# wording is checked in tests/lightweight-template.


for file in "$REVIEW_FILE" "$SKILL_FILE" "$FLOW_FILE" "$README_FILE" "$GUIDE_FILE"; do
  assert_absent "$file" 'P2は原則としてMerge前に修正する。残す場合は人間が理由を確認して明示判断する。'
  assert_absent "$file" 'P2のみ残る場合は人間の理由確認と明示判断が必要である。'
  assert_absent "$file" 'P2が0件、または残置理由を人間が明示判断'
  assert_absent "$file" 'P2のみ残る場合は人間の明示判断が必要です。'
  assert_absent "$file" '新しいP1 / P2'
  assert_absent "$file" '新しいP0 / P1 / P2がないことを確認する。'
  assert_absent "$file" 'P2は解消または人間が残置理由を確認済みか'
done

# READMEから開始しても、PR前の検証とレビューを逆転・省略しない。
python3 - "$README_FILE" <<'PYREADME'
from pathlib import Path
import re, sys
text = Path(sys.argv[1]).read_text()

def valid_flow(text):
    parts = text.split('## 標準フロー\n', 1)
    if len(parts) != 2:
        return False
    flow = parts[1].split('\n## ', 1)[0]
    steps = re.findall(r'^\d+\. (.+)$', flow, re.M)
    markers = ('標準検証を実行', 'Pre-PR Review', 'PR作成後')
    positions = []
    for marker in markers:
        matches = [i for i, step in enumerate(steps) if marker in step]
        if len(matches) != 1:
            return False
        positions.append(matches[0])
    if not positions[0] < positions[1] < positions[2]:
        return False
    review = steps[positions[1]]
    return all(marker in review for marker in (
        '必要修正 → 再verify → 重大問題なし',
        '重大問題・検証不能時',
        'commit・PR作成・レビュー依頼へ進まず停止する',
    ))

assert valid_flow(text), 'README must verify and self-review before PR, stopping on failure'
review_line = next(line for line in text.splitlines() if re.match(r'^\d+\. Pre-PR Review', line))
pr_line = next(line for line in text.splitlines() if re.match(r'^\d+\. PR作成後', line))
assert not valid_flow(text.replace(review_line, '')), 'missing Pre-PR Review must fail'
swapped = text.replace(review_line, '__REVIEW_STEP__').replace(pr_line, review_line).replace('__REVIEW_STEP__', pr_line)
assert not valid_flow(swapped), 'PR before self-review must fail'
assert not valid_flow(text.replace('重大問題・検証不能時', '確認事項がある場合')), 'missing failure stop must fail'
print('README Pre-PR order: positive and 3 negative cases PASS')
PYREADME

printf 'Review Evidence documentation contract passed\n'
