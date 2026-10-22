# Nine標準AI開発テンプレート 利用ガイド

## 1. このリポジトリの役割

`ai-development` は、各AI開発プロジェクトで共通に使う開発ルール、Issue / PR テンプレート、CI / セキュリティ設定の原本を管理するリポジトリです。

標準の構成は、`templates/lightweight/` の軽量構成です（#192 で切り替え。限定試行の記録は [lightweight-trial](lightweight-trial.md)）。ほかの資料（UI、Deploy、検収、Security境界など）は、Issue が指したときに読む参照用の資料です。

役割の分担:

- Codex: 計画とIssue化（`.agents/skills/plan-to-issues/`）
- Claude Code: Issueの実装から、レビュー指摘への対応、マージ依頼まで（`.claude/skills/steward/`）
- Codex Review: 正式レビュー
- GitHub Actions: Codex / Claude Code とは独立した機械的な再検証
- 人間: 重要な判断、検収、Merge

## 2. 新規プロジェクト開始時の使い方

新しいプロジェクトでは、まず GitHub にリポジトリを作り、軽量構成を配置します（下の手順）。そのうえで、技術構成に合わせて次を設定します。

1. `.github/workflows/ci.yml`（8章の技術構成別テンプレートから選ぶ）
2. Security Preflight と、利用できれば CodeQL（12章）
3. Dependabot（10章）と Secrets 管理の方針（11章）
4. Ruleset / Branch protection と `Automatically delete head branches`（9章）
5. `.github/pr-gate-checks` に、マージ依頼の前に必須とする check の名前（CI と Security の job 名）
6. README に、プロジェクト固有のビルド、テスト、使ってはいけない環境

情報の読み取りや外部への送信を伴う案件では、[AI Agent Security Boundary](ai-agent-security-boundary.md)（`docs/ai-agent-security-boundary.md`）で情報分類・宛先・権限・承認を確かめます。新規Web/UI案件では [Framework Decision](architecture/framework-decision.md) と [UI標準](product-ui-standard.md) を、計画の重要な未決は [Plan Review Gate](plan-review-gate.md) を、Issue が指したときに読みます。

### 最小AGENTSと参照先の配置

配置は `templates/lightweight/place.sh` で行います。置く前に全部の配置先を確かめ、既存の設定を上書きせず、衝突があれば何も書かずに止まります。既存の AGENTS.md / CLAUDE.md には管理ブロックを足し、`.claude/settings.json` は足りない設定だけを足します。詳しい挙動と復旧（`--restore`）、更新（再実行）、照合（`--check`）は [templates/lightweight/README.md](../templates/lightweight/README.md) を参照します。

次の例では、`template_source_root` に ai-development の checkout、`project_output_root` に対象プロジェクトの absolute path を設定します。配置先は git リポジトリの root に限ります。

```bash
set -e
: "${template_source_root:?ai-developmentのcheckoutのabsolute pathを設定する}"
: "${project_output_root:?対象projectのabsolute pathを設定する}"
mkdir -p "$project_output_root"
git -C "$project_output_root" rev-parse --git-dir >/dev/null 2>&1 || git -C "$project_output_root" init -q
"$template_source_root/templates/lightweight/place.sh" --dry-run "$project_output_root"
"$template_source_root/templates/lightweight/place.sh" "$project_output_root"
```

dry-run の差分を確かめてから配置します。プロジェクト固有の `scripts/verify.sh` などを残すときは `--keep <path>` を付けます。配置は有効化や検証の成功ではありません。新しい Claude Code のセッションでフックが読み込まれること、`./scripts/verify.sh`、CI、Security は別に確かめます。

## 2.1 Risk Tierの記入

子Issue と PR には、Risk Tier（`LOW / MEDIUM / HIGH`）と理由を記入します。既定は MEDIUM、混在は最大の Tier、安全への影響が不明なものと Gate 自体の変更は HIGH です。LOW は、実行の動作・API・依存・workflow・安全ルールに影響しない文言や表示だけの変更に限ります。HIGH では、安全境界、復旧、必要な人間の承認と追加の検証を書き、別のセッションでもレビューします。Tier によって標準検証、CI、Security、正式レビュー、人間の Merge 判断を免除しません。詳しくは [Adaptive Development Flow](adaptive-development-flow.md) を参照します。

## 3. AGENTS.md

軽量構成の `AGENTS.md`（約 2.4 KB）は、作業境界、検証とレビュー、必要なときに読むものだけを持ちます。標準 flow や最小契約を毎回読む必要はありません。主なルール:

- Issue の範囲内だけ変更し、1子Issue = 1 PR で進める
- main へ直接 push しない、force push しない、他者の未コミット変更を守る
- 本番、Deploy、破壊操作、認証、権限、課金、公開範囲、repo 保護設定の変更と、新しい重要設計は人間の承認を得る
- Secrets と実データを commit、Issue、PR、log へ出さない
- commit と PR の前に標準検証と自己レビューを行い、失敗・実行不能・全件 skip を成功にしない
- PR 後は最終 head で CI、Security、正式レビューを別々に確かめ、重大な指摘を未解決のままマージを依頼しない
- 実装、CI 成功、ユーザー検収を区別する

プロジェクト固有のルールは、管理ブロックの外（AGENTS.md の上の節）に書きます。

## 4. 親Issueテンプレート

ファイル: `.github/ISSUE_TEMPLATE/parent-issue.md`

Goal / Context / Scope・Boundaries / Non-goals / Done / Verification / Children・Dependencies でロードマップを記録します。Done は子PRのマージだけでなく、利用者の確認や実際の利用で判定できる条件で書きます。

## 4.1 デプロイ設計とRelease / Production計画

Release / Production が適用される案件では、[docs/deployment-release-design.md](deployment-release-design.md) を Issue から指し、実装完了と本番投入可能を分けて記録します。Merge は Production Deploy を意味しません。

## 4.2 実利用検証と検収

実装・Deploy の完了と、目的を満たしたことの検収を分けます。検収の正本は [docs/acceptance-verification.md](acceptance-verification.md) です。`Implementation Done`、`Deployed`、`Product Accepted` は別の状態です。

## 4.3 Plan Review Gate（計画書Grilling）

計画書から Issue 化する前の重要な未決の確認は [docs/plan-review-gate.md](plan-review-gate.md) を、計画書の作り方は [plan-authoring](plan-authoring.md) を参照します。軽量構成では、Codex が `plan-to-issues` の手順で確かめます。

## 5. 子Issueテンプレート

ファイル: `.github/ISSUE_TEMPLATE/child-issue.md`

Goal / Context / Scope・Boundaries / Non-goals / Done / Verification / Dependencies を記入します。Scope / Boundaries に Risk Tier と理由、人間の承認が必要な操作、扱う情報と送信先（該当するときだけ）を書きます。Done は実装の手順ではなく、確かめられる結果で書きます。

## 6. 子Issue品質チェック

子Issue を登録する前に、`plan-to-issues` の手順で、目的、変更範囲、独立した完了判定、1 PR でのレビュー可能性、依存関係、安全境界を確かめます。詳しい観点は [Issue Quality Check](issue-quality-check.md) を参照します。

## 7. Pull Requestテンプレート

ファイル: `.github/pull_request_template.md`

対応 Issue（`Closes #`）、変更内容、判断と前提（Risk Tier）、検証（対象 head の full SHA、ローカル、CI / Security、正式レビュー、必要なときだけユーザー検収）、未完了と対象外を記録します。未実行、全件 skip、取得できない結果、古い head の結果は成功と書きません。

CI、Security、正式レビューは別々に確かめ、最終 Merge は人間が判断します。最終 head の照合は `scripts/check-pr-head.sh <PR番号>` で行います。

## 8. 標準検証入口とGitHub Actions CIテンプレート

保存場所:

- `templates/verification/verify.sh`
- `templates/github-actions/`

### 標準検証入口

新規プロジェクトでは、まず `templates/verification/verify.sh` を `scripts/verify.sh` として配置し、実行権限を付与します。

ローカル・Agent・GitHub Actionsの検証コマンドは、原則として次の1つに統一します。

```bash
./scripts/verify.sh
```

標準入口は次の順序で工程を実行します。

1. lint
2. type check
3. test
4. build

対象外工程は `skipped` と理由をログへ出します。対象工程のツール未導入や失敗は工程名を示して非0終了し、後続工程へ進みません。4工程すべてが対象外、または工程スクリプトが1つもない場合も、検証ゼロの成功を防ぐため非0終了します。

### Node.js

`node-ci.yml` はNode.js / TypeScript系プロジェクト向けです。

- `.nvmrc` にNode.jsの正確なバージョンを固定する
- `package-lock.json` をcommitし、CIは `npm ci` を使う
- `package.json` の `scripts.lint`、`scripts.typecheck`、`scripts.test`、`scripts.build` を標準入口から実行する
- 存在しないscriptは対象外として明示する

### Python

`python-ci.yml` はPython系プロジェクト向けです。

- `.python-version` にPythonの正確なバージョンを固定する
- `requirements-dev.txt`、`uv.lock`、`poetry.lock` 等でRuff / mypy / pytest / buildなどの開発ツールを固定する
- Ruff、mypy、pytest、PEP 517 buildの設定がある工程を標準入口から実行する
- 設定がない工程は対象外として明示する。テストファイルが存在する場合のpytest未導入は失敗とする

### Generic

`generic-ci.yml` はNode.js / Python以外、または技術スタック未確定のプロジェクト向けです。

- `scripts/lint.sh`
- `scripts/typecheck.sh`
- `scripts/test.sh`
- `scripts/build.sh`

を必要な工程だけ実装し、標準入口から順番に呼び出します。工程スクリプトがない工程は対象外として明示します。工程スクリプトが1つもない場合は、既存の `scripts/ci.sh` や任意の単一コマンドへ暗黙にfallbackせず、標準検証を失敗させて工程別スクリプトへの移行を促します。

### 生成直後のサンプル検証

テンプレート正本には `tests/verification/run-samples.sh` を含めます。このスクリプトは生成相当の一時プロジェクトを作成し、次を検証します。

- 正常系で4工程が順序どおり成功する
- lint失敗時に非0終了し、失敗工程をログから特定できる
- lint失敗後にtype check / test / buildが実行されない

### 開発ツールの更新

バージョン固定を変更する場合は、固定ファイル、依存lock、CIテンプレートを必要に応じて同じPRで更新します。更新後は `tests/verification/run-samples.sh` と対象プロジェクトの `./scripts/verify.sh` を再実行し、更新理由と結果をPR本文へ記録します。

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

## 12. Security Preflight / CodeQL

利用可能なリポジトリでは `.github/workflows/codeql.yml` として配置します。

### 目的

GitHub側でソースコードのセキュリティ問題を静的解析します。

CodeQLは通常のCIとは役割が異なります。

- CI: ビルド、lint、型、テストなどの動作検証
- CodeQL: セキュリティ上問題になり得るコードパターンの検出

利用可能な言語・GitHubプラン・リポジトリ設定を確認してから有効化します。

GitHub Security checkの有無にかかわらず、CIとSecurityの判定は分離します。利用可能なGitHub Security checkがないプロジェクトでは、`templates/security/security-preflight.sh` を `scripts/security-preflight.sh` としてコピーし、`chmod +x scripts/security-preflight.sh` を実行します。Security Preflightは既知のsecret patternと、対応するlockfileがある場合のnpm auditを検査し、全体の `SECURITY_STATUS` と依存チェックの `DEPENDENCY_STATUS` を機械可読に出力します。

Security Preflightと通常のレビュー用helperはBash 5以上が必要です。macOS標準`/bin/bash` 3.2で実行すると外部操作前に停止し、Preflightは`SECURITY_UNAVAILABLE`を出します。使用するBashの絶対パスを `BASH5` に設定して `"$BASH5" --version` で確認し、Preflightは `"$BASH5" scripts/security-preflight.sh .` として起動します。以下の待機例も `bash` の代わりに `"$BASH5"` を使います。待機helperはfallback Preflightを同じBashで起動します。手動JEV評価用helperは今回のBash 5前提に含めません。インストールやPATH変更は自動化しません。

- `SECURITY_PASSED`
- `SECURITY_FAILED`
- `SECURITY_NOT_APPLICABLE`（依存チェックの対象マニフェストがない場合。`DEPENDENCY_STATUS` と理由を監査記録へ残す）
- `SECURITY_UNAVAILABLE`（未対応マニフェスト、scanner、実行環境、結果が利用できない場合。人間判断が必要）

標準の待機スクリプトへfallbackのパスを渡す例:

```bash
"$BASH5" "$RUNTIME_DIR/scripts/wait-checks.sh" "$REPO" "$EXPECTED_SHA" 300 60 30 "./scripts/security-preflight.sh"
```

`SECURITY_FAILED` はMerge禁止、`SECURITY_UNAVAILABLE` は人間の明示判断なしに通過させません。CIの成功だけでSecurity成功とは判断せず、修正後は同じ新しいPR head SHAに対してCI・Security・レビューを再実行します。

## 12.1 AI Agent Security Boundary

新規プロジェクトでAIエージェントにToolを渡す場合は、docs/ai-agent-security-boundary.md を読み、Parent Issue、Child Issue、PRの該当欄へ適用結果を記録する。

- 情報をPUBLIC / INTERNAL / CONFIDENTIALに分類する。
- LLM環境をMANAGED / UNMANAGEDと判定し、CONFIDENTIAL情報の送信先を確認する。
- Intake / ReadとExposure / Writeを分け、Sensitive Read Capability × External Write Capabilityを高リスクとして判定する。
- Least PrivilegeのscopeとHuman Approval Boundaryを記録する。
- 外部コンテンツをtrusted instructionとして扱わず、適用対象外や例外の理由、残るリスク、代替制御、承認者を記録する。

テンプレート利用プロジェクトでは、適用可否を「対象外」とだけ書かず、対象Tool、データ分類、代替制御、承認者まで記録する。

## 12.2 Harness MinimalismとETCSLV台帳

AI開発テンプレートへ新しいハーネスを追加する前に、docs/ai-development-harness-inventory.md へ失敗モード、発火条件、Context、State、決定論的判定、コスト、重複、安全上の必須性、判定、削除・再評価条件を記録する。

既存ハーネスを削除または簡素化する場合は、対象の受入条件、代替制御、影響範囲、実測結果、対象SHAを記録する。
新規プロジェクトでは、台帳を常時Contextへ投入せず、追加または変更するハーネスに関係する項目を参照する。

モデル、Codex、Tool、CIの能力向上だけを理由にSecurity Boundary、Human Approval Boundary、Production保護を弱めない。
対象外やREMOVE_CANDIDATEの判定は、失敗モードと代替制御を確認した別IssueまたはPRで決定する。

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
Framework Decision
    ├─ NEEDS_DECISION → Design Decision → 計画書更新 → 再Review
    ├─ DECIDED / NOT_APPLICABLE → 次工程
    ↓
UI Level Decision / PRODUCT前提整理
    ↓
Plan Review Gate（Grilling）
    ├─ NEEDS_DECISION → Design Decision → 計画書更新 → 再Review
    ├─ PASS → 親Issue
    └─ NOT_APPLICABLE → 省略理由を記録 → 親Issue
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
通常レーン / Safe Auto-Fix・Auto-Merge判定
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
    ├─→ 最新mainから次のIssue用branchを作成 → 次の子Issue
    └─→ Production Deploy後の実利用シナリオ検証
         ↓
       計画時の成功条件との照合 → Accepted / Not Accepted / Conditional
         ↓
       発見事項の分類 → 修正Issue / 改善Issue / 次サイクル
```

Merge後の次Issue着手と、Deploy後の実利用検証・検収は独立した工程として扱う。依存関係のない次Issueは、検収完了を待たずに優先順位と依存関係に従って開始できる。検収で見つかった事項は、元PRの修正ループへ戻さず、必要な修正Issue / 改善Issueとして追跡する。

## 15. 新規リポジトリ初期化チェックリスト

新しい開発リポジトリを作成したら以下を確認します。

- [ ] 最小 `AGENTS.md` と同revisionの `docs/` 一式を配置（単体copyしない）
- [ ] `.agents/skills/` と参照原本 `templates/` を配置
- [ ] `docs/nine-standard-ai-development-flow.md` / `docs/code-review-contract.md` / `docs/test-design.md` / `docs/minimal-development-contract.md` と条件表の参照先を対象projectで開ける
- [ ] ai-development自身の検証行を除き、対象projectの `scripts/verify.sh` とCIを設定
- [ ] `docs/ai-agent-security-boundary.md` を配置
- [ ] `docs/ai-development-harness-inventory.md` を配置
- [ ] `docs/architecture/framework-decision.md` を配置
- [ ] `docs/plan-review-gate.md` を配置
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
- [ ] `templates/security/security-preflight.sh` を `scripts/security-preflight.sh` として配置し、実行権限を付与
- [ ] 利用可能ならCodeQLを有効化
- [ ] 最初の親Issueを作成
- [ ] 子Issue品質チェックを実施

## 16. 普段の短縮指示

ChatGPTには例えば次のように依頼します。

方針が見えたあと、計画書化（詳細は [計画書の作り方](plan-authoring.md)）:

> 今までの方針で、Nineの計画書の作り方に沿って計画書を作成してください。会話で決まっていない欄は推測で埋めないでください。テンプレ上必要だが未決の項目は候補と推奨を出して確認してください。重要判断が残る場合はNEEDS_DECISIONとし、Issue化しないでください。

計画書のあと、Issue化:

> この計画をNine標準AI開発フローでIssue化して。Issue化前にPlan Review（Grilling）を実施し、PASSまたは理由付きNOT_APPLICABLEの場合だけ親Issue / 子Issueへ変換して。NEEDS_DECISIONの場合はIssue化を止め、Design Decisionの候補案と推奨案を提示して。

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
