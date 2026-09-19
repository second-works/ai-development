# Instruction Architecture Inventory

## Decision First

Issue #121では、既存の機能・Safety Gate・検証責務を移動または削除せず、Instructionの配置判断を先に記録する。

常時必要な停止条件と判断入口は `AGENTS.md` に残し、詳細仕様は `docs/`、反復手順は `.agents/skills/`、決定的な判定は `scripts/`・`tests/`・CI、入力欄はIssue / PR templateへ分ける。

実際の移動・統合・削除は、この台帳の判断をレビューした後に、影響範囲ごとの子Issueへ分割する。

## Scope and classification

| 分類 | 意味 | 主な配置 |
| --- | --- | --- |
| `RESIDENT` | すべての作業で最初に必要な禁止事項、停止条件、基本境界 | `AGENTS.md` |
| `ENTRYPOINT` | 条件発生時に正本文書を取得する短い入口 | `AGENTS.md` → `docs/` |
| `CANONICAL_DETAIL` | 設計仕様、状態、判断基準、背景の正本 | `docs/` |
| `REPEATABLE_EXECUTION` | 特定作業を再現する手順とスクリプト | `.agents/skills/`, `templates/` |
| `MECHANICAL_CHECK` | 機械的に判定できる契約、テスト、CI | `scripts/`, `tests/`, `.github/workflows/` |
| `INPUT_CONTRACT` | Issue / PR作成時に埋める今回値 | `.github/ISSUE_TEMPLATE/`, `.github/pull_request_template.md` |
| `TOOL_OR_PROJECT_CONFIG` | Codexや個別プロジェクトの実行設定 | `.codex/`, `.cursor/`, 各プロジェクト |
| `ISSUE_ONLY` | 今回だけの要求、Acceptance、Design Decision | GitHub Issue / PR |

配置は排他的ではない。同じテーマが複数層に現れる場合は、`AGENTS.md`に短い適用条件、正本文書に詳細、templateに今回値、test/CIに機械判定を置く。

## Baseline and change boundary

- 基準: `main` の `1f48747`（2026-09-20取得）。
- 変更前の `AGENTS.md`: **47,136 bytes**。
- Issue #121の実装では、まずこの台帳とread-only smoke testを追加する。
- 既存ルールの意味を変える移動・削除・統合、Safety / Security / Review / Acceptance / Human Merge条件の弱体化は行わない。
- `AGENTS.md`変更後のサイズは、同じcheckoutで `wc -c AGENTS.md` を再実行して記録する。

## AGENTS.md section inventory

| `AGENTS.md` section | 判定 | 正本または参照先 | 今回の扱い / 判断理由 |
| --- | --- | --- | --- |
| `Purpose` | `RESIDENT` | `docs/instruction-architecture-inventory.md` | このリポジトリと配置台帳の入口。短いまま残す。 |
| `Core Rules` | `RESIDENT` | Issue / PR rule、各正本文書 | すべての作業で必要な基本禁止事項だけを常駐させる。詳細分離は子Issue候補。 |
| `AI生成ドキュメント原則` | `RESIDENT` | Issue / PR template | 文書生成時の常時判断。定型の重複は増やさない。 |
| `Adaptive Development Flow / Risk Tier` | `ENTRYPOINT` | `docs/adaptive-development-flow.md` | 判定詳細は正本文書へ。AGENTSにはHIGH停止条件を残す。 |
| `Design / State Modeling` | `RESIDENT` | 各案件の型・schema・信頼境界 | 言語横断の設計原則で、現時点の専用正本がないため残す。専用文書化は子Issue候補。 |
| `Structured Current State` | `ENTRYPOINT` | `docs/ai-execution-state.md` | schema、enum、遷移は正本文書へ委譲する。 |
| `GitHub上の言語` | `RESIDENT` | README、Issue / PR template | 外部へ出す文章の基本方針であり、常時必要。 |
| `Plan Review Gate` | `ENTRYPOINT` | `docs/plan-review-gate.md` | 判定と出力形式は正本文書へ委譲する。 |
| `Framework Decision` | `ENTRYPOINT` | `docs/architecture/framework-decision.md` | UI / Runtime案件の発火条件と停止入口だけを残す。 |
| `AI / Codex Reference Contract` | `RESIDENT` | `docs/product-ui-standard.md`、案件 `docs/design.md` | PRODUCT UIの重要判断前に必要な参照順序。詳細は正本文書へ。 |
| `Child Issue Quality Gate` | `ENTRYPOINT` | `docs/issue-quality-check.md` | MUST / SHOULD / Scoreは正本文書へ委譲する。 |
| `Issue Selection` | `RESIDENT` | GitHub Issue | 依存と優先順位が不明なときの停止条件。 |
| `Issue / PR Rule` | `RESIDENT` | Issue / PR template | 作業単位と実装前確認の共通入口。 |
| `RAG Architecture Standard` | `ENTRYPOINT` | `docs/architecture/rag-guidelines.md` | RAG採用時だけ詳細を取得する。案件固有の `rag-design.md` は任意のプロジェクト成果物で、template本体の必須ファイルではない。 |
| `Test Design / Safe Test Deletion` | `ENTRYPOINT` | `docs/nine-standard-ai-development-flow.md`、各プロジェクトのtests | テスト変更時に必要な責務移行条件。専用正本化は子Issue候補。 |
| `Implementation Workflow` | `ENTRYPOINT` | `docs/nine-standard-ai-development-flow.md` | 手順全文を常駐させず、Issue単位の入口と停止条件を残す。 |
| `Standard Verification Gate` | `ENTRYPOINT` | `templates/verification/verify.sh`、`docs/template-guide.md` | template本体と生成先プロジェクトの境界を明示する。 |
| `Parent Issue Completion` | `ENTRYPOINT` | `docs/nine-standard-ai-development-flow.md` | 親Issue完了時だけ参照する。 |
| `GitHub Actions CI` | `ENTRYPOINT` | `.github/workflows/ci.yml`、`templates/github-actions/` | 実行コマンドはworkflow / templateを正本とする。 |
| `Code Review Rules` | `ENTRYPOINT` | `docs/nine-standard-ai-development-flow.md` | レビュー起動と探索範囲は短く保ち、手順詳細は正本文書へ。 |
| `Review Evidence Contract` | `CANONICAL_DETAIL` | `AGENTS.md`、PR template | 現在の唯一の正本。別文書化は責務重複を確認してから子Issue化する。 |
| `Rule Promotion` | `ENTRYPOINT` | `docs/nine-standard-ai-development-flow.md` | 反復指摘を機械判定へ昇格する入口。自動昇格はしない。 |
| `Harness Minimalism` | `ENTRYPOINT` | `docs/ai-development-harness-inventory.md` | 台帳と再評価条件は正本文書へ委譲する。 |
| `GitHub Guardrails` | `ENTRYPOINT` | `docs/github-repository-security-baseline.md` | Ruleset等の詳細はSecurity正本へ。 |
| `Dependabot` | `ENTRYPOINT` | `templates/dependabot/`、`docs/template-guide.md` | template選択と運用詳細を分離する。 |
| `Secrets` | `RESIDENT` | `docs/ai-agent-security-boundary.md` | 漏えい禁止と停止条件は常駐させる。詳細はSecurity正本へ。 |
| `AI Agent Security Boundary` | `ENTRYPOINT` | `docs/ai-agent-security-boundary.md` | 境界判定の詳細は正本文書へ委譲する。 |
| `CodeQL / Code Scanning` | `ENTRYPOINT` | `docs/github-repository-security-baseline.md`、`templates/github-actions/codeql.yml` | 利用可否とworkflowを参照する。 |
| `Security Preflight` | `ENTRYPOINT` | `templates/security/security-preflight.sh` | template本体と生成先 `scripts/security-preflight.sh` を区別する。 |
| `Full-System Security Audit` | `ENTRYPOINT` | `docs/deployment-release-design.md` | Release Candidate時だけ取得する。 |
| `Before PR` | `ENTRYPOINT` | `docs/template-guide.md`、PR template | 標準検証の実行入口を示し、工程詳細はtemplateへ委譲する。 |
| `PR Description` | `INPUT_CONTRACT` | `.github/pull_request_template.md` | PRの今回値を入力する欄。AGENTSには必須項目の境界だけを残す。 |
| `Prohibited Actions` | `RESIDENT` | `docs/ai-agent-security-boundary.md` | 常時適用の禁止事項と停止条件。 |
| `Human Decision Points` | `RESIDENT` | Issue / PR | AIが推測で決めてはいけない境界。 |
| `Standard Codex Instruction` | `ENTRYPOINT` | `README.md`、`docs/template-guide.md` | 実行依頼の例であり、常時ルールではない。詳細移動は子Issue候補。 |

本表は `AGENTS.md` の現行35セクションをすべて列挙する。`RESIDENT` とした項目でも、将来専用正本と参照テストが整えば短縮候補になる。

## Layer boundary

### `AGENTS.md`

AIが毎回最初に読む共通境界。Issueを仕様の基準にすること、範囲外変更・秘密情報・直接main変更の禁止、HIGHリスクや人間判断で停止すること、条件発生時の正本文書への参照だけを置く。

### `docs/`

設計原則、状態schema、Gate、Security、Acceptance、レビュー証跡など、条件発生時に取得する詳細仕様を置く。`AGENTS.md`と同じ詳細を全文複製しない。

### `.agents/skills/` and `templates/`

反復する特定作業の実行手順と、生成先へコピーする雛形を置く。Skillは適用範囲と停止条件を明記し、templateは生成先での配置先を明記する。

### `scripts/`, `tests/`, and `.github/workflows/`

機械的に判定できる検証を置く。文書の存在だけでなく、参照先、状態値、失敗時の停止、読み取り専用境界を契約テストで確認する。

### Issue / PR / project config

今回のAcceptance、Risk Tier、Design Decision、対象SHAはIssue / PRへ記録する。`.codex/config.toml` は現テンプレート本体に存在しないため、Codexのバージョンやhost依存の設定をこのIssueで新規固定しない。`.cursor/environment.json` はtool固有設定として扱う。

## Read-only smoke test

文書の存在確認だけでは、指示が適用されることの証拠にならない。Issue #121では、実装や外部書き込みを行わない次のread-only確認を定義し、`tests/instruction-architecture/run-samples.sh` で実施する。

1. **Source map**: 現在の `AGENTS.md`、`docs/`、`.agents/skills/`、`.github/`、`tests/` の役割を説明でき、主要な正本文書が存在する。
2. **Gate enumeration**: 任意のIssueに対して、実装前のRisk / Design Decision / Security Boundary、標準検証、CI / Security / Review、Human Mergeの入口を列挙できる。
3. **Scope**: repo-local Skillは対象ディレクトリと作業目的が一致した場合だけ適用され、全作業の常駐ルールへ昇格していない。
4. **Triggered retrieval**: Framework、Plan Review、Acceptance、Security、RAGなどの詳細は、発火条件と正本文書の対応をたどれる。
5. **Read-only boundary**: read-only確認ではbranch、commit、push、PR、Issueコメントを作成しない。確認前後のGit状態が一致する。
6. **Runtime evidence**: 利用可能なCodexの実機または公式仕様で確認できない `/status`、`/debug-config` 等のコマンドを、標準手順として固定しない。

このshell smoke testはCodex自身の全runtimeを再現するものではない。source map、参照経路、禁止された書き込みの不在、Git状態不変という決定可能な境界をCIで固定し、実機でしか確認できない適用結果は人間が読むIssue / PR証跡へ残す。

## Deferred decisions and follow-up boundary

- `AGENTS.md` の詳細を実際に `docs/` へ移す場合は、移動前後の参照経路、適用漏れ、サイズ差分、失敗時の停止を別PRで検証する。
- `Review Evidence Contract` の専用文書化は、PR templateと `AGENTS.md` の責務重複を確認してから判断する。
- `Design / State Modeling` と `Test Design / Safe Test Deletion` の専用正本化は、既存の標準フローとの重複を確認して子Issue化する。
- `docs/architecture/rag-design.md` はRAG採用プロジェクトの案件固有記録であり、template repositoryへ空ファイルを追加しない。
- Codex設定層のtemplate化は、対象host、version drift、適用スコープ、secret / network境界を確認できるDesign Decisionができるまで行わない。

## Verification record

- 変更前 `AGENTS.md`: 47,136 bytes（`main` `1f48747`）。
- 変更後 `AGENTS.md`: 47,438 bytes（`+302 bytes`）。
- 変更理由: Purposeに本台帳への参照と、常駐ルール・詳細仕様・反復手順・機械判定の境界を1段落追加した。
- 成功条件: 台帳の全セクション列挙、read-only smoke test、既存契約テスト、CI / Security / Review / Human Merge境界の維持。
