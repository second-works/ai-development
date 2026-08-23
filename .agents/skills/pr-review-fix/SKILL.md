---
name: pr-review-fix
description: 既存GitHub PRのCodex Code Review指摘を、同じPRのhead branchへ安全に修正・pushし、SHA一致確認と再検証後に再レビューする。ユーザーが「PR #XXのレビュー修正を進めて」などと依頼したときに使う。新規remote branch/PR作成やMergeには使わない。
---

# PR Review Fix

既存PRのレビュー指摘を、そのPRのhead branchだけで修正するSkill。

## 絶対ルール

- `@codex review` はレビュー専用。
- `@codex address that feedback` は使わない。
- 新しいremote branch / 別作業branch / 新しいPRを作らない。
- 既存PR head branchと同名のlocal tracking branch作成だけ許可する。
- default branchへ直接pushしない。
- 対象PRのhead branch以外へpushしない。
- P0 / P1 / P2をIssue範囲内で修正する。P3は原則必須にしない。
- 同じ問題が3回以上繰り返す、仕様判断が必要、Issue範囲外、branch/SHA不一致なら停止して人間へ戻す。人間が明示的に継続を指示した場合だけ再開する。
- Mergeは実行しない。最終Mergeは人間判断。

## 前提

- repo rootで実行する。
- `git` / `gh` / `python3` が利用可能。
- `gh auth status` が成功する。
- working treeがclean。
- 対象PRがopenかつ同一repository内。

## 標準入力

```text
PR #25のレビュー修正を進めて
```

PR番号が不明なら推測せず確認する。

## 実行手順

### 1. PRを固定

```bash
PREPARE_OUTPUT="$(bash .agents/skills/pr-review-fix/scripts/prepare-pr.sh <PR番号>)"
printf '%s\n' "$PREPARE_OUTPUT"
```

`REPO` / `HEAD_BRANCH` / `BEFORE_SHA` / `RUNTIME_DIR` / `VERIFY_SCRIPT` を記録する。

prepare scriptは以下を検証する。

- PR open / non-cross-repository / head != default branch
- working tree clean
- `origin` のfetch URLと全push URLが同じ `HOST/owner/repo` を指す
- GitHub.com / GitHub Enterpriseを含めhostまでrepository identityに含める
- GitHub操作対象を検証済みoriginから固定
- remote-tracking refを明示refspecで更新
- 既存head branchをcheckout
- local HEAD = GitHub PR head SHA

またcheckout前にscriptsを一時ディレクトリへ退避し、Skill追加前の古いPR branchでも後続scriptを利用可能にする。

### 2. 最新レビュー指摘を取得

`REPO` は `HOST/owner/repo` 形式なので、`gh pr` にはそのまま渡し、`gh api` ではhostとAPI pathを分離する。

```bash
HOST="${REPO%%/*}"
REPO_PATH="${REPO#*/}"

gh pr view <PR番号> --repo "$REPO" --comments

gh api --hostname "$HOST" --paginate --slurp \
  "repos/$REPO_PATH/pulls/<PR番号>/comments?per_page=100"

gh api --hostname "$HOST" --paginate --slurp \
  "repos/$REPO_PATH/pulls/<PR番号>/reviews?per_page=100"
```

古いheadのoutdated指摘と現在headの有効指摘を区別し、現在有効なP0/P1/P2だけを対象にする。

### 3. Issue範囲を確認

PR本文の `Closes #XX` 等からIssueを確認し、Issue本文を仕様基準にする。

- Issue範囲内: 修正
- Issue範囲外: 停止して報告
- 仕様曖昧: 推測せず人間へ確認

### 4. 同じhead branch上で修正

```bash
test "$(git branch --show-current)" = "$HEAD_BRANCH"
test -z "$(git status --porcelain)"
```

branchを移動せずIssue範囲内だけ修正する。

### 5. commit / push

```bash
git status --short
git diff --check
git add <変更ファイル>
git commit -m "review: Codex指摘を修正"
EXPECTED_SHA="$(git rev-parse HEAD)"
git push origin "HEAD:refs/heads/$HEAD_BRANCH"
```

prepare scriptでoriginのfetch URLと全push URLが同じrepository identityであることを確認済みでなければpushしない。

### 6. push後SHA照合

```bash
bash "$VERIFY_SCRIPT" <PR番号> "$EXPECTED_SHA" "$BEFORE_SHA" "$REPO"
```

以下すべて必須。

- `EXPECTED_SHA != BEFORE_SHA`
- local HEAD = `EXPECTED_SHA`
- GitHub PR head SHA = `EXPECTED_SHA`
- current branch = `HEAD_BRANCH`
- working tree clean

`verify-pr-head.sh` は通常 `REPO=HOST/owner/repo` を明示して使う。repo引数を省略した場合も、`origin` のfetch URLと全push URLからhostを含むrepository identityを再構築し、一致しないremote構成では停止する。

不一致なら再検証へ進まず停止する。

### 7. 更新後SHAでローカル再検証

前後で必ず確認する。

```bash
test -z "$(git status --porcelain)"
test "$(git rev-parse HEAD)" = "$EXPECTED_SHA"
```

repository定義に従い tests → lint → type check → build の順で実行する。存在しないものは対象外と記録する。テストでtracked fileが変化した場合、その結果を対象SHAの検証結果として扱わない。

### 8. CI / securityを対象SHAで待機・確認

```bash
bash "$RUNTIME_DIR/scripts/wait-checks.sh" "$REPO" "$EXPECTED_SHA"
```

wait scriptは次を保証する。

- `REPO=HOST/owner/repo` を `HOST` と `owner/repo` に分離し、`gh api --hostname` を使う
- check runs / statusを `--paginate --slurp` で全ページ取得する
- queued / in_progress / pendingは待機
- failure / error / cancelled / timed_out等は停止
- check/status集合と結果が一定時間変化しない安定期間を待つ
- 後発checkやpending復帰で安定判定をリセット
- grace期間後も0件なら `STATUS=NO_CHECKS_OBSERVED` を出して**非0終了し停止する**
- check未観測をCI/security成功として扱わない。継続するには人間の明示判断が必要

手動確認する場合もhostとpathを分離し、全ページ取得する。

```bash
HOST="${REPO%%/*}"
REPO_PATH="${REPO#*/}"

gh api --hostname "$HOST" --paginate --slurp \
  "repos/$REPO_PATH/commits/$EXPECTED_SHA/check-runs?per_page=100"

gh api --hostname "$HOST" --paginate --slurp \
  "repos/$REPO_PATH/commits/$EXPECTED_SHA/status?per_page=100"
```

CI/security確認後、再レビュー前にもう一度照合する。

```bash
bash "$VERIFY_SCRIPT" <PR番号> "$EXPECTED_SHA" "$BEFORE_SHA" "$REPO"
```

### 9. 更新後headへ再レビュー依頼

今回の再レビュー依頼より前に存在した同一SHAのCodex結果を誤って再利用しないよう、**再レビュー依頼コメント自身のGitHub comment IDを取得して基準点にする**。

```bash
HOST="${REPO%%/*}"
REPO_PATH="${REPO#*/}"
REVIEW_REQUEST_BODY="$(cat <<EOF
更新後head \`$EXPECTED_SHA\` を対象に再レビューしてください。

@codex review
EOF
)"

REVIEW_REQUEST_COMMENT_ID="$(
  gh api --hostname "$HOST" \
    --method POST \
    "repos/$REPO_PATH/issues/<PR番号>/comments" \
    -f body="$REVIEW_REQUEST_BODY" \
    --jq '.id'
)"

test -n "$REVIEW_REQUEST_COMMENT_ID"
```

### 10. 再レビュー完了を待つ

```bash
bash "$RUNTIME_DIR/scripts/wait-codex-review.sh" \
  "$REPO" <PR番号> "$EXPECTED_SHA" "$REVIEW_REQUEST_COMMENT_ID"
```

このscriptは次を保証する。

- `REPO` をhostとpathへ分離し、REST/GraphQLとも対象hostへ問い合わせる
- `Reviewed commit` が `EXPECTED_SHA` と一致する
- **`REVIEW_REQUEST_COMMENT_ID` より後に作成されたCodex結果だけを今回の再レビュー完了として受理する**
- 同じSHAに対する古い自動レビュー/再レビュー結果は完了判定に使わない
- Codex actorは既知の `chatgpt-codex-connector` / `chatgpt-codex-connector[bot]` の完全一致かつGitHub actor type `Bot` の場合だけ受理する
- loginに単に `codex` を含む別ユーザー/別botのコメントはレビュー結果として受理しない
- 再レビュー依頼後に新しく投稿されたP0/P1/P2 inline指摘を確認する
- GraphQL reviewThreadsも全ページ確認し、**現在の `EXPECTED_SHA` に対する未解決・非outdatedの既存P0/P1/P2 threadが1件でも残れば成功扱いにしない**

結果:

- `STATUS=REVIEW_PASSED`: 新規指摘も未解決の既存指摘もない場合だけ次へ
- `STATUS=REVIEW_CHANGES_REQUIRED`: 同じ修正ループへ戻る
- timeout: 再レビュー待ちとして停止

### 11. 最終SHA再照合

```bash
bash "$VERIFY_SCRIPT" <PR番号> "$EXPECTED_SHA" "$BEFORE_SHA" "$REPO"
test -z "$(git status --porcelain)"
```

CI / security / Codex Reviewがすべて `EXPECTED_SHA` 対象だったことを確認する。待機中にPR headが動いた場合は成功扱いにしない。

### 12. 最終報告

最低限、PR番号、repository、head branch、修正前後SHA、push SHA、修正したP0/P1/P2、local test、CI/security、再レビュー依頼comment ID、reviewed commit、未解決指摘、最終SHA照合結果を報告する。

最後に「最終Mergeは人間判断」と明記して停止する。

## 禁止操作

- PR headと異なる名前でのbranch作成
- `gh pr create`
- `gh pr merge`
- default branchへの直接push
- force push
- `@codex address that feedback`
- 代替branch / follow-up PR作成
