# GitHub Repository Security Baseline

Nine標準AI開発フローで新規リポジトリを準備するときのGitHub側ガードレール。

## 1. Ruleset / Branch Protection

`main` を保護し、AIエージェントの誤操作もGitHub側で拒否できる構成にする。

推奨設定:

- Pull Request経由の変更を必須化
- GitHub Actions CIの成功を必須化
- CodeQLを利用する場合はセキュリティチェックも確認する
- force push禁止
- `main` など保護対象branchの削除禁止
- merge前に最新baseとの整合性を確認

AGENTS.mdのルールだけに依存せず、GitHub側でも強制する。

Issue用の短命head branchは保護対象branchとは区別する。新規リポジトリでは `Automatically delete head branches` をONにし、Merge済みPRのIssue用head branchを原則自動削除する。

## 2. Dependabot

技術スタックに応じたDependabot設定を `.github/dependabot.yml` として配置する。

テンプレート:

- Node.js: `templates/dependabot/dependabot-node.yml`
- Python: `templates/dependabot/dependabot-python.yml`

依存関係更新PRも通常のCIとレビューを通してmergeする。

## 3. Secrets

秘密情報はコード・Issue・PR本文へ直接記載しない。

- `.env` はcommitしない
- API key / token / passwordはGitHub Actions Secretsまたは適切なsecret managerへ保存
- workflowでは `${{ secrets.NAME }}` から参照
- Secret scanning / push protectionが利用可能なら有効化
- ログへ秘密情報を出力しない

## 4. CodeQL / Code Scanning

## 4.1 AI Agent Security Boundary

AIエージェントの情報フローは docs/ai-agent-security-boundary.md を基準とする。
Repository Security Baselineが扱うリポジトリ、Secrets、CodeQL、Ruleset、Branch Protectionの防御と、Agent Security Boundaryが扱う情報分類、LLM環境、ToolのRead / Exposure、最小権限、外部送信、人間承認を分けて記録する。

- Sensitive Read Capability × External Write Capability を高リスクとして判定する。
- Tool、Destination、filesystem、repository、networkのscopeを最小化し、外部コンテンツを trusted instruction として扱わない。
- CONFIDENTIAL 情報の外部送信、権限拡大、Production変更などは、人間の明示承認まで実行しない。



利用可能なリポジトリではCodeQLを有効化する。

テンプレート: `templates/github-actions/codeql.yml`

言語matrixは実プロジェクトに合わせて変更する。CodeQLがプラン・言語・リポジトリ条件で利用できない場合は、その事実を記録し、通常CIとレビューを継続する。

## 5. 二重チェック方針

品質保証は一方だけに依存しない。

### Codex側

- Issue範囲確認
- 実装
- ローカルテスト
- lint / type check / build
- 自己レビュー

### GitHub側

- PR強制
- Actions CI
- required status checks
- Dependabot
- Code scanning（利用可能時）
- secret protection（利用可能時）

Codexが見落としてもGitHubで止め、GitHub設定だけでは判断できない仕様逸脱をCodexと人間レビューで止める。

## 新規リポジトリ初期化チェック

- [ ] `AGENTS.md` を配置
- [ ] Issueテンプレートを配置
- [ ] PRテンプレートを配置
- [ ] `.github/workflows/ci.yml` を配置
- [ ] Ruleset / branch protectionを設定
- [ ] `.github/dependabot.yml` を配置
- [ ] `Automatically delete head branches` をONにする
- [ ] `main` など保護対象branchの削除禁止とIssue用短命branchの自動削除を確認
- [ ] GitHub Actions Secretsを必要に応じて登録
- [ ] Secret scanning / push protectionの利用可否を確認
- [ ] CodeQLの利用可否を確認し、有効なら設定
- [ ] CI status checkをmerge条件として必須化

## AGENTS残責務の移行準備

固定原文はmain `d4ee8ee56ad15ca4bcbca604bc3622a1400b667b` のAGENTS。以下は本文短縮に先立つ詳細責務の保存であり、現在のAGENTSを置換しない。既存節は概説・具体手順、以下は旧AGENTSから保持する責務・例外。将来の短縮後も両方を適用し、矛盾があれば推測せず停止する。Security・承認条件は変更しない。重複本文と参照テストの整理は後続Issueで行う。

### 移行契約: GitHub Guardrails

GitHub側の強制チェックは [`docs/github-repository-security-baseline.md`](github-repository-security-baseline.md) を標準とする。

新規プロジェクトでは可能な範囲で以下を設定する。

- Ruleset / branch protectionでPR経由を必須化
- GitHub Actions CIをrequired status checkにする
- force pushとmainの直接変更を禁止
- Dependabotを設定
- SecretsはGitHub Actions Secrets等で管理
- Secret scanning / push protectionが利用可能なら有効化
- CodeQL / code scanningが利用可能なら有効化

Codex側の自己チェックだけ、GitHub側の自動チェックだけ、のどちらか一方に依存しない。

### 移行契約: CodeQL / Code Scanning

利用可能なプロジェクトではCodeQLまたはGitHub code scanningを有効化する。

標準workflow: `templates/github-actions/codeql.yml`

対象言語はプロジェクトに合わせて調整する。

プラン、リポジトリ種別、対象言語等の条件により利用できない場合は、その事実を記録し、通常CIとレビューで補完する。

### 移行契約: Secrets

- `.env` をcommitしない。
- API key / token / passwordをコード、Issue、PR本文へ直接記載しない。
- GitHub Actionsで必要な秘密情報は原則としてGitHub Actions Secretsから参照する。
- ログへ秘密情報を出力しない。
- Secret scanning / push protectionが利用可能な場合は有効化する。
