# GitHub Repository Security Baseline

Nine標準AI開発フローで新規リポジトリを準備するときのGitHub側ガードレール。

## 1. Ruleset / Branch Protection

`main` を保護し、AIエージェントの誤操作もGitHub側で拒否できる構成にする。

推奨設定:

- Pull Request経由の変更を必須化
- GitHub Actions CIの成功を必須化
- CodeQLを利用する場合はセキュリティチェックも確認する
- force push禁止
- branch deletion禁止
- merge前に最新baseとの整合性を確認

AGENTS.mdのルールだけに依存せず、GitHub側でも強制する。

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
- [ ] GitHub Actions Secretsを必要に応じて登録
- [ ] Secret scanning / push protectionの利用可否を確認
- [ ] CodeQLの利用可否を確認し、有効なら設定
- [ ] CI status checkをmerge条件として必須化
