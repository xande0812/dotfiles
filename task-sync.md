# task-sync

複数案件の Nulab Backlog と GitHub に散った自分宛てのタスクを Taskwarrior に集約し、
期限切れ・期限間近を通知するための仕組み。

## 目的

案件ごとにタスク管理ツールが違うと、期限が近いものや着手が遅れているものに気づくのが遅れる。
どのツールにあるタスクでも同じ台帳で「期限順に並べる」「期限切れを出す」ができる状態にする。

台帳は Taskwarrior。選んだ理由は、この仕組みで難しいのが「同期の冪等性」と「遅れの検知」の 2 点で、
Taskwarrior は両方（uuid による import、urgency と overdue）を標準で持っているため。
AI agent には `task export` の JSON を読ませる。

**取得元での操作を置き換えるものではない。** ステータス変更やコメントは Backlog / GitHub 側で行う。

## 構成

| ファイル | 役割 |
|---|---|
| `.config/task/taskrc` | Taskwarrior 設定。データは `~/vault/task/`、同期用 UDA を定義 |
| `.local/bin/task-sync` | bee と gh で取得し、`task import` で取り込む（bun / TypeScript） |
| `.local/bin/task-alert` | 期限切れと期限間近を macOS 通知に出す（zsh） |
| `Library/LaunchAgents/dev.xande.task-sync.plist` | 30 分ごとに `task-sync && task-alert` を実行する launchd agent |
| `~/vault/task/sync.json` | 同期対象の Backlog スペース一覧。案件固有なのでリポジトリには置かない |

### データの流れ

```
bee issue list -a @me  ─┐
gh search issues/prs   ─┴→ 正規化(SourceTask) → ImportRecord → task import → ~/vault/task/
                                                                      └→ task-alert → 通知
```

### 取得対象

- Backlog: `sync.json` に列挙した各スペースで、自分が担当かつ「完了」（status id 4）以外の課題
- GitHub: 自分が assignee の issue と PR、レビュー依頼された PR（`review` タグが付く）

### Taskwarrior 上の表現

| Taskwarrior 属性 | Backlog | GitHub |
|---|---|---|
| `uuid` | URL から uuid v5 で決定的に生成 | 同左 |
| `description` | 課題の件名 | issue / PR のタイトル |
| `project` | プロジェクトキー（課題キーの `-` より前） | `owner/repo` |
| `due` | 期限日のローカル 23:59:59 | なし（GitHub issue に期限フィールドが無い） |
| `entry` | 課題の作成日時 | issue / PR の作成日時 |
| `source`（UDA） | `backlog` | `github` |
| `external_id`（UDA） | 課題キー | `owner/repo#番号` |
| `url`（UDA） | `https://<host>/view/<課題キー>` | issue / PR の URL |

期限を 23:59:59 にしているのは、Taskwarrior が日付だけの `due` を 00:00 と解釈し、
期限日当日の朝から overdue 扱いになるのを避けるため。

### 完了の反映

取得元で閉じた（担当から外れた）タスクは次の取得結果に現れない。
task-sync は「過去に同期した未完了タスク」のうち今回の取得結果に無いものを `completed` にする。
判定に使うのは UDA `source` の有無なので、Taskwarrior で手動作成したタスクは触らない。

この判定は取得結果が完全であることを前提にしている。取得元のどれかが失敗したら取り込み自体を行わず、
GitHub の検索が上限（1000 件）に達した場合も不完全とみなして止める。
それでも取得元の一時的な欠落で誤って完了にした場合、次回の同期でそのタスクは再び取得結果に現れ、
同じ uuid で `pending` として import されるので自動的に戻る。

### 同期されたタスクの編集

`task import` は同じ uuid のタスクを丸ごと置き換える。同期されたタスクに Taskwarrior 側で加えた編集
（annotation、priority など）は次回の同期で消える。編集は取得元で行うこと。

## セットアップ

1. `mise bootstrap` で Taskwarrior（brew `task`）、bee（npm レジストリの `@nulab/bee` を pnpm でインストール）、設定ファイルが入る
2. Backlog スペースごとに `bee auth login`（ホスト名と API キー）。
   認証情報は `$XDG_CONFIG_HOME/.beerc`（この環境では `~/.config/.beerc`）に保存される。
   bee のドキュメントは `~/.beerc` と書いているが、実装は `XDG_CONFIG_HOME` があればそちらを優先する。
   vault の外なので、マシン初期化後は再ログインが必要
3. `~/vault/task/sync.json` を作る

   ```sh
   mkdir -p ~/vault/task
   echo '{ "backlog": { "spaces": ["example.backlog.com"] } }' > ~/vault/task/sync.json
   ```

4. `gh auth login` 済みであること（keyring のトークンを使う）
5. `mise run task-sync-install` で launchd agent を登録する。plist は copy モードなので、
   編集したら `mise bootstrap --only dotfiles` の後にもう一度実行する

## 使い方

```sh
task-sync                 # 手動で同期。add/mod/skip/completed の件数を出す
task-alert                # 期限切れ + 3 日以内を通知
task-alert 7              # 期限切れ + 7 日以内
task next                 # urgency 順
task overdue              # 期限切れ
task due.before:eow list  # 今週中
task source:backlog list  # Backlog 由来だけ
task export               # AI agent に読ませる JSON
```

ログは `~/.local/state/task-sync/` に出る。

### 終了コード

| コマンド | 値 |
|---|---|
| `task-sync` | 0 で成功。bee / gh のいずれかが失敗したら取り込みに入る前に非 0 で止まる。`task import` は 1 件ずつ保存するので、途中で失敗した場合は部分的に反映されるが、次回の正常な同期で収束する |
| `task-alert` | 常に 0 |

## 既知の制約

- GitHub issue には期限フィールドが無いので、GitHub 由来のタスクは `due` を持たない。
  milestone の期限を使うなら `gh search` ではなく GraphQL が必要になるため、必要になった時点で足す
- Backlog の「完了」判定は標準ステータス id 4 に固定している。カスタムステータスで運用上完了扱いのものがあれば
  未完了として残る
- `bee auth status` は JSON を出さないので、スペース一覧は `sync.json` に手で書く。bee にログインしたスペースと
  食い違っていても検出できない
- plist はユーザー名を含む絶対パス（launchd が `~` を展開しないため）
