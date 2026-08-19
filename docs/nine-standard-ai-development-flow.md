# Nine標準AI開発フロー

## ChatGPT × GitHub × Codex × GitHub Actions

## 1. 基本方針

開発は原則として次の流れで進める。

**要望 → ChatGPTで要件整理・設計 → GitHub親Issue → 子Issue → Codex実装 → ローカルテスト → PR → GitHub Actions CI → セキュリティチェック → AIレビュー → 人間確認 → Merge**

大きな計画をCodexへ一括投入せず、レビュー可能な単位まで分割する。

原則は **1子Issue = 1 PR**。

品質保証は、Codex側の自己チェックとGitHub側の強制チェックを二重化する。

## 2. ChatGPTの役割

ChatGPTは開発マネージャー兼設計担当として使う。

開発開始時に整理する項目：

- 何を作るか
- なぜ作るか
- 利用者
- 必要機能
- 使用技術
- 現在の環境
- 完成条件
- セキュリティ上の制約
- 今回やらないこと

標準依頼文：

> この開発内容をGitHub Issueベースで実装できる形に整理してください。親Issueと1 PR単位の子Issueに分解し、各子Issueには完了条件、変更対象、変更禁止範囲、テスト条件、依存関係を書いてください。

## 3. 親Issue

親Issueは実装指示ではなくプロジェクト全体のロードマップとして使う。

含める項目：

- 目的
- 背景
- 今回実装する範囲
- 子Issue一覧
- 後続候補
- 今回やらないこと
- 全体完了条件

## 4. 子Issue

子IssueはCodexが実装でき、かつ人間が1 PRとしてレビューできるサイズにする。

各子Issueには以下を必ず含める。

- 目的
- 実装内容
- やらないこと
- 変更してよい範囲
- 原則変更しない範囲
- 完了条件
- テスト
- 依存関係

子IssueはGitHub登録前に `docs/issue-quality-check.md` に従って妥当性チェックを行う。

## 5. Codex実装

Codexには原則として子Issueを1件ずつ渡す。

標準指示：

> GitHub Issue #XXを実装してください。Issue記載内容を仕様の基準とし、範囲外の実装や不要なリファクタリングを行わず、必要なテストを追加してください。lint / type check / test / buildのうちプロジェクトで定義されているものを実行し、完了したらPRを作成してください。PR作成後はGitHub Actions CIと利用可能なセキュリティチェックの結果も確認してください。仕様だけでは判断できない重大な問題は推測で拡張しないでください。

## 6. 並列化

独立している子Issueのみ並列実行する。

直列化を優先する例：

- 同じファイルを変更する
- 共通設定を変更する
- 共通型を変更する
- データモデル→API→UIのような依存関係がある
- package管理ファイルを複数Issueが変更する

並列実行する場合は可能ならIssueごとにbranch/worktreeを分離する。

## 7. PR

Codex実装終了後は以下の流れとする。

**Issue → Branch → 実装 → ローカルテスト → Commit → PR → GitHub Actions CI → セキュリティチェック**

PR本文には最低限以下を書く。

- 対応Issue
- 変更内容
- ローカルテスト結果
- GitHub Actions CI結果
- セキュリティチェック結果（有効な場合）
- 注意点・残課題

### Merge後のbranch管理

PRをMergeした後は、役目を終えたIssue用の短命head branchを原則削除する。

新規リポジトリでは、SettingsのPull Requests設定にある `Automatically delete head branches` をONにし、Merge済みPRのIssue用head branchが自動削除されるようにする。

`main` などの保護対象branchは削除禁止を維持する。自動削除の対象はMerge済みPRのIssue用head branchであり、保護対象branchとは区別して扱う。

次のIssueに着手するときは、最新の `main` から新しいIssue用branchを作成する。

## 8. GitHub Actions CI

各プロジェクトでは原則として `main` 向けPull RequestでCIを自動実行する。

技術スタックに応じて、以下を自動検証する。

- dependency install
- lint
- type check
- unit / integration tests
- build

標準テンプレート：

- `templates/github-actions/node-ci.yml`
- `templates/github-actions/python-ci.yml`
- `templates/github-actions/generic-ci.yml`

新規プロジェクト準備時は、技術スタックに合うテンプレートを `.github/workflows/ci.yml` として配置し、実際のコマンドやバージョンに合わせて調整する。

CodexのローカルテストとGitHub Actions CIは二重チェックとして扱う。

CIが失敗しているPRは原則mergeしない。

## 9. GitHub側ガードレール

GitHub側の標準防御は `docs/github-repository-security-baseline.md` に従う。

### Ruleset / Branch Protection

`main` は保護し、可能な範囲で以下を強制する。

- Pull Request経由の変更
- GitHub Actions CIのrequired status check
- force push禁止
- `main` など保護対象branchの削除禁止
- mainへの直接push禁止

AIエージェントが誤った操作を試みてもGitHub側で止められる状態を目標とする。

### Dependabot

依存関係更新を定期確認する。

標準テンプレート：

- `templates/dependabot/dependabot-node.yml`
- `templates/dependabot/dependabot-python.yml`

各プロジェクトでは `.github/dependabot.yml` として配置する。

Dependabot PRも通常のCI・レビューを通してmergeする。

### Secrets

- `.env` をcommitしない
- API key / token / passwordをコード、Issue、PR本文へ書かない
- GitHub Actionsで必要な秘密情報はGitHub Actions Secrets等から参照する
- Secret scanning / push protectionが利用可能なら有効化する
- ログへの秘密情報出力を避ける

### CodeQL / Code Scanning

利用可能なプロジェクトではCodeQLまたはcode scanningを有効化する。

標準workflow：`templates/github-actions/codeql.yml`

対象言語はプロジェクトに合わせて変更する。利用条件を満たさない場合は、その事実を記録し、CIとレビューで補完する。

## 10. CI / セキュリティチェック失敗時

失敗した場合は以下の順で対応する。

1. 失敗したjob / step / alertを確認する。
2. ログや検出内容から原因を特定する。
3. Issue範囲内で修正する。
4. PR branchへ追加commitする。
5. 自動チェックの再実行結果を確認する。
6. 成功するまで完了扱いにしない。

チェックを通すためにテストやセキュリティ検査を削除・無効化しない。

## 11. レビュー

自動チェック成功後はAIレビューと人間レビューを組み合わせる。

確認ポイント：

- Issueの要求を満たしているか
- Issue範囲外の変更がないか
- テストが十分か
- GitHub Actions CIが成功しているか
- セキュリティチェックに重大な問題がないか
- 不要な依存追加がないか
- 既存機能への影響がないか

最終mergeは人間が判断する。

## 12. プロジェクト規模

### 小規模

1 Issue → Codex → 1 PR → CI / Security → Merge

### 中規模

親Issue → 3〜8程度の子Issue → 各PR → CI / Security → Merge

### 大規模

親Issue → Phase分割 → 子Issue → 各PR → CI / Security → Merge

大規模プロジェクトではPhase間の依存関係を明示する。

## 13. 新規リポジトリ準備

新規プロジェクトのリポジトリを作成したら、標準として以下を準備する。

- `AGENTS.md`
- `.github/ISSUE_TEMPLATE/`
- `.github/pull_request_template.md`
- `.github/workflows/ci.yml`
- Ruleset / branch protection
- Merge済みPRのhead branch自動削除（`Automatically delete head branches`）- `.github/dependabot.yml`
- GitHub Actions Secrets（必要な場合）
- Secret scanning / push protection（利用可能な場合）
- CodeQL / code scanning（利用可能な場合）

詳細チェックリストは `docs/github-repository-security-baseline.md` を参照する。

## 14. 短縮指示

ChatGPTに **「GitHub Issue方式で計画して」** と依頼された場合、原則として以下を作る。

- 親Issue
- 1 PR単位の子Issue
- 子Issue妥当性チェック
- 依存関係
- 並列/直列判断
- Codex用指示
- 完了条件
- 推奨CI構成
- 推奨GitHubガードレール

**「Codex実装用にして」** と依頼された場合、各子IssueをCodexがそのまま実行できる粒度まで具体化する。

## 15. 基本原則

**ChatGPTは考える。**

**GitHubは仕事を管理する。**

**Codexは実装し自己チェックする。**

**GitHub Actionsは機械的に再検証する。**

**GitHub Ruleset / Securityは誤操作と脆弱性を止める。**

**PRは品質の関門にする。**

**人間は仕様とマージを決める。**
