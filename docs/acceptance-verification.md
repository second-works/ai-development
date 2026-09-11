# 実利用検証・検収標準

## 1. 文書の目的

この文書は、実装・Deployの完了と、実際の利用者が当初の目的を達成できたことを分けて記録するための標準である。

Deployment as Code、Release、Health Check、Smoke Testの詳細は [docs/deployment-release-design.md](deployment-release-design.md) を参照する。この文書は、それらの後に行う実利用検証と検収の責務・記録形式を担当する。

## 2. 状態を分けて扱う

次の状態を同じ「完了」として扱わない。

| 状態 | 判定内容 |
| --- | --- |
| `Implementation Done` | Issue受入条件、標準検証、CI、レビュー、Mergeが完了している |
| `Deployed` | 対象環境へDeployされ、Health Check / Smoke Testが完了している |
| `Product Accepted` | 計画時の目的・成功条件に対して、実利用シナリオを実行し、検収判定が完了している |

`Implementation Done` はコードを正しく作れたか、`Deployed` は対象環境で正常に動くか、`Product Accepted` は作る目的を満たしたかを表す。Codexレビュー指摘がないことや、CI・Smoke Testが成功したことだけでは `Product Accepted` にならない。

Productionという概念が薄いローカル専用アプリでも、実際の利用環境を検証環境として同じ状態分離を適用する。

## 3. 計画時に定義する検収計画

親Issueまたは計画書で、実装前に次の項目を定義する。対象外の項目は省略せず、対象外とする理由を記録する。

- 解決したい課題 / 利用目的:
- 対象ユーザー / 利用者:
- 実利用シナリオ（開始条件から完了まで）:
- 成功条件（利用者が達成できること、測定方法）:
- 失敗条件（検収不可とする条件）:
- 検証環境（Production、Staging、ローカル等）:
- 必要な実データ / fixtureとデータ準備方法:
- 人間確認が必要な項目（UX、操作感、出力の有用性、実データの妥当性等）:
- 検収実施タイミング:
- 検証結果の保存先:
- 計画時の主要予測 / 前提:
- 設計判断の失敗仮説:
- 設計判断が誤りと判断する観測:
- 機能が動いても選択した設計 / 設定に価値がない条件:
- 代替案に対する優位性を確認できない場合の扱い:

設計判断の失敗仮説は、単なる機能不具合だけでなく、選択した設計・設定が目的に寄与しない場合も含める。対象外の項目は省略せず、対象外とする理由を記録する。

計画時に定義していない新要求を、検収時に後付けでAcceptance Blockerへ変更しない。新要求は原則 `IMPROVEMENT` または `FUTURE` として次サイクルで判断する。

## 4. 標準フロー

Health Check / Smoke Testとは別に、利用者として主要ユースケースを最初から最後まで実行する。

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
     ├─ Accepted → 完成 / 運用へ
     └─ Not Accepted / Conditional → 原因分類 → 修正Issue / 改善Issue
```

Stagingを省略する場合は、既存のDeployment設計に従って理由と代替確認方法を記録する。E2Eで自動化できる項目は自動化してよいが、UX、操作感、出力の有用性、実データの妥当性などは人間確認の対象として残す。

MonitoringはPost-deploy Health Check後に開始し、障害時のRollback判断・実行を検収完了まで遅らせない。実利用検証は監視・復旧を妨げない形で行う。


### PRODUCT UI Visual / UI Acceptance（UI LevelがPRODUCTの場合）

Acceptance Verificationに、実利用時のVisual ReviewとUI Acceptanceを統合する。UI LevelはIssueで確定した値を引き継ぎ、検収時に再推測しない。

- \`PRODUCT\`: 下記のVisual Review / UI Acceptanceを適用し、スクリーンショットまたはRender結果と判定を保存する。
- \`UTILITY\`: 主要操作、Loading、Empty、Error + Recovery、Success/feedback、最低限のAccessibilityを確認する。PRODUCT用のVisual Review項目を必須化しない。
- \`NONE\`: UI Acceptanceは対象外とし、対象外の理由を記録する。
- \`NEEDS_DECISION\`: UI Levelの決定までAcceptanceを開始せず、未決定事項と決定期限を記録する。

PRODUCTの検証順序は、機能の動作確認や主観的な自動採点とは分離し、次の順序で記録する。

\`\`\`text
Screenshot / Render
  ↓ Visual Review
  ↓ Fix（指摘がある場合）
  ↓ UI Acceptance
  ↓ Product Acceptance
\`\`\`

Visual Reviewの判定は人間が行い、スクリーンショットやRender結果、対象commit / 環境、指摘と修正結果を証跡として残す。Visual ReviewをCIの主観的な品質ブール値にしない。UI受入を完了しても、実利用シナリオの目的・成功条件を満たしたことを示すProduct Acceptanceにはならない（\`Implementation Done\` != \`UI Accepted\` != \`Product Accepted\`）。

#### PRODUCT Visual Review checklist

- [ ] Primary user flowを開始から完了まで確認した
- [ ] Primary Action clarity（主目的のActionが明確であること）を確認した
- [ ] Navigation（現在地、遷移、戻る操作）を確認した
- [ ] Loading状態を確認した
- [ ] Empty状態を確認した
- [ ] Error + Recovery（失敗理由と復旧手段）を確認した
- [ ] Success/feedback（完了・保存・反映のフィードバック）を確認した
- [ ] Responsive（対象幅でのレイアウトと操作性）を確認した
- [ ] Accessibility minimum（キーボード操作、フォーカス、名前、コントラスト等）を確認した
- [ ] Design consistency（既存UIとの一貫性）を確認した
- [ ] \`docs/design.md\` conformity（Design Profile / design.mdとの整合）を確認した

#### UI状態とAcceptance記録

UI状態は色だけで表現せず、意味の異なる状態を混同しない。少なくとも \`UNKNOWN\` != \`ERROR\`、\`EMPTY\` != \`ERROR\`、\`UNAVAILABLE\` != \`FAILED\` として、画面上の文言・状態名・復旧可能性を記録する。

PRODUCTのAcceptance記録には、既存の検収記録に加えて次を記録する。

- UI Level:
- Acceptance target artifact（画面、主要フロー、対象幅）:
- Screenshot / Render evidence（保存先、取得日時、対象commit / 環境）:
- Visual Review result: \`Accepted\` / \`Not Accepted\` / \`Conditional\`
- UI Acceptance result: \`Accepted\` / \`Not Accepted\` / \`Conditional\`
- Visual Reviewの指摘、Fix内容、再確認結果:
- UI状態（\`UNKNOWN\` / \`EMPTY\` / \`ERROR\` / \`UNAVAILABLE\` を含む）と表示・復旧確認:
- Accessibility minimumの確認結果:
- \`docs/design.md\` conformityの確認結果:
- UI受入対象外の理由（\`NONE\` / \`UTILITY\` の場合）:

Visual ReviewまたはUI Acceptanceが\`Not Accepted\`の場合は、Product Acceptanceを\`Accepted\`にしない。\`Conditional\`の場合は、受入条件、期限、未解決事項を既存の検収記録へ接続する。

## 5. 検収記録

検収結果は、同じ結果を再現・追跡できる場所へ一度だけ保存する。最低限、次を記録する。

- 判定対象のRelease / commit / tag / SHA:
- 検証環境:
- 実利用シナリオ:
- 成功条件ごとの結果と証跡:
- 失敗条件への該当:
- 発見事項:
- 判定: `Accepted` / `Not Accepted` / `Conditional`
- 未解決事項:
- 関連する修正Issue / 改善Issue:

### Plan vs Reality
- 計画時の主要予測 / 前提:
- 実際の結果:
- 失敗した前提:
- 不要または過剰だった設計:
- 予期せぬ問題:
- 次の計画へ反映する教訓:
- 代替案に対する優位性を確認できたか。確認できない場合の判定・扱い:

Plan vs Realityは、実利用検証の結果をProduct Acceptedの記録として残す項目である。機能が動作していても、選択した設計・設定の価値や代替案に対する優位性の確認が計画時の目的・成功条件に含まれる場合、その優位性が確認できなければ `Accepted` とせず、`Conditional`、`Not Accepted`、またはDesign Decision Escalationの対象として理由を記録する。比較が計画上の対象外、または低リスク変更として対象外理由と扱いを事前定義していた場合は、その定義に従って `Accepted` を含む検収判定を行う。 計画時に定義した設計判断の失敗観測または価値なし条件が実利用で成立した場合は、目的・成功条件への重複記載がなくても、検収結果を `Not Accepted` または `Conditional` とし、設計前提そのものの不適合ならDesign Decision Escalationへ接続する。

検収を実施していない場合は、`Not run` と実施できない理由、実施予定のタイミングを記録する。`Conditional` の場合は、受入条件、期限、未解決事項を明記する。

## 6. 発見事項の分類と次の扱い

検収で見つかった事項は、当初の計画と実装済み仕様への影響で分類する。

| 分類 | 判定 | 次の扱い |
| --- | --- | --- |
| `ACCEPTANCE BLOCKER` | 計画時の目的・成功条件を満たさず、検収できない | 原因と影響を整理し、修正Issue / PRとして追跡する |
| `DEFECT` | 実装済み仕様が実利用環境で壊れている | 修正Issue / PRとして追跡する |
| `IMPROVEMENT` | 目的は満たすが、利用後に分かった改善 | 必要性を判断し、別Issue候補として次サイクルへ送る |
| `FUTURE` | 将来拡張または新しい要求 | 元PRへ戻さず、別Issue候補として管理する |

`IMPROVEMENT / FUTURE` を元PRのレビュー修正ループへ戻さない。`ACCEPTANCE BLOCKER / DEFECT` も、Merge済みPRへ無制限に変更を追加せず、原因・影響・対応Issueを明示して追跡可能にする。

## 7. Design Decision Escalation

実利用検証で、技術選定、データ保存方式、UX前提、Deployment構成などの設計前提そのものが目的に適合しないと判明した場合は、局所修正を続けない。

停止 → 原因と影響の整理 → 選択肢と推奨案の提示 → Design Decisionの再判断 → 必要な新Issueの作成、の順で人間へ戻す。既存の `Design Decision Escalation` と `1 Issue / 1 PR`、人間によるMerge判断を維持する。

## 8. 完了チェック

- [ ] `Implementation Done`、`Deployed`、`Product Accepted` を別状態として記録した
- [ ] 計画時に検収計画を定義した
- [ ] 設計判断の失敗仮説と、誤りと判断する観測を定義した
- [ ] 実利用シナリオを実行し、計画時の成功条件と照合した
- [ ] Plan vs Reality（予測、実績、失敗した前提、不要 / 過剰設計、予期せぬ問題、教訓）を記録した
- [ ] Health Check / Smoke Testと実利用検証を分けて記録した
- [ ] `Accepted` / `Not Accepted` / `Conditional` のいずれかで判定した
- [ ] 親Issueを完了扱いにする場合、`Accepted` または受入条件・期限を明記した許容済み `Conditional` である（`Not Accepted` や未解決の `ACCEPTANCE BLOCKER` を残していない）
- [ ] 発見事項を `ACCEPTANCE BLOCKER` / `DEFECT` / `IMPROVEMENT` / `FUTURE` に分類した
- [ ] 改善・新要求を元PRの無限修正ループへ戻していない
- [ ] 必要な修正Issue / 改善Issueを関連付けた
- [ ] 設計前提の誤りをDesign Decision Escalationへ戻した（該当時）
