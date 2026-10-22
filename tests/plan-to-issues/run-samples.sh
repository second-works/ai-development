#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
agents="$ROOT/AGENTS.md"
# The repository uses the lightweight Skill (#197); place.sh --check keeps it equal to
# templates/lightweight/.agents/skills/plan-to-issues/SKILL.md.
skill="$ROOT/.agents/skills/plan-to-issues/SKILL.md"

require() {
  local file="$1"
  local needle="$2"
  grep -Fq -- "$needle" "$file" || {
    printf 'missing plan-to-issues contract: %s: %s\n' "$file" "$needle" >&2
    exit 1
  }
}

[[ -f "$skill" ]] || {
  printf 'plan-to-issues Skill is missing: %s\n' "$skill" >&2
  exit 1
}

for path in \
  docs/plan-review-gate.md \
  docs/issue-quality-check.md \
  docs/adaptive-development-flow.md \
  docs/architecture/framework-decision.md \
  .github/ISSUE_TEMPLATE/parent-issue.md \
  .github/ISSUE_TEMPLATE/child-issue.md; do
  [[ -e "$ROOT/$path" ]] || {
    printf 'plan-to-issues canonical source is missing: %s\n' "$path" >&2
    exit 1
  }
done

require "$ROOT/docs/plan-review-gate.md" '### Plan to Issues Routing'
require "$ROOT/docs/plan-review-gate.md" '.agents/skills/plan-to-issues/SKILL.md'
require "$ROOT/docs/plan-review-gate.md" '「この方向でIssue化して」'
require "$ROOT/docs/plan-review-gate.md" '「親Issueと子Issueに分けて」'
require "$ROOT/docs/plan-review-gate.md" '既存Issueの実装・レビュー・コメント確認'
require "$ROOT/docs/plan-review-gate.md" 'Plan ReviewまたはChild Issue Quality Gateの停止条件'

require "$skill" 'name: plan-to-issues'
# Stop instead of guessing, one PR per child Issue, real numbers, and no implementation.
for needle in \
  '登録せずに必要な判断だけを示して止まる' \
  '子Issueは1つにつき1 PRとする' \
  '1 PRで終わるときは、親Issueを作らず単一のIssueにする' \
  'Goal / Context / Scope・Boundaries / Non-goals / Done / Verification / Dependenciesの7項目' \
  'Risk Tier（LOW / MEDIUM / HIGH）と理由' \
  '安全への影響が分からなければHIGH' \
  'ユーザーが登録を依頼したときだけGitHubへ書き込む' \
  '番号は推測しない' \
  'ブランチ作成、実装、PR作成、マージ、次のIssueへの着手はしない'; do
  require "$skill" "$needle"
done


for template in parent child; do
  file="$ROOT/.github/ISSUE_TEMPLATE/$template-issue.md"
  require "$file" 'Risk Tier（LOW / MEDIUM / HIGH）と理由'
  require "$file" '人間の承認が必要な操作'
done


require "$agents" '.agents/skills/plan-to-issues/'

# 文書に載せた記入例を検査する限定fixture。任意の計画を判定する実行Gateではない。
python3 - "$ROOT" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
headings = ['Goal', 'Context', 'Scope / Boundaries', 'Non-goals', 'Done',
            'Verification', 'Dependencies']
for kind in ('parent', 'child'):
    template = (root / f'.github/ISSUE_TEMPLATE/{kind}-issue.md').read_text()
    metadata = template.split('---', 2)[1]
    for field in ('name:', 'about:', 'title:', 'labels:', 'assignees:'):
        assert field in metadata, (kind, field)
    expected = headings.copy()
    if kind == 'parent':
        expected[-1] = 'Children / Dependencies'
    assert re.findall(r'^# (.+)$', template, re.M) == expected, kind
    # GitHub Issue本文の参照はrepoのmainに解決する。対象pathの欠落を検出する。
    for route in re.findall(r'\]\(\.\./blob/main/([^)#]+)', template):
        assert (root / route).is_file(), route

doc = (root / 'docs/minimal-development-contract.md').read_text()
examples = doc.split('### 最小子Issueの記入例（入力契約の確認用）', 1)[1]
bodies = re.findall(r'```markdown\n(.*?)\n```', examples, re.S)
assert len(bodies) == 3

def sections(body):
    parts = re.split(r'^# (.+)\n', body, flags=re.M)
    assert not parts[0].strip()
    return dict(zip(parts[1::2], parts[2::2]))

def valid_fixture(values):
    # 六つのMUSTと、今回例で必要な安全記録を別々に確認する。
    if not all(values.get(key, '').strip() for key in headings):
        return False
    boundary = values['Scope / Boundaries']
    if '1子Issue = 1 PR' not in values['Goal']:
        return False
    if not re.search(r'Risk Tier: (LOW|MEDIUM|HIGH)、\S', boundary):
        return False
    if not all(token in boundary for token in ('PUBLIC', 'PR branch', 'Human Approval:')):
        return False
    if '後で決める' in values['Dependencies'] or 'NEEDS_DECISION' in values['Context']:
        return False
    if not re.search(r'Plan Review: (PASS|NOT_APPLICABLE)、.+docs/plan-review-gate.md', values['Context']):
        return False
    if 'UI Level: PRODUCT' in values['Context']:
        if not all(token in values['Context'] for token in
                   ('Framework Decision: DECIDED', 'product-ui-standard.md', 'docs/design.md')):
            return False
        if 'Visual/UI Acceptance' not in values['Verification']:
            return False
    if 'Risk Tier: HIGH' in boundary:
        if not all(token in boundary for token in
                   ('LLM: MANAGED', 'Tool / Destination allowlist:', '未承認、停止する')):
            return False
    return True

values = [sections(body) for body in bodies]
assert all(valid_fixture(value) for value in values)
assert not any(token in values[0]['Context'] for token in ('UI Level:', 'Framework Decision:'))
for key in headings:
    broken = dict(values[0], **{key: ''})
    assert not valid_fixture(broken), f'missing {key} must stop'
assert not valid_fixture(dict(values[0], Dependencies='後で決める'))
assert not valid_fixture(dict(values[1], Context=values[1]['Context'] + ' NEEDS_DECISION'))
assert not valid_fixture(dict(values[1], Verification='標準検証のみ'))
for token in ('Risk Tier: HIGH', 'Tool / Destination allowlist:', '未承認、停止する'):
    broken = dict(values[2], **{'Scope / Boundaries': values[2]['Scope / Boundaries'].replace(token, '')})
    assert not valid_fixture(broken), f'missing safety control {token} must stop'
print('Minimal input examples: 3 positive, 13 negative cases PASS')
PY

printf 'Plan to Issues Skill contract: PASS\n'
