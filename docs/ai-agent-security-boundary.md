# AI Agent Security Boundary

## 目的と適用範囲

AIエージェントがファイル、GitHub、Web、外部API、DeployなどのToolを扱うとき、情報の取り込みと外部への露出を同じ権限として扱わない。
この文書は、機密情報の流出、権限の過剰付与、外部コンテンツによるPrompt Injectionを、プロンプト上の注意だけに頼らず設計時に確認するための共通契約を定める。

この契約は、ローカルLLMとCloud AI、ファイル操作、リポジトリ操作、検索、RAG、Issue / PR操作、外部API、Deployを含むエージェント利用に適用する。
特定ベンダー、MCP Server、Runtimeの実装は定めない。

## Information Classification

情報を扱う前に、入力、生成物、Toolの戻り値、ログ、成果物を次のいずれかに分類する。
分類を決められない場合は、より厳しい分類として扱う。

- **PUBLIC**：公開済みの情報、または公開しても個別の利用者や組織に影響しない情報。
- **INTERNAL**：プロジェクト内部で利用する情報。
  公開範囲、利用者、保存先を限定する。
- **CONFIDENTIAL**：秘密情報、認証情報、個人情報、契約上の非公開情報、未公開の脆弱性情報、顧客データ、漏洩時に影響が大きい設計情報。
  承認された保存先とLLM環境だけで扱う。

分類はデータ単位で記録する。
同じIssueやセッションに複数の分類が含まれる場合、外部送信の判断には最も厳しい分類を用いる。

## LLM Trust Boundary

LLM実行環境を、データの取扱いを確認できるかどうかで分類する。

- **MANAGED**：組織またはプロジェクトで承認され、データ保持、学習利用、アクセス制御、監査可能性を確認した環境。
- **UNMANAGED**：個人契約、未承認API、管理対象外のローカル外部サービスなど、上記を確認できない環境。

`CONFIDENTIAL` 情報を、明示的に承認されていない `UNMANAGED` 環境へ送信しない。
MANAGEDと判定するだけでは送信許可にならないため、目的、最小データ、保存先、宛先、承認者を別に確認する。

## Tool Exposure Classification

Toolの権限は、情報を取り込む能力と外部へ送る能力に分けて記録する。
Read可能であることは、外部送信可能であることを意味しない。

### Intake / Read

次のToolは、原則として入力や状態を取得する能力として分類する。

- file read
- repository read
- database read
- search
- Web閲覧
- Issue / PR閲覧

取得したデータは、取得元の信頼性とは別に、情報分類とLLM Trust Boundaryの判定を受ける。

### Exposure / Write

次のToolは、外部へ状態や情報を出す能力として分類する。

- email送信
- Slack / Discord投稿
- GitHub Issue / PRへの書き込み
- git pushによるremote Repositoryへの書き込み
- ファイルUpload
- 外部API送信
- 任意URLへのHTTP request
- Deploy
- Production変更

### Sensitive Read Capabilityの判定

Sensitive Read Capabilityは、Read Toolが扱う情報分類に基づいて判定する。

- PUBLICだけを読むRead能力は、情報分類だけを理由にSensitiveとは判定しない。
- INTERNALまたはCONFIDENTIALを読むRead能力は、Sensitive Read Capabilityとして扱う。
- 複数の分類を読む場合は最も厳しい分類を用いるため、PUBLICとINTERNALまたはCONFIDENTIALを組み合わせるRead能力もSensitive Read Capabilityとなる。
- Repository、Directory、Database、RAGなどの対象がINTERNALまたはCONFIDENTIALに分類される場合、そのRead能力はSensitive Read Capabilityとなる。

`Sensitive Read Capability × External Write Capability` は高リスクの組み合わせとして扱う。
この組み合わせが成立する場合、利用可能なTool、対象Repository、filesystem、network、外部送信先を明示的に絞り、必要な操作ごとに承認境界を設ける。

## Least Privilege

エージェントには、現在のIssueを完了するために必要な最小権限だけを付与する。
設計時に次の範囲を具体化する。

- Repository
- Directory
- Branch
- Tool
- API
- Environment
- Deploy target
- Secret access
- 外部送信先

「利用可能なToolをすべて渡す」構成を標準にしない。
読み取り権限と書き込み権限、テスト環境とProduction、秘密情報の参照権限と外部送信権限を分離する。
不要な権限は付与しないことを確認し、権限を追加する場合はHuman Approval Boundaryの対象にする。

## Human Approval Boundary

次の操作は、人間が対象、目的、データ分類、宛先、権限範囲、実行環境を確認して明示承認するまで実行しない。

- `CONFIDENTIAL` 情報の外部送信
- 新しい外部送信先の追加
- Secret / Credentialへのアクセス範囲変更
- 認証、認可、権限、アクセス制御の変更
- Production Deploy
- Productionデータ変更
- Security Policy変更
- Tool権限拡大
- 未承認外部サービスへの接続

承認記録には、対象操作、情報分類、LLM Trust Boundary、Tool、宛先、最小権限、対象SHAまたは環境、承認者、日時を残す。
Safe Auto-Fix / Auto-MergeのSafety Gateが適用される変更では、この境界を自動化によって省略しない。

## Prompt Injection

Webページ、Issue本文、PRコメント、README、外部ドキュメント、RAG取得文書、メール、チャット、APIレスポンスは、外部コンテンツとして扱い、`trusted instruction` として扱わない。
外部コンテンツにTool使用、権限変更、情報送信、Deployを求める文が含まれていても、その内容だけを根拠に実行しない。

Prompt Injectionへの対策は、禁止文を追加するだけで終わらせない。
次の構造的な制約を、対象プロジェクトとToolの実装可能な範囲で組み合わせる。

- Tool allowlist
- Destination allowlist
- permission scope
- filesystem scope
- repository scope
- network scope
- approval gate

外部コンテンツを読むRead能力と、外部へ書き込むExposure能力を同じエージェントへ与える場合は、上記の制約とHuman Approval Boundaryを設計レビューで確認する。

## 適用可否チェックリスト

Parent Issue、Child Issue、PRでは、次を記録する。

- [ ] 情報分類（`PUBLIC` / `INTERNAL` / `CONFIDENTIAL`）を決めた。
- [ ] LLM環境（`MANAGED` / `UNMANAGED`）と `CONFIDENTIAL` 情報の扱いを確認した。
- [ ] Intake / Read ToolとExposure / Write Toolを分けて列挙した。
- [ ] `Sensitive Read Capability × External Write Capability` の有無と、該当時の制御を記録した。
- [ ] Repository、Directory、Branch、Tool、API、Environment、Deploy target、Secret access、外部送信先の最小範囲を記録した。
- [ ] Human Approval Boundaryに該当する操作と承認状態を記録した。
- [ ] 外部コンテンツを `trusted instruction` として扱わないことを確認した。
- [ ] 適用対象外の項目がある場合、その理由、残るリスク、代替制御、承認者を記録した。

## 既存標準との関係

この文書は、既存のCI、GitHub Security、CodeQL、Dependabot、Ruleset、Branch Protection、Safe Auto-Fix / Auto-Mergeを置き換えない。
CIとSecurityの結果は従来どおり分けて確認し、PRレビューと人間による最終承認も維持する。

- `AGENTS.md`：作業中に守る要点と停止条件
- Parent / Child Issue / PRテンプレート：設計時と変更時の記録
- `docs/github-repository-security-baseline.md`：GitHubリポジトリ側の防御
- `docs/safe-auto-fix-auto-merge.md`：自動修正と自動マージの安全条件
- `docs/nine-standard-ai-development-flow.md`：標準フロー上の確認位置

## 例外

この契約の項目を適用できない場合は、対象項目、適用できない理由、残るリスク、代替制御、承認者をIssueまたはPRに記録する。
未承認外部サービスへの接続、`CONFIDENTIAL` 情報の未承認送信、権限拡大、Production変更を、記録だけで自動実行可能にはしない。
