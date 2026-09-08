---
name: Child Issue
about: 1 PR単位でCodexに実装させる子Issue
title: "[Task] "
labels: []
assignees: []
---

# 目的

<!-- このIssueだけで達成すること -->

# 今回の変更

- 実装内容:
- 変更してよい範囲:
- 原則変更しない範囲:
- やらないこと:
- 完了条件:
- Parent / Depends on:

> 1子Issue = 1 PR。登録・実装開始前に [Issue Quality Check](../blob/main/docs/issue-quality-check.md) のMUSTを満たすこと。MUST不足はScoreにかかわらず停止する。

# Risk Tier

- Tier（LOW / MEDIUM / HIGH）:
- 判定理由・影響範囲:
- 追加検証・承認、または対象外の理由:
- 再判定（実装開始 / PR提出 / 影響変更時）:

判定順・例外は [Adaptive Development Flow](../blob/main/docs/adaptive-development-flow.md) を参照する。LOWでも標準検証、CI、Security、Codex Review、人間Merge判断を省略しない。

# テストと受入条件

- 正常値 / 値の範囲 / 整合性:
- 境界値 / 異常系 / 回帰:
- 実行する標準検証・手動確認:
- 既存テストを変更する場合の保証先:

テスト責務・テスト層・既存テスト変更時の保証先は [Test Design / Safe Test Deletion](../blob/main/AGENTS.md#test-design--safe-test-deletion) を正本として参照する。Deploy後の検収は [Acceptance Verification](../blob/main/docs/acceptance-verification.md) を参照する。

# Agent Security Boundary（安全境界と停止条件）

- 情報分類（PUBLIC / INTERNAL / CONFIDENTIAL）:
- LLM Trust Boundary:
- Read / Write範囲とLeast Privilege:
- Human Approvalが必要な操作と状態:
- 適用対象外の項目、理由、残るリスク、代替制御、承認者:
- Prompt Injection対策:

[AI Agent Security Boundary](../blob/main/docs/ai-agent-security-boundary.md) の境界に該当する外部送信、権限拡大、Secrets、Security Policy、Production操作は人間承認まで停止する。事前承認のない重要設計変更は、親IssueのDesign Decisionへエスカレーションして決定まで実装を止める。

# Harness（追加・変更時のみ）

- 台帳ID / 判定:
- 失敗モード・代替制御:
- 変更理由・再評価条件:

詳細は [Harness Minimalism台帳](../blob/main/docs/ai-development-harness-inventory.md) を参照する。追加・変更がなければ「なし」と理由を記録する。

# Harness Minimalism / ETCSLV

- 判定（KEEP / STRENGTHEN / SIMPLIFY / REMOVE_CANDIDATE）:

# Current State

- Current phase / 次アクション:
- Issue acceptance status:
- Product Acceptance result:
- Product Acceptance target artifact:
- Current Deploy target artifact:
- Current head SHA / Expected SHA:
- Verification status（local / CI / Security / Review）:
- 対象SHAと local / CI / Security / Review:
- 停止理由（該当時）:

Current Stateのenumと観測方法は [AI Execution State](../blob/main/docs/ai-execution-state.md) を参照する。Issue記載内容を仕様の基準とし、修正は同じPR branchで行う。最終Mergeは人間が判断する。
