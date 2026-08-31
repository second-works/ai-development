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
