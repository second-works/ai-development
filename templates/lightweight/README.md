# 軽量構成

**状態: 標準（#197 で切り替え）。** 新しいprojectにはここから `place.sh` で配置する。このrepo自身も同じ構成を配置して使い、CI の `place.sh --check .` で、repo直下のファイルがここと一致していることを確かめる。限定試行の記録は [lightweight-trial](../../docs/lightweight-trial.md)。

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

既存の設定と未コミットの変更を残したまま置き、今回の差分だけを戻せる（#195）。配置先はgitのrepositoryのrootに限る（戻すための控えを `.git/` の下に置くため、1つのrepositoryに配置先は1つ）。

```bash
templates/lightweight/place.sh --dry-run <project-root>   # 置く内容と差分を表示する。何も書かない
templates/lightweight/place.sh <project-root>             # 置く
templates/lightweight/place.sh --check <project-root>     # 不足・衝突・古いファイルを表示する。何も書かない
templates/lightweight/place.sh --restore <project-root>   # 最後の配置で変えたものだけを戻す
```

**出典の固定。** 候補はこのrepoの1つのcommitから読む。既定はHEADで、候補のファイルに未コミットの変更があれば止める（どのcommitにも対応しないため）。`--ref <commit>` で別のcommitを指定できる。読んだcommitのfull SHAはdry-runの先頭に表示し、配置先の `.ai/lightweight-placement.tsv` には、配置したファイルの中身が最後に変わったときのcommitを記録する（中身が同じなら、新しいcommitから再実行しても記録は変えない）。

**既存のファイルの扱い。** 全部の配置先を一時ディレクトリで組み立ててから書く。1つでも衝突があれば何も書かずに止まる（終了コード1）。

| 配置先 | 既にあるとき |
| --- | --- |
| `AGENTS.md`、`CLAUDE.md` | 末尾に管理ブロック（`<!-- lightweight:begin ... -->` 〜 `<!-- lightweight:end -->`）を足す。ブロックの外は変えない。CLAUDE.mdが既に `@AGENTS.md` を読み込んでいれば、二重に読み込まない。ブロックの中が手で変えられていたり、印が壊れていたりすれば衝突。印には path を書かない（AGENTS.mdのpathが実在するかを検査するprojectがあるため）。古い印（`templates/lightweight/place.sh` と書いていたもの）のブロックがあれば、二重に足さずに衝突 |
| `.claude/settings.json` | 足りないdenyと、pushを止めるフックだけを足す（フックは、Bashに当たるmatcher（`Bash`、`*`、空）の下にあるときだけ、既にあるとみなす）。既存の設定、deny、フックは残す。JSONでない、`permissions.deny` や `hooks.PreToolUse` が配列でない、jqがない場合は衝突 |
| その他のファイル | 同じ内容なら何もしない。前回この配置で置いたままなら更新する。違う内容なら衝突。プロジェクトのファイルを残すには `--keep <path>`（記録され、次回以降も残す） |
| 配置先か親ディレクトリがsymlink（例: `.claude` → `~/.claude`） | 衝突（project外に書くため） |

**再実行と復旧。** 同じcommitでの再実行は何も変えない（控えも作らない）。新しいcommitからの再実行は、変わったファイルだけを更新する。書く前に、変える前の内容を `.git/lightweight-placement/` に控え、変更の記録を書いてからファイルを書く。

- 途中で失敗したり、中断（HUP、INT、TERM）されたりしたら、その回に変えたファイルを元に戻し、作ったファイルとディレクトリを消す。
- 強制終了などで戻せなかった回が残っていれば、次の配置は止まる。`--restore` で戻してから再実行する。
- `--restore` は最後の配置だけを戻す。未コミットの変更も含めて、配置前の内容に戻る。配置の後に手で変えたファイルがあれば、何も戻さずに止まる（控えの場所を表示する）。もう一度実行すると、その前の配置を戻す。
- `.ai/lightweight-placement.tsv` は、配置したファイルの内容の記録。commitしておくと、別のcloneでも更新と `--check` が同じように働く。控え（`.git/lightweight-placement/`）はそのcloneだけにある。

**配置は有効化や検証の成功ではない。** Claude Codeがフックを読み込むのは新しいセッションから。`./scripts/verify.sh`、CI、Security、レビューは別に行う。`--check` もファイルの照合だけで、これらは確かめない（出力の最後にそう表示する）。

**このスクリプトが触らないガード。** `git add` の一括追加の禁止と、秘密情報や生成物のcommit拒否は、ai-project-bootstrapが配る `.ai/GIT_RULES.md` と `.git/hooks/pre-commit` が担う。配置はこの2つを変えない（`--check` は「left as it was」と表示する）。Secretsは、置く `scripts/security-preflight.sh`、`.env` を読ませないdeny、AGENTS.mdのルールでも扱う。

**ai-project-bootstrapとの併用の限界。**

- 古い `.ai/GIT_RULES.md` は「文書だけの変更はmainへ直接コミットしてよい」としていて、置くAGENTS.md（mainへ直接pushしない）と矛盾する。配置時に見つけたら警告し、AGENTS.mdに従う。bootstrap側の正本は2026-10-23に直した（#202）ので、bootstrapの `upgrade` を実行すれば新しい内容に置き換わる。
- bootstrapの `enable-claude` は、`@AGENTS.md` を含むCLAUDE.mdを固定の内容で書き直す。配置の後にbootstrapを動かすと、CLAUDE.mdの管理ブロックが消える。`--check` は「outdated: CLAUDE.md」として示すので、`place.sh` を再実行する。

## ガードの範囲と限界

フックは、Bashのコマンド文字列と、作業ディレクトリのgitの設定だけを見る。シェルの構文解析はしない（親 #192 の方針で、独自の解析器は作らない）。行継続をつなぎ、`;`、`&&`、`|`、改行で区切り（2回目は `$(` と `` ` `` でも区切る）、シェルと同じようにリダイレクト（`>log`、`2>&1` など）を取り除き、引用符とバックスラッシュを外した各部分のうち、gitで始まり、pushがgitのサブコマンドであるものをpushとみなす。commitメッセージやPR本文の中の「push」「main」は対象にしない。

| 止める | 止めない（限界） |
| --- | --- |
| `git push origin main`、`"main"`、`HEAD:'main'`、`refs/heads/main`、行継続で次の行にある宛先 | aliasやスクリプトの中のpush、`bash -c "..."` の中 |
| `--force`、`-f`、`--force-with-lease`、`--mirror`、`+`付きrefspec | `gh` やGitHub APIからの操作、他のツール |
| `--all`、`--branches`、`:`、`*` を含むrefspec | ブランチ削除（`--delete`）、push以外のgit操作 |
| `/usr/bin/git`、`git -C <dir>`、`--git-dir <dir>`、`VAR=1 git`、`env -i`、`then` / `do` / `time` / `command` / `!` / `xargs` / `timeout 60` / `nice` / `sudo -u <user>` の後ろ、`( ... )`、`$( ... )`、`` ` ... ` `` の中 | `git -C <別の場所>` や `cd <別の場所> &&` で別repoを操作する場合のブランチと設定の判定（下の「別のrepoでのpush」） |
| `$` や `` ` `` で組み立てたpush、gitのサブコマンドを変数にしたもの（確かめられないため止める。そのまま書く） | 上記以外の凝った書き方（関数、eval、ヒアドキュメントで渡すスクリプトなど） |
| main / master上での `git push`、jqがない・入力が読めないときのpush | |
| 宛先を書かないpushで、`remote.<name>.push`（main / master、`*`、`:`）、`push.default=matching`、`push.default=upstream` によってmain / masterへ送られるもの | 上記以外のgitの設定（`url.<base>.pushInsteadOf` など） |

**止めすぎることがある。** 引用符の中の `;`、`|`、`$(`、バッククォートも区切りとして扱う。そのため、`git commit -m "note; git push origin main"` や、PR本文のインラインコード（`` --body "use `git push origin main`" ``）のように、メッセージの中で区切りの後ろに「git push … main」が来る形は止まる。安全側の誤検知なので、本文は `--body-file` でファイルから渡すか、メッセージを書き換えて再実行する。

**別のrepoでのpush。** ブランチと設定は、Claude Codeの作業ディレクトリ（セッションを開いたrepo）で判定する。`git -C <別の場所>` や `cd <別の場所> &&` で別のrepoをpushすると、次の2つが起きる。

- 作業ディレクトリのrepoがmain / master上にあると、別repoのfeature branchへの安全なpushも止まる。作業ディレクトリのrepoをIssue branchに切り替えてから実行する（未コミットの変更があって切り替えられないときは、そのrepoでセッションを開き直す）。
- 作業ディレクトリのrepoがfeature branch上にあると、別repoのmain上での宛先を書かない `git push` は止まらない。宛先に `main` / `master` を書いたpushは、文字列で止める。別repoでは、宛先のbranchを必ず書いてpushする。そのrepoにGitHubのブランチ保護がなければ、mainへ入ってしまう。

**フック自体が実行できないときは止まらない。** Claude Codeはexit 2以外のフックの失敗を警告として扱い、コマンドをそのまま実行する。実行権限が外れた、`bash` が見つからない、`$CLAUDE_PROJECT_DIR` が空、といった場合はpushが通る。`settings.json` のdeny（`git push --force` / `-f` で始まるコマンド）はこのときも働くが、main宛ては防げない。

文字列による検出なので、確実な保証にはならない。確実に守るのはGitHubのブランチ保護。ai-developmentのmainは2026-10-22に設定した（#163）。配置先のrepoでは、それぞれ設定を確かめる（privateのrepoは、無料プランでは設定できない）。

`check-pr-head.sh` の正式レビューの判定は、Codex Reviewが書く要約コメント（`codex-review-state:v1`）と、レビュアーごとの最新の判定（APPROVED / CHANGES_REQUESTED / DISMISSED。後のCOMMENTEDでは消えない）を読み、Request changesが残っていれば止める。GitHubの `reviewDecision` はレビュー必須のブランチ保護があるときだけ値が入るので、補助として読む。通常のPRコメントで届いた指摘は読まないので、steward 8のとおり自分で読む。別のレビューを使うprojectでは、`PR_GATE_REVIEWER` を変えるか、この照合を手で行う。必須checkの名前は、projectの `.github/pr-gate-checks`（1行に1つ。`#` で始まる行と空行は無視）に書く。照合は、GitHub上のPRのbaseブランチにある版を読む。手元の未コミットの編集や、照合するPR自身の変更で必須checkを減らせないようにするためで、変更はmergeの後に効く（このファイルの変更は人間のレビュー対象）。`PR_GATE_CHECKS`（カンマ区切り）があればそちらを優先し、ファイルがなければ既定の `verification,Security Preflight` を使う。ファイルを読めないとき（404以外のエラー）は成功にしない。各名前は、check runと、同じheadのcommit status（同じcontext）の両方で探し、どちらかに失敗か実行中があれば止める（Securityの結果をcommit statusで報告するworkflow向け）。commit statusは書き込み権限があれば誰でも作れるので、この照合は誤りを防ぐためのもので、偽装は防がない。

## pr-review-fixから引き継がないもの

P2の四分類表、定型出力、JEV / Local Judgeの連携、レビュー回数の上限、待機helper一式。最終headの照合だけを `check-pr-head.sh` の1本にまとめた。
