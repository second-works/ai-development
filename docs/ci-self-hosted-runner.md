# CIのself-hosted runner

**Decision: Template CIとSecurityは、所有者のMac mini M2上のself-hosted runnerで実行する。forkからのPRはMacで実行しない。**

[#191](https://github.com/second-works/ai-development/issues/191)。2026-10-19以降、GitHub-hosted runnerは課金・利用上限のためジョブ開始前に失敗している（runner未割当、step 0件）。所有者の指示（2026-10-21）で、CIとSecurityの2本だけを移した。

## 構成

| 項目 | 値 |
| --- | --- |
| ランナー名 | `<LocalHostName>-ai-development` |
| フォルダ | `~/actions-runner-ai-development` |
| `runs-on` | `[self-hosted, macOS, ai-development]` |
| 対象workflow | `ci.yml`（job `verification`）、`security.yml`（job `security-preflight`） |
| 対象外 | `slack-failure-alert.yml`（Secretを持つ通知をMacへ渡さない） |

## 安全境界

- PRのコードは所有者のMacで任意のshellとして動く。両jobは、PRのhead repoがこのrepoと一致するとき（とCIのpush）だけMacで動く。
- forkのPRはjobをskipせず、`runs-on` の式で `ubuntu-latest` へ回す。GitHubは条件でskipしたjobを成功として報告し、必須チェックでもMergeを止めないため。hosted runnerが止まっている間、fork PRのCI・Securityは開始前に失敗し、成功にはならない。hosted runnerの回復か人間の判断を待つ。
- runnerは所有者のOSユーザーで動く。専用ユーザー化は未実施の残存リスクとして扱う。
- ランナーの `.env` は読み書きしない。必要な環境変数はworkflowの `env:` に書く。

## 前提ツール

- Bash 5（Homebrew `/opt/homebrew/bin/bash`）。runnerの `.path` で `/bin` より前にあること。CIの最初のstepでBash 5未満なら失敗させる。
- `/usr/local/bin` のIntel版gitを使わない。登録スクリプトが `.path` から除く。
- Node.jsは `actions/setup-node` が入れる。

## 操作

登録・状態確認・PATH修正・解除は所有者が `register-ci-runner` スキルのスクリプトで行う。登録と解除はトークンを使うため、所有者がターミナルで実行する。

```bash
~/.codex/skills/register-ci-runner/scripts/register-runner.sh second-works/ai-development --status
```

Macが停止・スリープ中はジョブが待機状態のままになる。待機中を成功扱いしない。hosted runnerへ戻す条件（課金回復後）は未決定で、#191で人間が判断する。
