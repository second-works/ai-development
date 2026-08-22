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
8. `@codex review` をレビュー専用で実行
9. P0 / P1 / P2指摘があれば、対象PRの番号・head branch・修正前head SHAを記録し、Codex Desktop/Work等で既存PRのhead branchをチェックアウトしてIssue範囲内を修正
10. 同じhead branchへcommit/pushし、新しいPRを作成せず、修正後head SHAが更新されたことを確認
11. SHAを確認できない・更新されていない・同じhead branchへpushできない場合は停止
12. 更新後のheadを対象にローカルテスト → CI → セキュリティチェック → `@codex review` を順に実行
13. 人間が最終確認
14. Merge

CodexのAutomatic reviewsが利用可能な場合は自動レビューを原則とし、無効な場合はPR上で `@codex review` を依頼します。

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
- Codex Code ReviewはPR差分をレビューする
- PRを品質の関門にする
- 人間が仕様とマージを決める
