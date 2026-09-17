# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## このリポジトリについて

[mise](https://mise.jdx.dev/) で宣言的に管理する個人用 macOS dotfiles。ビルド/テスト/lint パイプラインは無い
——これはアプリケーションではなく設定である。このリポジトリ自体がマシンの環境の正である。変更の妥当性は
テストスイートではなく `mise` コマンドの再実行で確認する。

方針（`README.md` 参照）: バックアップ対象は `~/vault` のみ。それ以外はすべて `mise` からこのリポジトリを
使って再現可能であるべき、使い捨てのものとして扱う。

## アーキテクチャ

`mise.toml` がエントリポイントで、以下4種類の状態を宣言する。

- `[dotfiles]` — リポジトリ内のファイルを `~` 配下にマッピングする。既定モードは `symlink`。実行権限が
  必要なもの（`ssh-sign`、`home-audit`）は `mode = "copy"` を使う。**copy モードのファイルはライブ反映されない**
  ——編集後は `mise bootstrap --only dotfiles` を実行して `~` に反映すること。
- `[bootstrap.packages]` — mise の brew-cask バックエンド経由でインストールする GUI アプリ・フォント。
- `[tasks]` — Homebrew tap が API メタデータを公開していないため `[bootstrap.packages]` に置けず、
  `brew` CLI 経由で直接インストールするツール（AeroSpace、Docker Sandboxes/`sbx`）。
- `[tools]`（`.config/mise/config.toml`、グローバル mise 設定内） — CLI ツールのバージョン
  （bun、starship、lazygit、ghq、fzf、gh）。

リポジトリの構成は `$HOME` を1:1でミラーしている。例: `.config/zsh/ghq-fzf.zsh` は
`~/.config/zsh/ghq-fzf.zsh` に対応し、`.local/bin/home-audit` は `~/.local/bin/home-audit` に対応する。
新しく管理対象のファイルを追加する場合は、対応するリポジトリパスにファイルを置くのと同時に
`mise.toml` の `[dotfiles]` にエントリを追加すること。

### 主なコマンド

```sh
mise trust                        # このリポジトリの mise.toml を信頼する
mise bootstrap --dry-run          # bootstrap の変更内容をプレビュー
mise bootstrap                    # [dotfiles] + [bootstrap.packages] を適用
mise bootstrap --only dotfiles    # [dotfiles] のみ再適用（copy モードのファイルを編集した後に必要）
mise run brew-extras              # bootstrap でカバーされない [tasks] のインストール（aerospace、sbx）
mise run git-signing-key          # commit 署名用の Secure Enclave 鍵を生成
mise run textlint-global          # ~/.config/textlint にグローバル textlint を導入
```

### 2種類の SSH 鍵、2つの用途

- 認証（clone/push）: 1Password SSH agent。生体認証あり（`.ssh/config`）。
- 署名（commit/tag）: Secure Enclave 鍵を `.local/bin/ssh-sign` 経由で使用。認証なし
  （`.gitconfig` の `gpg.ssh.program`）。

SSH/git署名周りの設定を触るときは、これらを混同しないこと。信頼レベルが異なるため意図的に別の仕組みに
なっている。

### home-audit

`.local/bin/home-audit`（copy モードの dotfile）は、`~/vault` の外で更新されたファイルを検出し、
「バックアップ対象は vault のみ」という方針からの逸脱を可視化するツール。設計思想、除外リストの考え方、
既知の失敗モードの詳細は `home-audit.md` に記載されている。スクリプトを変更する前、特に
`EXCLUDES`/`PRUNE_NAMES` を触る前（除外エントリには必ず理由コメントを付けること）や bash の機能を
使う前（macOS 標準の bash 3.2 が対象のため `mapfile`/`readarray` は不可）に読むこと。

### textlint（AI っぽい日本語の検出）

`textlint-rule-preset-ai-words-ja` をグローバルに使うための構成。2つの部分からなる。

- `.config/textlint/` — textlint 専用の pnpm プロジェクト。`mise run textlint-global` で
  `~/.config/textlint` に install する。設定ファイルだけを symlink でマップしているので
  `node_modules` はリポジトリ内に作られない。`.local/bin/textlint-ja` が cwd に関係なく
  この設定で textlint を起動するラッパー。
- `.claude/skills/textlint-ai-words/` — Claude Code の PostToolUse フック。Markdown を書いた
  直後に lint し、検出時は exit 2 で指摘を Claude に返す。

**mise の `npm:` バックエンドは使えない**: textlint はルールパッケージを textlint 自身の
インストール位置から `require.resolve()` で解決するため、本体とルールが同じ node_modules
ツリーに居る必要がある。`npm:` バックエンドはパッケージごとに prefix を分けるので解決できない。

**フックを `~/.claude/settings.json` に書かない理由**: Claude Code 自身が theme/tui/model を
そのファイルに書き戻すため、dotfiles で追跡すると差分が汚れる。代わりに skills-directory
plugin（`~/.claude/skills/<name>/` に `.claude-plugin/plugin.json` を置くと自動ロードされる）
として hooks を持たせている。personal scope なので全プロジェクトに効く。

**preset が `minimumReleaseAge` に引っかかる**: グローバルの pnpm 設定が7日未満のリリースを
拒否するのに対し、この preset は全バージョンが新しい。`.config/textlint/pnpm-workspace.yaml`
でバージョン単位の例外を切っている。詳細はそのファイルのコメントを参照。

### task-sync

Backlog と GitHub の自分宛てタスクを Taskwarrior（データは `~/vault/task/`）に集約する仕組み。
`.local/bin/task-sync`（bun/TypeScript、取り込み）、`.local/bin/task-alert`（zsh、期限通知）、
`.config/task/taskrc`、`Library/LaunchAgents/dev.xande.task-sync.plist`（30 分ごと）で構成される。
設計、Taskwarrior 上の属性の対応、既知の制約は `task-sync.md` に記載されている。
スクリプトの `SourceTask`/`ImportRecord` 型がコントラクトで、UDA を増減するときは taskrc と両方を変えること。
同期対象の Backlog スペース一覧は案件固有なのでリポジトリには置かず `~/vault/task/sync.json` に書く。

