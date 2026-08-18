# AGENTS.md

## Purpose

このリポジトリはNine標準AI開発フローと、AIエージェント向け共通開発ルールを管理する。

## Core Rules

- Issueの範囲外を実装しない。
- 不要なリファクタリングをしない。
- 既存動作を壊さない。
- 新規機能・バグ修正には必要なテストを追加する。
- テストを無効化して成功扱いにしない。
- 秘密情報、APIキー、パスワード、`.env` をcommitしない。
- `main`へ直接pushしない。原則としてIssueごとのbranchとPRを使う。
- force pushを行わない。
- 指定外の依存関係を安易に追加しない。
- 公開APIや既存インターフェースを勝手に変更しない。
- 判断不能な仕様は推測で拡張せず、Issue上の仕様を優先する。

## Issue / PR Rule

原則として **1子Issue = 1 PR** とする。

実装前にIssueから以下を確認する。

1. 目的
2. 実装範囲
3. やらないこと
4. 変更可能範囲
5. 変更を避ける範囲
6. 完了条件
7. テスト条件
8. 依存Issue

## Before PR

プロジェクトで定義されている場合、PR作成前に以下を実行する。

- tests
- lint
- type check
- build

失敗した場合は原因を確認し、Issue範囲内で修正する。

## PR Description

PRには最低限以下を書く。

- 対応Issue
- 変更内容
- テスト結果
- 注意点・残課題

## Human Decision Points

以下は人間の判断を優先する。

- 仕様確定
- Issue範囲の変更
- 破壊的変更
- セキュリティ上重要な判断
- mainへのmerge
