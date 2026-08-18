# GitHub Ruleset / Branch Protection 設定ガイド

## 目的

`AGENTS.md` に記載した「mainへ直接pushしない」「CI成功後にMergeする」などのルールを、GitHub側でも強制する。

Nine標準AI開発フローでは、Codex側の自己チェックとGitHub側の強制チェックを二重化する。

## 推奨対象

`main` branch

## 推奨Ruleset名

`protect-main`

## 設定手順

1. 対象GitHubリポジトリを開く。
2. `Settings` を開く。
3. 左メニューの `Rules` → `Rulesets` を開く。
4. `New ruleset` → `New branch ruleset` を選ぶ。
5. Ruleset name に `protect-main` を入力する。
6. Enforcement status を `Active` にする。
7. Target branches で `main` を対象にする。
8. 以下のルールを設定する。

## 標準で有効にするルール

### Require a pull request before merging

有効にする。

目的:

- mainへの直接変更を避ける
- 1 Issue = 1 PR運用をGitHub側でも担保する
- PR差分、CI結果、レビュー履歴を残す

個人開発の初期段階では、承認レビュー人数を必須にすると自分自身でMergeできないケースがあるため、`Required approvals` はまず0またはGitHubプラン/運用に合わせて設定する。

### Require status checks to pass before merging

有効にする。

GitHub Actionsを一度実行してから、CI workflowのstatus checkを必須対象として選択する。

標準CIでは `CI` workflow配下のjobを必須チェックとして指定する。

初回リポジトリでは、CI workflowを配置しただけではstatus check候補が表示されない場合がある。その場合は一度PRまたはpushでActionsを実行してからRulesetへ戻る。

### Block force pushes

有効にする。

### Restrict deletions

main branchを誤って削除しないよう有効化を推奨する。

### Require conversation resolution before merging

レビューコメントを利用するプロジェクトでは有効化を推奨する。

## 最初は任意でよいルール

以下はプロジェクト規模や運用成熟度に応じて追加する。

- Require signed commits
- Require linear history
- Require merge queue
- Require code scanning results
- Required approving reviews

初回の小規模個人開発では、ルールを厳しくしすぎて開発不能になることを避け、まずPR必須・CI必須・force push禁止を中心にする。

## Bypass

原則として通常開発ではRulesetを迂回しない。

管理者等へbypass権限を付ける場合も、緊急時やRuleset設定ミス修正用として扱う。

Codexや通常の自動化処理へ安易にbypass権限を与えない。

## Nine標準推奨値

```text
Ruleset name: protect-main
Status: Active
Target: main

Require pull request: ON
Required approvals: 0（初期個人開発）
Require status checks: ON
Block force pushes: ON
Restrict deletions: ON
Conversation resolution: 推奨
```

## CI必須化のタイミング

新規リポジトリ初期化時は次の順番で設定する。

```text
CI workflow配置
    ↓
最初のPR / Actions実行
    ↓
CI status check名がGitHubに登録される
    ↓
RulesetでRequire status checksをON
    ↓
CI成功しないPRはMerge不可
```

## Bootstrap CIについて

新規リポジトリでは、最初の基盤Issueより前にテストファイルが存在しないことがある。

Nine標準Python CIテンプレートでは、テストファイルがまだ存在しない場合のみBootstrapとしてpytestをskipする。テストファイルが作成された後は、pytestが存在しない・失敗する場合はCIを失敗させる。

この例外は「テストが存在するのにskipする」目的では使わない。

## 確認項目

Ruleset作成後に以下を確認する。

- mainへの直接pushが防止されるか
- PRからMergeできるか
- CI失敗時にMergeがブロックされるか
- CI成功後にMerge可能になるか
- force pushが禁止されているか

実際のプロジェクトで問題があれば、`ai-development` の標準設定自体を見直す。
