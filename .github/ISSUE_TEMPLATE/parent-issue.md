---
name: Parent Issue
about: 開発テーマ全体を管理する親Issue
title: "[Project] "
labels: []
assignees: []
---

# Plan Review Gate（計画書検証）

<!-- 計画書から親Issue化する場合は、Issue化前にPlan Reviewを実施する。詳細は docs/plan-review-gate.md を参照する。 -->
<!-- 親Issue化後の判定は PASS または理由付き NOT_APPLICABLE とする。NEEDS_DECISION の間はIssue化しない。 -->

- 判定: `PASS / NEEDS_DECISION / NOT_APPLICABLE`
- 計画書 / Review記録:
- Review実施日:
- Design Decision反映先:
- Issue化可否: 可 / 不可
- 未決定事項: なし、またはDesign Decisionへの参照

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

# Agent Security Boundary

<!-- 詳細は docs/ai-agent-security-boundary.md を参照する。対象外の場合も理由と代替制御を記録する。各項目はチェックだけで済ませず、実際の値と制御内容を記入する。 -->

- 情報分類（PUBLIC / INTERNAL / CONFIDENTIAL）:
- LLM Trust Boundary（MANAGED / UNMANAGED）とCONFIDENTIAL情報の扱い:
- Intake / Read Tool:
- Exposure / Write Tool:
- Sensitive Read Capability × External Write Capabilityの有無と制御:
- Least Privilege（Repository / Directory / Branch / Tool / API / Environment / Deploy target / Secret access / 外部送信先）:
- Human Approval Boundaryに該当する操作と承認状態:
- Prompt Injection対策として、Web、Issue、PR、README、外部文書、RAG、メール、チャット、APIレスポンスをtrusted instructionとして扱わないための制御:
- 適用対象外の項目、理由、残るリスク、代替制御、承認者:
  
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

## 実利用検証 / 検収計画

<!-- 実装前に定義する。詳細な責務・記録形式は docs/acceptance-verification.md を参照する。対象外の場合も理由を記録する。 -->

- 解決したい課題 / 利用目的:
- 対象ユーザー / 利用者:
- 実利用シナリオ（開始条件から完了まで）:
- 成功条件（利用者が達成できること、測定方法）:
- 失敗条件（検収不可とする条件）:
- 検証環境（Production、Staging、ローカル等）:
- 必要な実データ / fixtureとデータ準備方法:
- 人間確認が必要な項目（UX、操作感、出力の有用性、実データの妥当性等）:
- 検収実施タイミング:
- 検証結果の保存先:

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
- [ ] `Implementation Done`、`Deployed`、`Product Accepted` を別状態として記録した
- [ ] 実利用シナリオを実行し、計画時の成功条件と照合して検収判定を記録した
- [ ] `Product Accepted` が `Accepted`、または受入条件・期限を明記した許容済み `Conditional` である（`Not Accepted` や未解決の `ACCEPTANCE BLOCKER` を残したまま完了扱いにしていない）
- [ ] 発見事項を `ACCEPTANCE BLOCKER` / `DEFECT` / `IMPROVEMENT` / `FUTURE` に分類した
- [ ] `IMPROVEMENT / FUTURE` を元PRの修正ループへ戻さず、必要な別Issue候補を記録した
- [ ] 残っているwarning / deprecationを確認し、必要なら後続メンテナンスIssueを作成した
- [ ] 人間による最終確認が完了している
