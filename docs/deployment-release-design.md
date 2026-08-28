# Deployment as Code 設計・Release / Production運用標準

## 1. 文書の目的

この文書は、GitHub上の実装完了と、本番投入可能な状態を分けて記録するための設計標準である。

実装PRは、コード・テスト・ドキュメントをGitHub上で完了させる。
本番投入可能とは、対象環境、データ、Secrets、Release判定、Deploy、確認、監視、Rollbackまでの運用経路を決定し、必要な検証を終えた状態を指す。
本番投入を今回行わない場合も、理由と次に判断するタイミングを記録する。

この文書は設計項目と安全条件の正本であり、標準フローは工程順、親Issueテンプレートはプロジェクトごとの決定記録を担当する。Deploy後の実利用検証と検収は [docs/acceptance-verification.md](acceptance-verification.md) を正本とし、Health Check / Smoke Testとは別に扱う。

## 2. 計画時に記録する設計項目

各項目は、採用案だけでなく「不要」と判断した場合の理由も記録する。

| 項目 | 記録する内容 |
| --- | --- |
| Production runtime | 本番の実行環境、OS / platform、公開範囲、想定規模 |
| Container | Docker / Docker Compose等が必要か。不要なら、再現性・運用・対象環境を踏まえた理由 |
| Persistent data | DB、ファイル、vector store、外部ストレージ、backup、logの保存先と、アプリ／コンテナ再作成後も残る仕組み |
| Deployment method | GitHub Actions、self-hosted runner、Cloudflare連携、VPS等の方式、実行主体、権限、承認方法 |
| Release Candidate / artifact identity | commit SHA、artifact ID、image digest等で候補を識別し、Stagingで検証した同一成果物をProductionへ昇格させる方法 |
| Secrets / external services | Secrets、環境変数、外部API／サービス、GitHub Environmentの利用。値そのものは記録しない |
| Backup / migration | 永続データ変更前のbackup、DB / schema / vector migration、失敗時の停止・復旧手順 |
| Post-deploy check | Health Check、Smoke Test、必要なE2E、確認対象、合格条件、失敗時の扱い |
| Rollback | アプリ、設定、schema、vector index、データの互換性を含むRollback単位と実行条件 |

## 3. 標準Release / Production工程

標準順序は次のとおりとする。小規模・ローカルアプリなどでStagingを省略する場合は、Design Decisionに理由と代替確認方法を記録する。

```text
Merge
  ↓ Release Candidate
  ↓ Staging Deploy（必要な場合）
  ↓ E2E / Smoke Test
  ↓ Release判定
  ↓ Production Deploy
  ↓ Post-deploy Health Check
  ↓ Monitoring開始 / Rollback判断
  ↓ 実利用シナリオ検証
  ↓ 計画時の目的・成功条件との照合
  ↓ 検収判定
  ↓ Monitoring / Rollback
```

Mergeは実装の統合であり、Production Deployの自動実行を意味しない。
Production Deployは、CI成功、必要なSecurity Check、Release判定、必要なbackupとmigration確認を満たした後に実行する。
自動承認が適切でない場合は、GitHub Environmentsの`production`などで人間の承認を要求する。

## 4. 環境別の設計判断

### Cloudflare等のマネージド環境

Cloudflare Workers / Pages等でDockerが不要な場合は、Dockerを導入せず、GitHub Actionsまたは公式連携によるDeploy、Secrets、binding、migration、Health Checkを記録する。
Cloudflareを全プロジェクトの必須基盤にはしない。

### Home PC / VPSのWeb・API

self-hosted runnerからDocker / Docker Composeを使う案は候補の一つである。
採用する場合はrunnerの最小権限、実行場所、公開ポート、Secrets、volumeや外部DBの保存先、Deploy失敗時の停止・復旧を記録する。
self-hosted runner、Docker、Compose、Staging、MergeからProductionへの自動Deployを一律に強制しない。

### macOS固有アプリ

macOSアプリやmacOS専用のローカル運用では、Dockerを使わない選択を標準的な候補として扱う。
LaunchAgent、アプリバンドル、ローカルデータ、ログ、更新・Rollback方法など、対象環境に合った運用経路を記録する。

## 5. 永続データとRollback

アプリやコンテナの再作成と、永続データのライフサイクルを分離する。
永続データを持つ場合は、少なくとも保存先、backup頻度・保持期間、復元確認、migrationの前後互換性を記録する。

schema、DB、vector store、indexなどに後方互換性のない変更がある場合は、アプリだけをRollbackしてはならない。
次のいずれかを明示する。

- expand / migrate / contractの段階的移行
- データを含むRollback手順
- 非互換変更をProduction Deploy前に停止する判定

migration失敗時は、後続のDeployやHealth Checkを成功扱いにせず、backupからの復旧または安全な再実行手順へ進む。

## 6. Secrets・安全性の最低条件

- Secrets、APIキー、個人情報、実データをGit、Issue、PR、ログへ書かない
- SecretsはGitHub Secrets、GitHub Environment、対象基盤のSecret管理などから実行時に注入する
- self-hosted runnerは専用アカウント・最小権限・不要な公開ポートなしを基本とする
- Production Deploy前にCIと必要なSecurity Checkを成功させる
- backupが必要な変更では、backup成功をDeployの前提条件にする
- Health Check / Smoke Testの失敗時はRelease失敗として扱い、MonitoringとRollbackへ接続する

Health Check / Smoke Testの成功だけでは、利用者が当初の目的を達成したことを意味しない。Post-deploy後に実利用シナリオを実行し、検収判定と発見事項の分類を行う。具体的な状態、記録項目、`Accepted` / `Not Accepted` / `Conditional` の扱いは [docs/acceptance-verification.md](acceptance-verification.md) に従う。

MonitoringはPost-deploy Health Check後に開始し、障害時のRollback判断・実行を検収完了まで遅らせない。実利用検証はMonitoring / Rollbackを妨げない形で行う。

## 7. Design Decisionとエスカレーション

少なくとも次の判断を、プロジェクトの親Issueまたは設計記録に残す。

- Cloudflare、Home PC、VPS等の実行環境
- Docker / Composeの採否と理由
- self-hosted runnerの採否と権限
- Stagingの要否と省略理由
- 永続データの保存先とbackup
- 自動Deploy・人間承認の境界
- Rollbackの単位とデータ互換性

Issue本文や親IssueのDesign Decisionにない重要な設計判断が実装中に必要になった場合は、Codexは推測で実装せず停止する。
選択肢、推奨案、影響範囲、親Issue更新または追加Issueの要否を提示し、人間の決定後に記録を更新する。
Docker化、Kubernetes導入、全プロジェクトのCloudflare統一、大規模な既存アプリ移行は、このIssueの自動的な完了条件ではない。

## 8. 完了チェック

- [ ] GitHub上の実装完了と本番投入可能を別状態として記録した
- [ ] Production runtime、Container、Persistent dataを記録した
- [ ] Deployment method、Secrets / external servicesを記録した
- [ ] backup、migration、失敗時の復旧を記録した
- [ ] Staging要否、Smoke Test、Release判定を記録した
- [ ] Production Deploy後のHealth Check、Monitoring、Rollbackを記録した
- [ ] データの後方互換性または非互換時の停止・移行方法を確認した
- [ ] CI、Security Check、秘密情報の扱いを確認した
- [ ] 不要とした工程には理由がある
