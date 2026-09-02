---
name: Child Issue
about: 1 PR単位でCodexに実装させる子Issue
title: "[Task] "
labels: []
assignees: []
---

# 目的

<!-- このIssueだけで達成すること -->

# 実装内容

- [ ] 

# やらないこと

- Issue範囲外の機能追加
- 不要なリファクタリング
- 指定外の依存関係追加
- 既存API仕様の無断変更
- テストの無効化
- force push

# 変更してよい範囲

```text
path/to/allowed/**
```

# 原則変更しない範囲

```text
path/to/protected/**
.env
```

<!-- 変更が不可避なら理由を明記する -->

# 完了条件

- [ ] 指定機能が実装されている
- [ ] 既存テストが成功する
- [ ] 必要な新規テストが追加されている
- [ ] lint / type check / buildのうち定義済みのチェックが成功する
- [ ] 秘密情報を含まない
- [ ] PRが作成されている

# Current State

<!-- Current Stateの正本とenumは docs/ai-execution-state.md を参照する。全文を転記せず、実装時点の要約だけを記録する。 -->

- Current phase: `PLAN_READY / IMPLEMENT / LOCAL_VERIFY / PR_OPEN / CI_SECURITY / REVIEW / FIX / REVERIFY / READY_FOR_HUMAN_MERGE / MERGED / DEPLOY / ACCEPTANCE / COMPLETED`
- Issue acceptance status:
- Product Acceptance result:
- Product Acceptance conditions / deadline / follow-up Issue:
- Current head SHA:
- Expected SHA:
- Verification status（local / CI / Security / Review）:
- Review round / blocking finding status:
- Stop reason:
- Next action:

# Agent Security Boundary

<!-- 詳細は docs/ai-agent-security-boundary.md を参照する。 -->

- 情報分類（PUBLIC / INTERNAL / CONFIDENTIAL）:
- LLM Trust Boundary（MANAGED / UNMANAGED）:
- Intake / Read Tool:
- Exposure / Write Tool:
- Sensitive Read Capability × External Write Capabilityの有無と制御:
- Least Privilege（Repository / Directory / Branch / Tool / API / Environment / Deploy target / Secret access / 外部送信先）:
- Human Approval Boundaryに該当する操作と承認状態:
- 外部コンテンツをtrusted instructionとして扱わないための制御:
- 適用対象外の項目、理由、残るリスク、代替制御、承認者:

# Harness Minimalism / ETCSLV

<!-- 新しいハーネスの追加または既存ハーネスの変更では、各項目を記入する。詳細は docs/ai-development-harness-inventory.md を参照する。 -->

- 対象ハーネス:
- ETCSLV分類（Execution / Tools / Context / State / Lifecycle Hooks / Verification）:
- 解決する失敗モード:
- 発火条件:
- 入力 / Context:
- 出力 / State変更:
- 決定論的判定へ移せるか:
- 実行コスト / 運用負荷:
- 重複する仕組み:
- 安全上必須か:
- 判定（KEEP / STRENGTHEN / SIMPLIFY / REMOVE_CANDIDATE）:
- 削除・再評価条件:
- 関連Issue / 正本文書:

# Design Decision Escalation

子Issueの実装中に、Issue本文または親Issueの `Design Decision` に明記・事前承認されていない重要な設計判断が必要になった場合は、独自判断で実装を継続せず停止する。

## 停止条件

次のいずれかに該当する変更が事前承認されていない場合は停止する。

1. DBスキーマ、マイグレーション、永続化モデルを変更する。
2. 公開API、CLI、設定ファイル形式、外部インターフェースを変更する。
3. 既存の型、状態モデル、責務境界、主要データ構造を変更する。
4. 新しい主要ライブラリ、外部サービス、永続化方式を導入する。
5. 認証、認可、秘密情報、セキュリティ境界を変更する。
6. Issueの完了条件、やらないこと、変更可能範囲を変更しないと実装できない。
7. 複数の妥当な設計案があり、選択によって将来拡張性、保守性、互換性が大きく変わる。
8. 親Issueの `Design Decision` と矛盾する。
9. 別Issueの責務や実装範囲まで変更しないと成立しない。

## エスカレーション時の標準出力

停止した場合は、単に「判断が必要」と報告せず、このIssueまたは作業報告に次の形式で提案を残す。

```markdown
## Design Decision Escalation

### 停止理由

### 該当する設計境界 / Design Decision

### 選択肢
- A:
- B:

### 影響範囲
- A:
- B:

### 推奨案

### 親Issue更新の要否

### 追加Issueの要否

### 元Issue再開に必要な決定
```

人間が判断した後、必要に応じて親Issueの `Design Decision` を更新するか追加Issueを作成し、決定事項を明記してから元Issueを再開する。

## 自律実装してよい範囲

停止条件に該当しない、既存設計の範囲内の実装判断はCodexに任せる。

- privateな関数・メソッド分割
- 変数名や内部実装の整理
- 既存設計の範囲内のリファクタリング
- テストケース追加
- 既存インターフェースを変えない内部エラーハンドリング改善
- 完了条件を満たすための局所的な実装詳細

既存の `1 Issue / 1 PR → 実装 → CI → AIレビュー → 修正 → マージ` の流れは変更しない。Design Decision Escalationは実装中の重要な設計判断を人間へ戻すための停止手段であり、PRレビューの代替ではない。

# Codexレビュー後の修正方針

- [ ] `@codex review` はレビュー専用とし、修正を実行しない
- [ ] P0 / P1 / P2の修正は `@codex address that feedback` を標準手順に使わず、既存PRのhead branchをチェックアウトして行う
- [ ] 修正前に対象PR番号・head branch・head SHAを確認する
- [ ] 修正後は同じhead branchへcommit / pushし、新しいPRを作らず既存PRを再利用する
- [ ] pushした修正コミットSHAとGitHub上のPR head SHAが一致することを確認する
- [ ] GitHub上でhead SHAの更新を確認し、未確認・未更新・不一致なら再検証へ進まない
- [ ] 修正コミットSHAを検証対象SHAとして記録し、そのSHAを対象に更新後のheadをローカルテスト → CI → セキュリティチェック → `@codex review` の順で再検証する
- [ ] 各チェックの対象SHAを記録し、再検証完了時に修正コミットSHA・検証対象SHA・PR head SHAが一致することを確認する
- [ ] 最終Mergeは人間が判断する

# テスト

Issue作成時は、正常系だけでなく以下の観点を具体的なテスト条件として検討する。

- [ ] 正常値 — 期待する値・レスポンスを取得できる
  - 条件: <!-- 入力値・期待値・期待結果を具体的に記入 -->
  - 対象外の場合の理由: <!-- 対象外なら理由を記入 -->
- [ ] 値の範囲 — 数値などが仕様上の有効範囲内である
  - 条件: <!-- 最小値・最大値・許容範囲・期待結果を具体的に記入 -->
  - 対象外の場合の理由: <!-- 対象外なら理由を記入 -->
- [ ] 整合性 — 関連する複数の値・状態が互いに矛盾していない
  - 条件: <!-- 確認する値・状態の関係と期待結果を具体的に記入 -->
  - 対象外の場合の理由: <!-- 対象外なら理由を記入 -->
- [ ] 境界値 — 0、最大値、空データなどの境界条件で問題がない
  - 条件: <!-- 確認する境界値・入力・期待結果を具体的に記入 -->
  - 対象外の場合の理由: <!-- 対象外なら理由を記入 -->
- [ ] 異常系 — 想定外の入力・戻り値・失敗時に適切に処理する
  - 条件: <!-- 異常入力・失敗条件・期待するエラー処理を具体的に記入 -->
  - 対象外の場合の理由: <!-- 対象外なら理由を記入 -->
- [ ] 回帰テスト — 既知の不具合が再発した場合に検出できる
  - 条件: <!-- 再現条件・検出方法・期待結果を具体的に記入 -->
  - 対象外の場合の理由: <!-- 対象外なら理由を記入 -->

不具合修正Issueでは、可能な限り修正前の実装では失敗し、修正後の実装では成功する回帰テストを追加する。該当しない場合は、その理由をIssue本文に記載する。

```bash
# プロジェクトに合わせて記入
```

# 依存関係

- Parent: #
- Depends on: #

# Codexへの追加指示

Issue記載内容を仕様の基準とする。仕様だけでは判断できない重大な問題がある場合、推測で範囲を拡張せず、`Design Decision Escalation` の停止条件と標準出力に従うこと。
