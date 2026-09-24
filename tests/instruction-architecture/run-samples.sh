#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
inventory="$ROOT/docs/instruction-architecture-inventory.md"
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

[[ -f "$inventory" ]] || {
  printf 'instruction architecture inventory is missing: %s\n' "$inventory" >&2
  exit 1
}

require() {
  local file="$1"
  local needle="$2"
  grep -Fq -- "$needle" "$ROOT/$file" || {
    printf 'missing instruction architecture contract: %s: %s\n' "$file" "$needle" >&2
    exit 1
  }
}

require "AGENTS.md" 'docs/instruction-architecture-inventory.md'
require "AGENTS.md" '### Existing PR Review Feedback Routing'
require "AGENTS.md" '作業開始前に必ず `.agents/skills/pr-review-fix/SKILL.md` を読み、そのSkillに従う'
require "AGENTS.md" '「コメント確認して修正して」'
require "AGENTS.md" '「レビュー結果対応して」'
require "AGENTS.md" '単に「コメント」という語が含まれるだけでは起動しない'
require ".agents/skills/pr-review-fix/SKILL.md" 'ユーザーがSkill名やPR番号を明示しなくても'
require ".agents/skills/pr-review-fix/SKILL.md" '「コメント確認して修正して」'
require ".agents/skills/pr-review-fix/SKILL.md" '単なるIssueコメント閲覧'
require "docs/instruction-architecture-inventory.md" '## Decision First'
require "docs/instruction-architecture-inventory.md" '変更前の `AGENTS.md`: **47,136 bytes**'
require "docs/instruction-architecture-inventory.md" '変更後 `AGENTS.md`: 47,438 bytes（`+302 bytes`）'
require "docs/instruction-architecture-inventory.md" '現行35トップレベルセクション（`##`）をすべて列挙し'
require "docs/instruction-architecture-inventory.md" '## Overlap, contradiction, and source-of-truth ledger'
require "docs/instruction-architecture-inventory.md" 'IA-01'
require "docs/instruction-architecture-inventory.md" 'IA-02'
require "docs/instruction-architecture-inventory.md" '### IA-02 Review Evidence layer map'
require "docs/instruction-architecture-inventory.md" '`README.md`'
require "docs/instruction-architecture-inventory.md" '`docs/template-guide.md`'
require "docs/instruction-architecture-inventory.md" '`docs/ai-development-harness-inventory.md#V-02`'
require "docs/instruction-architecture-inventory.md" '`docs/ai-execution-state.md`'
require "docs/instruction-architecture-inventory.md" '`docs/nine-standard-ai-development-flow.md`'
require "docs/instruction-architecture-inventory.md" '`.agents/skills/pr-review-fix/SKILL.md`'
require "docs/instruction-architecture-inventory.md" '`Core Rules > Template Change Evaluation Routing` | `ENTRYPOINT` | `KEEP`'
require "docs/instruction-architecture-inventory.md" '`.agents/skills/template-change-evaluator/SKILL.md`'
require "docs/instruction-architecture-inventory.md" '`template-change-evaluator` はテンプレート改善の採否・重複・配置判断に限定'
require "docs/instruction-architecture-inventory.md" '`tests/review-evidence/run-samples.sh`'
require "docs/instruction-architecture-inventory.md" '`tests/template-simplification/run-samples.sh`'
require "docs/instruction-architecture-inventory.md" '`tests/verification-evidence/run-samples.sh`'
require "docs/instruction-architecture-inventory.md" '`tests/pr-review-followups/run-samples.sh`'
require "docs/instruction-architecture-inventory.md" '正本競合は未解消として記録する'
require "docs/instruction-architecture-inventory.md" 'docs側とSkill側を正本参照入口へ短縮'
require "docs/instruction-architecture-inventory.md" '`Parent Issue Completion` | `ENTRYPOINT` | `KEEP`'
require "docs/instruction-architecture-inventory.md" '## Agent-executed protocol'
require "docs/instruction-architecture-inventory.md" '### Execution record'
require "docs/instruction-architecture-inventory.md" '### Historical verification record (pre-self-reference)'
require "docs/instruction-architecture-inventory.md" 'PRのheadを証跡文書自身のコミットへ自己参照させない'
require "docs/instruction-architecture-inventory.md" '## Read-only smoke test'
require "docs/instruction-architecture-inventory.md" 'branch、commit、push、PR、Issueコメントを作成しない'
require "docs/instruction-architecture-inventory.md" 'index entryと`assume-unchanged` / `skip-worktree` flag'
require "docs/instruction-architecture-inventory.md" 'dangling symbolic refを含むref storage'
require "docs/instruction-architecture-inventory.md" 'common ref storage'
require "tests/instruction-architecture/run-samples.sh" 'GIT_OPTIONAL_LOCKS=0'
require "tests/instruction-architecture/run-samples.sh" 'before_raw_index'
require "docs/instruction-architecture-inventory.md" '`AGENTS.md`、`docs/`、`.agents/skills/`、`.github/`、`tests/`'
require "docs/instruction-architecture-inventory.md" '`docs/architecture/rag-design.md` はRAG採用プロジェクトの案件固有記録'

while IFS= read -r section; do
  [[ -n "$section" ]] || continue
  row="$(grep -F -- "| \`$section\` |" "$inventory" || true)"
  [[ -n "$row" ]] || {
    printf 'AGENTS section is not recorded in inventory: %s\n' "$section" >&2
    exit 1
  }
  case "$row" in
    *'| `KEEP` |'*|*'| `SHORTEN+REFERENCE` |'*|*'| `MOVE` |'*|*'| `MERGE` |'*) ;;
    *)
      printf 'AGENTS section has no relocation candidate: %s\n' "$section" >&2
      exit 1
      ;;
  esac
done < <(sed -n 's/^## \(.*\)$/\1/p' "$agents")

for path in \
  docs/adaptive-development-flow.md \
  docs/ai-agent-security-boundary.md \
  docs/ai-development-harness-inventory.md \
  docs/ai-execution-state.md \
  docs/architecture/framework-decision.md \
  docs/architecture/rag-guidelines.md \
  docs/acceptance-verification.md \
  docs/deployment-release-design.md \
  docs/github-repository-security-baseline.md \
  docs/issue-quality-check.md \
  docs/plan-review-gate.md \
  docs/safe-auto-fix-auto-merge.md \
  docs/nine-standard-ai-development-flow.md \
  templates/verification/verify.sh \
  templates/security/security-preflight.sh \
  .agents/skills/pr-review-fix/SKILL.md \
  .agents/skills/template-change-evaluator/SKILL.md \
  .github/workflows/ci.yml \
  .github/workflows/security.yml; do
  [[ -e "$ROOT/$path" ]] || {
    printf 'instruction architecture source is missing: %s\n' "$path" >&2
    exit 1
  }
done

grep -Fq -- '## Read-only smoke test' "$inventory"
grep -Fq -- '## Deferred decisions and follow-up boundary' "$inventory"
grep -Fq -- '## Overlap, contradiction, and source-of-truth ledger' "$inventory"
grep -Fq -- '## Agent-executed protocol' "$inventory"
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
