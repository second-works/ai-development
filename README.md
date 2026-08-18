# ai-development

Nine標準AI開発フローを管理する非公開リポジトリです。

## 目的

ChatGPTで要件整理・設計を行い、GitHub Issueで作業を分解し、Codexで実装・テスト・PR作成まで進める標準手順をここで管理します。

## 標準フロー

1. ChatGPTで要件整理
2. 親Issueを作成
3. 1 PR単位の子Issueへ分解
4. Codexで実装
5. テスト実行
6. PR作成
7. Codexレビュー
8. 人間が最終確認
9. Merge

詳細は [`docs/nine-standard-ai-development-flow.md`](docs/nine-standard-ai-development-flow.md) を参照してください。

## 主要ファイル

- `AGENTS.md` — AIエージェント共通ルール
- `docs/nine-standard-ai-development-flow.md` — 標準開発フロー
- `.github/ISSUE_TEMPLATE/parent-issue.md` — 親Issueテンプレート
- `.github/ISSUE_TEMPLATE/child-issue.md` — 子Issueテンプレート
- `.github/pull_request_template.md` — PRテンプレート

## 基本原則

- ChatGPTは考える
- GitHubは仕事を管理する
- Codexは実装する
- PRを品質の関門にする
- 人間が仕様とマージを決める
