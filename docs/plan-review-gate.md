# Plan Review Gate（計画書Grilling）

## 1. 目的

Plan Review Gateは、ChatGPT等で作成した計画書を親Issue / 子Issueへ変換する前に、実装に必要な重要判断が確定しているかを検証する工程である。

目的は計画書を作り直すことでも、質問を増やすことでもない。実装中にAIが仕様・設計を推測で補完しなければならない状態を減らし、Issue化と実装を安全に開始できるかを判断する。

## 2. 標準位置と責務

Plan Review Gateは、計画書作成後、親Issue / 子Issue化前に置く。

~~~text
相談 / 要件整理
  ↓
計画書作成
  ↓
Plan Review Gate（Grilling）
  ├─ NEEDS_DECISION → Design Decision確定 → 計画書更新 → 再Review
  ├─ PASS → 親Issue / 子Issue化
  └─ NOT_APPLICABLE → 省略理由を記録 → Issue化
~~~

NEEDS_DECISIONの間は、親Issue / 子Issue化および実装開始へ進まない。重大な判断をAIがユーザー未承認のまま確定してはならない。

Plan Review Gateは、既存の 1 Issue / 1 PR、CI、Codex Code Review、P2四分類、人間Merge判断を変更しない。

## 3. Review対象

計画書に次の観点の不足、曖昧さ、暗黙の前提、相互依存を確認する。

- 未決定事項、曖昧な要求、暗黙の前提
- 依存関係、エッジケース、失敗時挙動
- データモデル / 状態モデル
- 外部入力、外部API、DB、filesystem等の境界
- セキュリティ、権限、Secrets
- Deployment設計
- 永続データ、migration、rollback
- 検収方法、成功条件、実利用シナリオ
- 将来拡張と現在Scopeの境界
- 実装中にAIが重大な設計判断を代行しそうな箇所

### 反証レビュー（既存Plan Reviewの一部）

Plan Reviewでは、採用案を正当化するだけでなく、計画が成立しない可能性を先に確認する。次の問いを、計画の規模に応じて簡潔に記録する。

1. この計画が失敗するとしたら、主な原因は何か。
2. 採用案が成立しない条件・前提は何か。
3. 同じ目的を、より単純な代替案で達成できないか。
4. 採用案に不利な証拠、比較対象、既存手法を見落としていないか。
5. 計画が期待する結果を、検証前に前提として扱っていないか。
6. 関連する過去のAcceptance VerificationのPlan vs Reality記録と、そこから得られた教訓を今回計画へ反映したか。

これらは新しいGateや独立した台帳ではなく、既存のPlan Review記録とDesign Decisionの根拠として扱う。

状態・データモデルを含む計画では、Issue #30の設計原則と整合するかを確認する。すなわち、不正状態を構造で表現しにくくすること、外部入力を境界で検証・変換すること、可能な範囲で状態分岐の網羅性を保つことを検討する。ただし、特定言語の高度な型設計を必須化しない。

Deploymentと検収はここで再設計しない。Deploymentの設計項目は `docs/deployment-release-design.md`、実利用検証と検収の項目は `docs/acceptance-verification.md` を参照し、不足があれば既存のDesign Decisionへ戻す。

## 4. 判定

### PASS

実装に必要な重要判断、依存関係、失敗時挙動、成功条件が確定しており、親Issue / 子Issue化へ進める。

### NEEDS_DECISION

実装結果に重大な差を生じる未決定事項がある。Design Decisionで候補案、trade-off、採用案を確定し、計画書を更新してから再Reviewする。

次のような場合はIssue化を止める。

- 保存方式、認証方式、外部APIの責務境界が未決定
- 本番実行環境、データ破壊時の挙動、rollback方針が未決定
- 成功条件が定義されていない
- Scopeの含否で実装構造が変わる
- 状態モデルや主要なデータ構造の選択が未決定

### NOT_APPLICABLE

誤字修正、軽微な文書修正、既存仕様内の明確な局所変更など、重いPlan Reviewを要しない。省略理由を記録する。

単なる命名、局所実装、可逆で低リスクな内部判断まで人間へ戻さない。対象範囲に重大な判断が含まれる場合は、NOT_APPLICABLEで省略しない。

## 5. Design Decision / Escalationとの接続

- **Plan Review Gate**: 実装開始前に、計画書から発見できる曖昧さ・未決定事項を洗い出す。
- **Design Decision**: Plan Reviewで発見した重要な判断について、候補案、trade-off、採用案、懸念点を記録する。Plan Reviewの論点を別の独自台帳へ重複保存しない。
- **Design Decision Escalation**: PASS後の実装中に、計画書・親IssueのDesign Decisionにない新たな重大判断が発生した場合に停止し、人間へ戻す。Plan Reviewが完了していても削除・置換しない。

## 6. 標準出力

~~~markdown
## Plan Review

判定: PASS / NEEDS_DECISION / NOT_APPLICABLE

### 未決定事項
- ...

### 暗黙の前提
- ...

### 反証検証
- 失敗するとしたら主な原因:
- 採用案が成立しない条件・前提:
- より単純な代替案:
- 採用案に不利な証拠・比較対象・既存手法:
- 期待する結果を先取りしていないか:
- 関連する過去のPlan vs Reality記録:
- 今回計画へ反映した教訓:

### 主要リスク / エッジケース
- ...

### Design Decisionへ送る項目
- ...

### Issue化可否
- 可 / 不可
~~~

NEEDS_DECISIONでは未決定事項と推奨案を提示し、Issue化可否を「不可」とする。PASSではDesign Decisionの確定内容を参照し、NOT_APPLICABLEでは省略理由を記録する。

質問が必要な場合も一問一答形式を固定しない。関連する論点をまとめて提示してよい。

## 7. 標準利用方法

計画書を `ai-development` へ渡すときは、次のように依頼する。

> この計画書をNine標準AI開発フローで実装します。まずPlan Review（Grilling）を行い、未決定事項と主要リスクを整理してください。実装可能な場合だけ、既存の親Issue / 子Issueテンプレートへ変換してください。重大な未決定事項がある場合はIssue化を止め、Design Decisionの候補案と推奨案を提示してください。

Plan Review後にIssue化する場合も、親Issue・子Issueの目的、範囲、完了条件、テスト条件、依存関係を既存テンプレートで確認する。Plan Reviewは子Issue品質チェックを置き換えず、Issue登録前の `docs/issue-quality-check.md` による確認も維持する。

## 8. 適用範囲

新規プロジェクト、親Issue / Roadmap、新機能、データモデル・状態管理・外部境界・Deploymentの変更、複数Issueへ影響する設計変更では、原則としてPlan Reviewを実施する。

誤字修正、軽微な文書修正、既存仕様内の単純なバグ修正、明確な局所変更は、軽量確認または `NOT_APPLICABLE` とできる。省略理由を残す。

## 9. やらないこと

- 計画書の自動的な全面書き換え
- AIによる未承認の重大設計の確定
- すべてのIssueへの長い質問セッションの強制
- 一問一答形式の必須化
- 新しいDesign Decision体系や独自台帳の作成
- 既存のDesign Decision Escalation、Deployment設計、Acceptance設計の置換
- 既存プロジェクトへの一括適用
- P2四分類、CI、Codex Review、Merge権限の変更

## 10. 確認ケース

- Storage方式が未決定の新規RAG計画は `NEEDS_DECISION` となり、Issue化を停止する。
- Deployment環境が未決定の場合は、既存Deployment設計を参照してDesign Decisionへ送る。
- 成功条件が曖昧な場合は、Issue化前に検収条件の定義を要求する。
- 複数booleanを前提とした状態モデルでは、構造的な状態表現を検討対象として提示する。
- 単純なREADME誤字修正は `NOT_APPLICABLE` とし、省略理由を記録できる。
- 重要判断が確定した計画書は `PASS` として親Issue / 子Issue化へ進める。
- PASS後の実装中に新たな重大判断が発生した場合は、既存Design Decision Escalationで停止する。
- Plan Reviewの論点を新しい独自台帳へ重複保存せず、Design Decisionへ統合する。
