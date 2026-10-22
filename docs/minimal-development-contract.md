# Issue生成＋Codex実装のMinimal Contract

> 2026-10-23 に整理した。エージェントの入口（AGENTS.md、steward、plan-to-issues）から参照されず、テストも内容を確かめていない節を削除し、テストが確かめる節だけを残した。削除前の全文は commit `0e8523a` にある（`git show 0e8523a:docs/minimal-development-contract.md`）。

**Decision: 常駐するのは作業範囲・検証・レビュー・人間承認の境界だけとし、Issueには今回のGoal / Context / Boundaries / Done / Verificationを記す。**

`ai-development` は、Nine標準のIssue生成とCodex実装に必要なテンプレートを提供する。

親 [#168](https://github.com/second-works/ai-development/issues/168)、Phase 2 [#171](https://github.com/second-works/ai-development/issues/171)。基準mainは `7a52b2b3f46487b91190a6c923926c9325913046`。棚卸しは [#169 / PR #170](https://github.com/second-works/ai-development/pull/170)、そのレビュー修正は `7d6c419da5bdc729ad0ee9c8696a615c4baaef11`。2026-10-03の人間確認と「次のフェーズへ」の指示を受けて設計を進めた。

本書はPhase 2で合意しPR #172でマージした最小契約。Issue #177でAGENTSと参照テストを切り替えた。親子テンプレートとplan-to-issuesはIssue #179で変更し、CI workflowの変更は別Issueとする。先行PR #170 / #172 / #174は2026-10-04の人間指示でマージ済み。現行ルールの置換・削除は責務移行と参照検証の成功後に直列化する。PR #176までの残責務移行後、Issue #177で最小AGENTSを有効化した。既存projectへの一括適用や自動Mergeは導入しない。

Issue #177で最小AGENTSと詳細docsの参照経路を有効化し、Issue #179で親子テンプレートとplan-to-issuesを以下の最小入力契約へ切り替える。条件表は読取入口とし、非該当の専門欄は生成しない。既存Issueに書かれたScope / Done / Verificationを本契約から推測で省略しない。

## Issue #179: 入力責務の移行

基準はPR #178のmerge `5a721707d4b79af7324f0979d96bec7283bad163`。YAML metadataを維持し、今回値は7見出しへ置く。既存IssueとPR template / helper / CIの実行契約は変更しない。

| 旧テンプレートの責務 | 最小入力と詳細の保持先 |
| --- | --- |
| 目的・採用判断・技術補足・Scope・Non-goals・代替案 | Goal / Context / Scope / Non-goals。採用判断と理由はContext、必要な補足・比較だけ設計記録を参照 |
| Risk Tier・影響・再判定 | Scope / BoundariesへTierと理由。判定/再判定はadaptive-development-flow.mdの全変更ルール |
| Plan Review / Framework / UI引き継ぎ | 計画から生成するIssueはPlan Review判定・理由・正本参照をContextに必ず保存。Framework / UIは適用時の結果・分類理由・参照・未決と停止範囲を追加。NEEDS_DECISIONは登録/実装停止 |
| PRODUCTの5段階参照・Component / Visual / Accessibility | product-ui-standard.mdのAI / Codex Reference Contractと案件docs/design.md。重要判断欠落・矛盾・取得不能時停止。非PRODUCTへ過剰適用しない |
| Security分類・環境・Read/Write・最小権限・承認・例外・Prompt Injection | Boundariesへ今回値、ai-agent-security-boundary.mdの適用チェック。機密送信・権限・Production等は明示承認まで停止。適用制御の例外は理由・残るリスク・代替制御・承認者を必須とする |
| テスト6観点・安全なテスト削除 | Verificationで必要ケース・期待結果を選ぶ。test-design.mdに従い代替成功前に旧保証を消さない |
| Harness / ETCSLV・失敗モード・再評価条件 | 検証・Tool保証変更時だけ [template-guide](template-guide.md#122-検査やgateを足すとき減らすとき) の12.2章と [test-design](test-design.md) を参照し、防ぎたい失敗・代替保証・削除順・再評価条件をIssue/PRへ記録 |
| Current State / acceptance_status / Product Acceptance / 対象SHA | 再開・検証引き継ぎ・検収識別時だけai-execution-state.mdを参照。schema v3と現head検証、同一artifact照合・不一致停止は保持 |
| Release policy / RC audit / 検収計画 / 全体完了 | 適用時はdeployment-release-design.md、acceptance-verification.mdへ接続。監査結果・RC静的監査・Staging・identity・検収条件を記録。親Closeはparent-issue-completion.mdの5項目を確認し、MergeだけでProduct Acceptedにしない |

確認例は既存tests/plan-to-issuesの最小本文検査を使う。これは入力契約の回帰であり、Phase 5の実際のIssue → 実装 → PR → Reviewの受入を代替しない。

### 最小子Issueの記入例（入力契約の確認用）

これらは未登録の例。Scope・Done・Verificationの意味はCodexのself-reviewでも確認する。テキスト検査だけで一般の計画判断を自動化できたとは扱わない。

#### 文言修正

```markdown
# Goal
READMEの旧製品名を現行名称へ訂正する。1子Issue = 1 PR。
# Context
名称が読者を誤解させる。Plan Review: NOT_APPLICABLE、局所文言のみ、正本: docs/plan-review-gate.md。
# Scope / Boundaries
README.mdの名称1箇所。Risk Tier: LOW、実行動作変更なし。PUBLIC文書のみ読取、書込は対象repoのPR branch、機密送信・Production操作なし。Human Approval: Mergeは人間判断。
# Non-goals
実装・設定・他の文言は変更しない。
# Done
読者が現行製品名を確認でき、リンク先と名称が一致する。
# Verification
README表示と公式名称を照合して一致、diffとリンク確認、既存検証の成功を確認する。
# Dependencies
なし。
```

#### PRODUCT UI

```markdown
# Goal
一般利用者が一覧から確認画面へ進める導線を実装する。1子Issue = 1 PR。
# Context
採用済み設計の導線が未実装。Plan Review: PASS、重要UXは確定、正本: docs/plan-review-gate.md。UI Level: PRODUCT、一般利用者の主要操作。Framework Decision: DECIDED、既存採用を継承。product-ui-standard.mdと案件docs/design.mdを参照し、5段階の参照順に従う。
# Scope / Boundaries
src/screens/listと既存UI test。Risk Tier: MEDIUM、画面遷移へ影響。PUBLIC fixtureのみ読取、書込は対象repoのPR branch。Human Approval: 未承認の重要UX判断は停止、Mergeは人間判断。
# Non-goals
Framework再選定、認証・本番Deployは行わない。
# Done
利用者が主要操作を認識し、キーボードでも確認画面へ進み、失敗時に回復できる。
# Verification
主要flow E2E、loading/empty/error、focusとAccessibility、対象deviceでVisual/UI Acceptanceを確認しdocs/design.mdの成功条件と照合する。標準検証、CI / Security / Codex Reviewを確認する。
# Dependencies
Parent: #100。Depends on: #101（採用設計、完了済み）。
```

#### 高リスク操作の準備

```markdown
# Goal
承認前に実行しない本番migration手順と復旧試験を作成する。1子Issue = 1 PR。
# Context
停止条件と復旧を実行前に確認する。Plan Review: PASS、設計は承認済み、正本: docs/plan-review-gate.md。deployment-release-design.mdを適用する。
# Scope / Boundaries
docs/migration.mdと隔離fixture testのみ。Risk Tier: HIGH、本番データ破損リスク。Read: PUBLIC fixtureのみ、実データ・Secretsを取得しない。LLM: MANAGED。Write: 対象repoのPR branchだけ。Tool / Destination allowlist: ローカルtestと対象repo。Human Approval: Production操作は未承認、停止する。権限変更・外部送信は行わない。例外なし。
# Non-goals
本番migration・Deploy・権限設定は実行しない。
# Done
隔離fixtureでmigration後の互換性とbackupからの復旧を確認でき、運用者が承認前停止を識別できる。
# Verification
正常・異常時のデータ照合、rollback fixture、標準検証とCI / Security / Codex Review。ReleaseはRC identityとFull-System Security Auditの結果を記録して別途人間承認を得るまで停止する。
# Dependencies
なし。
```

#### 依存が未確定の場合

上の文言修正のDependenciesが「後で決める」なら、なしと補完せず登録・実装を停止する。依存する設計や仕様を特定して再判定する。PRODUCTの重要UXが未確定、安全境界が不明、または6 MUSTの一つでも欠落した場合も同様。
