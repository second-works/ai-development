# 軽量構成の限定試行

**状態: 準備中（#196）。試行先の実装Issueと変更範囲は、人間の確認待ち。実配置はまだしていない。**

親 [#192](https://github.com/second-works/ai-development/issues/192)、本Issue [#196](https://github.com/second-works/ai-development/issues/196)。配置の仕組みは [#195](https://github.com/second-works/ai-development/issues/195)（PR #201）の `templates/lightweight/place.sh`。

## 1. 試行の対象

| 項目 | 値 | 状態 |
| --- | --- | --- |
| 試行先repo | second-works/hermes-self-improvement（`.hermes` 本体ではない） | 所有者が承認（2026-10-22、依頼元セッション経由） |
| 元SHA（復旧元） | main `10419e1a49b62b28c6862102c7f08d8c9d03f4b2`（2026-10-22にremoteで確認） | 確定 |
| 配置元 | ai-development main `19426a233b7751ed7de7e033dec2a32aecfdea4f` | 確定 |
| 配置する場所 | main から切った試行用ブランチの、別のworktree | 案。ローカルのcheckoutは `issue-7-isolated-skill-delegation` ブランチで、ステージ済み47件・未追跡111件の作業中のため使わない |
| 実装するIssue（1件） | 未定 | **人間の確認待ち**（2章） |
| 実装PRの追跡先 | hermes-self-improvement の別PR。この文書のPRは試行記録だけ | 確定 |
| 担当 | Claude Code（実装・レビュー指摘対応）、Codex Review（正式レビュー）、人間（マージ） | 確定 |

## 2. 変更する設定path（dry-run の結果）

元SHAの複製に対して `place.sh --dry-run` を実行した（実repoには書いていない）。

衝突は次の6件で、そのままでは何も書かずに止まる（終了コード1）。どれも、hermes が持つ旧標準版のファイル。

| path | hermes | 旧標準（ai-development main）との差 | 軽量候補 |
| --- | --- | --- | --- |
| `.agents/skills/plan-to-issues/SKILL.md` | 8,805 B | 同じ | 2,850 B |
| `.github/pull_request_template.md` | 3,484 B | 2行 | 458 B |
| `.github/ISSUE_TEMPLATE/parent-issue.md`、`child-issue.md` | 旧標準版 | — | 軽量版 |
| `scripts/verify.sh` | 4,483 B | 11行（project固有の調整） | 旧標準と同じ原本 |
| `scripts/security-preflight.sh` | 10,953 B | 109行（project固有の調整） | 旧標準と同じ原本 |

6件すべてを `--keep` すると、配置は成功し、変わるのは次だけになる。

- 作成: `CLAUDE.md`、`.claude/settings.json`、`.claude/hooks/guard-git-push.sh`、`.claude/skills/steward/SKILL.md`、`scripts/check-pr-head.sh`、`.ai/lightweight-placement.tsv`
- 更新: `AGENTS.md`（末尾に軽量ブロックを追記。既存の本文は変えない）

**判断が必要な点:** すべて `--keep` すると、AGENTS.md には旧標準のルール（標準flow、pr-review-fixなどの必読）と軽量のルールが並ぶ。そのため「読む量」の比較が成り立たない。比較を成り立たせるには、次の2つが必要になる。

1. plan-to-issues とIssue / PRテンプレートを軽量版に置き換える（hermesの既存ファイルを先に外す）。
2. AGENTS.md の旧標準の必読指定を外す。

`verify.sh` と `security-preflight.sh` は project固有の調整があるので、`--keep` で残す案とする。

## 3. 比較の条件

| 指標 | 旧標準（hermesの現状） | 軽量構成 | 取り方 |
| --- | --- | --- | --- |
| 実装時の必読 | 98,809 B（AGENTS 6,339、標準flow 54,051、レビュー正本 14,336、Security境界 11,267、Tier 7,876、test-design 2,893、design-state 2,047） | 置き換えた場合 7,283 B（AGENTS 2,390、CLAUDE 437、steward 4,456） | 試行中に実際に読んだ資料をセッションから数える |
| 配布量 | `.agents` 120 KB、`docs` 644 KB（49 files） | 2章の作成分 | 配置の前後の差 |
| 人間の確認回数と時間 | 近い規模の過去PR（候補: PR #17）から取る | 試行PRで記録 | 取れない値は不明とする |
| 手戻り、作業時間、CI・人間の待ち時間 | 同上 | 同上 | PRのcommitとイベントの時刻 |
| レビュー指摘への対応 | — | 正式レビューの実指摘。出なければ合成指摘の隔離試験で補い、実績とは分ける | — |

## 4. 復旧

`place.sh --restore <worktree>` で、配置の差分だけを戻す。試行用ブランチを捨てれば、元SHAの状態に戻る。mainへの直接push、force push、保護設定の変更はしない。

## 5. 結果

未実施。
