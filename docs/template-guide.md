# Nine標準AI開発テンプレート 利用ガイド

## 1. このリポジトリの役割

`ai-development` は、各AI開発プロジェクトで共通利用する開発ルール・Issue/PRテンプレート・CI/セキュリティ設定の原本を管理するリポジトリです。

新しいプロジェクトでは、このリポジトリの内容をそのまま全部コピーするのではなく、プロジェクトの技術構成に合わせて必要なテンプレートを選び、調整して利用します。

基本思想は次の分担です。

- ChatGPT: 要件整理、設計、親Issue/子Issueの作成、Issue品質チェック
- GitHub: Issue、PR、履歴、CI、セキュリティ、マージ制御
- Codex: Issue単位の実装、ローカルテスト、PR作成、既存PRのhead branchでの修正
- GitHub Actions: Codexとは独立した機械的な再検証
- 人間: 仕様確定、例外判断、最終レビュー、Merge

## 2. 新規プロジェクト開始時の使い方

新しいプロジェクトでは、まずGitHubに対象プロジェクト用リポジトリを作成します。

その後、原則として以下を準備します。

1. `AGENTS.md`
2. `.github/ISSUE_TEMPLATE/parent-issue.md`
3. `.github/ISSUE_TEMPLATE/child-issue.md`
4. `.github/pull_request_template.md`
5. `.github/workflows/ci.yml`
6. Dependabot設定
7. Secrets管理方針
8. 利用可能ならCodeQL
9. Ruleset / Branch protection
10. `Automatically delete head branches` の有効化

設定後、計画書を親Issue・子Issueへ変換し、子Issue単位でCodexに実装させます。

## 3. AGENTS.md

### 目的

CodexなどのAIエージェントに、プロジェクトで守るべき共通ルールを伝えるためのファイルです。

主なルール:

- GitHub Issueを仕様の基準とする
- 1子Issue = 1 PR
- Issue範囲外を実装しない
- 依存Issueを確認する
- mainへ直接pushしない
- 必要なテストを実行する
- GitHub Actions CIの結果も確認する
- Codexレビュー後の修正は既存PRのhead branchへ反映し、head SHA更新を確認する
- 秘密情報をcommitしない
- 仕様が不明確なら推測で拡張しない

### 新規プロジェクトでの扱い

`ai-development/AGENTS.md` を原本として各プロジェクトのルートへ配置し、そのプロジェクト固有のコマンド、ディレクトリ構成、禁止事項などを追記します。

## 4. 親Issueテンプレート

ファイル:

`.github/ISSUE_TEMPLATE/parent-issue.md`

### 目的

プロジェクトや大きな機能全体のロードマップを管理します。

親IssueそのものをCodexへ丸ごと実装させることは原則としません。

親Issueには以下を整理します。

- 目的
- 背景
- 実装範囲
- 子Issue一覧
- 後続候補
- 今回やらないこと
- 全体完了条件

## 5. 子Issueテンプレート

ファイル:

`.github/ISSUE_TEMPLATE/child-issue.md`

### 目的

Codexが実際に実装する作業指示書です。

原則:

**1子Issue = 1 PR**

子Issueには最低限以下を記載します。

- 目的
- 実装内容
- やらないこと
- 変更してよい範囲
- 原則変更しない範囲
- 完了条件
- テスト条件
- 依存Issue

### テスト設計で検討する観点

テスト条件には、正常系だけでなく以下の6観点を具体的に記載します。

1. 正常値 — 期待する値・レスポンスを取得できるか
2. 値の範囲 — 数値などが仕様上の有効範囲内か
3. 整合性 — 関連する複数の値・状態が互いに矛盾していないか
4. 境界値 — 0、最大値、空データなどの境界条件で問題がないか
5. 異常系 — 想定外の入力・戻り値・失敗時に適切に処理できるか
6. 回帰テスト — 既知の不具合が再発した場合に検出できるか

テンプレートでは各観点に、入力値・境界・期待値・期待結果などの具体的なテスト条件を記入する欄を設けています。対象外の場合は、各観点の「対象外の場合の理由」に対象外と判断した理由を記載します。

不具合修正Issueでは、可能な限り「修正前の実装では失敗し、修正後の実装では成功する回帰テスト」を追加します。該当しない場合は、Issue本文に理由を記載します。

## 6. 子Issue品質チェック

ファイル:

`docs/issue-quality-check.md`

子IssueをGitHubへ正式登録する前に、以下の5項目を確認します。

1. 目的が1つか
2. 変更範囲を予測できるか
3. 単独で完了判定・テストできるか
4. 1 PRでレビュー可能か
5. 依存関係が明確か

各項目0〜2点、合計10点で評価します。

- 9〜10点: 原則登録可能
- 7〜8点: 修正してから登録
- 6点以下: 分割・統合・再設計

特に目的、テスト可能性、依存関係のいずれかが0点なら、そのまま実装へ進めません。

## 7. Pull Requestテンプレート

ファイル:

`.github/pull_request_template.md`

### 目的

Codexまたは人間がPRを作成するときの報告形式を統一します。

最低限確認する内容:

- 対応Issue
- 変更内容
- ローカルテスト結果
- GitHub Actions CI結果
- 注意点
- 残課題

可能な場合は `Closes #Issue番号` を使い、Merge時にIssueと連動させます。

### Codexレビュー後の修正

PRテンプレートには、修正時の対象PR番号、head branch、修正前後のhead SHAを記録します。

標準手順は次のとおりです。

1. `@codex review` はレビュー専用として実行する。
2. P0 / P1 / P2の修正は `@codex address that feedback` を標準手順に使わず、既存PRのhead branchをCodex Desktop / Work等でチェックアウトして行う。
3. 修正前にPR番号・head branch・head SHAを確認する。
4. 同じhead branchへcommit / pushし、新しいPRを作らず既存PRを再利用する。
5. pushした修正コミットSHAを検証対象SHAとして記録し、GitHub上の同じPRのhead branchとhead SHAがそのSHAと一致することを確認する。SHAを確認できない、更新されていない、または一致しない場合は再検証へ進まない。
6. 記録した検証対象SHAを固定して、更新後のheadをローカルテスト → CI → セキュリティチェック → `@codex review` の順で再検証し、各チェックの対象SHAを記録する。
7. 再検証完了時に、GitHub上のPR head SHAがpushした修正コミットSHAおよび記録した検証対象SHAと一致することを確認する。不一致の場合は完了扱いにせず停止する。
8. AIはMergeせず、人間が最終Mergeを判断する。


## 8. GitHub Actions CIテンプレート

保存場所:

`templates/github-actions/`

### Node.js

`node-ci.yml`

Node.js / TypeScript系プロジェクト向けです。

主に以下を自動実行します。

- dependency install
- lint
- type check
- test
- build

### Python

`python-ci.yml`

Python系プロジェクト向けです。

プロジェクトで使用するpytest、ruff、mypy等に合わせて調整します。

#### Bootstrap例外

新規リポジトリでは最初の基盤Issueより前にテストファイルが0件の場合があります。この状態でpytestをそのまま実行するとCIが失敗することがあるため、標準Pythonテンプレートは**テストファイルが存在しない期間だけ**Bootstrapとしてpytestをskipします。

テストファイルが1件でも作成された後は、pytest未導入やテスト失敗をCI失敗として扱います。これはテスト回避のための例外ではありません。

### Generic

`generic-ci.yml`

Node.js/Python以外、または技術スタックがまだ確定していないプロジェクトの土台です。

### 配置方法

対象テンプレートを新規プロジェクトの

`.github/workflows/ci.yml`

として配置し、実際のpackage manager、言語バージョン、テストコマンドなどに合わせて変更します。

重要: テンプレートを無調整で利用せず、そのリポジトリで実際に実行できるコマンドか確認します。

## 9. Ruleset / Branch protection

関連資料:

`templates/github-security/ruleset-guide.md`

### 目的

AGENTS.mdに書いたルールを、GitHub側でも強制します。

推奨設定:

- mainへの直接pushを禁止
- Pull Requestを必須化
- GitHub Actions CI成功を必須化
- force push禁止
- `main` など保護対象branchの削除を禁止

Rulesetの削除禁止は `main` などの保護対象branchに適用します。Issue用の短命head branchは、リポジトリ設定の `Automatically delete head branches` をONにして、PR Merge後に原則自動削除します。

### 標準設定手順

1. リポジトリの `Settings` を開く
2. `Rules` → `Rulesets`
3. `New ruleset` → `New branch ruleset`
4. Ruleset名を `protect-main` にする
5. Enforcement statusを `Active`
6. Target branchesで `main` を対象にする
7. `Require a pull request before merging` をON
8. `Require status checks to pass before merging` をON
9. `Block force pushes` をON
10. `Restrict deletions` をON推奨

CIのrequired status checkは、workflowを一度実行しないと候補に出ない場合があります。その場合は最初のPRでActionsを動かした後、Ruleset設定へ戻ってCI checkを必須化します。

個人開発の初期段階ではRequired approvalsを必須にすると自分でMergeできなくなる場合があるため、まず0件で運用し、必要に応じて後から増やします。

詳細は `templates/github-security/ruleset-guide.md` を参照してください。

## 10. Dependabot

テンプレートはプロジェクトのpackage ecosystemに合わせて `.github/dependabot.yml` として配置します。

### 目的

依存パッケージの更新を継続的に確認します。

不要なecosystemは削除し、更新頻度や対象ディレクトリをプロジェクトに合わせます。

## 11. Secrets管理

### 基本原則

- APIキーをソースコードへ書かない
- `.env` をcommitしない
- Actionsで必要な秘密情報はGitHub Secretsを利用する
- ログへ秘密情報を出力しない
- 利用可能ならSecret scanning / push protectionを有効化する

Codexへの指示にも秘密情報をコードへ埋め込まないことを含めます。

## 12. CodeQL

利用可能なリポジトリでは `.github/workflows/codeql.yml` として配置します。

### 目的

GitHub側でソースコードのセキュリティ問題を静的解析します。

CodeQLは通常のCIとは役割が異なります。

- CI: ビルド、lint、型、テストなどの動作検証
- CodeQL: セキュリティ上問題になり得るコードパターンの検出

利用可能な言語・GitHubプラン・リポジトリ設定を確認してから有効化します。

## 13. 二重チェックの考え方

Nine標準AI開発フローでは、AIだけにもGitHubだけにも品質保証を依存しません。

### Codex側

- Issueを理解する
- Issue範囲を守る
- コードを実装する
- テストを書く
- ローカルで検証する
- 自己レビューする

### GitHub側

- Rulesetで危険な操作を禁止する
- Actions CIで独立して再テストする
- Dependabotで依存関係を監視する
- Secrets対策で秘密情報流出を防ぐ
- CodeQLでセキュリティ問題を検査する
- PRとして変更履歴を残す

### 人間側

- 仕様が正しいか判断する
- Issueの分割が適切か確認する
- AIが意図を取り違えていないか確認する
- 例外を認めるか判断する
- 最終Mergeを決定する

この三層構造を基本とします。

## 14. 標準的な開発の流れ

```text
相談・アイデア
    ↓
ChatGPTで計画書
    ↓
親Issue
    ↓
子Issue案
    ↓
子Issue品質チェック
    ↓
GitHubへ子Issue登録
    ↓
Codex実装
    ↓
Codexローカルテスト
    ↓
Pull Request
    ↓
GitHub Actions CI
    ↓
CodeQL等のセキュリティチェック
    ↓
Codex Code Review（レビュー専用）
    ↓
必要なら既存PRのhead branchで修正
    ↓
SHA更新確認 → ローカルテスト → CI → セキュリティチェック → 更新後headを再レビュー
    ↓
人間レビュー
    ↓
Merge
    ↓
Merge済みIssue用branchを自動削除
    ↓
最新mainから次のIssue用branchを作成
    ↓
次の子Issue
```

## 15. 新規リポジトリ初期化チェックリスト

新しい開発リポジトリを作成したら以下を確認します。

- [ ] `AGENTS.md` を配置
- [ ] 親Issueテンプレートを配置
- [ ] 子Issueテンプレートを配置
- [ ] PRテンプレートを配置
- [ ] 技術スタックに合うActions CIを配置
- [ ] 初期Bootstrap時にテスト0件でも意図せずCI失敗しないことを確認
- [ ] 最初のテスト作成後はテスト失敗がCIを確実に失敗させることを確認
- [ ] Ruleset / Branch protectionを設定
- [ ] `Automatically delete head branches` をONにする
- [ ] `main` など保護対象branchの削除禁止とIssue用短命branchの自動削除を確認
- [ ] PR経由を必須化
- [ ] Actions実行後にCI status checkをrequiredに設定
- [ ] force push禁止を確認
- [ ] Dependabotを設定
- [ ] Secrets管理を確認
- [ ] 利用可能ならSecret scanning / push protectionを有効化
- [ ] 利用可能ならCodeQLを有効化
- [ ] 最初の親Issueを作成
- [ ] 子Issue品質チェックを実施

## 16. 普段の短縮指示

ChatGPTには例えば次のように依頼します。

> この計画をNine標準AI開発フローでIssue化して。

または

> このリポジトリをNine標準AI開発フローで初期化して。

Codexには基本的に次のように指示します。

> このリポジトリのGitHub Issueを確認し、AGENTS.mdに従って対象Issueを実装してください。

詳細な共通ルールはAGENTS.mdとIssue側に持たせることで、毎回長いプロンプトを書く必要を減らします。

## 17. このリポジトリを変更するとき

`ai-development` は今後の全プロジェクトの原本になるため、テンプレート変更時は次を確認します。

- 既存プロジェクトにも反映すべき変更か
- 新規プロジェクトだけに適用すべき変更か
- Codexの作業ルールに影響するか
- GitHub ActionsやSecurity設定に影響するか

大きな変更は、このリポジトリ自体でもIssue → PR → CI → Reviewの流れを使うことを推奨します。
