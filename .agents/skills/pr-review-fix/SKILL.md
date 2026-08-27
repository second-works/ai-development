---
name: pr-review-fix
description: 既存GitHub PRのCodex Code Review指摘を、同じPRのhead branchへ安全に修正・pushし、SHA一致確認と再検証後にレビューを収束させる。ユーザーが「PR #XXのレビュー修正を進めて」などと依頼したときに使う。新規remote branch/PR作成やMergeには使わない。
---

# PR Review Fix

既存PRのレビュー指摘を、そのPRのhead branchだけで修正し、安全に収束させるSkill。

レビューの目的は「指摘を0件にすること」ではない。
完了条件は、**Issueの受入条件を満たし、CI/securityが成功し、今回のPRに起因するBLOCKINGが残っていないこと**。

## 絶対ルール

- `@codex review` はレビュー専用。
- `@codex address that feedback` は使わない。
- 新しいremote branch / 別作業branch / 新しいPRを作らない。
- 既存PR head branchと同名のlocal tracking branch作成だけ許可する。
- default branchへ直接pushしない。
- 対象PRのhead branch以外へpushしない。
- P0 / P1は原則BLOCKINGとして必ず修正する。
- P2は自動的な必須修正にしない。必ず `BLOCKING / IN-SCOPE FIX / FOLLOW-UP / DISMISS` に分類する。
- P3は原則Merge阻害条件にしない。
- 修正後レビューで新しいP2が出ても、それだけで追加修正ループへ戻らない。
- 既存コード、未変更領域、設計改善、追加堅牢化、将来懸念、ベストプラクティス上の改善は原則FOLLOW-UPとし、当該PRの修正要求に含めない。
- 同じ問題が3回以上繰り返す、仕様判断が必要、Issue範囲外、branch/SHA不一致、または修正範囲が当初Issueから大きく逸脱した場合は停止して人間へ戻す。
- Mergeは実行しない。最終Mergeは人間判断。

## P2分類ルール

CodexのP2は、そのまま「必須修正」と解釈しない。
各P2を次の4分類にする。

### BLOCKING

このままマージすると、今回のPR差分が原因で以下のいずれかが具体的に発生するもの。

- Issue受入条件違反
- 明確な機能不具合
- 回帰
- データ破損
- セキュリティ問題
- 本番運用上の明確な破綻

BLOCKINGにするには、最低限以下を説明できること。

- 何が壊れるか
- どの入力・状態・実行経路で起きるか
- 今回のPR差分が原因であること
- Issue受入条件との関係

「将来的に問題になる可能性」「より堅牢になる」「ベストプラクティス」「念のため」だけではBLOCKINGにしない。

### IN-SCOPE FIX

Issue範囲内で、修正が小さく、副作用が限定的で、今回直す合理性が高いもの。
ただしMerge阻害ではない。

### FOLLOW-UP

指摘自体は妥当だが、今回のIssue目的達成には不要なもの。
既存コード、未変更領域、設計改善、追加堅牢化、将来拡張、別責務の改善は原則ここに分類する。

### DISMISS

誤検知、根拠不足、スタイル差、重複指摘、すでに解消済みのもの。

## レビュー収束ルール

初回レビューと修正後レビューを区別する。

### 初回レビュー

PR全体を対象にしてよい。
P0 / P1 / P2を収集し、P2を上記4分類へ整理する。

### 修正後レビュー

品質改善の新規探索を目的にしない。
確認対象は以下に限定する。

- 前回BLOCKINGが解消したか
- 今回の修正差分が新たな重大回帰を発生させていないか
- Issue受入条件を満たしているか
- CI / securityが成功しているか

修正後に新たなP2が出た場合は、まず「今回の修正が直接原因か」を確認する。

- 直接原因で、具体的な重大不具合になる: BLOCKING候補
- 修正をきっかけに見つかっただけ: FOLLOW-UP
- 改善・堅牢化・将来懸念: FOLLOW-UP
- 既存問題: FOLLOW-UP
- 根拠不足: DISMISS

非BLOCKINGのP2は、理由をコメントしてthreadをresolveし、追加修正ループへ戻さない。

## 修正範囲が膨らんだ場合

レビュー修正を重ねて当初Issueから大きく逸脱した場合、さらに修正を積み増さない。
次を整理する。

- 残すべき変更
- 戻すべき変更
- FOLLOW-UP Issueへ分離すべき変更

必要なら追加修正よりrevertを優先する。

## 前提

- repo rootで実行する。
- `git` / `gh` / `python3` が利用可能。
- 対象repositoryのhostに対する `gh auth status --hostname <HOST>` が成功する。
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
- originから導出した対象hostだけ `gh auth status --hostname` で認証確認する
- GitHub操作対象を検証済みoriginから固定
- remote-tracking refを明示refspecで更新
- 既存head branchをcheckout
- local HEAD = GitHub PR head SHA

checkout前にscriptsを一時ディレクトリへ退避し、Skill追加前の古いPR branchでも後続scriptを利用可能にする。

### 2. 最新レビュー指摘を取得

```bash
HOST="${REPO%%/*}"
REPO_PATH="${REPO#*/}"

gh pr view <PR番号> --repo "$REPO" --comments

gh api --hostname "$HOST" --paginate --slurp \
  "repos/$REPO_PATH/pulls/<PR番号>/comments?per_page=100"

gh api --hostname "$HOST" --paginate --slurp \
  "repos/$REPO_PATH/pulls/<PR番号>/reviews?per_page=100"
```

古いheadのoutdated指摘と現在headの有効指摘を区別する。
現在有効なP0/P1はBLOCKINGとして扱い、P2は自動修正せず分類へ回す。

### 3. Issue範囲と受入条件を確認

PR本文の `Closes #XX` 等からIssueを確認し、Issue本文を仕様基準にする。

- Issue範囲内: 分類後に必要なものだけ修正
- Issue範囲外: FOLLOW-UPまたは停止して報告
- 仕様曖昧: 推測せず人間へ確認

### 4. 指摘を分類

現在有効な指摘を以下へ整理する。

- P0 / P1: BLOCKING
- P2: `BLOCKING / IN-SCOPE FIX / FOLLOW-UP / DISMISS`
- P3: 原則FOLLOW-UPまたはDISMISS

P2をBLOCKINGと判定する場合は、具体的な失敗条件・再現経路・PR差分との因果・Issue受入条件との関係を記録する。

### 5. 同じhead branch上で修正

修正対象は次だけに限定する。

- P0 / P1
- BLOCKINGと判定したP2
- 必要なら副作用が限定的なIN-SCOPE FIX

FOLLOW-UP / DISMISSはコード修正しない。

```bash
test "$(git branch --show-current)" = "$HEAD_BRANCH"
test -z "$(git status --porcelain)"
```

### 6. commit / push

```bash
git status --short
git diff --check
git add <変更ファイル>
git commit -m "review: Codex指摘を修正"
EXPECTED_SHA="$(git rev-parse HEAD)"
git push origin "HEAD:refs/heads/$HEAD_BRANCH"
```

prepare scriptでoriginのfetch URLと全push URLが同じrepository identityであることを確認済みでなければpushしない。

### 7. push後SHA照合

```bash
bash "$VERIFY_SCRIPT" <PR番号> "$EXPECTED_SHA" "$BEFORE_SHA" "$REPO"
```

以下すべて必須。

- `EXPECTED_SHA != BEFORE_SHA`
- local HEAD = `EXPECTED_SHA`
- GitHub PR head SHA = `EXPECTED_SHA`
- current branch = `HEAD_BRANCH`
- working tree clean

不一致なら再検証へ進まず停止する。

### 8. 更新後SHAでローカル再検証

```bash
test -z "$(git status --porcelain)"
test "$(git rev-parse HEAD)" = "$EXPECTED_SHA"
```

標準検証入口 `./scripts/verify.sh` を実行する。
内部順序は lint → type check → test → build とし、存在しない工程は対象外理由を記録する。
標準入口を実行できない場合は成功扱いにせず停止する。

### 9. CI / securityを対象SHAで待機・確認

```bash
bash "$RUNTIME_DIR/scripts/wait-checks.sh" "$REPO" "$EXPECTED_SHA"
```

check未観測やsuccess以外の結果を成功扱いにしない。

### 10. 更新後headへ再レビュー依頼

修正後レビューでは、新規の品質改善探索ではなく、BLOCKING解消と修正差分による重大回帰確認に限定する旨を明示する。

```bash
HOST="${REPO%%/*}"
REPO_PATH="${REPO#*/}"

REVIEW_BASELINE_ID="$(
  gh api --hostname "$HOST" --paginate --slurp \
    "repos/$REPO_PATH/pulls/<PR番号>/reviews?per_page=100" \
  | python3 -c 'import json,sys; pages=json.load(sys.stdin); ids=[int(r.get("id") or 0) for p in pages for r in (p if isinstance(p,list) else [p])]; print(max(ids, default=0))'
)"

REVIEW_REQUEST_BODY="$(cat <<EOF
更新後head \`$EXPECTED_SHA\` を対象に再レビューしてください。

確認対象は、前回BLOCKINGの解消、今回の修正差分による重大回帰、Issue受入条件違反、セキュリティ問題に限定してください。
既存コード、未変更領域、設計改善、追加堅牢化、将来懸念は今回の修正要求対象外です。
新しいP2相当を発見した場合も、自動的に必須修正とはせず、具体的なBLOCKING根拠がある場合だけ指摘してください。

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
```

依頼直前の最大PR review IDと依頼comment IDをfreshness基準として記録する。

### 11. 再レビュー結果を判定

```bash
bash "$RUNTIME_DIR/scripts/wait-codex-review.sh" \
  "$REPO" <PR番号> "$EXPECTED_SHA" \
  "$REVIEW_REQUEST_COMMENT_ID" "$REVIEW_BASELINE_ID"
```

`wait-codex-review.sh` はP0/P1とP2を分離する。

- `STATUS=REVIEW_CHANGES_REQUIRED`: P0/P1あり。修正ループへ戻る。
- `STATUS=REVIEW_P2_CLASSIFICATION_REQUIRED`: P2あり。自動修正せず、このSkillのP2分類ルールで判定する。
- `STATUS=REVIEW_PASSED`: P0/P1/P2の未処理指摘なし。
- timeout: 再レビュー待ちとして停止。

`REVIEW_P2_CLASSIFICATION_REQUIRED` の場合:

1. 各P2を `BLOCKING / IN-SCOPE FIX / FOLLOW-UP / DISMISS` に分類する。
2. BLOCKINGだけ修正する。
3. 非BLOCKINGは理由をPRコメントまたはthread replyへ記録する。
4. 非BLOCKING threadはresolveする。
5. 非BLOCKING P2だけが残ったことを理由に再修正・再レビューを繰り返さない。

### 12. 最終SHA再照合

```bash
bash "$VERIFY_SCRIPT" <PR番号> "$EXPECTED_SHA" "$BEFORE_SHA" "$REPO"
test -z "$(git status --porcelain)"
```

CI / security / Codex Reviewがすべて `EXPECTED_SHA` 対象だったことを確認する。

### 13. 最終収束判定

以下をすべて満たしたらレビュー修正を終了する。

- Issue受入条件を満たす
- 標準検証成功
- CI / security成功
- P0 / P1なし
- BLOCKING判定されたP2なし
- 今回PR起因の明確な不具合・回帰・セキュリティ問題なし

**P2が0件であることは完了条件ではない。**

### 14. 最終報告

最低限、以下を報告する。

- PR番号 / repository / head branch
- 修正前後SHA / push SHA
- P0 / P1 / P2の件数と分類
- BLOCKING残件
- FOLLOW-UP / DISMISS項目
- Issue受入条件の充足状況
- 標準検証 `./scripts/verify.sh`
- CI / security
- 再レビュー対象SHA
- 不要に拡大した変更の有無
- `マージ可能` または `まだマージ不可` の結論

最後に「最終Mergeは人間判断」と明記して停止する。

## 参考事例

AI-Memory-RAG PR #39では、P2修正後に新たなP2が発生し続け、レビュー修正が長期化した。
最終的に、Issue受入条件・今回PR起因の明確な不具合/回帰/セキュリティ問題・CI成功に確認範囲を限定し、既存コード・未変更領域・設計改善・追加堅牢化・将来懸念を修正要求から除外したことで `BLOCKINGなし` に収束した。

このSkillでは同じ失敗を防ぐため、レビューコメント0件ではなくBLOCKING 0件を完了条件とする。

## 禁止操作

- PR headと異なる名前でのbranch作成
- `gh pr create`
- `gh pr merge`
- default branchへの直接push
- force push
- `@codex address that feedback`
- 代替branch / follow-up PR作成
