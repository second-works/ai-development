---
name: pr-review-fix
description: 既存GitHub PRのCodex Code Review指摘を、同じPRのhead branchへ安全に修正・pushし、SHA一致確認と再検証後に再レビューを依頼する。ユーザーが「PR #XXのレビュー修正を進めて」「レビュー指摘を直して」などと依頼したときに使う。新規remote branch/PR作成やMergeには使わない。
---

# PR Review Fix

既存PRのレビュー指摘を、**そのPRのhead branchだけ**で修正するためのSkill。

## 絶対ルール

- `@codex review` はレビュー専用とする。
- `@codex address that feedback` は使わない。
- 新しいremote branchや別の作業branchを作らない。既存PR head branchをcheckoutするための同名local tracking branch作成だけは許可する。
- 新しいPRを作らない。
- `main` / default branchへ直接pushしない。
- 対象PRのhead branch以外へpushしない。
- P0 / P1 / P2だけをIssue範囲内で修正する。P3は原則として修正必須にしない。
- 同じ問題が3回以上繰り返す、仕様判断が必要、Issue範囲外へ広がる、branch/SHAが一致しない場合は停止して人間へ戻す。
- Mergeは絶対に実行しない。最終Mergeは人間が判断する。

## 前提

- repo rootで実行する。
- `git`、`gh`、`python3` が利用できること。
- `gh auth status` が成功すること。
- 作業ツリーがcleanであること。
- 対象PRがopenで、同一repository内のPRであること。

前提を満たさない場合は推測で進めず停止する。

## 標準入力

ユーザーは原則としてPR番号だけを指定する。

例:

```text
PR #25のレビュー修正を進めて
```

PR番号が不明な場合は勝手に推測せず確認する。

## 実行手順

### 1. PRを固定する

最初にprepare scriptを実行する。

```bash
PREPARE_OUTPUT="$(bash .agents/skills/pr-review-fix/scripts/prepare-pr.sh <PR番号>)"
printf '%s\n' "$PREPARE_OUTPUT"
```

出力された以下を記録する。

- `REPO`
- `HEAD_BRANCH`
- `BEFORE_SHA`
- `RUNTIME_DIR`
- `VERIFY_SCRIPT`

prepare scriptは次を確認する。

- PRがopen
- cross-repository PRではない
- head branchがdefault branchではない
- Git作業ツリーがclean
- `origin` のfetch URLとpush URLが同じGitHub repositoryを指す
- GitHub操作対象repositoryをその検証済み`origin`から固定
- GitHub上のhead branch/head SHAを取得
- remote-tracking refを明示的なrefspecで最新化
- 既存remote head branchと同名のlocal branchをcheckout（local branchがなければtracking branchを作成）
- local HEADとGitHub PR head SHAが一致

また、checkout前にSkillのscript一式を一時ディレクトリへ退避する。これにより、Skill追加前に作成された古いPR branchへcheckoutしてrepo-local Skillがworking treeから消えても、`RUNTIME_DIR/scripts/` 配下のscriptを継続利用できる。

1つでも失敗したら修正へ進まない。

### 2. レビュー指摘を取得する

対象PRの最新レビューとinline commentを確認する。GitHub操作では必ずprepare scriptで得た `REPO` を明示する。

```bash
gh pr view <PR番号> --repo "$REPO" --comments

gh api --paginate "repos/$REPO/pulls/<PR番号>/comments"

gh api --paginate "repos/$REPO/pulls/<PR番号>/reviews"
```

古いhead SHAに対するoutdatedな指摘と、現在headへの有効な指摘を区別する。

P0 / P1 / P2の現在有効な指摘だけを修正対象とする。

### 3. Issue範囲を確認する

PR本文の `Closes #XX` 等から対応Issueを確認し、Issue本文を仕様の基準とする。

- Issue範囲内 → 修正可能
- Issue範囲外 → 修正せず人間へ報告
- 仕様が曖昧 → 推測せず人間へ確認

### 4. 同じhead branch上で修正する

prepare scriptがcheckoutしたbranchから移動しない。

修正前に再度確認する。

```bash
test "$(git branch --show-current)" = "$HEAD_BRANCH"
test -z "$(git status --porcelain)"
```

Issue範囲内の指摘だけを修正する。

### 5. commit / pushする

修正内容だけをcommitする。

```bash
git status --short
git diff --check
git add <変更ファイル>
git commit -m "review: Codex指摘を修正"
EXPECTED_SHA="$(git rev-parse HEAD)"
git push origin "HEAD:refs/heads/$HEAD_BRANCH"
```

prepare scriptで`origin`のfetch/push repository一致を確認済みであることを前提とする。`HEAD_BRANCH`以外へpushしてはいけない。

### 6. GitHub PR head SHAを照合する

push直後に、checkout前に退避されたverify scriptを使って照合する。

```bash
bash "$VERIFY_SCRIPT" <PR番号> "$EXPECTED_SHA" "$BEFORE_SHA" "$REPO"
```

次の条件をすべて満たさなければ停止する。

- `EXPECTED_SHA != BEFORE_SHA`
- pushしたlocal commit SHA = `EXPECTED_SHA`
- GitHub上のPR head SHA = `EXPECTED_SHA`
- 現在checkout中のbranchのHEAD = `EXPECTED_SHA`
- 作業ツリーがclean

SHAが単に変わっただけでは成功扱いにしない。**同じ値であること**を確認する。

### 7. 更新後SHAでローカル再検証する

一致確認した `EXPECTED_SHA` を検証対象SHAとして固定する。

ローカルチェック前に、作業ツリーとHEADを確認する。

```bash
test -z "$(git status --porcelain)"
test "$(git rev-parse HEAD)" = "$EXPECTED_SHA"
```

repositoryで定義されたローカルチェックを次の順で実行する。

1. tests
2. lint
3. type check
4. build

定義がないものは「対象外」と記録する。テストを無効化して成功扱いにしない。

**各ローカルチェック後**にも次を確認する。

```bash
test -z "$(git status --porcelain)"
test "$(git rev-parse HEAD)" = "$EXPECTED_SHA"
```

ローカルテストがtracked fileを書き換えた、未commit差分が残った、またはHEADが変わった場合は、その結果を `EXPECTED_SHA` の検証結果として扱わず停止する。

### 8. CI / セキュリティチェックを対象SHAで待機・確認する

push直後にcheck runがまだ登録されていないケースを考慮し、`EXPECTED_SHA`に対するcheck runs/statusesを一定時間pollする。

```bash
bash "$RUNTIME_DIR/scripts/wait-checks.sh" "$REPO" "$EXPECTED_SHA"
```

このscriptは次を行う。

- `EXPECTED_SHA` のcheck runs/statusesが出現するまでgrace期間待つ
- queued / in_progress / pending中は待機する
- failure / error / cancelled / timed_out等は失敗として停止する
- すべて成功・neutral・skipped等の許容終了状態になった場合だけ成功扱いにする
- grace期間後もcheck/statusが0件なら `NO_CHECKS_OBSERVED` として明示報告する

必要に応じてAPI結果を追加確認する。

```bash
gh api "repos/$REPO/commits/$EXPECTED_SHA/check-runs"
gh api "repos/$REPO/commits/$EXPECTED_SHA/status"
```

CI / セキュリティ確認後、再レビュー依頼前にもう一度PR headを固定確認する。

```bash
bash "$VERIFY_SCRIPT" <PR番号> "$EXPECTED_SHA" "$BEFORE_SHA" "$REPO"
```

### 9. 更新後headへ再レビューを依頼する

すべての前段確認後にだけ実行する。`@codex review` が確実に独立した行になるよう、文字列`\n`ではなく実際の改行を含む本文を`--body-file -`で投稿する。

```bash
gh pr comment <PR番号> --repo "$REPO" --body-file - <<EOF
更新後head \`$EXPECTED_SHA\` を対象に再レビューしてください。

@codex review
EOF
```

再レビュー依頼後はMergeしない。

### 10. 再レビュー完了を待って結果を確認する

再レビューは非同期なので、comment投稿直後に完了報告してはいけない。

```bash
bash "$RUNTIME_DIR/scripts/wait-codex-review.sh" "$REPO" <PR番号> "$EXPECTED_SHA"
```

このscriptは、Codexの`Reviewed commit`が`EXPECTED_SHA`と一致するレビューを待ち、そのcommitに対する新しいP0 / P1 / P2 inline指摘の有無を確認する。

- `STATUS=REVIEW_PASSED` → 次へ進む
- `STATUS=REVIEW_CHANGES_REQUIRED` → 同じ修正ループへ戻る
- timeout → 「再レビュー待ち」と報告して停止し、成功扱いにしない

必要に応じてreview threadsも確認し、古いheadに対するoutdated指摘と現在headの有効指摘を区別する。

### 11. 最終SHAを再照合する

再レビュー結果を確認した**後**に、PR headが待機中に動いていないことを最終確認する。

```bash
bash "$VERIFY_SCRIPT" <PR番号> "$EXPECTED_SHA" "$BEFORE_SHA" "$REPO"
test -z "$(git status --porcelain)"
```

さらに、CI / security / Codex Reviewの各結果が `EXPECTED_SHA` に対するものだったことを確認する。

ここでPR head SHAが変わっていた場合、それまでの検証結果を現在headの結果として扱わず停止する。

### 12. 最終報告

最低限、次を報告する。

- PR番号
- repository
- head branch
- 修正前head SHA (`BEFORE_SHA`)
- 修正後head SHA (`EXPECTED_SHA`)
- push commit SHA
- 変更した指摘（P0/P1/P2）
- ローカルテスト結果と対象SHA
- CI結果と対象SHA
- セキュリティチェック結果と対象SHA
- 再レビュー結果とreviewed commit
- 未解決指摘
- 最終PR head SHA照合結果

最後に「最終Mergeは人間判断」と明記して停止する。

## 禁止コマンド/操作

- PR head branchと異なる名前での `git checkout -b ...` / `git switch -c ...`
- `gh pr create`
- `gh pr merge`
- `git push origin main`
- `git push --force` / `git push -f`
- `@codex address that feedback`

既存PR head branchが取得できない場合に、代替branchやfollow-up PRを作ることも禁止する。
