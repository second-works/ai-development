---
name: Parent Issue
about: 開発テーマ全体を管理する親Issue
title: "[Project] "
labels: []
assignees: []
---

# 目的

<!-- プロジェクト全体で達成すること -->

# Plan Review / Design Decision

- Plan Review: `PASS / NEEDS_DECISION / NOT_APPLICABLE`
- 記録・正本: [Plan Review Gate](../../docs/plan-review-gate.md)
- 採用案と理由:
- 未決定事項・決定タイミング:

> `NEEDS_DECISION` の間は子Issue化・実装開始を停止する。重要な設計変更は正本のDesign Decisionへ記録する。

# 今回の範囲

- 今回実装する範囲:
- やらないこと:
- 子Issue（原則 1子Issue = 1 PR）:
- 依存関係・実装順:

# 安全境界とリリース判断

- 情報分類 / LLM Trust Boundary:
- Read / Write範囲:
- Human Approvalが必要な操作と状態:
- 対象外・例外、残るリスク、代替制御:
- Release / Production方針、または対象外の理由:

詳細は [AI Agent Security Boundary](../../docs/ai-agent-security-boundary.md) と [Deployment / Release Design](../../docs/deployment-release-design.md) を参照する。Secrets、権限、Security Policy、Production操作は人間承認まで停止する。

# 検収計画

- 対象ユーザー・実利用シナリオ:
- 成功 / 失敗条件:
- 検証環境・人間確認:
- Product Acceptanceの記録先:

検収の正本は [Acceptance Verification](../../docs/acceptance-verification.md)。Implementation、Deploy、Product Acceptedは別状態として記録する。

# Current State

- Current phase:
- 観測済みSHA / CI・Security・Review:
- 次アクション:

# 全体完了条件

- [ ] 子IssueがすべてMerge / Close済み
- [ ] 必要な検証・CI・Security・Reviewを確認済み
- [ ] Product Acceptanceを記録済み
- [ ] 人間が最終確認済み
