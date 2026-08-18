# Nine標準AI開発フロー

## ChatGPT × GitHub × Codex × GitHub Actions

## 1. 基本方針

開発は原則として次の流れで進める。

**要望 → ChatGPTで要件整理・設計 → GitHub親Issue → 子Issue → Codex実装 → ローカルテスト → PR → GitHub Actions CI → AIレビュー → 人間確認 → Merge**

大きな計画をCodexへ一括投入せず、レビュー可能な単位まで分割する。

原則は **1子Issue = 1 PR**。

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

> GitHub Issue #XXを実装してください。Issue記載内容を仕様の基準とし、範囲外の実装や不要なリファクタリングを行わず、必要なテストを追加してください。lint / type check / test / buildのうちプロジェクトで定義されているものを実行し、完了したらPRを作成してください。PR作成後はGitHub Actions CIの結果も確認してください。仕様だけでは判断できない重大な問題は推測で拡張しないでください。

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

**Issue → Branch → 実装 → ローカルテスト → Commit → PR → GitHub Actions CI**

PR本文には最低限以下を書く。

- 対応Issue
- 変更内容
- ローカルテスト結果
- GitHub Actions CI結果
- 注意点・残課題

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

可能な場合はGitHubのbranch protection / rulesetでCI status checkを必須化する。

## 9. CI失敗時

CIが失敗した場合は以下の順で対応する。

1. 失敗したjob / stepを確認する。
2. ログから原因を特定する。
3. Issue範囲内で修正する。
4. PR branchへ追加commitする。
5. Actionsの再実行結果を確認する。
6. 成功するまで完了扱いにしない。

CIを通すためにテストを削除・無効化したり、Issue範囲外の大規模変更を行わない。

## 10. レビュー

CI成功後はAIレビューと人間レビューを組み合わせる。

確認ポイント：

- Issueの要求を満たしているか
- Issue範囲外の変更がないか
- テストが十分か
- GitHub Actions CIが成功しているか
- セキュリティ問題がないか
- 不要な依存追加がないか
- 既存機能への影響がないか

最終mergeは人間が判断する。

## 11. プロジェクト規模

### 小規模

1 Issue → Codex → 1 PR → CI → Merge

### 中規模

親Issue → 3〜8程度の子Issue → 各PR → CI → Merge

### 大規模

親Issue → Phase分割 → 子Issue → 各PR → CI → Merge

大規模プロジェクトではPhase間の依存関係を明示する。

## 12. 新規リポジトリ準備

新規プロジェクトのリポジトリを作成したら、標準として以下を準備する。

- `AGENTS.md`
- `.github/ISSUE_TEMPLATE/`
- `.github/pull_request_template.md`
- `.github/workflows/ci.yml`

CI workflowはプロジェクトの技術スタックに合わせてテンプレートから選択する。

## 13. 短縮指示

ChatGPTに **「GitHub Issue方式で計画して」** と依頼された場合、原則として以下を作る。

- 親Issue
- 1 PR単位の子Issue
- 子Issue妥当性チェック
- 依存関係
- 並列/直列判断
- Codex用指示
- 完了条件
- 推奨CI構成

**「Codex実装用にして」** と依頼された場合、各子IssueをCodexがそのまま実行できる粒度まで具体化する。

## 14. 基本原則

**ChatGPTは考える。**

**GitHubは仕事を管理する。**

**Codexは実装する。**

**GitHub Actionsは機械的に検証する。**

**PRは品質の関門にする。**

**人間は仕様とマージを決める。**
