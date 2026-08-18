---
name: Child Issue
description: 1 PR単位でCodexに実装させる子Issue
title: "[Task] "
labels: []
assignees: []
---

# 目的

<!-- このIssueだけで達成すること -->

# 実装内容

- [ ] 

# やらないこと

- Issue範囲外の機能追加
- 不要なリファクタリング
- 指定外の依存関係追加
- 既存API仕様の無断変更
- テストの無効化
- force push

# 変更してよい範囲

```text
path/to/allowed/**
```

# 原則変更しない範囲

```text
path/to/protected/**
.env
```

<!-- 変更が不可避なら理由を明記する -->

# 完了条件

- [ ] 指定機能が実装されている
- [ ] 既存テストが成功する
- [ ] 必要な新規テストが追加されている
- [ ] lint / type check / buildのうち定義済みのチェックが成功する
- [ ] 秘密情報を含まない
- [ ] PRが作成されている

# テスト

```bash
# プロジェクトに合わせて記入
```

# 依存関係

- Parent: #
- Depends on: #

# Codexへの追加指示

Issue記載内容を仕様の基準とする。仕様だけでは判断できない重大な問題がある場合、推測で範囲を拡張しないこと。
