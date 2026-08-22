# AGENTS.md

## Purpose

このリポジトリはNine標準AI開発フローと、AIエージェント向け共通開発ルールを管理する。

各プロジェクトでこのテンプレートを利用する場合、GitHub Issueを実装仕様の基準とし、CodexなどのAIエージェントはIssue単位で安全に作業を進める。

## Core Rules

- GitHub Issueを仕様の基準とする。
- 原則として **1子Issue = 1 PR** とする。
- Issueの範囲外を実装しない。
- Issue設計時のテスト条件では、正常値、値の範囲、整合性、境界値、異常系、回帰テストの6観点を検討する。
- 不具合修正Issueでは、可能な限り修正前の実装では失敗し、修正後の実装では成功する回帰テストを追加する。
- 依存Issueが未完了の場合は、原則として着手しない。
- 不要なリファクタリングをしない。
- 既存動作を壊さない。
- 新規機能・バグ修正には必要なテストを追加する。
- テストの追加・更新・統合・削除では、検証責務がどこで保証されるかを明確にする。
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

## GitHub上の言語

人間が読むGitHub上の文章は、原則として日本語で記述する。

日本語を原則とする対象:

- Pull Requestのタイトル
- Pull Requestの本文
- Issueへのコメント
- Pull Requestへの作業報告・修正報告
- レビュー指摘への返信
- Commit message
- READMEや運用ドキュメントなどの人間向け文書

以下は英語のままでよい:

- ソースコード
- 変数名、関数名、クラス名等の識別子
- API名、ライブラリ名、パッケージ名
- CLIコマンド、ファイルパス、設定キー
- 外部サービスやツールが出力したエラーメッセージの原文
- GitHub Actions等で技術上英語が適切な識別子
- Dependabot等の外部サービスが自動生成するタイトル・本文

英語の技術用語を無理に翻訳して意味を曖昧にしない。日本語説明の中で必要に応じて英語の固有名詞・識別子をそのまま使用する。

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

## RAG Architecture Standard

RAGを新規構築・変更する場合は [`docs/architecture/rag-guidelines.md`](docs/architecture/rag-guidelines.md) を標準設計指針として参照する。

原則として最小構成から開始し、検索品質・回答品質・運用コストを評価してから上位Phaseへ進む。高機能であることだけを理由にRAPTORやGraphRAG等を先行導入しない。

RAGを採用する各プロジェクトでは、原則として `docs/architecture/rag-design.md` を作成し、少なくとも次を記録する。

- 採用Phase
- 採用するRetriever / Reranker / Metadata構成
- 未採用Phaseと理由
- 品質評価指標
- 標準から逸脱する場合の理由

本番RAGでは、引用・出典追跡・根拠整合性・ハルシネーション検証・権限制御を要件に応じて評価対象とする。

## Test Design / Safe Test Deletion

テストは「数を増やすこと」ではなく、「必要な検証責務を適切な層で保証すること」を目的とする。

原則として、次のように責務に応じてテスト種別を選ぶ。

- ビジネスロジック、計算、値変換、境界条件: Unit Test
- HTTP入力、Controller、API契約、認証・認可、入力バリデーション: Controller / API Test
- SQL、永続化、DB制約、Repository境界: Repository Test
- 複数コンポーネントの接続、主要ユースケース: Integration Test
- ユーザー視点の重要なHappy Path、システム全体の接続確認: E2E Test

すべてをIntegration / E2Eで検証する設計は避ける。遅いテストや重複テストが増えた場合は、責務をより小さいテスト層へ移せないか検討する。

既存テストを削除・統合する場合は、削除前に以下を確認する。

1. そのテストが何を保証しているか説明できる。
2. 同じ検証責務が別のテストで保証されている、または不要になった合理的理由がある。
3. 責務を別テストへ移す場合は、新しいテストが先に追加され成功している。
4. 認証・認可、入力検証、Repository境界、重要な回帰テストなどの安全性確認が失われない。
5. 重要なHappy Path / Integration / E2Eの安全網が必要に応じて残っている。
6. 削除理由と検証責務の移行先をPR本文またはIssueで説明できる。

「CIを速くしたい」「テストが遅い」「コード量を減らしたい」だけを理由に、検証責務の所在を確認せずテストを削除してはいけない。

テスト移行では、可能な限り **新しいテストを追加して成功を確認してから古いテストを削除する**。大規模なテスト整理では、ドメインや責務ごとにIssue / PRを分け、比較可能な状態を保ちながら段階的に進める。

## Implementation Workflow

1. 対象Issueを読む。
2. 依存Issueが完了していることを確認する。
3. Issue専用branchを作成する。
4. Issue範囲内だけを実装する。
5. 必要なテストを追加・更新する。削除・統合を伴う場合は検証責務の移行先を確認する。
6. tests / lint / type check / build を可能な範囲で実行する。
7. 失敗があればIssue範囲内で原因を修正する。
8. 変更内容を自己レビューする。
9. PRを作成する。
10. GitHub Actions CIの結果を確認する。
11. CI失敗時は原因を修正し、成功するまでPRを完了扱いにしない。
12. CI成功後にCodex Code Reviewを実行する。Automatic reviewsが有効な場合は自動結果を確認し、無効な場合はPRで `@codex review` を依頼する。
13. P0 / P1 / P2指摘がある場合はIssue範囲内で修正する。修正は既存PRのhead branchで行い、新しいPRを作成しない。修正前後のPR番号・head branch・head SHAを記録し、同じhead branchへのcommit/push後にhead SHAが更新されたことを確認してから、ローカルテスト、GitHub Actions CI、利用可能なセキュリティチェックを再実行し、更新後のheadを対象に再レビューする。
14. P0 / P1が解消され、P2がないか人間が残置理由を確認し、CIが成功し、利用可能なセキュリティチェックが成功または人間が例外を明示判断した状態で人間の最終確認へ進む。
15. PR本文に対応Issue、変更内容、テスト結果、CI結果、Codexレビュー結果、注意点を記載する。
16. PR作成後は勝手に次のIssueへ範囲を拡張しない。

## Parent Issue Completion

子IssueのPRが `Closes #<Issue番号>` で自動Closeされても、親Issue本文の子Issueチェックボックスは自動更新されない場合がある。

親IssueをCloseする前に以下を必ず確認する。

1. すべての必要な子IssueがMerge / Close済みか。
2. 親Issue本文の子Issueチェックボックスを最終状態へ更新したか。
3. 全体完了条件を実際のPR、CI、セキュリティチェック、AIレビュー、手動確認結果と照合したか。
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

## Code Review Rules

Codex Code Reviewを、GitHub Actions CI後・人間の最終確認前の標準品質ゲートとして使用する。

### 起動方法

- CodexのAutomatic reviewsが利用可能なリポジトリでは、原則として自動レビューを有効化する。
- Automatic reviewsが無効または利用できない場合は、PR上で `@codex review` を実行してレビューを依頼する。
- 実装担当Codexの自己レビューだけで完了扱いにせず、PR単位のCodex Code Review結果を確認する。

### レビュー観点

最低限、以下を確認する。

- IssueのAcceptance Criteria / 完了条件を満たしているか
- Issue範囲外の変更が混ざっていないか
- 明確なバグ、回帰、境界値・異常系の見落としがないか
- 必要なテストが不足していないか
- 認証・認可、秘密情報、入力検証などのセキュリティ上の問題がないか
- 不要な依存関係や破壊的変更がないか
- テスト削除・skip・例外握りつぶし等で品質ゲートを回避していないか

### SeverityとMerge条件

- **P0 / P1**: Merge禁止。必ず修正する。
- **P2**: 原則としてMerge前に修正する。修正しない場合は人間が理由を確認して明示的に判断する。
- **P3**: 改善候補。原則としてMerge阻害条件にはしない。必要なら後続Issueへ切り出す。

標準Merge条件は次のとおりとする。

- GitHub Actions CI成功
- 利用可能なセキュリティチェック成功、または人間が例外を明示判断
- Codex Code ReviewのP0 / P1が0件
- P2が0件、または人間が残置理由を明示判断
- 人間の最終確認完了

### 修正ループ

CodexレビューでP0 / P1 / P2が見つかった場合は、次の順で対応する。

1. 指摘内容がIssue範囲内か確認する。
2. `@codex review` はレビュー専用として実行し、レビュー結果と対象PRを記録する。レビュー実行自体で修正・commit・push・PR作成は行わない。
3. 修正前に対象PR番号、既存PRのhead branch、修正前のhead SHAを確認して記録する。
4. Issue範囲内の修正は、Codex Desktop/Work等で既存PRのhead branchをチェックアウトして行う。PRコメントから修正を実行する標準手順にはせず、新しいPRも作成しない。
5. 修正後は同じhead branchへcommit/pushし、修正前後のhead SHAが実際に更新されたことを確認する。SHAを確認できない、または更新されていない場合は、ローカルテスト・CI・セキュリティチェック・再レビューへ進まず確認を止める。
6. head SHAの更新確認後に、tests / lint / type check / build、GitHub Actions CI、利用可能なセキュリティチェックをこの順序で再実行する。
7. CIと利用可能なセキュリティチェックが成功、または例外を人間が明示判断した後に、更新後のheadを対象として `@codex review` を再実行し、指摘が解消されたことと新しいP0 / P1 / P2がないことを確認する。
8. 同じ問題を3回以上繰り返す、仕様判断が必要、破壊的変更が必要、Issue範囲外へ広がる、または同じhead branchへのpushができない場合は自律修正を停止して人間に判断を求める。

AIレビューは品質判断を補助するものであり、AI自身にMerge権限を委譲しない。最終Mergeは必ず人間が判断する。

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
- Codex Code Review結果（P0 / P1 / P2 / P3と未解決指摘）
- warning / deprecationの有無
- 注意点・残課題

テストを削除・統合した場合は、削除対象が担っていた検証責務と、その責務を削除後にどこで保証するかを記載する。

可能な場合は `Closes #<Issue番号>` を使用し、PRのmergeとIssueの完了を関連付ける。

## Prohibited Actions

- Issueにない機能を先回りして追加する。
- 別Issueの作業を同じPRへ混ぜる。
- テスト失敗を隠す。
- 検証責務の移行先を確認せず、単にCI高速化やコード削減を目的としてテストを削除する。
- GitHub Actions CIの失敗を無視して完了扱いにする。
- Codex Code ReviewのP0 / P1を未解決のままMergeする。
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
- CodexレビューのP2を残置する例外判断
- mainへのmerge

## Standard Codex Instruction

Codexにリポジトリを指定して作業させる場合の基本指示は次のとおりとする。

> このリポジトリのGitHub Issueを確認し、未完了Issueを依存関係と優先順位に従って実装してください。AGENTS.mdを遵守し、1 Issue = 1 PRで進めてください。各Issueで必要なテストを実行し、Issueの範囲外は実装しないでください。PR作成後はGitHub Actions CIと利用可能なセキュリティチェックの結果を確認し、失敗している場合はIssue範囲内で修正してください。CI成功後は `@codex review` をレビュー専用で実行し、P0 / P1 / P2指摘があれば対象PRのhead branchをCodex Desktop/Work等でチェックアウトして修正してください。修正前後のPR番号・head branch・head SHAを記録し、同じhead branchへcommit/pushしてhead SHAの更新を確認してから、ローカルテスト、GitHub Actions CI、利用可能なセキュリティチェック、更新後のheadへの `@codex review` を順に再実行してください。SHAを確認できない、更新されていない、同じhead branchへpushできない場合は停止して人間に確認してください。新しいPRは作成せず、最終Mergeは人間が判断します。
