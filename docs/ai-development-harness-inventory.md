# AI開発ハーネス台帳

## 目的

この台帳は、AI開発テンプレートに存在するハーネスの役割、発火条件、実行コスト、重複、安全性、削除または再評価条件を一つの正本で追跡する。
台帳は新しい工程を増やすための一覧ではなく、既存工程を残す、強化する、簡素化する、削除候補にする判断の根拠を記録するために使う。

## Harness Minimalism

ハーネスは、観測された失敗モードまたは既知の重大リスクに対応する場合だけ追加する。
新しいハーネスを追加するときは、少なくとも次を記録する。

- 解決する失敗モード
- 発火条件
- 入力と参照するContext
- 出力と変更するState
- 決定論的な判定へ移せるか
- 実行コストと運用負荷
- 既存ハーネスとの重複
- 安全上の必須性
- 判定（KEEP / STRENGTHEN / SIMPLIFY / REMOVE_CANDIDATE）
- 削除または再評価条件
- 関連Issueと正本文書

モデルやToolの能力が向上した場合も、ハーネスを自動的に残す理由にはしない。
一方で、Security Boundary、Human Approval Boundary、Production保護のように、失敗の発生を待つと被害を防げない制約は、実測コストだけを理由に弱めない。

## 判定の定義

- **KEEP**：現在の失敗モードまたは重大リスクに対して役割が明確であり、現状の境界を維持する。
- **STRENGTHEN**：役割は必要だが、観測可能性、決定論的検証、Context / Stateの引継ぎなどを強化する。
- **SIMPLIFY**：役割を維持しながら、重複する説明、不要な入力、過剰な実行回数、運用負荷を減らす。
- **REMOVE_CANDIDATE**：現在の失敗モードまたは安全上の必要性を確認できず、削除または代替を評価する候補。
  この判定は削除の実行ではなく、依存関係、代替制御、影響範囲を確認するための保留状態である。

## 評価手順

各ハーネスを次の順序で確認する。

1. 失敗モードまたは既知の重大リスクを、Issue、レビュー指摘、失敗テスト、運用記録へ結び付ける。
2. 発火条件、入力、出力、State変更、決定論的判定の可否を記録する。
3. 同じ失敗を別のハーネスも検出していないか確認する。
4. 実行コストと運用負荷を、品質、安全性、追跡可能性の効果と比較する。
5. 判定を決め、削除または再評価の条件を記録する。
6. 判定を変更した場合は、理由と対象SHAまたは実測結果を更新する。

「失敗が観測されていない」ことと「安全上不要である」ことは同じではない。
Security、権限、Productionなどの既知重大リスクは、実際の事故が起きていなくてもKEEPの根拠になる。

## 根拠レコード

- **#56**：今回のETCSLV棚卸しの要求、判定基準、受入条件、テスト観点を定義する監査元Issue。
- **E-01からV-03、およびL-02aからL-02c**：各台帳項目の根拠レコードID。個別の運用事故やレビュー指摘を新たに主張するものではなく、Issue #56の監査条件と各項目の現行正本を追跡するための識別子。
## 主要ハーネスの判定

| ID | ハーネス | ETCSLV | 判定 | 正本または参照 |
| --- | --- | --- | --- | --- |
| E-01 | IssueからPRまでの実行単位 | E | KEEP | AGENTS.md、Issue / PRテンプレート |
| E-02 | Plan Review Gate | E | KEEP | docs/plan-review-gate.md |
| E-03 | Design DecisionとEscalation | E | KEEP | Issueテンプレート、AGENTS.md |
| E-04 | Safe Auto-Fix / Auto-Merge | E | KEEP | docs/safe-auto-fix-auto-merge.md |
| T-01 | CodexとSkills | T | SIMPLIFY | AGENTS.md、.agents/skills |
| T-02 | GitHub Actionsと外部Tool | T | KEEP | .github/workflows、AI Agent Security Boundary |
| C-01 | 正本文書とIssue / PR Context | C | STRENGTHEN | AGENTS.md、docs、Issue / PRテンプレート |
| C-02 | Review Context | C | SIMPLIFY | PRテンプレート、Review Evidence Contract |
| S-01 | Issue、PR、head SHA | S | KEEP | PR、Git履歴、CI結果 |
| S-02 | FOLLOW-UPとDesign Decision履歴 | S | KEEP | docs/review-followups.md、Issue |
| S-03 | Implementation、Deploy、Product Acceptance状態 | S | KEEP | Issue、PR、docs/acceptance-verification.md |
| L-01 | verify.shとCI | L | KEEP | templates/verification、.github/workflows/ci.yml |
| L-02a | Security Preflight | L | KEEP | templates/security、docs/ai-agent-security-boundary.md |
| L-02b | CodeQL | L | KEEP | GitHub Code Scanning、docs/github-repository-security-baseline.md |
| L-02c | Dependabot | L | KEEP | GitHub Dependabot、docs/github-repository-security-baseline.md |
| V-01 | Codex Code Review | V | SIMPLIFY | PRコメント、レビュー履歴 |
| V-02 | Review Evidence ContractとP2収束 | V | KEEP | AGENTS.md、.agents/skills/pr-review-fix |
| V-03 | Acceptance Verification | V | KEEP | docs/acceptance-verification.md |

## 台帳

### E-01 IssueからPRまでの実行単位

- **ETCSLV分類**：Execution
- **解決する失敗モード**：変更がIssueの受入条件から外れること、複数Issueの変更が一つのPRへ混在すること。
- **発火条件**：Issueを実装し、PRを作成するとき。
- **入力 / Context**：Issue本文、Design Decision、依存関係、AGENTS.md。
- **出力 / State変更**：Issue専用branch、PR、CI対象SHA。
- **決定論的判定可能か**：Issue番号、branch、PRの対応は機械確認できる。
- **実行コスト / 運用負荷**：PR作成とCIは必要だが、Issueごとに分けることでレビュー範囲を限定する。
- **重複する仕組み**：該当なし。Issue単位のbranch / PR対応を担う専用の追跡単位であり、他の実行ハーネスと同じ責務を持たない。
- **安全上必須か**：追跡可能性と変更範囲の制御に必要。
- **判定**：KEEP。
- **削除・再評価条件**：IssueとPRの対応を別の機械的な方法で同等以上に追跡できる場合に再評価する。
- **関連Issue / 正本文書**：#56、E-01。Issue #56の監査条件とこの項目の判定を追跡する。 正本：AGENTS.md、Issue / PRテンプレート。

### E-02 Plan Review Gate

- **ETCSLV分類**：Execution
- **解決する失敗モード**：未決定の要件や設計境界を残したままIssue化、実装を開始すること。
- **発火条件**：計画を親Issueまたは子Issueへ変換する前。
- **入力 / Context**：計画書、代替案、判断基準、懸念点、未決定事項。
- **出力 / State変更**：PASS、NOT_APPLICABLE、NEEDS_DECISIONの判定。
- **決定論的判定可能か**：未決定事項の存在は機械補助できるが、設計判断は人間またはレビューで確認する。
- **実行コスト / 運用負荷**：Issue化前の一回のレビュー。Design Decision Escalationとは発火時点が異なる。
- **重複する仕組み**：E-03 Design DecisionとEscalationとは実装前後の発火時点が異なるため重複しない。
- **安全上必須か**：未決定のまま実装を始めないために必要。
- **判定**：KEEP。
- **削除・再評価条件**：計画の未決定事項を同等の証拠でIssue化前に確認できる仕組みが整った場合に再評価する。
- **関連Issue / 正本文書**：#56、E-02。Issue #56の監査条件とこの項目の判定を追跡する。 正本：docs/plan-review-gate.md。

### E-03 Design DecisionとEscalation

- **ETCSLV分類**：Execution
- **解決する失敗モード**：実装中の重要な判断を、Issueの仕様や事前承認なしに独自決定すること。
- **発火条件**：既存のDesign Decisionにない設計境界へ到達したとき。
- **入力 / Context**：Issue、Design Decision、選択肢、影響範囲。
- **出力 / State変更**：停止理由、推奨案、親Issue更新または追加Issueの判断。
- **決定論的判定可能か**：変更範囲の検出は補助できるが、設計判断は決定論的に代替しない。
- **実行コスト / 運用負荷**：通常は発火しない。Plan Reviewは実装前、Escalationは実装中で役割が異なる。
- **重複する仕組み**：E-02 Plan Review Gateとは実装中の設計境界で発火する点が異なるため重複しない。
- **安全上必須か**：仕様のない権限、データ、Production変更を止めるために必要。
- **判定**：KEEP。
- **削除・再評価条件**：設計判断の承認と停止を同等に追跡できる運用へ置き換える場合に再評価する。
- **関連Issue / 正本文書**：#56、E-03。Issue #56の監査条件とこの項目の判定を追跡する。 正本：Issueテンプレート、AGENTS.md。

### E-04 Safe Auto-Fix / Auto-Merge

- **ETCSLV分類**：Execution
- **解決する失敗モード**：軽微な修正を自動化する過程で、認証、Secret、Deploy、Security Policy、権限を変更すること。
- **発火条件**：レビュー指摘を自動修正または自動マージの対象に分類するとき。
- **入力 / Context**：Issue範囲、レビュー指摘、変更差分、CI、Security、レビュー履歴。
- **出力 / State変更**：通常レーンまたはSafeレーンの判定、検証結果。
- **決定論的判定可能か**：変更ファイル、差分、CI結果は機械確認できる。安全性の例外判断は人間の承認を残す。
- **実行コスト / 運用負荷**：適格性確認と再検証が必要。通常のレビュー修正を二重に自動化しない。
- **重複する仕組み**：V-02 Review Evidence Contractと一部のレビュー判定を共有するが、Safeレーン適格性と権限変更の安全判定が固有。
- **安全上必須か**：自動化の権限範囲を制御するために必要。
- **判定**：KEEP。
- **削除・再評価条件**：安全条件、停止条件、監査記録を同等に保証できる自動化へ置換する場合に再評価する。
- **関連Issue / 正本文書**：#56、E-04。Issue #56の監査条件とこの項目の判定を追跡する。 正本：docs/safe-auto-fix-auto-merge.md。

### T-01 CodexとSkills

- **ETCSLV分類**：Tools
- **解決する失敗モード**：モデルの判断だけでは再現できない手順を毎回手作業で再構成すること、同じ処理を複数Skillへ重複実装すること。
- **発火条件**：標準手順を再利用可能なSkillへ切り出すとき。
- **入力 / Context**：Issue、AGENTS.md、対象PR、Skillの契約。
- **出力 / State変更**：実装、レビュー依頼、検証の実行。
- **決定論的判定可能か**：ファイル、branch、SHA、コマンド結果は機械確認できる。Skillを追加する価値は失敗モードと再利用頻度で評価する。
- **実行コスト / 運用負荷**：Skill数が増えるほど参照と更新の負荷が増える。既存Skillで足りる処理を新設しない。
- **重複する仕組み**：V-01 Codex Code ReviewとTool / Skill利用が重なるが、Skillの再利用契約とレビュー判定は別責務。
- **安全上必須か**：個々のSkillは一律に必須ではない。PR修正のSHA管理など、追跡可能性を担う契約は維持する。
- **判定**：SIMPLIFY。
- **削除・再評価条件**：対象Skillに固有の失敗モード、再利用、検証上の効果がなくなった場合にREMOVE_CANDIDATEとして再評価する。
- **関連Issue / 正本文書**：#56、T-01。Issue #56の監査条件とこの項目の判定を追跡する。 正本：AGENTS.md、.agents/skills/pr-review-fix/SKILL.md。

### T-02 GitHub Actionsと外部Tool

- **ETCSLV分類**：Tools
- **解決する失敗モード**：AIエージェントや外部Toolが、許可されていないRepository、network、Secret、Deploy先へアクセスすること。
- **発火条件**：CI、Security、Issue / PR操作、DeployなどのToolを実行するとき。
- **入力 / Context**：Repository、branch、workflow、Tool権限、環境、外部送信先。
- **出力 / State変更**：CI / Security結果、Issue / PR更新、Deployまたは外部状態変更。
- **決定論的判定可能か**：権限scope、対象SHA、workflow結果は機械確認できる。
- **実行コスト / 運用負荷**：CIとSecurityは異なる境界であり、同じ判定として統合しない。
- **重複する仕組み**：L-02a Security PreflightとTool権限境界が重なるが、T-02は外部Tool全般の許可scope、L-02aはPR Security検査の実行状態が対象。
- **安全上必須か**：Least Privilege、Security Boundary、Production保護に必要。
- **判定**：KEEP。
- **削除・再評価条件**：許可範囲、監査、失敗時の停止を同等に保証できるToolへ置換する場合に再評価する。
- **関連Issue / 正本文書**：#56、T-02。Issue #56の監査条件とこの項目の判定を追跡する。 正本：docs/ai-agent-security-boundary.md、GitHub workflow。

### C-01 正本文書とIssue / PR Context

- **ETCSLV分類**：Context
- **解決する失敗モード**：仕様、判断理由、安全条件が複数箇所で不一致になり、エージェントが必要な情報へ到達できないこと。
- **発火条件**：実装、レビュー、テンプレート利用、新規プロジェクト初期化のとき。
- **入力 / Context**：正本文書、AGENTS.md、Parent / Child Issue、PRテンプレート。
- **出力 / State変更**：参照関係、記録された設計判断、適用可否。
- **決定論的判定可能か**：参照先の存在とリンクは機械確認できる。正本の選択は設計判断として記録する。
- **実行コスト / 運用負荷**：全文複製を続けると更新コストが増える。正本と短い参照へ整理する。
- **重複する仕組み**：Issue / PRテンプレートの記入欄と重なるが、C-01は正本と参照の整合、テンプレートは入力入口である。
- **安全上必須か**：仕様と安全条件の一貫性に必要。
- **判定**：STRENGTHEN。
- **削除・再評価条件**：必要なContextをJIT取得でき、正本と参照の整合を契約テストで確認できる状態になった場合に再評価する。
- **関連Issue / 正本文書**：#56、C-01。Issue #56の監査条件とこの項目の判定を追跡する。 正本：AGENTS.md、docs、Issue / PRテンプレート。

### C-02 Review Context

- **ETCSLV分類**：Context
- **解決する失敗モード**：レビュー対象SHA、Issue範囲、受入条件、既存の指摘が不明なままレビューまたは修正を行うこと。
- **発火条件**：PRレビュー、レビュー修正、再レビューのとき。
- **入力 / Context**：PRテンプレートのReview Context、Issue、head SHA、レビュー履歴。
- **出力 / State変更**：レビュー対象、判定根拠、修正範囲の記録。
- **決定論的判定可能か**：SHA、変更ファイル、未解決スレッドは機械確認できる。
- **実行コスト / 運用負荷**：同じIssueとSHAを複数欄へ全文転記すると負荷が増える。必要な識別子と参照へ簡素化する。
- **重複する仕組み**：V-01 Codex Code Reviewと対象SHAを共有するが、C-02はレビュー入力の追跡、V-01はレビュー内容の検証を担う。
- **安全上必須か**：レビューの再現性には必要だが、記録の全文複製は不要。
- **判定**：SIMPLIFY。
- **削除・再評価条件**：対象SHA、Issue範囲、指摘の因果を別の追跡可能な記録で保持できる場合に再評価する。
- **関連Issue / 正本文書**：#56、C-02。Issue #56の監査条件とこの項目の判定を追跡する。 正本：PRテンプレート、Review Evidence Contract。

### S-01 Issue、PR、head SHA

- **ETCSLV分類**：State
- **解決する失敗モード**：古いCI、Security、レビュー結果を新しい差分へ誤って適用すること。
- **発火条件**：commit、push、レビュー依頼、CI / Security待機、マージ確認の各時点。
- **入力 / Context**：Issue番号、PR番号、branch、head SHA、base SHA。
- **出力 / State変更**：対象SHAごとの検証記録、merge状態。
- **決定論的判定可能か**：SHA、CI、Security、PR状態は機械確認できる。
- **実行コスト / 運用負荷**：SHAの照合は各trust boundaryで必要。別工程の結果を一つにまとめない。
- **重複する仕組み**：L-01 CI、L-02a Security、V-01 ReviewとSHAを共有するが、S-01は各結果を同一SHAへ結び付けるState管理である。
- **安全上必須か**：古い検証結果の誤使用を防ぐために必要。
- **判定**：KEEP。
- **削除・再評価条件**：検証結果と差分の同一性を同等に証明できる仕組みへ置換する場合に再評価する。
- **関連Issue / 正本文書**：#56、S-01。Issue #56の監査条件とこの項目の判定を追跡する。 正本：PR、Git履歴、CI結果。

### S-02 FOLLOW-UPとDesign Decision履歴

- **ETCSLV分類**：State
- **解決する失敗モード**：未対応事項や設計判断の理由がセッションを跨いで失われ、同じ調査や判断を繰り返すこと。
- **発火条件**：今回PRの範囲外に残す指摘、設計判断、次Issueを登録するとき。
- **入力 / Context**：レビュー指摘、Issue、設計判断、対象PR。
- **出力 / State変更**：FOLLOW-UP台帳、親Issueまたは追加Issueへの参照。
- **決定論的判定可能か**：台帳項目、Issue番号、PR番号は機械確認できる。
- **実行コスト / 運用負荷**：登録と参照が必要。Issue本文、PR本文、台帳へ同じ説明を全文複製しない。
- **重複する仕組み**：レビューコメントとIssueの記録が重なるが、S-02は範囲外事項と設計判断の継続履歴を保持する。
- **安全上必須か**：未対応を消失させず、修正範囲を広げないために必要。
- **判定**：KEEP。
- **削除・再評価条件**：IssueとPRの状態から未対応事項を漏れなく復元できる場合に再評価する。
- **関連Issue / 正本文書**：#56、S-02。Issue #56の監査条件とこの項目の判定を追跡する。 正本：docs/review-followups.md、Issue。

### S-03 Implementation、Deploy、Product Acceptance状態

- **ETCSLV分類**：State
- **解決する失敗モード**：実装済み、マージ済み、Deploy済み、利用者が受入済みを同じ完了状態として扱うこと。
- **発火条件**：PRマージ、Deploy、実利用検証、検収のとき。
- **入力 / Context**：Issue受入条件、PR、Release Candidate、環境、実利用シナリオ。
- **出力 / State変更**：Implementation Done、Deployed、Product Acceptedなどの独立した記録。
- **決定論的判定可能か**：PRマージ、Deploy結果、検証実行は機械確認できる。利用者の受入は人間確認を記録する。
- **実行コスト / 運用負荷**：状態を分けるための記録負荷があるが、工程の取り違えを防ぐ。
- **重複する仕組み**：V-03 Acceptance Verificationと状態確認が重なるが、S-03はImplementation / Deploy / Acceptedの状態分離、V-03は利用者受入の検証を担う。
- **安全上必須か**：Production変更と利用者受入を混同しないために必要。
- **判定**：KEEP。
- **削除・再評価条件**：状態遷移を同等以上に表現できる構造化Stateへ移行する場合に再評価する。
- **関連Issue / 正本文書**：#56、S-03。Issue #56の監査条件とこの項目の判定を追跡する。 正本：Issue、PR、docs/acceptance-verification.md。

### L-01 verify.shとCI

- **ETCSLV分類**：Lifecycle Hooks
- **解決する失敗モード**：ローカルで成功した変更が、独立環境でlint、型、test、buildに失敗すること。また、AI開発ハーネス台帳の必須スキーマ欠落、必須フィールドの欠落または重複、集約表と詳細レコードの不一致を受け入れること。
- **発火条件**：PR作成前とPR更新後、GitHub Actions実行時。tests/harness-minimalism/run-samples.sh は台帳または関連テンプレートを変更するPRで実行する。
- **入力 / Context**：Repository、変更差分、標準検証入口、依存関係、docs/ai-development-harness-inventory.md、AGENTS.md、Issue / PRテンプレート。
- **出力 / State変更**：CI結果、検証ログ、merge可否に使う状態。台帳契約違反がある場合はCIを失敗させる。
- **決定論的判定可能か**：lint、type check、test、build、台帳の必須フィールド、フィールド重複、集約表と詳細レコードのID・ETCSLV分類・判定一致は決定論的に判定する。
- **実行コスト / 運用負荷**：ローカルとCIは異なるtrust boundaryであり、同一結果として省略しない。台帳契約テストはShell、awk、grepによる軽量な1 CIステップで、外部サービスや追加依存を必要としない。
- **重複する仕組み**：CIはPR検証、verify.shはローカル入口で役割が異なる。tests/harness-minimalism/run-samples.sh は通常のlint、型、test、buildでは検出しない台帳スキーマと集約表の整合性を対象とし、L-02a SecurityはSecurity Boundaryを検証するため、いずれも通常CIの品質検証を代替しない。
- **安全上必須か**：変更の機械的な再検証と、ハーネス追加・変更時の追跡可能性を維持するために必要。Security Boundary、Human Approval Boundary、Production保護の代替ではない。
- **判定**：KEEP。
- **削除・再評価条件**：台帳スキーマ、必須フィールドの一意性、集約表と詳細レコードの整合性を、同等の独立検証環境と再現可能な結果で保証する仕組みへ置換する場合に再評価する。
- **関連Issue / 正本文書**：#56、L-01。Issue #56の監査条件とこの項目の判定を追跡する。 正本：templates/verification、.github/workflows/ci.yml、tests/harness-minimalism/run-samples.sh、docs/ai-development-harness-inventory.md。

### L-02a Security Preflight

- **ETCSLV分類**：Lifecycle Hooks
- **解決する失敗モード**：通常CIの成功だけで、Repository、Secret、Tool権限、外部送信先に関するSecurity Boundaryの逸脱や、利用可能なセキュリティ検査の失敗を見逃すこと。
- **発火条件**：PR更新時にSecurity workflowまたはPR単位のSecurity Preflightを実行するとき。
- **入力 / Context**：対象SHA、Git管理対象、workflow、Tool権限、Secretの扱い、外部送信先。
- **出力 / State変更**：Security Preflightの成功、警告、失敗、未実行の状態。利用不能を成功扱いにしない。
- **決定論的判定可能か**：workflowの実行状態、対象SHA、許可されたscopeは機械判定できる。利用可否や例外は記録して判断する。
- **実行コスト / 運用負荷**：PR更新ごとの独立した検査。CIやCodeQL、Dependabotの結果を代用しない。
- **重複する仕組み**：L-02b CodeQLとL-02c Dependabotとは検出対象が異なる。L-02aはSecurity Boundary、権限scope、PR検査の実行状態を対象とする。
- **安全上必須か**：Security Boundary、Least Privilege、Human Approval、Production保護を維持するために必要。
- **判定**：KEEP。
- **削除・再評価条件**：対象SHA、許可範囲、失敗時停止、監査記録を同等以上に保証するSecurity機構へ移行する場合に再評価する。
- **関連Issue / 正本文書**：#56、L-02a。Issue #56の監査条件とこの項目の判定を追跡する。 正本：templates/security、docs/ai-agent-security-boundary.md。

### L-02b CodeQL

- **ETCSLV分類**：Lifecycle Hooks
- **解決する失敗モード**：コードのデータフロー、Injection、権限処理などの脆弱性を、通常CIやSecurity Preflightの成功だけで見逃すこと。
- **発火条件**：CodeQLが対象言語とRepositoryで有効化され、PR、push、またはスケジュールの解析を実行するとき。
- **入力 / Context**：対象SHA、対象言語のソースコード、ビルド設定、CodeQL query suite、解析環境。
- **出力 / State変更**：Code Scanningの解析結果、アラート、PRへのチェック状態。
- **決定論的判定可能か**：対象SHA、解析結果、チェック状態は機械判定できる。CodeQLが利用不能または未設定の場合は成功扱いにしない。
- **実行コスト / 運用負荷**：言語解析と必要なビルドの実行負荷がある。対象言語、解析時間、失敗率を測定して再評価する。
- **重複する仕組み**：L-02a Security PreflightとL-02c Dependabotとは検出対象が異なる。L-02bはソースコードとデータフローの解析を対象とする。
- **安全上必須か**：コード上の既知の脆弱性を検出するために必要。利用不能時の扱いも安全条件として維持する。
- **判定**：KEEP。
- **削除・再評価条件**：対象言語、exact SHA、失敗時の停止、解析結果の監査を同等以上に保証するコード解析へ移行する場合に再評価する。
- **関連Issue / 正本文書**：#56、L-02b。Issue #56の監査条件とこの項目の判定を追跡する。 正本：GitHub Code Scanning、docs/github-repository-security-baseline.md。

### L-02c Dependabot

- **ETCSLV分類**：Lifecycle Hooks
- **解決する失敗モード**：依存パッケージの既知脆弱性や更新漏れを、アプリケーションCIやCodeQLの成功だけで見逃すこと。
- **発火条件**：Dependency Graphがmanifestまたはlockfileを解析し、Dependabot alertまたは更新PRを生成するとき。
- **入力 / Context**：対象Repository、manifest、lockfile、Dependency Graph、脆弱性データ、更新ポリシー。
- **出力 / State変更**：Dependabot alert、更新PR、依存更新のレビュー対象。
- **決定論的判定可能か**：対象manifest、alert、更新PR、更新元の脆弱性情報は機械確認できる。Dependency Graphや脆弱性データが利用不能な状態は成功扱いにしない。
- **実行コスト / 運用負荷**：依存解析と更新PRのレビュー負荷がある。alert件数、更新PR数、対応時間を測定して再評価する。
- **重複する仕組み**：L-02a Security PreflightとL-02b CodeQLとは検出対象が異なる。L-02cはmanifest / lockfileと依存脆弱性を対象とする。
- **安全上必須か**：依存由来の既知脆弱性を管理するために必要。自動更新PRの採用は人間レビューとCIを経る。
- **判定**：KEEP。
- **削除・再評価条件**：Dependency Graph、脆弱性情報、更新PR、レビュー記録を同等以上に保証する依存管理機構へ移行する場合に再評価する。
- **関連Issue / 正本文書**：#56、L-02c。Issue #56の監査条件とこの項目の判定を追跡する。 正本：GitHub Dependabot、docs/github-repository-security-baseline.md。

### V-01 Codex Code Review

- **ETCSLV分類**：Verification
- **解決する失敗モード**：CIでは表現できないIssue受入条件、仕様、レビュー観点の漏れを見落とすこと。
- **発火条件**：CI成功後、PRの対象SHAでレビューを依頼するとき。
- **入力 / Context**：Issue、PR差分、AGENTS.md、対象SHA、既存レビュー。
- **出力 / State変更**：レビュー結果、コメント、レビュー対象SHA。
- **決定論的判定可能か**：レビューの実行履歴と対象SHAは機械確認できる。内容の妥当性は人間が確認する。
- **実行コスト / 運用負荷**：CIの代替ではない。レビュー後に新規改善探索を無制限に繰り返すとコストだけが増える。
- **重複する仕組み**：L-01 CIとは仕様・受入条件の意味検証が異なる。C-02 Review Contextとはレビュー入力と判定の責務が異なる。
- **安全上必須か**：Issue仕様と差分の対応を独立に確認するために必要。
- **判定**：SIMPLIFY。
- **削除・再評価条件**：Issue受入条件、仕様、Security、変更因果を同等に検証できる別のレビュー契約が成立した場合に再評価する。
- **関連Issue / 正本文書**：#56、V-01。Issue #56の監査条件とこの項目の判定を追跡する。 正本：PR、AGENTS.md、レビュー履歴。

### V-02 Review Evidence ContractとP2収束

- **ETCSLV分類**：Verification
- **解決する失敗モード**：Severityだけで指摘をBlocking扱いすること、P2修正で無制限の修正ループへ入ること。
- **発火条件**：P0、P1、P2、P3のレビュー指摘を分類し、修正または記録するとき。
- **入力 / Context**：Finding、成立条件、PR因果、受入条件、再現手順、対象SHA。
- **出力 / State変更**：BLOCKING、IN-SCOPE FIX、FOLLOW-UP、DISMISS、レビュー収束状態。
- **決定論的判定可能か**：必須項目、対象SHA、未解決スレッドは機械確認できる。因果と受入条件はレビューで確認する。
- **実行コスト / 運用負荷**：記録負荷はあるが、P2の追加修正ループを制限する。
- **重複する仕組み**：V-01 Codex Code Reviewから指摘を受けるが、V-02はSeverity、因果、収束分類と記録を担い、レビュー実行を代替しない。
- **安全上必須か**：誤った修正範囲拡大と見逃しを分けるために必要。
- **判定**：KEEP。
- **削除・再評価条件**：同じ証拠、分類、停止、再レビューを同等に保証する契約へ移行する場合に再評価する。
- **関連Issue / 正本文書**：#56、V-02。Issue #56の監査条件とこの項目の判定を追跡する。 正本：AGENTS.md、.agents/skills/pr-review-fix。

### V-03 Acceptance Verification

- **ETCSLV分類**：Verification
- **解決する失敗モード**：実装やDeployが成功しただけで、利用者の目的を達成したと判断すること。
- **発火条件**：ReleaseまたはProduction Deploy後、検収を実施するとき。
- **入力 / Context**：利用目的、対象ユーザー、実利用シナリオ、成功条件、実データ、環境。
- **出力 / State変更**：Accepted、Not Accepted、Conditional、発見事項の分類。
- **決定論的判定可能か**：開始条件、成功条件、環境は検証できる。利用者の有用性は人間が確認する。
- **実行コスト / 運用負荷**：Deploy確認とは別工程。受入条件を同じ文面で複数文書へ複製しない。
- **重複する仕組み**：S-03 Implementation / Deploy状態と関係するが、V-03は利用者目的の実利用検証であり、状態記録を代替しない。
- **安全上必須か**：Product Acceptanceを実装完了と混同しないために必要。
- **判定**：KEEP。
- **削除・再評価条件**：利用者の目的と成功条件を同等に確認できる運用へ移行する場合に再評価する。
- **関連Issue / 正本文書**：#56、V-03。Issue #56の監査条件とこの項目の判定を追跡する。 正本：docs/acceptance-verification.md。

## 削除候補と簡素化候補

今回の棚卸しでは既存ハーネスを削除しない。
次の候補は、失敗モード、代替制御、実測コストを確認してから別PRまたは別Issueで判断する。

| 候補 | 判定 | 条件 |
| --- | --- | --- |
| 同じ運用ルールをAGENTS.md、標準フロー、Skillへ全文複製する説明 | SIMPLIFY | 正本文書を決め、参照と各工程固有の停止条件へ整理できること。 |
| 観測された失敗を追加せずに増やす補助Skillや追加レビュー | REMOVE_CANDIDATE | 対象失敗モード、再利用、Security上の必要性を示せないこと。 |
| 同じtrust boundaryで繰り返す重複検証 | REMOVE_CANDIDATE | 同一SHA、同一入力、同一環境であることを確認し、別の境界を失わず統合できること。 |
| レビュー後に新規改善探索へ戻る追加修正ループ | REMOVE_CANDIDATE | BLOCKINGでなく、今回Issueの受入条件やPR差分に因果がないこと。 |

## 新規ハーネスの記録様式

新しいハーネスを追加するPRでは、次の項目をPR本文とこの台帳へ記録する。

```text
Harness ID:
名称:
ETCSLV分類:
解決する失敗モード:
発火条件:
入力 / Context:
出力 / State変更:
決定論的判定可能か:
実行コスト / 運用負荷:
重複する仕組み:
安全上必須か:
判定: KEEP / STRENGTHEN / SIMPLIFY / REMOVE_CANDIDATE
削除・再評価条件:
関連Issue / 正本文書:
```

既存ハーネスを変更する場合も、変更理由、対象SHA、検証結果、削除または再評価条件を記録する。
記録できない新しいハーネスは、実装へ追加する前に停止して設計判断を確認する。

## モデル更新時の再評価

モデル、Codex、GitHub Actions、Toolの能力が変わったときは、次を確認する。

- 既存ハーネスが解決している失敗モードが現在も成立するか。
- モデルだけでは得られないContext、State、権限境界を補っているか。
- 決定論的なtest、type、lint、CI、Security ruleへ移せるか。
- 実行時間、API利用量、レビュー回数、運用負荷が変化したか。
- 安全上必要な制約を弱めずに簡素化できるか。
- 判定変更の根拠、実測結果、対象環境、対象SHAを記録したか。

再評価は、能力向上だけを理由に削除を決めない。
失敗モード、代替制御、実測結果、Securityと人間承認の境界を確認してから判定を更新する。

## 既存標準との関係

この台帳は、Issue、Design Decision、CI、Security、Codex Review、Review Evidence Contract、Safe Auto-Fix / Auto-Merge、Deployment、Product Acceptanceを置き換えない。
各工程の正本は既存文書に置き、台帳には役割、判定、重複、コスト、再評価条件を記録する。

- AGENTS.md：作業時の共通ルール
- docs/nine-standard-ai-development-flow.md：工程の流れ
- docs/ai-agent-security-boundary.md：AIエージェントの情報とToolの境界
- docs/safe-auto-fix-auto-merge.md：自動修正の安全条件
- docs/github-repository-security-baseline.md：GitHub側の防御
- docs/acceptance-verification.md：実利用検証と検収
