---
name: Parent Issue
about: 開発テーマ全体を管理する親Issue
title: "[Project] "
labels: []
assignees: []
---

# 目的

<!-- 何を実現するか -->

# 背景

<!-- なぜ必要か -->

# Design Decision

## 採用案

<!-- 今回採用する設計・方針と、その理由 -->

## 代替案

<!-- 少なくとも2案を検討し、採用しなかった理由を記録する -->

- Alternative A:
  - 概要:
  - 採用しない理由:
- Alternative B:
  - 概要:
  - 採用しない理由:

## 判断基準

<!-- 必要に応じて追加・削除する -->

- 実装コスト
- 保守性
- 性能
- セキュリティ
- 将来拡張性

## 懸念点

<!-- 採用案に残るリスク、未検証点、レビューで確認したい点 -->

- 

## 未決定事項

<!-- 未決定事項ごとに「なぜ今決めないか」「いつ/どのIssueで決めるか」を記録する -->

- 項目:
  - 未決定の理由:
  - 決定タイミング:
  - 関連Issue: #

## デプロイ設計 / Release・Production計画

<!-- 詳細な項目と安全条件は docs/deployment-release-design.md を参照する。不要な項目も理由を記録する。 -->

- Production runtime:
- Containerの要否と理由:
- Persistent dataの保存先・再作成後の生存方法:
- Deployment method・実行主体・権限:
- Release Candidate / artifact identity（commit SHA・artifact ID・image digest）:
- Secrets / 環境変数 / 外部サービス（値は記録しない）:
- backup・DB/schema/vector migration・失敗時の復旧:
- Stagingの要否と理由:
- E2E / Smoke Test・Release判定:
- Production Deploy後のHealth Check・Monitoring:
- Rollback単位・永続データ互換性:
- MergeからProduction Deployまでの承認境界:

## 子Issue実装中のDesign Decision Escalation

子Issueの実装中に、Issue本文またはこの親Issueの `Design Decision` に明記・事前承認されていない重要な設計判断が必要になった場合、Codexは独自判断で実装を継続せず停止する。Codexは停止理由、設計境界、選択肢、影響範囲、推奨案、親Issue更新・追加Issueの要否、元Issue再開に必要な決定事項を提示する。

人間の決定後、必要な内容をこの `Design Decision` または関連Issueへ記録してから、元の子Issueを再開する。これはPRレビューに代わるものではなく、既存の `1 Issue / 1 PR` とCI・AIレビュー・修正・マージの流れを維持する。

# 今回実装する範囲

- [ ] 

# 子Issue

- [ ] #

<!-- 注意: 子IssueがCloseしても、このチェックボックスは自動で[x]にならない場合があります。親IssueをCloseする前に手動またはChatGPTで最終確認してください。 -->

# 後続候補

<!-- 今回の完了後に検討する内容 -->

# 今回やらないこと

- 

# 依存関係・制約

- 

# 全体完了条件

- [ ] 必要な子IssueがすべてMerge / Close済み
- [ ] 親Issue内の子Issueチェックボックスを最終状態へ更新した
- [ ] Design Decisionの採用案・代替案・懸念点・未決定事項が最新状態になっている
- [ ] 必要なテストが成功している
- [ ] GitHub Actions CIが成功している
- [ ] 利用可能なセキュリティチェックを確認した
- [ ] ドキュメントが更新されている
- [ ] 実環境または想定環境で基本動作を確認している
- [ ] 残っているwarning / deprecationを確認し、必要なら後続メンテナンスIssueを作成した
- [ ] 人間による最終確認が完了している
