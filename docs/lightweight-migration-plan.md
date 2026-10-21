# 軽量化の削減範囲と最小責務

**Decision: 標準から外す対象は「通常フロー外のレビュー補助一式（pr-review-fix・JEV・Local Judge）」「自己管理の台帳・履歴資料」「巨大な必読flow」の3群とし、残す結果は親 #192 の11項目で固定する。Slack通知とFOLLOW-UP台帳は現役の保証なので、外すなら代替を先に成立させる移行対象とする。本書は提案であり、削除・設定変更は行わない。**

親 [#192](https://github.com/second-works/ai-development/issues/192)、本Issue [#193](https://github.com/second-works/ai-development/issues/193)。後続 #194〜#197 は本書の対象一覧と人間確認を前提に進める。過去のKB値（[受入記録](simplification-acceptance.md)、[棚卸し](simplification-inventory.md)）は再利用せず、以下で取り直した。

## 1. 基準と測定方法

- 基準: main `b2715a76c5ab3715ccce88167c23ce12c81e85b1`（2026-10-21T07:34Z、`git rev-parse origin/main` で確認）。
- サイズはUTF-8のbytesでありtoken数ではない。追跡ファイル（`git ls-files`）だけを数え、未追跡のローカル計画書・logsは含めない。
- 参照関係は、各追跡ファイル本文に出現するrepo内path・相対リンク・directory参照を機械的に照合した。文字列一致による推定のため、外部repo・個人設定・実行時の動的参照は「未確認」とする。
- 「必読」はAGENTS.mdが「必ず読む」「読む」と指定する入口だけを数えた。条件付き参照は別欄にした。

## 2. 変更前の実測

| 項目 | 実測 | 内訳・注記 |
| --- | --- | --- |
| 追跡ファイル全体 | 143 files / 1,011,056 B | tests 61 files / 237,934 B を含む |
| 配布量（[template-guide](template-guide.md#最小agentsと参照先の配置)の手動copy） | 71 files / 704,858 B | `AGENTS.md`、`docs/`全体、`.agents/skills/`全体、`templates/`全体、Issue/PR template、`ci.yml` |
| 実装時の必読 | 7 files / 97,795 B / 1,246行 | AGENTS 5,325、標準flow 54,051、レビュー正本 14,336、Security境界 11,267、Tier 7,876、test-design 2,893、design-state 2,047。git pushを伴うため境界文書は毎回該当 |
| 実装時の条件付き必読 | +40,232 B | 検証変更・Security・repo設定等で `minimal-development-contract.md` の条件表 |
| 計画時の必読 | 8 files / 88,486 B | AGENTS、plan-to-issues 8,805、最小契約 40,232、Plan Review 14,899、Issue品質 5,787、Tier、親子template |
| workflow | 6本 / 27,664 B | 標準: `ci.yml`、`security.yml`。手動・通知: `jev-triage`、`decision-shadow`、`local-judge-smoke`、`slack-failure-alert` |
| 検査入口 | 28 suites、CI 29 step | step 1はshell構文、28は各 `tests/*/run-samples.sh` |
| 外す候補A: レビュー補助一式 | 31 files / 269,034 B | pr-review-fix 7 files 86,453、auto-triage 13 files 73,364、手動workflow 3本、専用test 4 suites。Slack通知（1 file / 1,986 B）は現役のため集計に含めない（4・5章） |
| 外す候補B: 自己管理docs | 5 files / 135,617 B | harness台帳 63,844、instruction台帳 29,249、棚卸し 31,962、受入記録 8,392、field lessons 2,170。harness台帳は検証変更時に参照されるため、5章の前提を満たしてから外す。review-followups（4,951 B）は現役の記録先のため集計に含めない（5章） |

## 3. 参照関係と配布経路

- AGENTSの直接参照は13件（docs 11、Skill 2）。READMEは16件。pr-review-fixはAGENTS・README・[レビュー正本](code-review-contract.md)で「通常経路では起動しない手動資産」と既に定義済み（#168）。
- それでも配布に残る理由は、template-guideの `cp -R docs .agents/skills templates` がdirectoryごと運ぶため。通常フローから外れた資産も全件配布される。
- 配布元 `ai-project-bootstrap`（ローカルcheckout `97662b4`、2026-10-10）にai-developmentへの参照はない。現行の配布経路はtemplate-guideの手動copyだけ。remoteの最新状態は未確認。
- 利用側の観測（ローカルcheckout、読取のみ）: hermes-self-improvement `10419e1` は3 Skillとauto-triageを配置済み。FitnessAI `9660dc5` は `.claude/skills/steward`（9,330 B）と標準flow、auto-triageを持つ。他repoは未確認。
- AGENTS/READMEとIssue/PR templateから参照をたどると、非test 82 filesはすべて到達する。棚卸し・受入記録（`simplification-*`）を経由しないと到達しないもの: `docs/field-validation-lessons.md`、`SECURITY.md`、`templates/app/README.md`、`templates/app/.env.example`（棚卸し・受入記録自身はREADMEからの参照だけ）。後3件はGitHub標準または生成app雛形で、未使用とは判定しない。

## 4. 残す結果と対応表

| 現行の責務 | 区分 | 移す先 / 理由 |
| --- | --- | --- |
| Issue範囲遵守、1子Issue=1 PR、依存順 | 残す | AGENTS |
| main直接push・force push禁止、他者の変更保護 | 残す | AGENTS。main未保護（#163）のため文章ルールが唯一の保証 |
| 標準検証とself-review、失敗・不能・全skipで停止 | 残す | AGENTS。手順はsteward |
| テストを無効化しない、削除前に保証先確認 | 残す | AGENTS 1行 + [test-design](test-design.md) |
| 同一full HEADのlocal/CI/Security/正式レビュー、旧head失効 | 残す | AGENTS。照合手順はsteward |
| 重大指摘の解消、Security未取得を成功扱いしない | 残す | AGENTS |
| Secret保護、外部送信の境界 | 残す | AGENTS。詳細は[境界文書](ai-agent-security-boundary.md)を外部送信の判断時だけ読む |
| 重要操作の人間承認、実装と検収の区別、人間Merge | 残す | AGENTS |
| Issue選択・実装・PR前・PR記載の工程（標準flow後半） | 短い手順へ統合 | steward。標準flow 54 KBの必読を解除 |
| 計画・Plan Review・Issue品質の判断 | 短い手順へ統合 | plan-to-issues。Score・固定出力は外す |
| レビュー指摘の根拠確認・同じbranch修正・再検証 | 短い手順へ統合 | stewardに数行。pr-review-fixの分類表は移さない |
| Risk Tierの3段階記録、Current State全文、Harness欄 | 短い手順へ統合 | 該当Issueに重要リスクだけ直接書く。全案件の常設欄は外す |
| main宛push・force push・Secret混入の早期検出 | ガードへ置換 | 既存Security Preflight + Claude Codeのdeny/フック候補（#194）。文字列一致で完全保証とは書かない |
| 現head・CI/Security分離のhelper判定 | ガードへ置換 | Security workflowとstewardの確認手順。helper専用の判定は持たない |
| JEV・Decision Shadow・Local Judge | 理由を示して廃止 | 標準配布・標準CIから外す。通常フローで未使用、Secret・外部送信面を持ち、保守費が大きい |
| CI・Security失敗時のSlack通知 | 残す（移行は要確認） | Template CI / Securityの`failure`・`timed_out`で`workflow_run`が自動起動する現役の保証。外すなら代替の失敗通知か、通知がなくなる影響の人間承認を先に得る |
| FOLLOW-UP中央台帳への登録 | 短い手順へ統合（移行は要確認） | [レビュー正本](code-review-contract.md)が更新headの`FOLLOW-UP`かつ`ISSUE`に台帳登録commitを求め、PR templateも参照する現役手順。新しい記録先と契約・templateの切替を先に成立させる |
| 台帳・棚卸し・受入記録の更新義務（FOLLOW-UP台帳を除く）、文言一致だけの検査 | 理由を示して廃止 | 自己管理のための資産。履歴は復元元SHAを記録してmainから外す |
| template-change-evaluatorの常時routing | 理由を示して廃止 | 必読から外す。必要時の任意Skillとして残すかは#197で判断 |

## 5. 削減path一覧（候補）

実施は#197。各pathは「通常フローでの使用」を判定し、外部repoや個人環境での使用は未確認として残す。

| path | 通常フロー | 現在の被参照 / 保証 | 前提 |
| --- | --- | --- | --- |
| `.agents/skills/pr-review-fix/`（SKILL + scripts 6） | 未使用 | template-guide配布、`ci.yml`構文行、tests 8 suites、workflow 2本 | 6章の保証先を先に成立 |
| `templates/review-comment-auto-triage/`（13 files） | 未使用 | `triage-with-providers.py`、`tests/local-judge`、`tests/review-comment-auto-triage` | hermes・FitnessAIは配置済み。既配布分の扱いは未確認 |
| `.github/workflows/jev-triage.yml`、`decision-shadow.yml`、`local-judge-smoke.yml` | 未使用（`workflow_dispatch`のみ） | `tests/jev-triage-workflow`、`tests/local-judge` | Secret登録の削除は人間判断で別操作 |
| `.github/workflows/slack-failure-alert.yml` | 使用中（標準gate失敗時に自動起動） | `workflow_run`でTemplate CI / Security / JEV Triageの失敗を通知 | 削除候補にしない。外すなら代替の失敗通知か人間の明示承認を先に得る。merge済みのPR #199はこのjobをhosted runnerに残したため、hosted runnerが止まっている間は通知も届かない |
| `tests/pr-review-fix-jev/`、`tests/jev-triage-workflow/`、`tests/local-judge/`、`tests/review-comment-auto-triage/` | 対象資産の専用検査 | `ci.yml`の4 step | 対象資産と同じPRで外す。`test-wait-codex-review.py`の判定は6章 |
| `docs/ai-development-harness-inventory.md` | 条件付き（検証変更時） | child/PR template、最小契約、tests 9 suites | 安全項目の所在をtest-design等へ移してから |
| `docs/instruction-architecture-inventory.md`、`docs/simplification-inventory.md`、`docs/simplification-acceptance.md` | 履歴 | AGENTS末尾の配置履歴参照、README | 復元元SHAを記録 |
| `docs/field-validation-lessons.md` | 未使用 | 棚卸しからだけ | 復元元SHAを記録 |
| `docs/review-followups.md` | 使用中（通常レビューのFOLLOW-UP記録先） | レビュー正本の台帳登録手順、PR template、`tests/pr-review-followups` | 削除候補にしない。新しい記録先を決め、レビュー正本・PR template・testを切り替えて成功させてから外す |
| `docs/nine-standard-ai-development-flow.md` | 必読（54 KB） | AGENTS、tests 15 suites | 必読を解除し、生きた節だけstewardとREADMEへ。単純なarchive移動にしない |
| `docs/minimal-development-contract.md` | 条件表（40 KB） | AGENTS、plan-to-issues、tests 6 suites | 条件表だけを短く残すか統合するかは#194で判断 |
| 文言一致だけの文書契約test（`document-concision`、`template-simplification`、`issue-quality`、`current-state`、`adaptive-development-flow`、`template-change-evaluator`、`plan-review-gate`、`issue-template-ui`、`pr-review-followups`） | 文書の固定文言を検査 | `ci.yml` | 責務ごとに判定。安全文言は残すか置換。#168の分類（[28入口](simplification-inventory.md#28テスト入口の責務と削減判断)）を起点に再判定 |

残す実行回帰: `verification`、`app-template`、`security-preflight`、`github-state`、`html-status-report`、`cloud-agent-environment`、`instruction-architecture`のread-only部分。`scripts/collect-github-state.py`等はstewardで使わなければ配布から外す候補だが、未確認。

## 6. pr-review-fixの扱い

外す範囲: Skill本体と6 scripts、template-guideの配布、`ci.yml`の構文行・`pr-review-fix-jev` step、関連文書contractのSkill参照。削除はしない（#197で人間確認後）。

stewardへ移植しないもの: P2四分類表と定型出力、3ラウンド制限、Finding ID集計、JEV / Local Judge / provider比較、helperの待機ロジック全体。FOLLOW-UP中央台帳への登録はpr-review-fixではなくレビュー正本の現役手順なので、4章のとおり記録先を切り替えるまで維持する。

| 現在の検査 | 守っている結果 | 外した後の保証先 |
| --- | --- | --- |
| `test-wait-codex-review.py`（P0/P1、CHANGES_REQUESTED、DISMISSED、未解決thread） | 重大指摘・要修正状態を成功扱いしない | stewardの確認手順と人間Merge。**機械判定は失われる**ため、#194で代替の要否を判断する |
| `security-preflight`のwait-checks利用 | CIとSecurityを別判定、UNAVAILABLE非通過 | Security workflowの独立check名と、stewardでのcheck別確認。Preflight本体のtestは残す |
| `test-bash-version-guard.py`の4 helper行 | helperがBash 3.2で外部コマンドを走らせない | helper削除で対象消滅。Preflight本体のguard検査は残す |
| `verify-pr-head.sh`、`instruction-architecture`の配布確認 | push SHAとGitHub head SHAの一致、配布先にhelperがある | stewardでfull SHA照合を1手順として持つ。配布確認は新しい配布一覧へ更新 |
| `agent-security-boundary`、`review-evidence`、`current-state`、`pr-review-followups`のSkill marker | Skill本文に境界・証拠・状態の記述がある | Skill除去に合わせてmarker対象をstewardへ移すか削除。安全文言はAGENTSとstewardで保持 |

## 7. 他Issue・PRとの重複

| 対象 | 状態（2026-10-21取得） | 関係と扱い |
| --- | --- | --- |
| [#163](https://github.com/second-works/ai-development/issues/163) | open。main未保護、Ruleset/保護APIは403 | 保護がないため、push禁止等の文章ルールとガードを削らない。本計画で設定しない |
| [#188](https://github.com/second-works/ai-development/issues/188) | open。検討Issue | 候補pathに `pr-review-fix/` を含む。pr-review-fixを外すと、その観点はSecurity templates側だけに絞られる。#188を勝手にcloseしない |
| [#189](https://github.com/second-works/ai-development/issues/189) / [PR #190](https://github.com/second-works/ai-development/pull/190) | open。AGENTSへCursor Cloud節を追加 | #194/#197のAGENTS短縮と同じファイルを変える。#194開始前にmergeか保留かの人間判断が必要 |
| [#191](https://github.com/second-works/ai-development/issues/191) | closed。[PR #199](https://github.com/second-works/ai-development/pull/199)をmerge済み（`75c40cb`、2026-10-21） | CIとSecurityは所有者のMacのself-hosted runnerで実行する（[運用](ci-self-hosted-runner.md)）。後続は移行を前提にしてよい。残る未決: Slack通知はhosted runnerのままで届かない、hosted runnerへ戻す条件、runnerの専用ユーザー化、fork PRの振り分けの実地確認 |
| [#168](https://github.com/second-works/ai-development/issues/168) | closed | pr-review-fixの任意化は完了済み。重複実装しない |

## 8. 改訂計画の要点

- 役割: Codexは計画・Issue化（plan-to-issues）、Claude Codeは実装〜レビュー指摘対応〜マージ依頼（steward）、Codex Reviewは正式レビュー、人間は重要判断・検収・Merge。Codex用実装Skillの維持は必須にしない。
- 5段階（各1 PR、直列）: 1 本書で範囲確定（#193）→ 2 隔離環境で軽量候補を成立（#194）→ 3 bootstrapで非破壊配置と復旧（#195）→ 4 限定試行で負担と手戻りを評価（#196）→ 5 標準切替と旧資産削減（#197）。
- 停止条件: 仕様矛盾、重要未決、依存未完了、検証の失敗・不能・全skip、Security未取得、旧head、保護操作・設定適用・削除の未承認。先にAGENTSだけ削って後で補う順序は取らない。
- 対象外: 本番変更、個人設定の書換え、既存projectの一括移行、自動Merge、新しい外部サービス・管理基盤・Gate、FitnessAIへの移行。
- 指標: 読んだ資料と量、配布・必読・workflow・検査入口の前後差、人間の確認回数と時間、手戻り、作業時間と待ち時間、負例での停止。AGENTS 40行/4 KB程度と読む量1/5以下は努力目標。取得できない値は不明とする。

## 9. 人間の確認状態

| 判断事項 | 状態 |
| --- | --- |
| 5章の削減対象と6章の保証先 | **未確認**。本PRのレビューで確認を受ける |
| 限定試行先（Codex計画の候補はhermes-self-improvement） | **未確認** |
| PR #190を#194より先にmergeするか | **未確認** |
| 既配布済みrepoのauto-triage等の扱い | **未確認**。本計画の範囲外として各repoで判断 |
