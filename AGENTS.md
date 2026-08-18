# AGENTS.md

## Purpose

このリポジトリはNine標準AI開発フローと、AIエージェント向け共通開発ルールを管理する。

各プロジェクトでこのテンプレートを利用する場合、GitHub Issueを実装仕様の基準とし、CodexなどのAIエージェントはIssue単位で安全に作業を進める。

## Core Rules

- GitHub Issueを仕様の基準とする。
- 原則として **1子Issue = 1 PR** とする。
- Issueの範囲外を実装しない。
- 依存Issueが未完了の場合は、原則として着手しない。
- 不要なリファクタリングをしない。
- 既存動作を壊さない。
- 新規機能・バグ修正には必要なテストを追加する。
- 実装後はプロジェクトで定義されたテストを実行する。
- テストを無効化して成功扱いにしない。
- 秘密情報、APIキー、パスワード、`.env` をcommitしない。
- `main`へ直接pushしない。IssueごとのbranchとPRを使う。
- force pushを行わない。
- 指定外の依存関係を安易に追加しない。
- 公開APIや既存インターフェースを勝手に変更しない。
- 判断不能な仕様は推測で拡張せず、Issue上の仕様を優先する。
- 実装とテストが完了したらPRを作成して、そのIssueの作業を終了する。
- warning / deprecationはテスト成功と別に評価し、V1を止めない場合でも必要に応じて後続メンテナンスIssueへ記録する。

## Child Issue Quality Gate

子IssueはGitHub登録・Codex実装前に妥当性チェックを行う。

詳細基準は [`docs/issue-quality-check.md`](docs/issue-quality-check.md) を参照する。

最低限、以下の5項目を確認する。

1. 目的が1つに絞られているか
2. 変更範囲を予測できるか
3. 単独で完了判定・テストできるか
4. 1 PRでレビュー可能か
5. 依存関係が明確か

各項目0〜2点、合計10点で評価し、原則として9点以上をGitHub登録の目標とする。

7〜8点は軽微な修正を行い、6点以下は原則として分割・統合・再設計する。

特に「目的」「完了判定 / テスト可能性」「依存関係」のいずれかが0点の場合は、合計点にかかわらずそのまま実装へ進めない。

Issue化を依頼されたAIは、仮Issueをそのまま登録せず、必要に応じて分割・統合・依存関係の修正を行ってから登録する。

## Issue Selection

複数の未完了Issueがある場合は、以下の順序で着手対象を判断する。

1. 依存Issueがすべて完了しているIssue
2. 親IssueやIssue本文で優先順位が明示されているIssue
3. 他Issueの前提となる基盤・インターフェースのIssue
4. 独立して安全に実装できるIssue

依存関係が不明確、または複数Issueが同じ重要ファイルを変更する可能性が高い場合は、推測で並列実装せず人間に確認する。

Dependabot等の自動保守PRは開発本線の子Issueとは別枠として扱う。開発順序を乱さず、必要に応じて本線完了後または適切な保守タイミングで処理する。

## Issue / PR Rule

実装前にIssueから以下を確認する。

1. 目的
2. 実装範囲
3. やらないこと
4. 変更可能範囲
5. 変更を避ける範囲
6. 完了条件
7. テスト条件
8. 依存Issue

Issue本文とコードベースに矛盾がある場合は、勝手に仕様を変更せず問題を明示する。

## Implementation Workflow

1. 対象Issueを読む。
2. 依存Issueが完了していることを確認する。
3. Issue専用branchを作成する。
4. Issue範囲内だけを実装する。
5. 必要なテストを追加・更新する。
6. tests / lint / type check / build を可能な範囲で実行する。
7. 失敗があればIssue範囲内で原因を修正する。
8. 変更内容を自己レビューする。
9. PRを作成する。
10. GitHub Actions CIの結果を確認する。
11. CI失敗時は原因を修正し、成功するまでPRを完了扱いにしない。
12. PR本文に対応Issue、変更内容、テスト結果、CI結果、注意点を記載する。
13. PR作成後は勝手に次のIssueへ範囲を拡張しない。

## Parent Issue Completion

子IssueのPRが `Closes #<Issue番号>` で自動Closeされても、親Issue本文の子Issueチェックボックスは自動更新されない場合がある。

親IssueをCloseする前に以下を必ず確認する。

1. すべての必要な子IssueがMerge / Close済みか。
2. 親Issue本文の子Issueチェックボックスを最終状態へ更新したか。
3. 全体完了条件を実際のPR、CI、セキュリティチェック、手動確認結果と照合したか。
4. warning / deprecation等の残課題を確認し、必要なら後続メンテナンスIssueへ切り出したか。
5. 人間が最終確認したか。

## GitHub Actions CI

各プロジェクトでは、原則として `main` 向けPull RequestでGitHub Actions CIを自動実行する。

CIでは、技術スタックに応じて以下を可能な範囲で自動検証する。

- dependency install
- lint
- type check
- unit / integration tests
- build

標準テンプレートは以下を使用する。

- Node.js: `templates/github-actions/node-ci.yml`
- Python: `templates/github-actions/python-ci.yml`
- その他: `templates/github-actions/generic-ci.yml`

各プロジェクトでは選択したテンプレートを `.github/workflows/ci.yml` として配置し、そのプロジェクトの実コマンドに合わせて調整する。

PythonのBootstrap例外は、まだテストファイルが存在しない初期基盤期間だけに限定する。最初のテストが追加された後はpytestが実行・成功することを必須とする。

CIが失敗しているPRは原則mergeしない。

Codexがローカルでテスト済みと報告していても、GitHub Actionsによる再検証を省略しない。

## GitHub Guardrails

GitHub側の強制チェックは [`docs/github-repository-security-baseline.md`](docs/github-repository-security-baseline.md) を標準とする。

新規プロジェクトでは可能な範囲で以下を設定する。

- Ruleset / branch protectionでPR経由を必須化
- GitHub Actions CIをrequired status checkにする
- force pushとmainの直接変更を禁止
- Dependabotを設定
- SecretsはGitHub Actions Secrets等で管理
- Secret scanning / push protectionが利用可能なら有効化
- CodeQL / code scanningが利用可能なら有効化

Codex側の自己チェックだけ、GitHub側の自動チェックだけ、のどちらか一方に依存しない。

## Dependabot

依存関係は技術スタックに応じてDependabotで定期確認する。

標準テンプレート:

- Node.js: `templates/dependabot/dependabot-node.yml`
- Python: `templates/dependabot/dependabot-python.yml`

各プロジェクトでは `.github/dependabot.yml` として配置する。

Dependabotが作成したPRは開発本線のIssue番号とは別の保守PRである。PR番号が本線の番号の間に入ることは正常であり、作業順序の根拠にはしない。

Dependabot PRも通常のCIとレビューを通してからmergeする。古いベースで作成されCIが失敗している場合は、最新mainへrebase / updateしてCIを再実行してから判断する。

メジャーバージョン更新ではrelease notesとbreaking changesを確認し、CI成功だけでなくワークフローの用途との互換性も確認する。

## Secrets

- `.env` をcommitしない。
- API key / token / passwordをコード、Issue、PR本文へ直接記載しない。
- GitHub Actionsで必要な秘密情報は原則としてGitHub Actions Secretsから参照する。
- ログへ秘密情報を出力しない。
- Secret scanning / push protectionが利用可能な場合は有効化する。

## CodeQL / Code Scanning

利用可能なプロジェクトではCodeQLまたはGitHub code scanningを有効化する。

標準workflow: `templates/github-actions/codeql.yml`

対象言語はプロジェクトに合わせて調整する。

プラン、リポジトリ種別、対象言語等の条件により利用できない場合は、その事実を記録し、通常CIとレビューで補完する。

## Before PR

プロジェクトで定義されている場合、PR作成前に以下を実行する。

- tests
- lint
- type check
- build

失敗した場合は原因を確認し、Issue範囲内で修正する。

実行できないテストや検証がある場合は、成功したことにせずPR本文に理由を明記する。

warning / deprecationが残る場合はPR本文へ記載し、現Issueで解消しない合理的理由と後続対応の要否を明確にする。

## PR Description

PRには最低限以下を書く。

- 対応Issue
- 変更内容
- ローカルテスト結果
- GitHub Actions CI結果
- セキュリティチェック結果（有効な場合）
- warning / deprecationの有無
- 注意点・残課題

可能な場合は `Closes #<Issue番号>` を使用し、PRのmergeとIssueの完了を関連付ける。

## Prohibited Actions

- Issueにない機能を先回りして追加する。
- 別Issueの作業を同じPRへ混ぜる。
- テスト失敗を隠す。
- GitHub Actions CIの失敗を無視して完了扱いにする。
- セキュリティチェックを回避する。
- 秘密情報をコードへ埋め込む。
- 人間の承認なしに破壊的変更を行う。
- `main`へ直接pushする。
- force pushする。

## Human Decision Points

以下は人間の判断を優先する。

- 仕様確定
- Issue範囲の変更
- Issue間の優先順位が不明確な場合の判断
- 破壊的変更
- セキュリティ上重要な判断
- CI例外の許可
- セキュリティチェック例外の許可
- mainへのmerge

## Standard Codex Instruction

Codexにリポジトリを指定して作業させる場合の基本指示は次のとおりとする。

> このリポジトリのGitHub Issueを確認し、未完了Issueを依存関係と優先順位に従って実装してください。AGENTS.mdを遵守し、1 Issue = 1 PRで進めてください。各Issueで必要なテストを実行し、Issueの範囲外は実装しないでください。PR作成後はGitHub Actions CIと利用可能なセキュリティチェックの結果を確認し、失敗している場合はIssue範囲内で修正してください。依存関係や仕様が不明確な場合は推測で進めず確認してください。
