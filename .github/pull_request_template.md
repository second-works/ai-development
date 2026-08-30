# 対応Issue

Closes #

# 変更内容

- 

# テスト結果

- [ ] 標準検証入口 `./scripts/verify.sh` 成功（lint → type check → test → build）
- 標準検証を実行できない場合の理由:
- [ ] 手動動作確認

# 実利用検証 / Product Acceptance

実利用検証は、Health Check / Smoke TestおよびCI / Code Reviewとは別の検収工程として、原則Deploy後に実施する。実装段階で未実施の場合は、理由と引き継ぎ先を記録する。詳細は [docs/acceptance-verification.md](../docs/acceptance-verification.md) を参照する。

- Implementation Done: `未完了 / 完了`
- Deployed: `未実施 / 完了`
- Product Accepted: `Not run / Accepted / Not Accepted / Conditional`
- 判定対象のRelease / commit / tag / SHA:
- 検証環境:
- 実利用シナリオ:
- 計画時の成功条件との照合結果:
- 発見事項と分類（`ACCEPTANCE BLOCKER` / `DEFECT` / `IMPROVEMENT` / `FUTURE`）:
- 未解決事項・関連Issue:
- 未実施または対象外の理由・実施タイミング:

# GitHubチェック

- CI判定: `CI_PASSED / CI_FAILED / CI_UNAVAILABLE`
- Security Preflight判定: `SECURITY_PASSED / SECURITY_FAILED / SECURITY_NOT_APPLICABLE / SECURITY_UNAVAILABLE`
- GitHub Security / Code Scanning判定:
- CI対象SHA:
- Security対象SHA:
- `SECURITY_NOT_APPLICABLE` / `SECURITY_UNAVAILABLE` / 未実行の理由:
- [ ] CIとSecurityを別々に確認した
- [ ] `SECURITY_FAILED` がなく、`SECURITY_UNAVAILABLE` は人間が明示判断済み

セキュリティチェック例外理由（該当時）:

- なし

# Codex Code Review

## Safe Auto-Fix / Auto-Merge（該当時のみ）

Safeレーンを採用しない場合は `なし` とし、採用する場合は [Safe Auto-Fix / Auto-Mergeレーン標準](../docs/safe-auto-fix-auto-merge.md) の全条件を確認する。

- Safeレーン: `なし / 判定中 / 採用 / 通常レーンへ復帰`
- AUTO-FIX対象P2 / 元レビューID:
- eligibility / Safety Gate結果:
- 不成立のGate（該当時）:
- 自動修正commit SHA:
- `verify.sh`対象SHA:
- CI対象SHA:
- Security / Code Scanning対象SHA:
- Codex再Review対象SHA:
- Security適用除外の理由・人間の判断（該当時）:
- Auto-Merge Gate:
- Auto-Merge実行主体 / 実行時刻 / マージSHA（該当時）:

- [ ] P0 / P1 / `BLOCKING` P2がない
- [ ] 自動修正後の再レビューで新しいP2が発生していない（発生時は通常レーンへ復帰）
- [ ] 公開契約、DB、auth、security、infra、Deploy、network、Workflow権限、dependency major updateを変更していない
- [ ] テスト削除・skip・品質ゲート緩和をしていない
- [ ] AUTO-FIXは1ラウンドだけで、追加自動修正へ戻らない
- [ ] 自動修正commit SHA、各検証対象SHA、PR head SHAが一致している
- [ ] 必要な監査記録をPR上に残している

## レビュー修正ラウンド / 収束判断

- 現在のレビュー修正ラウンド数（初回レビューは0）:
- 新規P0:
- 新規P1:
- 新規P2:
- 3ラウンド到達時の停止判断:
- P2残置理由（該当時）:
- 人間による継続指示または受容判断:
- 標準検証 `./scripts/verify.sh` の結果:

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
- [ ] 通常レーンではAIにMerge権限を与えず、人間が最終Mergeを判断する。Safeレーン採用時は正本文書の条件と人間の採用判断を記録する

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
