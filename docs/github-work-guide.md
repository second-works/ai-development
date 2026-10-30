# GitHub作業指針（githubスクリプト）

モデルを使わずに GitHub の Issue/PR を読み、決まった規則で作業案内を作る読み取り専用のCLI。取得 → 版付き保存 → 前回差分 → 根拠付き手順 → 選択候補の再取得を行う。
hermes-self-improvement で作ったものを、second-works の公開リポジトリを1か所から点検するために移した（#218、#219）。各リポジトリへは配らない（`templates/lightweight/place.sh` の配置対象ではない）。AI の Hermes Agent 本体とは別物。

Risk Tier: MEDIUM。公開情報の読取とローカル新規成果物だけを追加し、認証・権限・既存Gate・本番を変更しない。

## 置き場所

| 物 | 場所 |
| --- | --- |
| 本体 | `scripts/github_work_guide/`（core.py、collector.py、guide.py、config.py） |
| CLI | `scripts/report_github_work_guide.py` |
| 対象リポジトリ | `config/github-work-guide.json` |
| テスト | `tests/github-work-guide/`（`run-samples.sh` を `./scripts/verify.sh` と CI が実行する） |
| 取得結果 | `runs/`（Git管理外） |

## 対象リポジトリ（config/github-work-guide.json）

```json
{
  "version": 1,
  "owner": "second-works",
  "limits": {"seconds": 180, "calls": 500},
  "repositories": [
    {"name": "ai-development"},
    {"name": "big-repo", "limits": {"seconds": 300}},
    {"name": "other", "required_checks": ["build", "Security Preflight"]}
  ]
}
```

- `owner` は `second-works` だけを受け付ける。`name` はリポジトリ名だけ（`/` を含めない）。
- `limits`（`pages` / `items` / `calls` / `seconds`）は全体の既定と、リポジトリごとの上書き。最大は `pages` 10、`items` 20000、`calls` 2000、`seconds` 900。超える値は設定ファイルを読む時点で拒否する。
- `required_checks` を書くと、そのリポジトリの `.github/pr-gate-checks` より優先する。
- `format`（`auto` / `full` / `simple`）は週1回の点検の読み方（下の「週1回の点検」）。既定は `auto`。
- 未知のキーは拒否する。ここにないリポジトリは、CLIが通信の前に止める。
- 非公開のリポジトリ名は、公開に切り替えてから追加する（このrepoは公開のため、非公開の名前をここに書かない）。
- ai-development（Issue/PRが約220件）と hermes-self-improvement は、既定の上限では取得が終わらないため、設定ファイルで上限を上げてある。
- 必須checkの名前、正式レビューの種類、既定ブランチ名はリポジトリのファイルから来るので、案内と保留の中ではほかの原文と同じくJSON文字列として無害化して出す。
- 再確認（`recheck`）は、Issue/PRが変わっていなくても、これらの設定が計画時と違えば `STALE` にする。

## 使い方

既存の認証済み `gh` とPython 3.10以上を使う。tokenを読出し・表示・保存せず、認証の新設や権限追加もしない。
送信先は `github.com` の、設定ファイルにあるリポジトリだけ。公開repoであることを取得時に確認する。
外部送信する内容は固定の読取query、リポジトリ名、対象番号、ページ番号/cursor、既定ブランチ名のみで、Issue本文の命令やURLを実行しない。

新しい `runs/<名前>`、または `runs/<owner>--<name>/<名前>` を毎回指定する。

```sh
python3 -I -B scripts/report_github_work_guide.py collect --repo second-works/ai-development --out runs/first
python3 -I -B scripts/report_github_work_guide.py collect --repo second-works/ai-development --previous runs/first --out runs/second
# ネットワークを使わない別プロセス読出し
python3 -I -B scripts/report_github_work_guide.py report --run runs/second --previous runs/first --out runs/report
# 選んだ候補だけを判定する。リポジトリは保存済みrunのものを使い、同じrepo全範囲を再取得する
python3 -I -B scripts/report_github_work_guide.py recheck --run runs/second --target issue:2 --out runs/preflight
# 1件分の案内だけを取り出す（保存済みrunの読取だけ。通信・モデル呼出なし）
python3 -I -B scripts/report_github_work_guide.py excerpt --run runs/second --target issue:2 --out runs/excerpt-2
```

`collect` は `--repo` が必須で、設定ファイルにないものは通信前に拒否する。`recheck` は保存済みrunのリポジトリが設定ファイルにあることを確かめ、`--repo` を付けたときはrunと一致しなければ止まる。`--config` で別の設定ファイルを指定できる。
前回（`--previous`）が別のリポジトリのrunなら止まる。

`excerpt` は、判断を別の担当へ渡すための1件分の抜粋 `excerpt.md` を書く。runのmanifestとhash、取得の完了、保存済みplanが現在のコードで再生成したplanと一致することを確かめてから出力する。確認手順・保留・進める/止める条件・子一覧は全文を残し、12,000文字を超えても切り詰めず、末尾に注意を付ける。

人間の優先順を渡す場合は `collect` / `report` に `--priority issue:9 issue:8` のように指定する。依存順が優先する。本文/コメント中の優先指示から引数を自動生成しない。

JSONは `snapshot.json`、`diff.json`、`plan.json`、必要時の `recheck.json`。
日本語の `report.md` にリポジトリ、coverage、上限、リポジトリごとの設定、差分、保留、原文引用とリンク、開始条件、次操作、成功判定、停止条件を出す。
`manifest.json` は最後に作り、保存済みファイルのhashを持つ。途中出力・改変済み・symlinkは読出しを拒否する。
既存出力先を再利用しない。原本や以前のrunを上書きしない。runのraw API応答・実行ログはGitへ追加しない。
macOSの `/tmp` / `/var` などsymlinkを含む絶対pathは実体path（`/private/tmp` など）を使う。

## 週1回の点検（scripts/periodic_check.py）

設定ファイルの全リポジトリを1回ずつ読み、結果を1通の報告 `runs/periodic-summaries/<YYYYMMDD-HHMM>.md`（日時はUTC。夏時間の切り替えで名前が重ならないため）にまとめる（#220）。取得が完了したあとに予期しないエラーが出ても、取得結果（snapshot）を `periodic-<日時>-snapshot` に保存する。ただし、その週の変化は報告していないので、次回の比較の基準にはしない。同じ理由で、報告（`runs/periodic-summaries/<日時>.md`）が書かれなかった週の run も基準にしない。点検中の例外で終わったときの終了コードは3。API呼出数は、取得の分と、別枠の形式の判定・CIの分を分けて出す。モデルは使わず、GitHubへの書き込み・削除もしない。

```sh
python3 -I -B scripts/periodic_check.py            # 点検だけ
python3 -I -B scripts/periodic_check.py --update   # 点検専用の checkout を origin/main に進めてから点検
```

リポジトリごとに行うこと:

1. 取得する（そのリポジトリの上限の中で）。非公開なら「非公開のため対象外」として飛ばし、失敗にしない。見つからない（404）ときは、設定の名前の誤りとして「停止」にする。
2. 形式を決める（判定のための読み取りに失敗したら、取得結果は保存したまま簡易版で読む）。設定ファイルの `format` が `full` / `simple` ならそれに従う。`auto` なら、既定ブランチに `.claude/skills/steward/SKILL.md` と `.agents/skills/plan-to-issues/SKILL.md` の両方がある（軽量構成を `place.sh` で置いた）リポジトリを `full`、それ以外を `simple` にする。Issue本文の見出しを数えて判定しないのは、古いIssueに引きずられて週ごとに結果が揺れるため。ファイルは有無だけを見て、中身は読まない。
3. 前回の完全なrun（`runs/<owner>--<name>/periodic-*` のうち、検証を通る、いちばん新しい COMPLETE のもの）と比べる。
4. 既定ブランチの workflow run を新しい順に30件読み、workflow（workflow_id）ごとに最新の結果を出す（形式の判定と合わせて、取得とは別の小さな枠で読む）。形の合わない run はその run だけ飛ばす。PR の run は除く（フォークの `main` ブランチからのPRを、既定ブランチのCIと取り違えないため）。最新が実行中でも、最後に終わった run（cancelled は除く）が成功・skipped・neutral・stale（GitHub が古い run を打ち切ったもの）以外なら警告にする。新しい30件がすべて PR の run だと、既定ブランチのCIは「runなし」になる。cancelled はコードの結果を表さないので、失敗を隠しも報告もしない。run が1つもないリポジトリは一覧に「runなし」と出す。別リポジトリのコードの run（フォークの同名ブランチ）も除く。30件の中に run がない workflow（まれにしか動かない schedule など）は見えない。
5. `full` なら作業案内（plan）も作り、親の検収待ち・完了範囲確認・案内の対象を出す。`simple` は作業案内を作らず、前回からの変化、14日以上動いていないOPEN、既定ブランチのCIだけを出す。

どちらの形式でも、取得時間とAPI呼出数がそのリポジトリの上限の8割以上なら警告する。形式の判定とCIの読み取りは、取得とは別の小さな枠（5回・120秒）で行うので、取得が上限ぎりぎりでも落ちない。CIを読めなかったときは警告にし、要対応に数える。正式レビューの設定（`.github/pr-gate-review` の有無と中身）と必須checkもリポジトリごとに出す。
報告の冒頭に、全リポジトリの状態・形式・要対応の件数・CIの一覧を置く。1つのリポジトリが失敗・上限到達しても、次のリポジトリは自分の上限で読む。

`--update` で checkout を進めたときは、新しい版のスクリプトを別のプロセスで動かして点検する（古いコードで新しい設定ファイルを読まないため）。新しい版が正しく終わらなかったときは、更新した側がその旨を報告に書き（新しい版が報告を書いた後に止まったときは追記する）、エラー出力を `runs/periodic-summaries/<日時>.child-stderr.txt` に残す。子プロセスの制限時間は、更新後の設定の時間の上限の合計に余裕を足した値。報告の冒頭に、点検したコードのコミットと、更新したときは更新前のコミットを書く。更新できなかったときは、その理由を報告に書き、今の版のまま点検する（終了コード1）。`--update` は、このスクリプトがある checkout の `runs/.periodic-check-checkout` を目印にする（`--runs` の場所ではない）ので、点検専用の checkout の中で動かす。報告の API 呼出数は、取得の分と、別枠の形式の判定・CIの分を分けて出す。上限の8割の警告は取得の分で判定する。

終了コード: 全リポジトリを点検できた（非公開による対象外を含む）なら0、どれかが停止したら1、既存の報告があるなど使い方の誤りは2、点検自体が例外で終わったら3。`--notify` で macOS の通知を出す。runs/ は自動で削除しない。

### 自動実行への移行（未実施）

hermes-self-improvement 側の週1回の点検（利用者の Mac の launchd と、hermes の点検専用 worktree。設定は hermes-self-improvement の `.claude/skills/periodic-check/SKILL.md`）は、移行が終わるまでそのまま動かす。切り替えと旧コードの削除は、別の作業として人が判断する。

切り替えるときの手順の例（利用者の Mac で、人が行う）:

1. ai-development の点検専用 worktree を作る（例: `git -C <ai-development の checkout> worktree add --detach <点検専用 worktree> origin/main`）。
2. その worktree に `runs/` を作り、空のファイル `runs/.periodic-check-checkout` を置く（`--update` はこの目印がある checkout だけを動かす）。
3. 手で1回 `python3 -I -B scripts/periodic_check.py --update` を実行し、報告を確かめる。
4. launchd の plist を、hermes 側の例（`.claude/skills/periodic-check/SKILL.md`）と同じ形で、ProgramArguments を新しい worktree の `scripts/periodic_check.py --update --notify` に、WorkingDirectory を新しい worktree にして置く。
5. 新しい点検が動くのを確かめてから、hermes 側の plist を外す。

## 非公開のリポジトリ

リポジトリ情報の `private` が `false` で `visibility` が `public` のときだけ、Issue/PRを読む。そうでなければ、それ以上は何も読まずに coverage を `SKIPPED`（「非公開のため対象外」）にする。リポジトリ情報が404（非公開で読む権限がないか、名前の誤り）のときも `SKIPPED`（「見つからないため対象外」）にする。
非公開による `SKIPPED` は失敗ではない（CLIの終了コード0）。404による `SKIPPED` は、利用者の gh なら非公開のリポジトリも見えるので名前の誤りの可能性が高く、終了コード2にする。どちらもsnapshotには項目も設定も入らない。

## リポジトリごとの設定

取得のはじめに、リポジトリ情報の既定ブランチ（`main` 以外でもよい）を読み、その既定ブランチから次の2ファイルを読む。読み方は `scripts/check-pr-head.sh` と同じで、空白だけの行と1文字目が `#` の行を無視し、check名は前後の空白も含めてそのまま使う（レビューの種類は空白を除く）。
`scripts/check-pr-head.sh` はこの2ファイルをPRのbaseブランチから読むので、既定ブランチ以外へのPRは、案内とマージ前の照合で必須checkが違うことがある。

| 項目 | 読む元 | ないとき |
| --- | --- | --- |
| 必須check | 設定ファイルの `required_checks`、なければ `.github/pr-gate-checks` | `verification`、`Security Preflight`（`scripts/check-pr-head.sh` の既定と同じ） |
| 正式レビューの種類 | `.github/pr-gate-review` | `codex` |

読んだ値は、出所（`config` / `repository` / `default`）と一緒にsnapshotに入れて封をする。planの再計算はこの値を使うので、後で設定ファイルを変えても保存済みrunの検証は崩れない。

正式レビューの種類:

- `codex`: `chatgpt-codex-connector[bot]` の、現headに対する APPROVED / COMMENTED のレビュー。
- `claude-code`: OWNER / MEMBER / COLLABORATOR が書いたPRコメントの `<!-- claude-code-review:v1 {"commit_sha":"<full sha>","status":"completed","has_unresolved_findings":false} -->`。そのうち最後のものが、現head・`completed`・`has_unresolved_findings` が真偽値の `false` のとき認める。公開repoには誰でもコメントできるので、ほかの作者のコメントは読まない。
- 認める種類のどれかで通れば、正式レビューは確認済み。どれかが現headで未解決の指摘ありなら保留する。知らない種類は通らず、`.github/pr-gate-review` を確認するよう保留に出す。
- `codex` は、レビューの本文に指摘があっても APPROVED / COMMENTED なら確認済みとする（hermes-self-improvement での判定のまま）。指摘の有無は、未解決threadの保留と `scripts/check-pr-head.sh`（`codex-review-state:v1` の `has_unresolved_findings`）で確かめる。
- OPEN PRの案内は、最後に `scripts/check-pr-head.sh <番号>` が READY を返すことを求める。照合スクリプトは軽量構成の版（#222 以降）なら `codex` と `claude-code` の両方を読む。それより前に配置したリポジトリでは、`place.sh` で更新するまで `codex` しか読まない。


## 取得範囲と限界

1回につき全状態のIssue/PR一覧、各本文と現在状態、Issue/PR会話コメント、PR head、GitHubのclosing issue関係を取得する。OPENのPRだけは、さらにheadのcheck runsとcommit statuses、正式レビュー、inline review comments、review threadの解決状態を取得する。

CLOSED/MERGEDのPRは「今回対応不要」としか案内に使わないため、check runs・commit status・レビュー・inline review comments・threadを取得しない。report冒頭の「取得対象外」に明記する。閉じたPRのこれらの変化は差分・再確認で比較せず、「変化なし」とは扱わない。依存先や関連候補として出る閉じたPRも、状態とheadだけで扱い、checkやレビューの成否を表示しない。2026-10-30の hermes-self-improvement の実データでは48件で237呼出・138秒かかり、上限180秒に近づいていた。Issue/PRが多いリポジトリは、設定ファイルでそのリポジトリの上限を上げる。
GraphQLは固定の `query` 2種のconnectionだけで、mutationも任意query入力もない。
RESTは、設定ファイルにあるリポジトリ1つに結び付いた固定routeのGETだけ。GraphQLのリポジトリ名は変数で渡し、queryの文字列には埋め込まない。shellは使わず、`gh api` の固定引数を呼ぶ。
書込API・操作実行・通知・予定変更・モデル・本番・Dockerの入口はない。

- 1系列あたり最大10ページ、1ページ100件。
- 全系列合計5000 list node、500 API呼出、全体180秒（1呼出最大30秒）。これは既定の値で、どれもリポジトリごとの上限。設定ファイルで最大 `items` 20000、`calls` 2000、`seconds` 900 まで上げられる（`pages` は10のまま）。
- API応答は1呼出10MB、保存JSONの読出しは1ファイル32MBまで。
- 再試行0。空の短い最終ページ/GraphQL pageInfoまで追い、check total_countも照合する。
- 認証不足、rate limit、欠落、不正schema、上限、時間切れ、途中失敗は `INCOMPLETE`。手順を生成しない。
- 一覧を最後に再取得し、件数・updated_at・stateの不一致を停止する。取得の途中でPRが開閉した場合もここで `INCOMPLETE` になり、閉じたPRとして省略した範囲を混在させない。GitHub APIは複数要求の原子的snapshotを提供しない。収集直後/確認直後の変化を防止するロックではない。
- PR file diff、添付、外部URLの内容、本番採用、実検収、任意の関連Issueまでの横断探索は取得しない。

coverageは取得完了の判定であり、必須checkやレビュー成功の判定とは別。
`COMPLETE` でも0件のcheck/レビューは必要条件の未確認となる。
必須名と正式レビューの種類はリポジトリごとの設定（下の「リポジトリごとの設定」）に従う。
現head・送信元ごとの最新attemptと同名commit status両方の成功、正式レビューを確認し、skip・古いhead・未解決thread・変更要求は保留する。
送信元は、アプリとcheck suiteの組。別のワークフローに同じ名前のjobがあれば、それぞれの最新が成功している必要がある（`scripts/check-pr-head.sh` の `filter=latest` と同じ）。同じsuiteでの再実行は、新しいattemptが古いものを置き換える。
botの👍/要約コメントだけのレビュー完了は自動認定しないため、人の確認が残る。
この判定はrepoの正式Merge Gateを代替しない。

## 手順と根拠

自由要約を入力する機能はない。ハーネスが次の7種から決め、原文の抜粋と現在状態を付ける。

| 種別 | 条件 / 次に人が確認すること |
| --- | --- |
| 今回対応不要 | CLOSED/MERGED。再実装を開始しない |
| 親の検収待ち | 子一覧の番号付き項目がすべてチェック済みで参照先がすべてCLOSED、別repo・PR・自分自身・未取得を指す行がなく、未チェックは参照を1つも含まない項目（人の検収・照合）だけ。各子の完了根拠と `docs/parent-issue-completion.md` の5項目を照合し、親のCloseを人が判断する |
| レビュー対応準備 | OPEN PR。現在head、check、レビュー、threadを確認 |
| 依存確認 | 依存が番号だけで書かれている。依存先と開始条件を確認 |
| 完了範囲確認 | OPEN Issueに、MERGED PRからのclosing関係、またはPR本文のRefs等による参照がある。Doneと実装範囲を照合 |
| 対象範囲確認 | 上記以外で保留がある。保留ごとの問いと解除条件を確認 |
| 計画整理 | その他の保留なしOPEN Issue。GoalとScopeを照合 |

### 読み取る形式

見出し（`#`〜`######`、コードブロック内は除く）を次の名前で認識する。前方一致は直後が空白・`/`・括弧・コロンの場合だけ。

| 欄 | 認識する見出し |
| --- | --- |
| goal | Goal / 目的 / 目標 |
| scope | Scope（Scope / Boundaries を含む） / 作業 / 範囲 / 対象範囲 |
| done | Done / 完了条件 / Acceptance criteria / 受入条件 |
| verification | Verification / 検証 |
| dependencies | Dependencies / 依存 |
| non_goals | Non-goals / 対象外 |
| boundaries | Boundaries / 境界 |

本文中の `依存: …` / `Dependencies: …` / `Depends on: …` の行も依存の記載として読む。
依存が `none` / `なし` / `依存なし`、または番号だけ（`- depends-on: #8`、`依存: #3, #5` など）のときだけ確定する。確定した番号はIssueとして解決するため、`PR #25` のようにPRと書かれた依存は確定せず、自然文の保留にする。
名前や文章を含む依存は確定せず、項目ごとに引用する。題名と語が一部一致するIssueを「候補（未確定）」として最大3件示すが、依存の順序には使わない。
条件付きの番号は、確定依存とは別の `dependency_hints` に確認先として保持する。
対象は現行の依存欄にある、文頭または句点・セミコロン・空白付きピリオドの直後の `Depends on:` / `依存:` と、その直後の番号列だけ。
`Parent: #31。Depends on: #35（#32→#33→#34→#35の人間Mergeと独立評価の証拠）。` では、確認先は#35だけとなり、条件は原文で引用する。
番号付きの条件混在は「番号なし」とせず、機械確定できない形式と説明する。
Parent、括弧内の参考番号、任意・再利用経路、コード例、コメント、履歴、対象外URLから確認先を推測しない。
直後に `PR #N` とあれば種別を保持し、取得されていない番号はUNFETCHEDのまま示す。

確認先の状態、Doneのチェック数、取得済みPRの明示RefsまたはGitHubのclosing関係、full headと出典を手順に示す。
RefsはPR本文の行頭（箇条書き可）の宣言とその番号列に限定し、コード例・コメント・単なる言及から結び付けない。
CLOSED/MERGEDや本文チェックを成功・採用の認定に使わず、実装範囲と評価根拠を人が照合する。
この案内は依存グラフ、優先順、保留の解除、取得範囲には影響しない。未対応文法や矛盾は保留を維持する。

一致の基準は、項目の語（英単語と、それ以外の文字の2文字組）のうち題名にも含まれる割合が0.3以上であること。候補は手がかりであり、正しさは測っていない。

### 保留の出し方

保留は理由の種類を分ける。`format`は欄がない・空・番号付き条件混在の未対応形式など形式の問題、`semantic`は複数の目的・自然文の依存・コメントでの方針変更・closingでない関係など意味の確定が必要なもの、`state`は依存先の状態、`gate`はPRの必須checkとレビュー。
各保留は、原文の該当箇所（evidence）、確認対象、確認する問い、解除条件を持つ。解除条件は「人が確認」で終わらせず、何を決めれば保留が外れるかを書く。

### 関連の扱い

同じrepoの `#N`、`owner/repo#N`、Issue/PRのURLを読み、両方向（本文が言及／相手が言及）で「関連候補」として出す。
`Refs` / `Related` / `Part of` / `Closes` / `関連` の直後にある参照は、参照の関係として区別する。GitHubのclosing関係（`closingIssuesReferences`）は別に表示する。
関連候補は依存の確定でも完了の証拠でもない。Refsだけの関係は `relation_not_closing` の保留になり、Issueのどの完了条件を満たしたかを人が確定する。
対象外repoのURLは「取得しない」と表示するだけで、内容を取得しない。
関連PRのMergeがIssueの最終更新より後なら、本文の状態の記述はMerge前の時点として読むよう注意を出す。

### 計画の検証

各候補は対象、原文の抜粋（1件300文字まで。切った場合は「抜粋」）、source hash、リンク、確認手順、保留、開始条件、成功判定、停止条件を持つ。
抜粋は原文の完全な部分文字列で、識別子は行番号（`issue:7:L34-L39`、コメントは `issue:4:c1:L3:53`）。
保存planはsnapshotからの再生成と全体一致が必要。種別変更、未知ID、捏造引用、余分な完了主張、順序改変を拒否する。
planの形式はversion 7、snapshotの形式はversion 2（ai-development への移植で、リポジトリ名とリポジトリごとの設定をsnapshotに入れた）。旧versionのplanを持つrunは、再確認の取得前に「旧versionのplanです。新しくcollectし直してから再確認してください。」で止まる。hermes-self-improvement で作った run（manifest と snapshot が version 1）は、「旧versionのplan」ではなく読めないrunとして拒否するので、新しくcollectし直す。
hashはローカル破損/改変の検知でありGitHub署名や発行元の証明ではない。snapshotを信頼できない人から受け取って実行根拠にしない。
MERGEDからIssue Close、本番適用、検収済みを推定しない。本文中の完了主張も引用された未検証データであり、ハーネスの結論ではない。
確認手順は固定の文型と、番号・head・日時・件数・根拠IDだけで作る。原文の文章は引用（JSON文字列として無害化）でだけ表示する。Issue番号ごとの判断文はコードにない。

## 差分と再確認

`FIRST` / `ADDED` / `UNCHANGED` / `CHANGED` / `UNAVAILABLE` を区別する。
取得できなくなった項目は削除・解決と呼ばない。変更フィールドにstate、body、headを含むdetail、comments、checks、statuses、reviews、threads等を表示する。

差分と再確認は、原本hashとは別の作業fingerprintで比べる。fingerprintは原本から、PRの `head.repo` / `base.repo` のrepo全体のメタデータ（`open_issues_count`、`pushed_at`、`updated_at` など）を `full_name` だけに縮め、CLOSED/MERGEDのPRから取得対象外の5系列（check runs・statuses・reviews・review comments・threads）を除いたもののhash。
これらだけが変わったitemは `UNCHANGED`（`metadata_only: true`）で、reportに件数を出す。state、title、本文、head SHA/ref、コメント、check、status、レビュー、thread、closing関係の変化は引き続き `CHANGED` / `STALE` になる。
原本と原本hashはそのまま保存し、読出し時に検証する。

再確認は保存planを検証後、実際に再取得する。対象・依存・関係の追加/欠落も検知するため、計画範囲の全itemのfingerprintを照合する。
関係のないコメント更新も `STALE` になる保守的な実装である。

## 検証

```sh
bash tests/github-work-guide/run-samples.sh
./scripts/verify.sh
bash scripts/security-preflight.sh .
```

`tests/github-work-guide/run-samples.sh` は `python3 -I -B -m unittest` で全テストを動かし、Python 3.10未満、失敗、skipがあれば失敗にする。`./scripts/verify.sh` は `tests/*/run-samples.sh` を全部実行するので、これで標準検証に入る。CIの「GitHub work guide regression」も同じものを実行する。
テストは標準ライブラリだけで、通信もモデルも使わない。合成APIと、hermes-self-improvement の公開Issue/PRを保存したfixture（`tests/github-work-guide/fixtures/`、2026-10-23と2026-10-28に取得）を使う。fixtureは取得元のリポジトリ名のまま封をし、別のリポジトリ名に置き換えても同じ案内になることを `test_multi_repo.py` で確かめる。

## 経緯

hermes-self-improvement の second-works/hermes-self-improvement#26、#28、#42、#49、#50、#51（どれも hermes-self-improvement の番号）などで作り、[元の資料](https://github.com/second-works/hermes-self-improvement/blob/26b105029029599ef3b3e34c35aae0d85fa8dcd3/docs/github-work-guide.md)に試験と判断の記録がある。ai-development への移植（#219）で変えたのは、対象リポジトリを設定ファイルで指定すること、リポジトリごとの設定を読むこと、非公開のリポジトリを失敗にせず対象外にすること、正式レビューに `claude-code` を加えたこと。読み取りの規則は変えていない。案内の文型は、必須checkと正式レビューの文言だけを、リポジトリごとの設定を出す形に変えた。
