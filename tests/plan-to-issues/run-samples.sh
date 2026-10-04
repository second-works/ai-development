#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
agents="$ROOT/AGENTS.md"
skill="$ROOT/.agents/skills/plan-to-issues/SKILL.md"
inventory="$ROOT/docs/instruction-architecture-inventory.md"
harness="$ROOT/docs/ai-development-harness-inventory.md"

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
require "$skill" 'Framework Decision（適用時）'
require "$skill" 'UI Level Decision（UI適用を確認し、UIがある場合だけ記録）'
require "$skill" 'UIの適用確認は全案件で行う'
require "$skill" 'Plan Review Gate'
require "$skill" 'Risk Tier'
require "$skill" 'Child Issue Quality Gate'
require "$skill" '`NEEDS_DECISION` の場合はIssue登録へ進まない'
require "$skill" '1子Issue = 1 PR'
require "$skill" '1 PRで完結する場合'
require "$skill" '空の親Issueを作ること自体を目的にしない'
require "$skill" '.github/ISSUE_TEMPLATE/parent-issue.md'
require "$skill" '.github/ISSUE_TEMPLATE/child-issue.md'
require "$skill" 'Plan Review結果（`PASS / NOT_APPLICABLE`）、理由、正本参照'
require "$skill" '単一Issueでも、Plan Reviewの判定・理由・正本参照'
require "$skill" 'MUST不足'
require "$skill" 'GitHubが返したIssue番号やURLを使用し、番号を推測しない'
require "$skill" 'Issue登録が完了したら、このSkillの作業は終了する'
require "$skill" 'Issueの実装を開始しない'
require "$skill" '同じ詳細をSkill本文へ複製して独自基準を作らない'

require "$inventory" '`Plan Review Gate > Plan to Issues Routing` | `ENTRYPOINT` | `KEEP`'
require "$inventory" '.agents/skills/plan-to-issues/SKILL.md'
require "$inventory" '`plan-to-issues` は合意済み計画からGitHub Issueへの変換に限定'
require "$harness" '#148'
require "$harness" '.agents/skills/plan-to-issues/SKILL.md'

for template in parent child; do
  file="$ROOT/.github/ISSUE_TEMPLATE/$template-issue.md"
  require "$file" '# Goal'
  require "$file" '# Context'
  require "$file" '# Scope / Boundaries'
  require "$file" '# Non-goals'
  require "$file" '# Done'
  require "$file" '# Verification'
  require "$file" '依存がなければ「なし」'
  require "$file" 'Plan Reviewの判定（PASS / NOT_APPLICABLE）、理由'
  require "$file" '../blob/main/docs/plan-review-gate.md'
  require "$file" '../blob/main/docs/minimal-development-contract.md#条件付き参照'
  require "$file" 'MUST不足なら登録・実装開始を停止'
done
require "$skill" '非UIに `NONE` 欄を強制しない'


require "$agents" '.agents/skills/plan-to-issues/SKILL.md を必ず読む'
require "$agents" '生成だけの依頼から実装を始めない'

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
