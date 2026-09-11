# Nine PRODUCT UI Standard v1

## 1. 目的と適用範囲

この標準は、案件ごとのUI設計品質を揃えるための最低契約である。特定の案件の色・フォント・レイアウトや、特定のフロントエンドframeworkを固定するものではない。

案件計画時にUI Levelを宣言する。

| UI Level | 対象 | 適用する契約 |
| --- | --- | --- |
| `NONE` | CLI / API / Batchなど、利用者向けUIを持たない案件 | UI仕様は原則不要。UI関連の受入項目は対象外理由を記録する |
| `UTILITY` | 管理画面、個人ツール、内部ツール | 機能性、現在状態、入力結果、エラーと回復を確認する |
| `PRODUCT` | 一般利用者向けWeb / App | 本文書、UI Specification、Design Profile、`docs/design.md`、Visual/UI Acceptanceを適用する |

UIを持つ可能性があるのに分類できない場合は、AI/Codexが推測せず `NEEDS_DECISION` とする。

## 2. Nine PRODUCT UIの5原則

1. **User Goal First** — 画面ではなく、誰が何を達成すれば完了かを先に定義する。
2. **Current State is Visible** — ユーザーが現在の状態を判断できる。
3. **Next Action is Clear** — 主要画面で次の行動が明確である。
4. **Invalid States are Prevented Structurally** — booleanの組み合わせに頼らず、enum / union / schemaなどで不正状態を作りにくくする。
5. **Implementation Done != UI Accepted** — コード完成とUI/UX検収を分離する。

## 3. PRODUCT UI Specification

### 3.1 User / Context

- Target User
- Primary Goal
- Usage Environment
- Device Priority: `Mobile First | Desktop First | Equal`
- Expected Skill Level

### 3.2 Information Architecture

- Screen List
- Navigation
- Screen Hierarchy
- Entry Point
- Primary Flow
- Exit / Completion Point

主要操作は `Entry -> Action -> Result` を追跡できるようにする。

### 3.3 Screen Specification

主要画面ごとに次を定義する。

- Screen
- Purpose
- Primary User Goal
- Primary Action
- Secondary Actions
- Displayed Information
- Possible States
- Error Recovery
- Next Screen

### 3.4 Required UI States

案件に必要な状態を明示的に区別する。

- `LOADING`
- `READY/NORMAL`
- `EMPTY`
- `SUCCESS`
- `ERROR`
- `DISABLED`
- `UNAVAILABLE/PERMISSION_DENIED`
- `NEEDS_REVIEW`
- `UNKNOWN`

`UNKNOWN != ERROR`、`EMPTY != ERROR`、`UNAVAILABLE != FAILED` とする。状態を色だけで表現せず、文字、アイコン、構造、または説明を併用する。

## 4. Design Profile

PRODUCT案件では、要件とは別に実際の見た目を決めるDesign Profileを作成する。デザインそのものを全案件で固定せず、決定手順と最低品質を固定する。

### 4.1 デザイン決定の優先順位

1. 案件固有のVisual Reference（ユーザー指定URL、スクリーンショット、既存製品、ブランドガイド）
2. Design Research（案件に適した2〜3のDesign Direction）
3. Default Design System（案件固有指定がない場合の候補）
4. AI実装裁量（余白、一般的なレスポンシブ調整、明白なアクセシビリティ改善などの細部）

案件固有のVisual Referenceがある場合は、何を採用し何を採用しないかを記録する。重要なDesign DirectionはHuman Design Decisionで確定する。

### 4.2 Visual Referenceの記録

各Referenceについて、次を記録する。

```md
Reference A: <URL or screenshot>
Use:
- information architecture
- information density
- component hierarchy

Do NOT copy:
- brand colors
- logo
- illustrations
- copyrighted visual assets
```

複数製品の要素を組み合わせる場合も、ブランドや著作物を無批判にコピーしない。

### 4.3 Default Design System

固有のDesign SystemがないWeb PRODUCTでは、技術要件に適合する場合に限り次を候補としてよい。

- React / Next.js
- Tailwind CSS
- shadcn/ui
- Lucide Icons
- Project-specific Design Tokens

これは強制スタックではない。既存技術、案件要件、ブランドDesign Systemを優先する。

## 5. Information Hierarchy

必要に応じて `Summary -> Detail -> Evidence / History / Source` の順で情報を整理する。初期画面には判断とPrimary Actionに必要な情報を優先して表示する。

## 6. Interaction / Feedback

主要操作は次を追跡できるようにする。

`Action -> Processing -> Success/Failure -> Next Action`

長時間処理ではProcessing状態を表示する。削除、取消、上書きなどの危険操作は通常操作と明確に区別し、Confirmationは必要な場合にだけ要求する。

## 7. Responsive Design

PRODUCTは原則レスポンシブ対応とする。単純縮小ではなく、画面幅に応じて情報の優先順位を変える。

小画面でも原則として次を失わない。

- Primary Action
- Current State
- Critical Information
- Error / Recovery Action

## 8. Accessibility Minimum

最低限、次を確認する。

- semantic HTML
- keyboard operation
- explicit labels
- visible focus
- readable typography
- sufficient contrast
- status not represented by color alone

## 9. AI / Codex Design Boundary

Codex/AIは仕様にない重要UX判断を勝手に確定しない。次が未決定の場合は原則 `NEEDS_DECISION` とし、既存のDesign Decisionへ接続する。

- Primary screen structure
- Navigation model
- Primary Action
- Critical user flow
- Destructive action behavior
- Mobile/Desktop priority
- Major Design Direction

一方、承認済みDesign Systemに従う微細なspacing、一般的レスポンシブ調整、明白なアクセシビリティ改善は実装裁量としてよい。

## 10. Visual Review / UI Acceptance

PRODUCTではコードレビューとVisual/UI Reviewを分離する。

```text
Implementation Done
  -> Screenshot / Render
  -> Visual Review
  -> Fix
  -> UI Acceptance
  -> Product Acceptance
```

UI Acceptanceでは最低限、次を確認する。

- Primary user flow
- Primary Action clarity
- Navigation
- Loading
- Empty
- Error + Recovery
- Success/feedback
- Responsive behavior
- Accessibility minimum
- Design consistency
- `docs/design.md` conformity

「画面が表示された」だけではPASSにしない。Visual/UIの主観的品質は決定論的なCI booleanで代替せず、人間確認の証跡を残す。

## 11. 既存標準との整合

- Plan Reviewは [Plan Review Gate](plan-review-gate.md) へ統合し、独立したUI Gateを作らない。
- 検収は [Acceptance Verification](acceptance-verification.md) へ統合し、Implementation、Deploy、Product Acceptanceを混同しない。
- Harnessの追加・変更は [Harness Minimalism / ETCSLV](ai-development-harness-inventory.md) に従う。
- `NONE` に不要なUIチェックを課さず、`UTILITY` にPRODUCT相当の重いVisual Reviewを強制しない。
- 自動検証はsemantic HTML、lint、既知のaccessibility ruleなど決定論的な範囲を優先し、主観的なデザイン品質を自動合否にしない。
- 重要なUX判断、既存状態モデルとの衝突、Design Systemの強制につながる変更はDesign Decisionへエスカレーションする。
