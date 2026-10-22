# 軽量構成の限定試行

**状態: 試行済み（#196）。hermes-self-improvement に軽量構成を配置し、1件の Issue を Claude Code で実装してマージまで確認した。判定は「切替提案へ進める（条件付き）」（6章）。1件の結果なので、安全性や速度を一般化しない。**

親 [#192](https://github.com/second-works/ai-development/issues/192)、本Issue [#196](https://github.com/second-works/ai-development/issues/196)。配置の仕組みは [#195](https://github.com/second-works/ai-development/issues/195)（PR #201）の `templates/lightweight/place.sh`。

## 1. 試行の対象

| 項目 | 値 |
| --- | --- |
| 試行先repo | second-works/hermes-self-improvement（`.hermes` 本体ではない）。所有者が承認（2026-10-22） |
| 元SHA（復旧元） | main `3bd42e30a7c088c22a74c455c712a94fbfdb7f2b`（PR #17 の merge 後。準備時点の `10419e1` から更新） |
| 配置元 | ai-development `41202b8bea491188aac53436075e5147cf1d43b5`（#203、#205 の修正を含む。最初は `19426a2`） |
| 配置した場所 | main から切った別の worktree。ローカルの checkout は、別の作業中（`issue-7-isolated-skill-delegation`、ステージ済み47件）のため使っていない |
| 配置PR | hermes [PR #22](https://github.com/second-works/hermes-self-improvement/pull/22)（merge `940d2b5`） |
| 実装したIssue | hermes [#21](https://github.com/second-works/hermes-self-improvement/issues/21)「worklog の `--output` が途中で失敗したとき、半端な出力を残さない」（Risk Tier MEDIUM。所有者が3案から選んだ） |
| 実装PR | hermes [PR #23](https://github.com/second-works/hermes-self-improvement/pull/23)（merge `fa6f354`、#21 は close） |
| 運用方針 | 試行後も hermes-self-improvement は軽量版で運用する（所有者の決定） |
| 担当 | Claude Code（配置・実装・レビュー指摘対応）、Codex Review（正式レビュー）、別セッションの Claude Code（HIGH の独立レビュー）、人間（判断・マージ） |

## 2. 変更した設定

元SHAの複製に対する dry-run では、旧標準版の6ファイルと衝突して止まった（何も書かない）。所有者の決定（2026-10-22）で次のとおり置き換えた。

1. `.agents/skills/plan-to-issues/SKILL.md` と、Issue / PR テンプレート3つを軽量版に置き換えた（既存ファイルを先に外してから配置）。
2. AGENTS.md は、旧標準の汎用の節（必読指定を含む）を外し、hermes 固有の節を残して、軽量ブロックを足した。
3. `scripts/verify.sh` と `scripts/security-preflight.sh` は、project 固有の調整があるので `--keep` で残した。
4. 作成: `CLAUDE.md`、`.claude/settings.json`、`.claude/hooks/guard-git-push.sh`、`.claude/skills/steward/SKILL.md`、`scripts/check-pr-head.sh`、`.ai/lightweight-placement.tsv`、`.github/pr-gate-checks`（`ci`、`Security Preflight`、`Analyze (python)`）。
5. `pr-review-fix` と `template-change-evaluator` の Skill は、AGENTS.md から参照しなくなったが、hermes のテストが参照しているので残した（外すかどうかは #197）。

## 3. 比較

比べる相手は、同じ worklog CLI を入れた PR #17（旧標準の構成、#16）。規模が違う（PR #17 は新機能で +1,879 行、#23 は既存関数の修正で、変更部分は +100 行ほど）ので、件数と時間は参考値。

| 指標 | 旧標準（PR #17） | 軽量構成（PR #22 / #23） | 注記 |
| --- | --- | --- | --- |
| 実装時の必読 | 98,809 B（AGENTS 6,339、標準flow 54,051、レビュー正本 14,336、Security境界 11,267、Tier 7,876、test-design 2,893、design-state 2,047） | 8,909 B（AGENTS 3,885、CLAUDE 568、steward 4,456） | AGENTS.md が必読と指定する量。約 1/11 |
| 実際に読んだ資料（#21 の実装） | 不明（記録なし） | 軽量の AGENTS・CLAUDE・steward・child template、`report.py` の `write_output`、関連テスト、`docs/worklog-candidates.md` の該当節 | このセッションは ai-development で起動しており、hermes の CLAUDE.md とフックは自動では読み込まれていない（手で読んだ） |
| 配布量 | `.agents` 120 KB、`docs` 644 KB（49 files） | 作成・置き換え 11 files（約 29 KB） | 旧資産の削除は #197 |
| 実装の作業時間 | 不明 | #21 の着手から push まで約 3分（01:23 → 01:26 UTC）、レビュー指摘の修正 2回（01:43、03:56） | 自動の検証を含む |
| 作成から merge まで | 約 4.4日（10-17 → 10-22。人間の判断待ちを含む） | #22: 約 2.5時間（01:22 → 03:50 UTC）、#23: 約 2.6時間（01:26 → 04:02 UTC） | 下の手戻りと待ちを含む |
| 正式レビューの指摘 | Codex のインライン指摘 5件、レビュー 3回 | #22: 2件、#23: 2件 | すべて同じPRで修正し、スレッドを解決した |
| 人間の確認 | 不明 | 6回: 試行先、置き換えの範囲、実装する Issue、テンプレート側で直す方針、使用量の上限の後の再開、hermes の merge 承認 | すべて依頼元セッション経由。かかった時間は不明 |
| 手戻り | 不明 | 2回（4章） | どちらもテンプレートの不具合 |
| CI・レビューの待ち | 不明 | Codex Review が running のまま止まり、再依頼が2回必要だった（約45分ずつ）。使用量の上限で約45分止まった | 待ち時間の多くは Codex の停止 |

## 4. 手戻り

試行で見つかったテンプレートの不具合は、所有者の判断で、試行先のテストやファイルを緩めずにテンプレート側で直した。

1. **管理ブロックの印に、配置先にない path があった**（#203、PR #204）。印に `templates/lightweight/place.sh` と書いていたため、hermes の `test_agent_references_are_present`（AGENTS.md の path が実在するか）が失敗した。印を path のない文言にし、`place.sh --restore` で戻してから配置し直した。`--restore` は、試行先で実際に使って動いた。
2. **最終headの照合が、hermes の check と合わなかった**（#205、PR #206）。既定の check 名が ai-development のもので、hermes の Security Preflight は check run ではなく commit status で報告される。独立レビューと Codex Review が指摘した。必須 check を base ブランチの `.github/pr-gate-checks` から読み、check run と commit status の両方を照合するようにした。PR #206 では、照合を緩めるおそれのある経路について、Codex（3件）と独立レビュー（2件）から計 5件の指摘があり、すべて直した。

## 5. 確かめたこと

- 正常系: 配置後の hermes の `./scripts/verify.sh`（test 30件）、Security Preflight（SECURITY_PASSED）、CI、CodeQL が成功した。
- フック: 配置した `guard-git-push.sh` に入力を渡し、main 宛てと force push を止め（exit 2）、feature ブランチへの push を通すことを確かめた。
- 復旧: 失敗した1回目の配置を `place.sh --restore` で戻し、配置前の内容（手で絞った AGENTS.md を含む）に戻ることを確かめた。
- 正式レビュー: Codex Review の実指摘（#22 で 2件、#23 で 2件）に対応した。#23 の2件めは、Draft を外したときの再レビューで出た（親ディレクトリの fsync の失敗）。指摘が実際に出たので、合成指摘での試験は行っていない。
- 照合: `scripts/check-pr-head.sh` が #22 と #23 で READY を返した。#22 は、自分が足す `.github/pr-gate-checks` が merge 前は効かないので、check 名を明示して照合した。
- 未確認: Claude Code が、hermes で新しく起動したセッションで、CLAUDE.md とフックを自動で読み込むこと。

## 6. 判定と残課題

**判定: 切替提案（#197）へ進める。ただし条件付き。**

- 理由: 必読の量が約 1/11 になり、実装、レビュー指摘への対応、照合、人間のマージまでが軽量構成の手順で成立した。見つかった問題はテンプレートの不具合で、試行の中で直した。
- 条件と残課題:
  - 1件の、小さく外部接続のない Issue での結果。規模の大きい案件や、UI・外部送信を伴う案件では確かめていない。
  - hermes で新しく起動した Claude Code のセッションで、CLAUDE.md とフックが読み込まれることは未確認。次の hermes の作業で確かめる。
  - Codex Review が running のまま止まることがあり、完了を待つ仕組み（照合スクリプトの再実行や再依頼）が要る。
  - main は保護されていない（#163）。フックは文字列による早期検出で、確実な保証ではない。
  - bootstrap の GIT_RULES の矛盾（#202）は未対応。
  - 旧資産（pr-review-fix など）の削除は #197 で扱う。
