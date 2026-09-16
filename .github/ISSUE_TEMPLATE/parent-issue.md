---
name: Parent Issue
about: 開発テーマ全体を管理する親Issue
title: "[Project] "
labels: []
assignees: []
---

# 目的

<!-- プロジェクト全体で達成すること -->

# Decision Summary

- 採用案:
- 主要理由:
- 影響:

# Framework Decision

- Result: `DECIDED / NOT_APPLICABLE / NEEDS_DECISION`
- 正本文書: [Framework Decision v1](../blob/main/docs/architecture/framework-decision.md)
- 適用対象 / 対象外理由:
- 決定内容・Framework依存の未決定事項:
- 子Issueへ引き継ぐ参照:

> `NEEDS_DECISION` の間はFramework依存のUI設計、子Issue化、実装開始を停止し、既存のDesign Decisionへ接続する。特定FrameworkをAIが暗黙に採用しない。

# Plan Review / Design Decision

- Plan Review: `PASS / NEEDS_DECISION / NOT_APPLICABLE`
- 記録・正本: [Plan Review Gate](../blob/main/docs/plan-review-gate.md)
- Framework Decision結果の参照:
- 採用案と理由:
- 未決定事項・決定タイミング:

> `NEEDS_DECISION` の間は子Issue化・実装開始を停止する。重要な設計変更は正本のDesign Decisionへ記録する。

# UI Level / PRODUCT UI

- UI Level: `NONE / UTILITY / PRODUCT / NEEDS_DECISION`
- 分類理由:
- PRODUCT時の適用仕様: [Nine PRODUCT UI Standard v1](../blob/main/docs/product-ui-standard.md)
- PRODUCT時のDesign Profile / docs/design.md: [Design Profile / design.md雛形](../blob/main/templates/app/docs/design.md)
- UI LevelがNEEDS_DECISIONの場合の未決定事項・決定期限:

> UI Levelが `NEEDS_DECISION` の間は、AI/Codexが分類や重要UX判断を推測せず、子Issue化・実装開始を停止する。PRODUCT以外ではPRODUCT用の必須欄やVisual/UI Acceptanceを強制しない。

# AI / Codex Reference Contract（PRODUCT UI実装時）

- 参照順序: Framework Decision結果 → UI Level → Nine PRODUCT UI Standard / `Component Decision Rules` → 案件 `docs/design.md` → component / library固有docs（存在時）
- Framework Decision結果・正本文書: [Framework Decision v1](../blob/main/docs/architecture/framework-decision.md)、親Issueの記録:
- UI Level・適用対象・親Issueの判断:
- Standard Design Rules: [Component Decision Rules](../blob/main/docs/product-ui-standard.md#component-decision-rules)
- 案件 `docs/design.md`: [Design Profile / docs/design.md雛形](../blob/main/templates/app/docs/design.md)
- 案件固有のvisual、brand、tokens、採用component、例外、根拠:
- component / library固有docsと採用理由（存在時）:
- 未決定事項・矛盾・候補不足・Design Decision参照:

> PRODUCT UIの重要判断は上記順序で参照する。判断材料が欠落・矛盾・不足する場合は推測で補完せず `NEEDS_DECISION` としてDesign Decisionへ接続し、実装を停止する。NONE / UTILITYではPRODUCT UI用の必須欄やVisual/UI Acceptanceを強制しない。

# 今回の範囲

- 今回実装する範囲:
- Non-goals（今回扱わないこと）:
- 子Issue（原則 1子Issue = 1 PR）:
- 依存関係・実装順:

## Alternatives

| 案 | 却下理由 |
| --- | --- |
|  |  |

# Agent Security Boundary とリリース判断

- 情報分類（PUBLIC / INTERNAL / CONFIDENTIAL）:
- LLM Trust Boundary:
- Read / Write範囲:
- Prompt Injection対策:
- Human Approvalが必要な操作と状態:
- 対象外・例外、残るリスク、代替制御:
- Release / Production方針、または対象外の理由:
- Full-System Security Audit対象のRelease Candidate SHA / artifact identity:
- RC静的監査とStaging上の確認の証拠:
- Full-System Security Audit結果（PASS / FAIL / NOT_APPLICABLE）と理由:

各項目はチェックだけで済ませず、実際の値と制御内容を記入する。

詳細は [AI Agent Security Boundary](../blob/main/docs/ai-agent-security-boundary.md) と [Deployment / Release Design](../blob/main/docs/deployment-release-design.md) を参照する。Secrets、権限、Security Policy、Production操作は人間承認まで停止する。

# 検収計画

- 対象ユーザー・実利用シナリオ:
- 成功 / 失敗条件:
- 検証環境・人間確認:
- Product Acceptanceの記録先:

検収の正本は [Acceptance Verification](../blob/main/docs/acceptance-verification.md)。Implementation、Deploy、Product Acceptedは別状態として記録する。

# Harness Minimalism / ETCSLV

- 解決する失敗モード:
- 削除・再評価条件:

詳細は [Harness Minimalism台帳](../blob/main/docs/ai-development-harness-inventory.md) を参照する。

# Current State

- Current phase:
- 観測済みSHA / CI・Security・Review:
- 次アクション:

# 全体完了条件

- [ ] 子IssueがすべてMerge / Close済み
- [ ] 必要な検証・CI・Security・Reviewを確認済み
- [ ] Product Acceptance target artifactとCurrent Deploy target artifactが設定済みかつ一致し、Accepted、または条件・期限・追跡Issueを記録し未解決ACCEPTANCE BLOCKERがないConditionalである
- [ ] Product Acceptanceを記録済み
- [ ] 人間が最終確認済み
