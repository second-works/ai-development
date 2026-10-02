# ai-development

Nine標準AI開発フローを管理する非公開リポジトリです。

## 目的

ChatGPTで要件整理・設計を行い、GitHub Issueで作業を分解し、Codexで実装・テスト・PR作成まで進める標準手順をここで管理します。

## 標準フロー

1. ChatGPTで要件整理・計画書作成（手順は [`docs/plan-authoring.md`](docs/plan-authoring.md)）
2. Framework Decision（要件 → Rendering Strategy → Application Architecture → Framework）
3. UI Level Decision / PRODUCT前提整理
4. Plan Review Gate（Grilling）
5. 必要なDesign Decisionを確定
6. 親Issueを作成
7. 1 PR単位の子Issueへ分解
8. Codexで実装
9. 標準検証 `./scripts/verify.sh` を実行
10. PR作成
11. GitHub Actions CI
12. Codex Code Review（レビュー専用）
13. P0 / P1は原則BLOCKINGとして必ず修正し、P2はSeverityだけで判断せず四分類（`BLOCKING / IN-SCOPE FIX / FOLLOW-UP / DISMISS`）する。非BLOCKING P2に個別人間承認は要求せず、既存PRのhead branchでBLOCKINGだけを修正
14. 修正前に対象PR番号・head branch・head SHAを確認し、同じhead branchへcommit / push
15. GitHub上で修正後のhead SHAが、pushした修正コミットSHAと一致することを確認
16. SHA未確認・未更新・不一致の場合は再テスト・CI・セキュリティチェック・再レビューへ進まず停止
17. 修正コミットSHAを検証対象SHAとして記録し、そのSHAを対象にローカルテスト → CI → セキュリティチェック → `@codex review` の順で再検証
18. 各チェックの対象SHAを記録し、再検証完了時にPR head SHAがpushした修正コミットSHAおよび検証対象SHAと一致することを確認。不一致なら完了扱いにせず停止
19. 新しいPRを作らず既存PRを再利用
20. 人間が最終確認
21. 人間がMerge

P0 / P1 / P2の修正に `@codex address that feedback` は標準手順として使用せず、`@codex review` はレビュー専用とします。CodexのAutomatic reviewsが利用可能な場合は自動レビューを原則とし、無効な場合はPR上で `@codex review` を依頼します。

レビュー修正ラウンドは、Codex Code Review → 修正 → 再検証・再レビューを1単位とし、初回レビューはラウンド0として記録します。第3ラウンド完了後に新しいP1 / BLOCKING P2が発生した場合は自動修正を停止して人間へ戻し、3ラウンドで強制Mergeしません。P0 / P1が残る場合はMerge禁止、非BLOCKING P2のみが残る場合は、分類と記録後に追加修正ループへ戻しません。通常レーンの最終Mergeは人間が判断します。P3は原則Merge阻害条件にしません。

レビュー指摘はReview Evidence Contract（Location、Trigger、Expected、Actual、PR Causality、Acceptance Criteria、Reproductionまたは決定的な静的根拠、Disposition）を伴って判断します。証拠不足の指摘をSeverityだけでBLOCKING扱いにしません。

受入条件・主要リスクの検証は、テスト実行とRequirementの検証を分けて [Verification Evidence Contract / Residual Risk Summary](docs/acceptance-verification.md#5-verification-evidence-contract--residual-risk-summary) に記録します。`VERIFIED / FAILED / NOT_VERIFIED / BLOCKED / SKIPPED`を区別し、既存のCI、Security、Review、Current State、Product Acceptanceを置き換えません。

レビュー指摘の修正ではrepo-local Skill `.agents/skills/pr-review-fix/` を利用できます。Codexへ `PR #XXのレビュー修正を進めて` と依頼すると、既存PRのhead branch固定、同一branchへの修正/push、SHA一致確認、CI/セキュリティチェック待機、更新後headへの再レビュー確認までを行い、Merge前で停止します。

Security PreflightとPRレビュー用shell helperはBash 5以上で実行します。macOS標準の`/bin/bash` 3.2では説明付きで非成功終了し、Security Preflightは`SECURITY_UNAVAILABLE`を返します。使用するBashのパスを確認し、例えばApple SiliconのHomebrew版なら `BASH5=/opt/homebrew/bin/bash`、`"$BASH5" --version` で確認してから `"$BASH5" .agents/skills/pr-review-fix/scripts/prepare-pr.sh <PR番号>` や `"$BASH5" scripts/security-preflight.sh .` を実行してください。スクリプトはBashをインストールしたりPATHを書き換えたりしません。

詳細は [`docs/nine-standard-ai-development-flow.md`](docs/nine-standard-ai-development-flow.md) を参照してください。

新規Web/UI案件では、UI設計前に [`docs/architecture/framework-decision.md`](docs/architecture/framework-decision.md) を確認し、結果をPlan Reviewへ引き継ぎます。`NEEDS_DECISION` の間はFramework依存のIssue化・実装を停止し、CLIや文書のみの変更は理由付きで `NOT_APPLICABLE` とします。

UIを持つ案件は、UI Level（`NONE / UTILITY / PRODUCT`）を宣言し、PRODUCTでは [`docs/product-ui-standard.md`](docs/product-ui-standard.md) と [`templates/app/docs/design.md`](templates/app/docs/design.md) を利用します。UI Levelが分類不能な場合は `NEEDS_DECISION` として、AIが重要なUX判断を推測で確定しないようにします。

テンプレートから生成したプロジェクトは、[`templates/verification/verify.sh`](templates/verification/verify.sh) を `scripts/verify.sh` として配置し、ローカル・Agent・GitHub Actionsで同じ標準検証入口を使用します。検証は lint → type check → test → build の順に進み、対象外工程は理由付きで明示され、失敗時は後続工程へ進みません。

自作アプリには、[`templates/app`](templates/app) の `bin/setup` / `bin/doctor` 雛形を配置します。setupは冪等にアプリ固有依存と永続データ領域を準備し、doctorは設定・依存・port・必要時のhealth endpointを検査します。

変更のRisk Tier（`LOW / MEDIUM / HIGH`）に応じて説明量と追加検証を調整します。[Adaptive Development Flow](docs/adaptive-development-flow.md) に判定条件と記入例をまとめています。標準検証・CI・Security・Codex Review・Human Merge判断・適用対象Acceptanceは維持します。

## 主要ファイル

- `AGENTS.md` — AIエージェント共通ルール・Codex Code Reviewルール
- `docs/nine-standard-ai-development-flow.md` — 標準開発フロー
- `docs/product-ui-standard.md` — Nine PRODUCT UI Standard v1
- `docs/architecture/framework-decision.md` — 要件からFrameworkまでの選定順序と判定を定める正本
- `docs/plan-authoring.md` — 会話から計画書を書く手順（READMEには手順全文を置かない）
- `docs/plan-review-gate.md` — 計画書の実装前Plan Review正本文書
- `docs/ai-execution-state.md` — schema v3のCurrent State契約と読み取り専用GitHub観測の利用手順
- `docs/instruction-architecture-inventory.md` — AGENTS / Skills / docs / CI / Issue / configの配置判断とread-only smoke test
- `scripts/collect-github-state.py` — Issue / PR / head SHA / workflow / reviewをJSONへ読み取り専用で収集する補助script
- `docs/deployment-release-design.md` — Deployment as Code・Release / Production設計標準
- `.github/ISSUE_TEMPLATE/parent-issue.md` — 親Issueテンプレート
- `.github/ISSUE_TEMPLATE/child-issue.md` — 子Issueテンプレート
- `templates/app/docs/design.md` — PRODUCT案件のDesign Source of Truth雛形
- `templates/review-comment-auto-triage` — Review Comment Auto-TriageのShadow Mode PoC雛形
- `templates/app/docs/framework-decision.md` — 案件ごとのFramework選定記録雛形
- `templates/planning/web-todo-app-plan.sample.md` — Web Todoアプリの計画書記入例（学習用。Nineが特定Frameworkを標準化した例ではない）
- `.github/pull_request_template.md` — PRテンプレート
- `.agents/skills/pr-review-fix/SKILL.md` — 既存PRのレビュー修正Skill

## 基本原則

- AI生成文書はDecision First、Non-goals、Minimum Documentationを共通原則とし、既存Gateの必須情報を保ったまま重複と不要な定型章を削る
- 計画書はIssue化前にPlan Review Gateで実装可能性を確認する
- ChatGPTは考える
- GitHubは仕事を管理する
- Codexは実装する
- GitHub Actionsは同じ標準検証入口を機械的に実行する
- Codex Code ReviewはPR差分をレビューする（レビュー専用）
- PR修正は既存PRのhead branchへ反映する
- PRを品質の関門にする
- 子Issue品質はMUSTを先に確認し、SHOULDと補助Scoreだけでは停止しない
- テンプレートは今回値を記入し、停止条件・安全境界・検収・レビュー収束の詳細は正本文書を参照する
- 人間が仕様とマージを決める
