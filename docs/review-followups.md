# Review Follow-ups

この台帳は、レビューでFOLLOW-UPと分類したうち、将来対応または障害調査で参照する価値がある既知リスクをリポジトリ横断で管理する。

## 登録ルール

中央台帳へ登録するのは、次のいずれかを満たす項目だけとする。

- 後日対応する価値が具体的に説明できる。
- 将来の障害調査で参照価値がある。
- 特定条件で不具合として顕在化する可能性を説明できる。

単なるスタイル改善、好みのリファクタリング、根拠の弱い懸念、実害を説明できない提案は、発生元PRの最終コメントに`NOTE`として残し、中央台帳へ登録しない。
`ISSUE`として登録してもGitHub Issueを自動作成せず、人間が必要性を確認してからIssue化する。

## 項目のライフサイクル

- `open`: 未対応で、調査・対応候補として有効。
- `resolved`: 解決Issue / PRで対応済み。
- `superseded`: 設計変更等で不要になった。置換理由を記録する。

`resolved` または `superseded` へ更新するときは、解決Issue / PRまたは置換理由を必ず追記する。
状態値は `open / resolved / superseded` のいずれかとする。

## 台帳登録後の検証対象SHA

更新後headの再レビューで新しいP2を `FOLLOW-UP` かつ `ISSUE` と判定した場合は、CI・security・review完了後であっても、中央台帳への登録commitを作成する。

台帳登録commitは新しい検証対象を作るため、次の遷移を必ず行う。

1. 同じPRのhead branchへ台帳登録commitを作成し、SHA照合前に `git push origin "HEAD:refs/heads/$HEAD_BRANCH"` を実行する。pushが成功しない場合はSHA照合・再検証へ進まない。
2. 登録commitのSHAを新しい `EXPECTED_SHA` / 検証対象SHAとして記録し、GitHub上のPR head SHAと一致することを確認する。
3. 登録前の `EXPECTED_SHA` に対するローカル検証、CI、security、再レビュー結果を新しいSHAの結果として再利用しない。
4. 台帳登録後の新しいSHAに対して、標準検証入口 → GitHub Actions CI → 利用可能なsecurity check → `@codex review` を再実行する。
5. 各検証結果が同じ新しいSHAを対象としていること、最終的なPR head SHAがそのSHAと一致することを確認する。

登録commit後にSHAを確認できない、検証結果の対象SHAが一致しない、または新しい検証を完了できない場合は、完了扱いにせず人間へ戻す。
`NOTE` / `DISMISS` と分類して台帳登録を行わない場合は、この遷移を開始しない。

## 障害調査での検索手順

1. 障害の症状、エラー文、機能名、モジュール名、関連ファイルから検索語を選ぶ。
2. このファイルを検索し、一致するFollow-up IDと状態を確認する。
3. `open` の候補について、発生元Issue / PRへ移動する。
4. 発生元PRのレビュー指摘と、後回し可能とした根拠を確認する。
5. 原因候補から外れただけなら `open` を維持する。リスクを解消した場合だけ解決Issue / PRを追記して `resolved` へ、設計変更で不要になった場合だけ置換理由を追記して `superseded` へ状態を更新する。

検索キーは次のとおりとする。

- 症状
- エラー文
- 機能名
- モジュール名
- 関連ファイル

## 台帳フォーマット

1件の登録につき、少なくとも次の項目を埋める。

| 項目 | 内容 |
| --- | --- |
| Follow-up ID | `FU-<PR番号>-<連番>` |
| 発生元Issue / PR | `#<Issue番号> / #<PR番号>` |
| 対象領域 | 機能名、モジュール名、または運用領域 |
| 内容 | 指摘された既知リスクまたは技術的負債 |
| 後回し可能とした根拠 | Issue受入条件への影響、現在マージした場合の影響、独立修正可能性 |
| 想定症状 | 将来発生し得る症状、エラー文、再現条件 |
| 関連ファイル / 機能 | 障害調査の入口 |
| 優先度 | P2 / P3、またはプロジェクトで定義した優先度 |
| 状態 | `open` / `resolved` / `superseded` |
| 解決Issue / PR | 対応済みの場合のIssue / PR。未対応は`なし` |
| 置換理由 | `superseded`の場合の理由。該当しない場合は`なし` |

## 登録済み項目

### FU-221-1

- 発生元Issue / PR: #219 / #221
- 対象領域: GitHub作業指針（githubスクリプト）の依存循環の判定
- 内容: 依存循環を見つけたとき、探索中の経路全体（循環に入っていない祖先を含む）に「依存循環」の保留を付ける。
- 後回し可能とした根拠: hermes-self-improvement から移した判定のままで、#219 は読み取りの規則を変えない移植。保留が増える側（安全側）の誤りで、独立に直せる。
- 想定症状: issue:1 → #2、#2 → #3、#3 → #2 のとき、循環にない issue:1 にも「依存循環」の保留と手順が出て、recheck が BLOCKED になる。
- 関連ファイル / 機能: `scripts/github_work_guide/core.py` の `build_plan`（DFS の `visiting`）
- 優先度: P3
- 状態: `open`
- 解決Issue / PR: なし
- 置換理由: なし

### FU-221-2

- 発生元Issue / PR: #219 / #221
- 対象領域: GitHub作業指針の gate 判定と `scripts/check-pr-head.sh` の違い
- 内容: `codex` の正式レビューは、Codex bot の APPROVED / COMMENTED レビューがあれば確認済みとし、`codex-review-state:v1` の `has_unresolved_findings` を読まない。また、過去に一度でも CHANGES_REQUESTED があれば保留にし、レビュアーごとの最新の判断だけを見る check-pr-head.sh と違う。
- 後回し可能とした根拠: hermes-self-improvement から移した判定のまま。案内は最後に check-pr-head.sh の READY を求めるので、マージ前の照合は check-pr-head.sh が行う。資料（docs/github-work-guide.md）に違いを書いた。
- 想定症状: レビュー本文に指摘がある Codex の COMMENTED レビューで、案内に保留が出ない。変更要求の後に承認されたPRで、案内に「変更要求レビューあり」が残り続ける。
- 関連ファイル / 機能: `scripts/github_work_guide/core.py` の `gate`
- 優先度: P2
- 状態: `open`
- 解決Issue / PR: なし
- 置換理由: なし

### FU-221-3

- 発生元Issue / PR: #219 / #221
- 対象領域: GitHub作業指針の本文の読み取り
- 内容: 本文の行 `depends-on: #N`（見出しなし）を依存の記載として認識しない。同じリポジトリへの参照の owner/name を大文字小文字を区別して比べるので、`Second-Works/ai-development#12` のような書き方は別リポジトリ扱いになる。依存欄の `#0` を番号として受け付け、`issue:0: 未取得` の保留になる。
- 後回し可能とした根拠: hermes-self-improvement から移した読み取りの規則のまま。依存欄の見出しや `- depends-on:` を依存欄の中に書く形式は読めている。保留が増える側の誤り。
- 想定症状: 依存欄の見出しがなく `- depends-on: #5` だけの Issue に「依存欄がない」の保留が出る。大文字を混ぜた参照の子一覧の行が「確認できない」になる。
- 関連ファイル / 機能: `scripts/github_work_guide/guide.py` の `LABEL`、`references`、`reference_count`
- 優先度: P3
- 状態: `open`
- 解決Issue / PR: なし
- 置換理由: なし

### FU-221-4

- 発生元Issue / PR: #219 / #221
- 対象領域: GitHub作業指針の取得の上限
- 内容: Issue/PR の一覧は100件×10ページで、ちょうど1000件以上あるリポジトリは取得が終わらない（INCOMPLETE）。設定ファイルの `items` / `calls` を上げても変わらない。
- 後回し可能とした根拠: 2026-10-30 時点で対象リポジトリの最大は ai-development の約220件。`page limit reached` で INCOMPLETE になるだけで、誤った案内は出ない。
- 想定症状: 1000件に近づいたリポジトリで、毎回 `取得不完全` になり plan が作られない。
- 関連ファイル / 機能: `scripts/github_work_guide/collector.py` の `rest_request`、`Collector.pages`、`MAXIMUM`
- 優先度: P3
- 状態: `open`
- 解決Issue / PR: なし
- 置換理由: なし

### FU-221-5

- 発生元Issue / PR: #219 / #221
- 対象領域: GitHub作業指針のコメントによる保留
- 内容: Issue のコメントに `Goal` / `目標` / `方針` が出てくると、書いた人（bot や外部の人を含む）にかかわらず `comment_change` の保留を付ける。公開リポジトリでは誰でもコメントできる。
- 後回し可能とした根拠: hermes-self-improvement から移した規則のまま。保留が増える側の誤りで、案内が誤って「進めてよい」になることはない。
- 想定症状: bot のコメントや外部の人のコメントで、Issue に「コメントのGoal/方針変更は人の確認が必要」の保留が付き、recheck が BLOCKED になる。
- 関連ファイル / 機能: `scripts/github_work_guide/core.py` の `analyze`（comment_change）
- 優先度: P3
- 状態: `open`
- 解決Issue / PR: なし
- 置換理由: なし

## 新規登録テンプレート

以下を複製し、発生元PRの最終収束コメントに記録した詳細と一致させる。

### FU-<PR番号>-<連番>

- 発生元Issue / PR: #<Issue番号> / #<PR番号>
- 対象領域:
- 内容:
- 後回し可能とした根拠:
- 想定症状:
- 関連ファイル / 機能:
- 優先度:
- 状態: `open`
- 解決Issue / PR: なし
- 置換理由: なし
