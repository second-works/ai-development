# Nine標準AI開発フロー

## ChatGPT × GitHub × Codex × GitHub Actions

## 1. 基本方針

開発は原則として次の流れで進める。

**要望 → ChatGPTで要件整理・計画書作成 → Plan Review Gate（Grilling） → 必要なDesign Decision確定 → GitHub親Issue → 子Issue → Codex実装 → ローカルテスト → PR → GitHub Actions CI → セキュリティチェック → Codex Code Review → 通常レーン / Safe Auto-Fix・Auto-Merge判定 → 必要なら修正・再CI・再レビュー → 人間確認またはSafety Gate成立後のAuto-Merge → Deploy → 実利用検証 → 検収判定**

大きな計画をCodexへ一括投入せず、レビュー可能な単位まで分割する。

原則は **1子Issue = 1 PR**。

品質保証は、Codex側の自己チェック、共通の標準検証入口、GitHub Actionsによる機械検証、Codex Code Review、人間の最終判断を組み合わせる。

テンプレート利用プロジェクトでは、ローカル・Agent・GitHub Actionsが同じ `./scripts/verify.sh` を呼び出す。標準検証は lint → type check → test → build の順に実行し、対象外工程は理由付きで明示する。標準検証を実行できない場合や失敗した場合は、commit・PR作成・レビュー依頼へ進まず停止する。

GitHub上の実装完了と本番投入可能な状態は分けて扱う。Release Candidate以降のDeployment as Code設計、判断項目、安全条件は [docs/deployment-release-design.md](deployment-release-design.md) を参照する。

実装・Deployの完了と、利用者が当初の目的を達成したことも分けて扱う。実利用検証、検収計画、判定、発見事項の分類は [docs/acceptance-verification.md](acceptance-verification.md) を正本とする。

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

## 2.1 Plan Review Gate（計画書Grilling）

計画書から親Issue / 子Issueへ変換する前に、[docs/plan-review-gate.md](plan-review-gate.md) に従ってPlan Review Gateを実施する。

PASSまたは理由付きNOT_APPLICABLEの場合だけIssue化へ進み、NEEDS_DECISIONの場合はIssue化・実装開始を止めて既存のDesign Decisionへ接続する。NOT_APPLICABLEの場合は省略理由を記録する。Plan Reviewは計画書の全面書き換え、一問一答の強制、既存のDesign Decision Escalationの置換ではない。

## 3. 親Issue

親Issueは実装指示ではなくプロジェクト全体のロードマップとして使う。Plan Review GateがPASSまたは理由付きのNOT_APPLICABLEとなった後に作成する。

含める項目：

- 目的
- 背景
- 今回実装する範囲
- 子Issue一覧
- 後続候補
- 今回やらないこと
- 全体完了条件
- 検収計画（課題、利用者、実利用シナリオ、成功条件、失敗条件、検証環境、人間確認項目）

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

> GitHub Issue #XXを実装してください。Issue記載内容を仕様の基準とし、範囲外の実装や不要なリファクタリングを行わず、必要なテストを追加してください。標準検証入口 `./scripts/verify.sh` を実行してください。内部順序は lint → type check → test → build とし、対象外工程は理由を記録します。標準入口を実行できない場合は成功扱いにせず停止してください。完了したらPRを作成してください。PR作成後はGitHub Actions CIと利用可能なセキュリティチェックの結果も確認してください。CI成功後は `@codex review` をレビュー専用で実行してください。P0 / P1 / P2指摘があれば `@codex address that feedback` を標準手順に使わず、既存PRのhead branchをチェックアウトして修正してください。修正前に対象PR番号・head branch・head SHAを確認し、同じhead branchへcommit / pushした修正コミットSHAとGitHub上の同じPRのhead SHAが一致することを確認してください。head branchまたはSHAを確認できない、SHAが更新されていない、またはpushした修正コミットSHAとPR head SHAが一致しない場合は再テスト・CI・セキュリティチェック・再レビューへ進まず人間に確認してください。修正コミットSHAを検証対象SHAとして記録し、更新後のheadに対してローカルテスト → GitHub Actions CI → 利用可能なセキュリティチェック → `@codex review` の順で再検証してください。各チェックの対象SHAを記録し、再検証完了時にGitHub上のPR head SHAがpushした修正コミットSHAおよび記録した検証対象SHAと一致することを確認してください。不一致の場合は完了扱いにせず人間に確認してください。新しいPRを作らず既存PRを再利用し、仕様だけでは判断できない重大な問題は推測で拡張せず、最終Mergeは人間が判断します。

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

**Issue → Branch → 実装 → ローカルテスト → Commit → PR → GitHub Actions CI → セキュリティチェック → Codex Code Review → 通常レーン / Safe Auto-Fix・Auto-Merge判定**

### レビュー修正時のPR / head branch固定

レビュー後に修正する場合は、レビュー担当と修正担当を分離する。

修正ラウンドは、Codex Code Review → Issue範囲内の修正 → 更新後headの標準検証・再レビューを1単位とする。初回レビューはラウンド0として記録する。第3ラウンド完了後の再レビューで新しいP1 / P2が発生した場合は、4ラウンド目の自動修正へ進まず停止して人間へ戻す。3ラウンドで強制Mergeしてはならない。P0 / P1が残る場合はMerge禁止、P2のみ残る場合は人間の理由確認と明示判断が必要である。Safe Auto-Fix / Auto-Mergeを採用する場合のSafety Gate、1ラウンド制限、SHA照合、停止条件、監査記録は [docs/safe-auto-fix-auto-merge.md](safe-auto-fix-auto-merge.md) を正本とする。

1. `@codex review` はレビュー専用とし、修正には使わない。
2. P0 / P1 / P2の修正は標準手順から `@codex address that feedback` を外し、Codex Desktop / Work等で既存PRのhead branchをチェックアウトして行う。
3. 修正前に対象PR番号、head branch、head SHAをGitHub上で確認・記録する。
4. 修正後は同じhead branchへcommit / pushし、新しいPRを作らず既存PRを再利用する。
5. pushした修正コミットのSHAを検証対象SHAとして記録し、GitHub上の同じPRのhead branchとhead SHAが、そのSHAと一致することを確認する。単に修正前後でSHAが異なるだけでは完了扱いにしない。SHAを確認できない、更新されていない、または一致しない場合は再検証へ進まず停止する。
6. 記録した検証対象SHAを固定して、標準検証入口 `./scripts/verify.sh`（lint → type check → test → build） → GitHub Actions CI → セキュリティチェック → 更新後headへの `@codex review` の順で再検証する。
7. 各チェックの対象SHAを記録し、再検証完了時にGitHub上のPR head SHAがpushした修正コミットSHAおよび記録した検証対象SHAと一致することを確認する。不一致の場合は完了扱いにせず停止する。
8. PR本文へ現在の修正ラウンド数、新規P0 / P1 / P2、3ラウンド到達時の停止判断、P2残置理由、人間の継続指示または受容判断、標準検証結果を記録する。
9. branchの取り違え、push失敗、Issue範囲外への拡大、同じ問題の3回以上の反復、または第3ラウンド後の新しいP1 / P2発生があれば人間へ戻す。
### Merge後のbranch管理

PRをMergeした後は、役目を終えたIssue用の短命head branchを原則削除する。

新規リポジトリでは、SettingsのPull Requests設定にある `Automatically delete head branches` をONにし、Merge済みPRのIssue用head branchが自動削除されるようにする。

`main` などの保護対象branchは削除禁止を維持する。自動削除の対象はMerge済みPRのIssue用head branchであり、保護対象branchとは区別して扱う。

次のIssueに着手するときは、最新の `main` から新しいIssue用branchを作成する。

## 7.1 Release / Production工程

Merge後のProduction工程は、対象環境とリスクに応じて次の順で計画する。

```text
Merge
  ↓ Release Candidate
  ↓ Staging Deploy（必要な場合）
  ↓ E2E / Smoke Test
  ↓ Release判定
  ↓ Production Deploy
  ↓ Post-deploy Health Check
  ↓ Monitoring / Rollback
```

Stagingを省略する場合は、親IssueまたはDesign Decisionに理由と代替確認方法を記録する。
CloudflareでDockerが不要な構成、Home PC / VPSのself-hosted runnerとDocker Compose、macOS固有アプリのDockerなし運用は、それぞれ候補として比較するが一律に強制しない。
永続データ、Secrets、backup、migration、Rollbackとデータ互換性をProduction計画に含める。
詳細な記録項目は [docs/deployment-release-design.md](deployment-release-design.md) を参照する。

Production Deploy後は、Health Check / Smoke Testとは別に実利用シナリオを実行し、計画時の目的・成功条件と照合して検収判定を行う。`Implementation Done`、`Deployed`、`Product Accepted` は別状態として記録する。詳細な検収計画・結果・発見事項の分類は [docs/acceptance-verification.md](acceptance-verification.md) に従う。

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

新規プロジェクト準備時は、`templates/verification/verify.sh` を `scripts/verify.sh` として配置し、技術スタックに合うCIテンプレートを `.github/workflows/ci.yml` として配置する。CIテンプレートは個別のlint / type check / test / buildコマンドを再定義せず、同じ `./scripts/verify.sh` を呼び出す。Node.jsは `.nvmrc` と `package-lock.json`、Pythonは `.python-version` と依存lock/pinなど、技術スタックに適した方法で開発ツールと実行環境を固定する。

CodexのローカルテストとGitHub Actions CIは二重チェックとして扱う。

CIが失敗しているPRは原則mergeしない。

## 9. Codex Code Review

Codex Code Reviewを、CI成功後・人間の最終確認前の標準品質ゲートとして使う。

### 起動方法

1. CodexのAutomatic reviewsが利用可能なリポジトリでは、自動レビューを原則有効化する。
2. Automatic reviewsが無効または利用できない場合は、PR上で `@codex review` を依頼する。これはレビュー専用であり、修正は実行しない。
3. 実装担当Codexの自己レビューだけで完了扱いにせず、PR単位のCode Review結果を確認する。

### レビュー観点

- Issueの要求・Acceptance Criteriaを満たしているか
- Issue範囲外の変更がないか
- 明確なバグ、回帰、境界値・異常系の見落としがないか
- テストが十分か
- 認証・認可、入力検証、秘密情報などのセキュリティ問題がないか
- 不要な依存追加や破壊的変更がないか
- テスト削除・skip・例外握りつぶしで品質ゲートを回避していないか

### SeverityとMerge条件

- **P0 / P1**: Merge禁止。必ず修正する。
- **P2**: 原則としてMerge前に修正する。残す場合は人間が理由を確認して明示判断する。
- **P3**: 改善候補。原則としてMerge阻害条件にはしない。必要なら後続Issueへ切り出す。

標準Merge条件：

- GitHub Actions CI成功
- 利用可能なセキュリティチェック成功、または例外を人間が明示判断
- Codex Code ReviewのP0 / P1が0件
- P2が0件、または残置理由を人間が明示判断
- 人間の最終確認完了

### 修正ループ

CodexレビューでP0 / P1 / P2が出た場合：

修正ラウンドは、Codex Code Review → 修正 → 標準検証・再レビューを1単位とし、初回レビューはラウンド0として記録する。第3ラウンド完了後の再レビューで新しいP1 / P2が発生した場合は自動修正を停止して人間へ戻す。3ラウンドで強制Mergeしてはならない。P0 / P1が残る場合はMerge禁止、P2のみ残る場合は人間の理由確認と明示判断が必要である。

1. 指摘がIssue範囲内か確認する。
2. `@codex review` はレビュー専用であり、レビュー担当に修正を実行させない。P0 / P1 / P2の修正は標準手順から `@codex address that feedback` を外し、Codex Desktop / Work等で行う。
3. 修正前に対象PR番号、head branch、head SHAをGitHub上で確認・記録し、既存PRのhead branchをチェックアウトする。
4. Issue範囲内で修正し、同じhead branchへcommit / pushする。新しいPRを作らず、既存PRを再利用する。
5. pushした修正コミットSHAを確認し、GitHub上の同じPRのhead branchとhead SHAが、そのSHAと一致することを確認する。単に修正前後でSHAが異なるだけでは完了扱いにしない。
6. head branchまたはSHAを確認できない、pushした修正コミットSHAとGitHub上のPR head SHAが一致しない、またはSHAが更新されていない場合は、標準検証、CI、セキュリティチェック、再レビューへ進まず停止して人間に確認を求める。
7. 記録した検証対象SHAを固定して、標準検証入口 `./scripts/verify.sh`（lint → type check → test → build） → GitHub Actions CI → 利用可能なセキュリティチェック → `@codex review` の順で再検証する。
8. 各チェックの対象SHAを記録し、再検証完了時にGitHub上のPR head SHAがpushした修正コミットSHAおよび記録した検証対象SHAと一致することを確認する。不一致の場合は完了扱いにせず停止する。
9. 前回指摘が解消され、新しいP0 / P1 / P2がないことを確認する。
10. PR本文へ現在の修正ラウンド数、新規P0 / P1 / P2、3ラウンド到達時の停止判断、P2残置理由、人間の継続指示または受容判断、標準検証結果を記録する。
11. 同じ問題を3回以上繰り返す、仕様判断が必要、branchを取り違える、pushに失敗する、破壊的変更が必要、Issue範囲外へ広がる、または第3ラウンド後に新しいP1 / P2が発生する場合は自律修正を停止し人間へ戻す。
通常レーンではAIレビューを補助として扱い、最終Merge判断は人間が行う。Safe Auto-Fix / Auto-Mergeは、正本文書のSafety Gateを満たし、人間が採用を明示した場合だけ利用できる限定例外である。

## 10. GitHub側ガードレール

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

## 11. CI / セキュリティチェック失敗時

失敗した場合は以下の順で対応する。

1. 失敗したjob / step / alertを確認する。
2. ログや検出内容から原因を特定する。
3. Issue範囲内で修正する。
4. 対象PRのhead branchへ追加commitする。
5. 自動チェックの再実行結果を確認する。
6. 成功するまで完了扱いにしない。

チェックを通すためにテストやセキュリティ検査を削除・無効化しない。

## 12. レビュー

自動チェック成功後はCodex Code Reviewと人間レビューを組み合わせる。

確認ポイント：

- Issueの要求を満たしているか
- Issue範囲外の変更がないか
- テストが十分か
- GitHub Actions CIが成功しているか
- セキュリティチェックに重大な問題がないか
- Codex Code ReviewのP0 / P1が解消され、P2は解消または人間が残置理由を確認済みか
- 不要な依存追加がないか
- 既存機能への影響がないか
- CI / Code Reviewの成功と、実利用で当初の目的を満たしたことを別々に確認する

最終mergeは人間が判断する。

## 13. プロジェクト規模

### 小規模

1 Issue → Codex → 1 PR → CI / Security → Codex Review → Merge

### 中規模

親Issue → 3〜8程度の子Issue → 各PR → CI / Security → Codex Review → Merge

### 大規模

親Issue → Phase分割 → 子Issue → 各PR → CI / Security → Codex Review → Merge

大規模プロジェクトではPhase間の依存関係を明示する。

## 14. 新規リポジトリ準備

新規プロジェクトのリポジトリを作成したら、標準として以下を準備する。

- `AGENTS.md`
- `.github/ISSUE_TEMPLATE/`
- `.github/pull_request_template.md`
- `.github/workflows/ci.yml`
- Codex Code Review（Automatic reviewsが利用可能なら有効化）
- Ruleset / branch protection
- Merge済みPRのhead branch自動削除（`Automatically delete head branches`）
- `.github/dependabot.yml`
- GitHub Actions Secrets（必要な場合）
- Secret scanning / push protection（利用可能な場合）
- CodeQL / code scanning（利用可能な場合）

詳細チェックリストは `docs/github-repository-security-baseline.md` を参照する。

## 15. 短縮指示

ChatGPTに **「GitHub Issue方式で計画して」** と依頼された場合、原則として以下を作る。

- 親Issue
- 1 PR単位の子Issue
- 子Issue妥当性チェック
- 依存関係
- 並列/直列判断
- Codex用指示
- 完了条件
- 推奨CI構成
- 推奨Codex Code Review構成
- 推奨GitHubガードレール

**「Codex実装用にして」** と依頼された場合、各子IssueをCodexがそのまま実行できる粒度まで具体化する。

## 16. 基本原則

**ChatGPTは考える。**

**GitHubは仕事を管理する。**

**Codexは実装し自己チェックする。**

**GitHub Actionsは機械的に再検証する。**

**Codex Code ReviewはPR差分を独立した品質ゲートとして確認する。**

**GitHub Ruleset / Securityは誤操作と脆弱性を止める。**

**PRは品質の関門にする。**

**人間は仕様とマージを決める。**
