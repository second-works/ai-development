# 対応Issue

Closes #

# 変更内容

- 

# テスト結果

- [ ] Tests
- [ ] Lint
- [ ] Type check
- [ ] Build
- [ ] 手動動作確認

<!-- 対象プロジェクトに存在しない項目は理由を記載 -->

# GitHubチェック

- [ ] GitHub Actions CI成功
- [ ] 利用可能なセキュリティチェックが成功、または利用不能・失敗時に人間が例外を明示判断済み

セキュリティチェック例外理由（該当時）:

- なし

# Codex Code Review

- [ ] `@codex review`実行済み（レビュー専用。修正は実行していない）
- [ ] P0 / P1 指摘なし、またはすべて解消済み
- [ ] P2 指摘なし、または人間が残置理由を確認済み
- [ ] 修正を行った場合、既存PRのhead branchを使用し、新しいPRを作成していない
- [ ] 修正を行った場合、修正前後のPR番号・head branch・head SHAを記録済み
- [ ] 修正を行った場合、修正前後のhead SHAを比較し、実際に更新されたことを確認済み
- [ ] 修正を行った場合、同じhead branchへcommit/push済み
- [ ] 修正を行った場合、head SHA更新確認後にローカルテスト（tests / lint / type check / build）を再実行済み
- [ ] 修正を行った場合、更新後のheadを対象にCIを再実行済み
- [ ] 修正を行った場合、セキュリティチェックを再実行済み、または人間が例外理由を確認済み
- [ ] 修正を行った場合、CIとセキュリティチェックの成功または例外判断後、更新後のheadを対象に`@codex review`を再実行済み

修正前のPR情報（修正時）:
- PR番号: なし
- head branch: なし
- head SHA: なし

修正後のPR情報（修正時）:
- PR番号: なし
- head branch: なし
- head SHA: なし

レビュー結果（P0 / P1 / P2 / P3 / 未解決指摘）:

- P0: なし
- P1: なし
- P2: なし
- P3: なし
- 未解決指摘・残置理由: なし

<!-- Automatic reviewsが無効な場合はPR上で @codex review を依頼する -->

# Issue範囲の確認

- [ ] Issueで要求された範囲に収まっている
- [ ] 不要なリファクタリングを含まない
- [ ] 不要な依存関係を追加していない
- [ ] 秘密情報を含まない
- [ ] 既存機能への影響を確認した

# Warning / Deprecation

- [ ] 新しいwarning / deprecationなし
- [ ] 残るwarning / deprecationは理由と後続対応要否を記載した

# 注意点・残課題

- なし

# レビュー時に特に確認してほしい点

- 
