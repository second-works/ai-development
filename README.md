# ai-development

Nine標準のIssue生成とCodex実装に使うテンプレートです。ChatGPTで合意した計画をGitHub Issueへ変換し、CodexがIssue単位で実装・検証・PR作成を進めます。

## はじめに

新しいprojectへの配置は [template-guide](docs/template-guide.md#2-新規プロジェクト開始時の使い方) に従います。AGENTSだけをコピーせず、参照するdocs・Skills・標準検証入口も配置してください。既存projectへ一括移行を強制せず、対象projectのルールと依存に合わせて採用します。

子IssueはGoal / Context / Scope・Boundaries / Non-goals / Done / Verification / Dependenciesの7項目を中心に、1子Issue = 1 PRへ分けます。テンプレートは今回値を記入し、非該当のFramework / UI / Harness / Stateの空欄は作りません。子Issue品質はMUSTを先に確認し、不足・重要未決・依存不明は登録と実装を停止します。

## 標準フロー

1. ChatGPTで要件整理・計画書作成（手順は [`docs/plan-authoring.md`](docs/plan-authoring.md)）
2. [plan-to-issues](.agents/skills/plan-to-issues/SKILL.md) が適用条件・Plan Review・6 MUSTを確認し、対象repoへIssueを登録する。生成だけの依頼では実装を始めない。
3. CodexがIssueのScope / Done / Verificationと依存を読み、範囲内を実装する。
4. 標準検証を実行する。生成projectは `./scripts/verify.sh`（lint → type check → test → build）、このrepoはBash 5で全 `tests/*/run-samples.sh`。対象外工程は理由を明示し、失敗・全skipを成功にしない。
5. Pre-PR Review（self-review）を行い、必要修正 → 再verify → 重大問題なしを確認する。`/review`は利用可能な手段の一つ。重大問題・検証不能時はcommit・PR作成・レビュー依頼へ進まず停止する。
6. PR作成後、現headのGitHub Actions CIとSecurityを別々に確認する。SECURITY_FAILEDは停止、SECURITY_UNAVAILABLEは人間判断なしに通過させない。
7. Codex Code Reviewを実施する。Automatic reviewsが利用できなければ `@codex review` を依頼する。通常のコメント対応はCodexが根拠・差分因果・受入条件を直接確認し、同じPR branchで修正する。
8. headが変わったら、同じ更新SHAのlocal / CI / Security / Codex Reviewを確認する。P0 / P1 / BLOCKING P2は未解決で進めず、レビュー回数だけで停止しない。
9. 検証証拠と未解決指摘を照合して、人間が最終Mergeを判断する。Deployと実利用検収は該当案件の別工程として確認する。

レビューの判定・P2四分類・Review Evidence Contractは [レビュー正本](docs/code-review-contract.md) を参照します。`pr-review-fix` とhelperは明示利用時の手動資産として保持し、通常対応では自動起動しません。`@codex address that feedback` は標準手順として使用しません。

## 条件付き参照と安全境界

[最小契約の条件表](docs/minimal-development-contract.md#条件付き参照)から、該当する正本だけを参照します。詳細手順をIssueやREADMEへ複製しません。

- 計画の重要未決は [Plan Review Gate](docs/plan-review-gate.md) でNEEDS_DECISIONとして停止します。
- 新規Web/UIや技術構成の変更は [Framework Decision](docs/architecture/framework-decision.md) を先に確認します。PRODUCT UIは [UI標準](docs/product-ui-standard.md) と案件 [design.md雛形](templates/app/docs/design.md) を使い、重要UXを推測で埋めません。
- Risk Tier（LOW / MEDIUM / HIGH）の理由と影響は [Adaptive Development Flow](docs/adaptive-development-flow.md) に従い記録します。Tierで標準検証・CI・Security・Review・承認を免除しません。
- 情報読取・外部送信は [AI Agent Security Boundary](docs/ai-agent-security-boundary.md) の情報分類・宛先・権限・承認を確認します。Secretsをcommit・Issue・logに出しません。未承認のProduction / Deploy / 破壊操作 / 認証・権限 / 課金 / 公開 / repo保護変更は停止します。
- 検証変更は [test-design](docs/test-design.md) の責務と保証先を確認し、代替成功前に旧保証を消しません。Security/Reviewの実効的回帰は保持します。
- Deployは [Release設計](docs/deployment-release-design.md)、検収は [Acceptance / Verification Evidence](docs/acceptance-verification.md) に従います。Merge成功だけでProduct Acceptedにせず、未実施と残るリスクを記録します。

Security Preflightと通常PRレビュー用shell helperの手動実行にはBash 5以上が必要です。macOS標準Bash 3.2は早期停止します。例: `/opt/homebrew/bin/bash scripts/security-preflight.sh .`。詳しい配置・環境手順はguideを参照してください。

標準の詳細は [Nine開発フロー](docs/nine-standard-ai-development-flow.md)、簡素化の検証と移行判断は [受入記録](docs/simplification-acceptance.md) を参照してください。
