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
7. GitHub Actions CI
8. Codex Code Review（レビュー専用）
9. P0 / P1 / P2指摘があれば、既存PRのhead branchをチェックアウトして修正
10. 修正前に対象PR番号・head branch・head SHAを確認し、同じhead branchへcommit / push
11. GitHub上で修正後のhead SHAが、pushした修正コミットSHAと一致することを確認
12. SHA未確認・未更新・不一致の場合は再テスト・CI・セキュリティチェック・再レビューへ進まず停止
13. 更新後のheadをローカルテスト → CI → セキュリティチェック → `@codex review` の順で再検証
14. 新しいPRを作らず既存PRを再利用
15. 人間が最終確認
16. 人間がMerge

P0 / P1 / P2の修正に `@codex address that feedback` は標準手順として使用せず、`@codex review` はレビュー専用とします。CodexのAutomatic reviewsが利用可能な場合は自動レビューを原則とし、無効な場合はPR上で `@codex review` を依頼します。

詳細は [`docs/nine-standard-ai-development-flow.md`](docs/nine-standard-ai-development-flow.md) を参照してください。

## 主要ファイル

- `AGENTS.md` — AIエージェント共通ルール・Codex Code Reviewルール
- `docs/nine-standard-ai-development-flow.md` — 標準開発フロー
- `.github/ISSUE_TEMPLATE/parent-issue.md` — 親Issueテンプレート
- `.github/ISSUE_TEMPLATE/child-issue.md` — 子Issueテンプレート
- `.github/pull_request_template.md` — PRテンプレート

## 基本原則

- ChatGPTは考える
- GitHubは仕事を管理する
- Codexは実装する
- GitHub Actionsは機械的に検証する
- Codex Code ReviewはPR差分をレビューする（レビュー専用）
- PR修正は既存PRのhead branchへ反映する
- PRを品質の関門にする
- 人間が仕様とマージを決める
