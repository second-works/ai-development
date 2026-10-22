#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
agents="$ROOT/AGENTS.md"
git_bin="$(command -v git)"
if ! "$git_bin" --version >/dev/null 2>&1; then
  for candidate in /usr/bin/git /bin/git; do
    if [[ -x "$candidate" ]] && "$candidate" --version >/dev/null 2>&1; then
      git_bin="$candidate"
      break
    fi
  done
fi
"$git_bin" --version >/dev/null 2>&1 || {
  printf 'a working Git executable is required for the read-only smoke test\n' >&2
  exit 1
}

tar_bin="$(command -v tar)"
[[ -n "$tar_bin" ]] || {
  printf 'a working tar executable is required for the read-only smoke test\n' >&2
  exit 1
}

digest_stream() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    printf 'a SHA-256 executable is required for the read-only smoke test\n' >&2
    return 1
  fi
}

digest_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    digest_stream < "$file"
  else
    printf '<missing-index>\n'
  fi
}

git_dir="$("$git_bin" -C "$ROOT" rev-parse --path-format=absolute --git-dir)"
git_common_dir="$("$git_bin" -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)"

snapshot_ref_storage() {
  snapshot_one_ref_storage() {
    local storage_dir="$1"
    local -a paths=()
    printf 'storage=%s\n' "$storage_dir"
    [[ -d "$storage_dir/refs" ]] && paths+=(refs)
    [[ -e "$storage_dir/packed-refs" ]] && paths+=(packed-refs)
    if ((${#paths[@]} == 0)); then
      printf '<no-ref-storage>\n'
      return
    fi
    "$tar_bin" -C "$storage_dir" -cf - "${paths[@]}"
  }

  {
    snapshot_one_ref_storage "$git_common_dir"
    if [[ "$git_dir" != "$git_common_dir" ]]; then
      snapshot_one_ref_storage "$git_dir"
    fi
  } | digest_stream
}

before_head="$("$git_bin" -C "$ROOT" rev-parse --verify HEAD)"
before_branch="$("$git_bin" -C "$ROOT" symbolic-ref --quiet --short HEAD || printf '<detached>')"
before_refs="$("$git_bin" -C "$ROOT" for-each-ref --format='%(refname) %(objectname) %(symref)')"
# Common and worktree-local raw ref storage captures dangling symbolic refs omitted by for-each-ref.
before_ref_storage="$(snapshot_ref_storage)"
# Disable Git's optional index refresh so this read-only probe cannot update the index stat cache.
before_status="$(GIT_OPTIONAL_LOCKS=0 "$git_bin" -C "$ROOT" status --porcelain=v1)"
# Keep a raw index digest as a second guard against metadata changes not represented by ls-files.
before_raw_index="$(digest_file "$git_dir/index")"
# --stage records index entries, and -v includes assume-unchanged / skip-worktree flags.
before_index="$("$git_bin" -C "$ROOT" ls-files --stage -v -z | digest_stream)"
before_worktree="$("$tar_bin" -C "$ROOT" --exclude=.git -cf - . | digest_stream)"

require() {
  local file="$1"
  local needle="$2"
  grep -Fq -- "$needle" "$ROOT/$file" || {
    printf 'missing instruction architecture contract: %s: %s\n' "$file" "$needle" >&2
    exit 1
  }
}

# The repository runs on the lightweight template (#197): AGENTS.md is this
# repository's own section plus the managed lightweight block. The block itself
# is compared with the template by templates/lightweight/place.sh --check.
require "AGENTS.md" '<!-- lightweight:begin'
require "AGENTS.md" './scripts/verify.sh'
require "AGENTS.md" 'docs/review-followups.md'
# The large flow and the conditional contract are reference material, not required reading.
for heavy in docs/nine-standard-ai-development-flow.md docs/minimal-development-contract.md \
  .agents/skills/template-change-evaluator/SKILL.md; do
  if grep -Fq -- "$heavy" "$agents"; then
    printf 'AGENTS.md must not require reading %s\n' "$heavy" >&2
    exit 1
  fi
done
if grep -Fq 'pr-review-fix' "$agents"; then
  printf 'normal review must not auto-route to pr-review-fix Skill\n' >&2
  exit 1
fi
# Every path that AGENTS.md names must exist.
python3 - "$ROOT" <<'PYROUTES'
from pathlib import Path
import re,sys
root=Path(sys.argv[1]);agents=(root/'AGENTS.md').read_text()
for target in re.findall(r'(?:docs|\.agents/skills|\.claude/skills|templates|scripts)/[\w./-]+\.(?:md|sh)',agents):
    assert (root/target).is_file(),target
PYROUTES
# Reference material stays reachable: README links each of these.
for path in \
  docs/code-review-contract.md \
  docs/test-design.md \
  docs/design-state-modeling.md \
  docs/parent-issue-completion.md \
  docs/product-ui-standard.md \
  docs/adaptive-development-flow.md \
  docs/ai-agent-security-boundary.md \
  docs/architecture/framework-decision.md \
  docs/acceptance-verification.md \
  docs/deployment-release-design.md \
  docs/github-repository-security-baseline.md \
  docs/plan-review-gate.md \
  docs/template-guide.md \
  docs/nine-standard-ai-development-flow.md \
  docs/minimal-development-contract.md; do
  [[ -e "$ROOT/$path" ]] || {
    printf 'instruction architecture source is missing: %s\n' "$path" >&2
    exit 1
  }
  grep -Fq "($path)" "$ROOT/README.md" || {
    printf 'reference document is not linked from README.md: %s\n' "$path" >&2
    exit 1
  }
done
for path in templates/verification/verify.sh templates/security/security-preflight.sh \
  .agents/skills/plan-to-issues/SKILL.md .claude/skills/steward/SKILL.md \
  .github/workflows/ci.yml .github/workflows/security.yml; do
  [[ -e "$ROOT/$path" ]] || { printf 'instruction architecture source is missing: %s\n' "$path" >&2; exit 1; }
done
# Run the guide's placement example in a fresh temporary project.
python3 - "$ROOT" <<'PYPLACEMENT'
from pathlib import Path
import os,re,subprocess,sys,tempfile
root=Path(sys.argv[1])
section=(root/'docs/template-guide.md').read_text().split('### 最小AGENTSと参照先の配置',1)[1].split('## 2.1 Risk Tierの記入',1)[0]
commands=re.search(r'```bash\n(.*?)\n```',section,re.S).group(1)
with tempfile.TemporaryDirectory(prefix='lightweight-placement-') as temp:
    project=Path(temp)/'project'
    # place.sh reads the committed candidate, so run it from a clone of HEAD: uncommitted
    # template edits (checked by tests/lightweight-template) do not stop this example.
    source=Path(temp)/'source'
    subprocess.run(['git','clone','--quiet','--no-hardlinks',str(root),str(source)],check=True,capture_output=True)
    env=dict(os.environ,template_source_root=str(source),project_output_root=str(project))
    subprocess.run(['bash','-c',commands],check=True,env=env,capture_output=True,text=True)
    agents=(project/'AGENTS.md').read_text()
    assert '<!-- lightweight:begin' in agents
    assert 'ai-development 固有の境界' not in agents,'this repository section must not be placed'
    for target in ('CLAUDE.md','.claude/settings.json','.claude/skills/steward/SKILL.md',
                   '.agents/skills/plan-to-issues/SKILL.md','scripts/verify.sh','scripts/check-pr-head.sh',
                   '.ai/lightweight-placement.tsv'):
        assert (project/target).is_file(),target
    before=(project/'AGENTS.md').read_bytes()
    repeat=subprocess.run(['bash','-c',commands],env=env,capture_output=True,text=True)
    assert repeat.returncode==0,'re-running the placement must be a no-op'
    assert (project/'AGENTS.md').read_bytes()==before,'re-running the placement changed AGENTS.md'
PYPLACEMENT
require "tests/instruction-architecture/run-samples.sh" 'GIT_OPTIONAL_LOCKS=0'
require "tests/instruction-architecture/run-samples.sh" 'before_raw_index'

after_head="$("$git_bin" -C "$ROOT" rev-parse --verify HEAD)"
after_branch="$("$git_bin" -C "$ROOT" symbolic-ref --quiet --short HEAD || printf '<detached>')"
after_refs="$("$git_bin" -C "$ROOT" for-each-ref --format='%(refname) %(objectname) %(symref)')"
after_ref_storage="$(snapshot_ref_storage)"
after_status="$(GIT_OPTIONAL_LOCKS=0 "$git_bin" -C "$ROOT" status --porcelain=v1)"
after_raw_index="$(digest_file "$git_dir/index")"
after_index="$("$git_bin" -C "$ROOT" ls-files --stage -v -z | digest_stream)"
after_worktree="$("$tar_bin" -C "$ROOT" --exclude=.git -cf - . | digest_stream)"
[[ "$before_head" == "$after_head" && "$before_branch" == "$after_branch" && "$before_refs" == "$after_refs" && "$before_ref_storage" == "$after_ref_storage" && "$before_status" == "$after_status" && "$before_raw_index" == "$after_raw_index" && "$before_index" == "$after_index" && "$before_worktree" == "$after_worktree" ]] || {
  printf 'read-only smoke test changed HEAD, branch, refs or common/worktree-local ref storage, index entries or flags, or worktree contents\n' >&2
  exit 1
}

printf 'Instruction architecture and read-only smoke test contract: PASS\n'
