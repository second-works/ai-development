# 軽量構成の候補

**状態: 候補（#194）。標準の配布はまだ切り替えていない。** 今の標準は repo 直下の `AGENTS.md`、`docs/`、`.agents/skills/` のまま。限定試行（#196）で確かめてから、#197 で標準にするかを判断する。

親 [#192](https://github.com/second-works/ai-development/issues/192)、削減範囲は [lightweight-migration-plan.md](../../docs/lightweight-migration-plan.md)。

## 中身

| 配置先 | 役割 |
| --- | --- |
| `AGENTS.md` | 共通の作業境界と停止条件（27行、2.4 KB） |
| `CLAUDE.md` | `@AGENTS.md` の読み込みとstewardへの入口 |
| `.agents/skills/plan-to-issues/` | Codexが計画を親子Issueにする手順 |
| `.claude/skills/steward/` | Claude CodeがIssueからマージ依頼まで進める手順 |
| `.claude/settings.json`、`.claude/hooks/guard-git-push.sh` | main宛てのpushとforce pushを止めるフック、`.env` を読ませない設定 |
| `scripts/check-pr-head.sh` | 最終headのcheck、正式レビュー、未解決スレッド、mainとの競合を読み取りだけで照合する |
| `.github/` のテンプレート | 親子Issueの7項目、PRの検証欄 |
| `scripts/verify.sh`、`scripts/security-preflight.sh` | 既存の原本（`templates/verification/`、`templates/security/`）をコピーする |

CIのworkflowは技術構成ごとに `templates/github-actions/` から選ぶ。ここでは配らない。

## 配置

```bash
templates/lightweight/place.sh --dry-run <project-root>
templates/lightweight/place.sh <project-root>
```

- 置く前に全部の配置先を調べる。1つでも既にあるか、親ディレクトリがsymlink（例: `.claude` → `~/.claude`）なら、何も書かずに衝突を表示して止まる（既存の `AGENTS.md`、`CLAUDE.md`、`.claude/settings.json` などは手で統合する）。
- 途中でコピーに失敗したり、中断（HUP、INT、TERM）されたりしたら、その回に作ったファイルと空のディレクトリだけを消す。
- 既存projectへの配置と復旧の手順は、bootstrap（#195）で扱う。

## ガードの範囲と限界

フックは、Bashのコマンド文字列と、作業ディレクトリのgitの設定だけを見る。シェルの構文解析はしない（親 #192 の方針で、独自の解析器は作らない）。行継続をつなぎ、`;`、`&&`、`|`、改行で区切り（2回目は `$(` と `` ` `` でも区切る）、引用符とバックスラッシュを外した各部分のうち、gitで始まり、pushがgitのサブコマンドであるものをpushとみなす。commitメッセージやPR本文の中の「push」「main」は対象にしない。

| 止める | 止めない（限界） |
| --- | --- |
| `git push origin main`、`"main"`、`HEAD:'main'`、`refs/heads/main`、行継続で次の行にある宛先 | aliasやスクリプトの中のpush、`bash -c "..."` の中 |
| `--force`、`-f`、`--force-with-lease`、`--mirror`、`+`付きrefspec | `gh` やGitHub APIからの操作、他のツール |
| `--all`、`--branches`、`:`、`*` を含むrefspec | ブランチ削除（`--delete`）、push以外のgit操作 |
| `/usr/bin/git`、`git -C <dir>`、`--git-dir <dir>`、`VAR=1 git`、`env -i`、`then` / `do` / `time` / `command` / `!` / `xargs` / `timeout 60` / `nice` / `sudo -u <user>` の後ろ、`( ... )`、`$( ... )`、`` ` ... ` `` の中 | `git -C <別の場所>` で別repoを操作する場合のブランチと設定の判定 |
| `$` や `` ` `` で組み立てたpush、gitのサブコマンドを変数にしたもの（確かめられないため止める。そのまま書く） | 上記以外の凝った書き方（関数、eval、ヒアドキュメントで渡すスクリプトなど） |
| main / master上での `git push`、jqがない・入力が読めないときのpush | |
| 宛先を書かないpushで、`remote.<name>.push`（main / master、`*`、`:`）、`push.default=matching`、`push.default=upstream` によってmain / masterへ送られるもの | 上記以外のgitの設定（`url.<base>.pushInsteadOf` など） |

**止めすぎることがある。** 引用符の中の `;`、`|`、`$(`、バッククォートも区切りとして扱う。そのため、`git commit -m "note; git push origin main"` や、PR本文のインラインコード（`` --body "use `git push origin main`" ``）のように、メッセージの中で区切りの後ろに「git push … main」が来る形は止まる。安全側の誤検知なので、本文は `--body-file` でファイルから渡すか、メッセージを書き換えて再実行する。

**フック自体が実行できないときは止まらない。** Claude Codeはexit 2以外のフックの失敗を警告として扱い、コマンドをそのまま実行する。実行権限が外れた、`bash` が見つからない、`$CLAUDE_PROJECT_DIR` が空、といった場合はpushが通る。`settings.json` のdeny（`git push --force` / `-f` で始まるコマンド）はこのときも働くが、main宛ては防げない。

文字列による検出なので、確実な保証にはならない。確実に守るのはGitHubのブランチ保護（このrepoでは未設定、#163）。

`check-pr-head.sh` の正式レビューの判定は、Codex Reviewが書く要約コメント（`codex-review-state:v1`）と、レビュアーごとの最新の判定（APPROVED / CHANGES_REQUESTED / DISMISSED。後のCOMMENTEDでは消えない）を読み、Request changesが残っていれば止める。GitHubの `reviewDecision` はレビュー必須のブランチ保護があるときだけ値が入るので、補助として読む。通常のPRコメントで届いた指摘は読まないので、steward 8のとおり自分で読む。別のレビューを使うprojectでは、`PR_GATE_REVIEWER` を変えるか、この照合を手で行う。必須checkの名前は `PR_GATE_CHECKS`（既定 `verification,Security Preflight`）で変える。

## pr-review-fixから引き継がないもの

P2の四分類表、定型出力、JEV / Local Judgeの連携、レビュー回数の上限、待機helper一式。最終headの照合だけを `check-pr-head.sh` の1本にまとめた。
