---
name: pickup
description: Obsidian vault の作業ノート（~/vault/obsidian/claude/work/）を読み込み、以前のセッションの作業を resume なしで再開する。ユーザーが /pickup を実行したとき、または「前の作業の続き」「作業ノートから再開」などと頼んだときに使う。
argument-hint: "[キーワード]"
---

# pickup

`/handoff` で書かれた作業ノートを読み、その作業を引き継ぐ。

- 作業ノートの置き場所: `~/vault/obsidian/claude/work/`
- このセッションの ID: `${CLAUDE_SESSION_ID}`
- 引数: `$ARGUMENTS`

## 1. ノートを選ぶ

1. 作業ノートの frontmatter（`title` `status` `cwd` `updated`）を一覧する。`status: done` は除く
2. 引数があれば、ファイル名・`title`・本文に引数を含むものに絞る
3. 候補が1件ならそれを使う。複数なら、今の作業ディレクトリと `cwd` が一致するものを上にして `updated` の新しい順に並べ、ユーザーに選んでもらう。0件ならそう伝えて終わる

## 2. 読み込んで状態を確かめる

1. ノートを全文読む
2. ノートの `cwd` が今の作業ディレクトリと違う場合、その旨をユーザーに伝える。そのディレクトリで `claude` を起動し直すか、このまま絶対パスで作業するかを聞く
3. ノートの内容が今も正しいかを確かめる。git 管理下なら `git status` と、ノートの `updated` 以降の `git log` を見る。ノートと食い違う点があれば挙げる

## 3. 引き継ぎを記録する

ノートの frontmatter の `sessions` に `${CLAUDE_SESSION_ID}` を追加し、`updated` を今の時刻にする。
`status` が `paused` なら、止まっていた理由が解消したかをユーザーに確認してから `active` に戻す。

## 4. 報告

目的・現状・次の一手を3〜5行に要約してユーザーに伝え、次の一手に着手してよいかを確認する。
ノートに書かれた次の一手を確認なしに実行しない。
