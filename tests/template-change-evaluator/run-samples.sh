#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
agents="$ROOT/AGENTS.md"
skill="$ROOT/.agents/skills/template-change-evaluator/SKILL.md"
harness="$ROOT/docs/ai-development-harness-inventory.md"

require() {
  local file="$1"
  local needle="$2"
  grep -Fq -- "$needle" "$file" || {
    printf 'missing template-change-evaluator contract: %s: %s\n' "$file" "$needle" >&2
    exit 1
  }
}

[[ -f "$skill" ]] || {
  printf 'template-change-evaluator Skill is missing: %s\n' "$skill" >&2
  exit 1
}

require "$ROOT/docs/nine-standard-ai-development-flow.md" '### Template Change Evaluation Routing'
require "$ROOT/docs/nine-standard-ai-development-flow.md" '.agents/skills/template-change-evaluator/SKILL.md'
require "$ROOT/docs/nine-standard-ai-development-flow.md" '「テンプレに取り入れる内容を精査して」'
require "$ROOT/docs/nine-standard-ai-development-flow.md" '記事や技術の単純な要約・解説'
require "$ROOT/docs/nine-standard-ai-development-flow.md" '既存repoの責務確認より先に新しいRule / Skill / script / CIを追加しない'

require "$skill" 'name: template-change-evaluator'
require "$skill" '採否を決める前に、必ず現行repoを確認する'
require "$skill" '`ALREADY_COVERED`'
require "$skill" '`ADOPT`'
require "$skill" '`ADAPT`'
require "$skill" '`REJECT`'
require "$skill" '`FOLLOW_UP`'
require "$skill" '`AGENTS`'
require "$skill" '`docs`'
require "$skill" '`Skill`'
require "$skill" '`script`'
require "$skill" '`test`'
require "$skill" '`CI`'
require "$skill" '`ISSUE_ONLY`'
require "$skill" '単純な紹介・要約だけが目的なら'
require "$skill" '評価依頼だけで自動的にmain変更やMergeを行わない'

require "$harness" '.agents/skills/template-change-evaluator/SKILL.md'
require "$harness" '#147'


require "$agents" '.agents/skills/template-change-evaluator/SKILL.md を判断前に読む'
require "$agents" '既存PRの指摘修正は対象外'

printf 'Template change evaluator Skill contract: PASS\n'
