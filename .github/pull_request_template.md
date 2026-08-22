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

## 修正時のPR / head branch記録

修正を行った場合は、既存PRのhead branchに対する作業だけを記録する。

- 対象PR番号: #
- 修正前のhead branch:
- 修正前のhead SHA:
- 修正後のhead branch:
- 修正後のhead SHA:
- 修正を行ったコミットSHA:
- 各再検証の対象SHA:
- GitHub上のPR head SHAとの一致確認（日時 / 確認者）:
- 再検証完了時のPR head SHA一致確認（日時 / 確認者）:
- SHA更新確認（日時 / 確認者）:

- [ ] `@codex review` はレビュー専用で、修正には使っていない
- [ ] `@codex address that feedback` を標準手順として使っていない
- [ ] 新しいPRを作らず、既存PRを再利用した
- [ ] pushした修正コミットSHAとGitHub上のPR head SHAが一致している
- [ ] ローカルテスト・CI・セキュリティチェック・再レビューの対象SHAを記録した
- [ ] 再検証完了時に、修正コミットSHA・検証対象SHA・PR head SHAが一致している
- [ ] SHA未確認・未更新・不一致時は再検証または完了扱いにせず停止した
- [ ] AIにMerge権限を与えず、最終Mergeは人間が判断する

- [ ] Codex Code Review実行済み
- [ ] P0 / P1 指摘なし、またはすべて解消済み
- [ ] P2 指摘なし、または人間が残置理由を確認済み
- [ ] 修正を行った場合、修正前のPR head SHAと修正後のPR head SHAを比較し、実際に更新されたことを確認済み
- [ ] 修正を行った場合、head SHA更新確認後にローカルテスト（tests / lint / type check / build）を再実行済み
- [ ] 修正を行った場合、更新後のheadを対象にCIを再実行済み
- [ ] 修正を行った場合、セキュリティチェックを再実行済み、または人間が例外理由を確認済み
- [ ] 修正を行った場合、CIとセキュリティチェックの成功または例外判断後、更新後のheadを対象にCodex Code Reviewを再実行済み

レビュー結果（P0 / P1 / P2 / P3 / 未解決指摘）:

- P0: なし
- P1: なし
- P2: なし
- P3: なし
- 未解決指摘・残置理由: なし

<!-- Automatic reviewsが無効な場合はPR上で @codex review を依頼する。@codex reviewはレビュー専用とし、修正は既存PRのhead branchで行う。 -->

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
