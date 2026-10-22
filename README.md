# ai-development

Nine標準のAI開発テンプレートです。Codex が計画を GitHub Issue にし、Claude Code が Issue 単位で実装からレビュー指摘への対応、マージ依頼まで進めます。マージと Issue の完了は人間が判断します。

標準の構成は、`templates/lightweight/` の軽量構成です（親 #192 で切り替え。試行の記録は [lightweight-trial](docs/lightweight-trial.md)）。このrepo自身も、同じ構成を `place.sh` で配置して使っています。

## はじめに

新しいprojectへの配置は [template-guide](docs/template-guide.md) の「最小AGENTSと参照先の配置」に従い、`templates/lightweight/place.sh` で行います。既存の設定を上書きせず、衝突があれば何も書かずに止まり、`--restore` で今回の差分だけを戻せます。詳しくは [templates/lightweight/README.md](templates/lightweight/README.md) を参照してください。

子Issueは Goal / Context / Scope・Boundaries / Non-goals / Done / Verification / Dependencies の7項目で、1子Issue = 1 PR に分けます。子Issue品質はMUSTを先に確認し、目的・範囲・完了判定・依存・安全境界が欠けていれば、登録と実装を止めます。

## 標準フロー

1. 合意した計画を、Codex が [plan-to-issues](.agents/skills/plan-to-issues/SKILL.md) の手順で親子Issueにする。未決事項があれば登録せずに止まり、生成だけの依頼では実装を始めない。
2. Claude Code が Issue の Scope / Done / Verification と依存を読み、[steward](.claude/skills/steward/SKILL.md) の手順で範囲内を実装する。
3. 標準検証を実行する（`./scripts/verify.sh`。このrepoでは全 `tests/*/run-samples.sh` を Bash 5 で実行する）。失敗・実行不能・全件skipは成功にしない。
4. Pre-PR Review（差分全体の自己レビュー）を行い、必要修正 → 再verify → 重大問題なしを確認する。重大問題・検証不能時はcommit・PR作成・レビュー依頼へ進まず停止する。
5. PR作成後、最終headで CI と Security を別々に確認する。結果を取得できなければ成功にせず、判断を求める。
6. 正式レビュー（Codex Review）を最終headで行う。Risk Tier が HIGH なら、別のセッションでもレビューする。指摘は根拠を確かめ、同じPRで直す。
7. headが変わったら、同じ新しいheadで検証・CI・Security・レビューを確かめ直す。`scripts/check-pr-head.sh <PR番号>` で照合できる。
8. 人間が最終Mergeを判断する。Deploy と実利用の検収は、該当する案件の別工程として確かめる。

## 参照用の資料

毎回読む必要はありません。Issue が指したとき、または該当する判断があるときに読みます。

- 計画とIssue: [Plan Review Gate](docs/plan-review-gate.md)、[Issue Quality Check](docs/issue-quality-check.md)、[計画書の作り方](docs/plan-authoring.md)、[親Issueの完了](docs/parent-issue-completion.md)
- Risk Tier: [Adaptive Development Flow](docs/adaptive-development-flow.md)
- UI と技術構成: [Framework Decision](docs/architecture/framework-decision.md)、[UI標準](docs/product-ui-standard.md)、案件の [design.md雛形](templates/app/docs/design.md)（`templates/app/docs/design.md`）
- Security と外部送信: [AI Agent Security Boundary](docs/ai-agent-security-boundary.md)、[GitHub Security Baseline](docs/github-repository-security-baseline.md)
- テストと設計: [test-design](docs/test-design.md)、[design-state-modeling](docs/design-state-modeling.md)
- Deploy と検収: [Release設計](docs/deployment-release-design.md)、[Acceptance / Verification Evidence](docs/acceptance-verification.md)
- レビュー: [レビュー正本](docs/code-review-contract.md)、FOLLOW-UP の記録先 [review-followups](docs/review-followups.md)
- 旧標準の詳細（参照のみ）: [Nine開発フロー](docs/nine-standard-ai-development-flow.md)、[最小契約](docs/minimal-development-contract.md)（テストが確かめる節だけを残した抜粋）
- 配置の手順と技術構成別の設定: [template-guide](docs/template-guide.md)

Security Preflight の手動実行には Bash 5 以上が必要です（macOS 標準の Bash 3.2 は早期に止まります）。例: `/opt/homebrew/bin/bash scripts/security-preflight.sh .`
