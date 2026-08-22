---
name: pr-review-fix
description: 既存GitHub PRのCodex Code Review指摘を、同じPRのhead branchへ安全に修正・pushし、SHA一致確認と再検証後に再レビューを依頼する。ユーザーが「PR #XXのレビュー修正を進めて」「レビュー指摘を直して」などと依頼したときに使う。新規branch/PR作成やMergeには使わない。
---

# PR Review Fix

既存PRのレビュー指摘を、**そのPRのhead branchだけ**で修正するためのSkill。

## 絶対ルール

- `@codex review` はレビュー専用とする。
- `@codex address that feedback` は使わない。
- 新しいbranchを作らない。
- 新しいPRを作らない。
- `main` / default branchへ直接pushしない。
- 対象PRのhead branch以外へpushしない。
- P0 / P1 / P2だけをIssue範囲内で修正する。P3は原則として修正必須にしない。
- 同じ問題が3回以上繰り返す、仕様判断が必要、Issue範囲外へ広がる、branch/SHAが一致しない場合は停止して人間へ戻す。
- Mergeは絶対に実行しない。最終Mergeは人間が判断する。

## 前提

- repo rootで実行する。
- `git` と `gh` が利用できること。
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
bash .agents/skills/pr-review-fix/scripts/prepare-pr.sh <PR番号>
```

このscriptは次を確認する。

- PRがopen
- cross-repository PRではない
- head branchがdefault branchではない
- Git作業ツリーがclean
- GitHub上のhead branch/head SHAを取得
- 既存head branchをcheckout
- local HEADとGitHub PR head SHAが一致

1つでも失敗したら修正へ進まない。

### 2. レビュー指摘を取得する

対象PRの最新レビューとinline commentを確認する。

```bash
gh pr view <PR番号> --comments

gh api --paginate repos/{owner}/{repo}/pulls/<PR番号>/comments

gh api --paginate repos/{owner}/{repo}/pulls/<PR番号>/reviews
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

修正後、repositoryで定義されたローカルチェックを実行する。

優先順:

1. tests
2. lint
3. type check
4. build

定義がないものは「対象外」と記録する。テストを無効化して成功扱いにしない。

### 5. commit / pushする

修正内容だけをcommitする。

```bash
git status --short
git diff --check
git add <変更ファイル>
git commit -m "review: Codex指摘を修正"
git push origin HEAD
```

`git push origin HEAD:<別branch>` のように別branchへpushしてはいけない。

### 6. GitHub PR head SHAを照合する

push直後のlocal commit SHAを固定し、verify scriptを実行する。

```bash
EXPECTED_SHA="$(git rev-parse HEAD)"
bash .agents/skills/pr-review-fix/scripts/verify-pr-head.sh <PR番号> "$EXPECTED_SHA"
```

次の3つが一致しなければ停止する。

- pushしたlocal commit SHA
- GitHub上のPR head SHA
- 現在checkout中のbranchのHEAD

SHAが変わっただけでは成功扱いにしない。**同じ値であること**を確認する。

### 7. 更新後SHAで再検証する

一致確認したSHAを検証対象SHAとして固定する。

順序は必ず次とする。

1. ローカルテスト
2. GitHub Actions CI
3. 利用可能なセキュリティチェック
4. 更新後headへのCodex Code Review

CI/status checkを確認するときは、検証対象SHAに対する結果であることを確認する。

利用可能な例:

```bash
gh pr checks <PR番号>
```

CIやセキュリティチェックが存在しない場合は、その事実を報告する。

### 8. 再レビューを依頼する

すべての前段確認後にだけ実行する。

```bash
gh pr comment <PR番号> --body "更新後headを対象に再レビューしてください。\n\n@codex review"
```

再レビュー依頼後はMergeしない。

### 9. 最終報告

最低限、次を報告する。

- PR番号
- head branch
- 修正前head SHA
- 修正後head SHA
- push commit SHA
- 変更した指摘（P0/P1/P2）
- ローカルテスト結果
- CI結果
- セキュリティチェック結果
- 再レビュー依頼済みか
- 未解決指摘

最後に「最終Mergeは人間判断」と明記して停止する。

## 禁止コマンド/操作

- `git checkout -b ...`
- `git switch -c ...`
- `gh pr create`
- `gh pr merge`
- `git push origin main`
- `git push --force` / `git push -f`
- `@codex address that feedback`

既存PR head branchが取得できない場合に、代替branchやfollow-up PRを作ることも禁止する。
