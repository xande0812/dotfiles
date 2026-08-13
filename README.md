# dotfiles

macOS の環境を mise で宣言的に再現するための設定一式。

## 方針

- バックアップ対象は `~/vault` のみ。それ以外は消えて良いものとして扱う
- 環境は `mise.toml` から再現する。手作業は下のチェックリストに明示する

## セットアップ

### 1. 前提ツール

```sh
# Xcode Command Line Tools
xcode-select --install

# Homebrew（AeroSpace と sbx のタスクが依存）
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# mise
curl https://mise.run | sh
export PATH="$HOME/.local/bin:$PATH"
```

### 2. このリポジトリ

初回は 1Password がまだ入っていないため HTTPS で clone する。

```sh
mkdir -p ~/vault
git clone https://github.com/xande0812/dotfiles.git ~/vault/dotfiles
cd ~/vault/dotfiles
```

### 3. bootstrap

```sh
mise trust
mise bootstrap --dry-run
mise bootstrap
mise run brew-extras
exec zsh
```

### 4. remote を SSH に切り替え

1Password のセットアップ後に実行する。

```sh
git remote set-url origin git@github.com:xande0812/dotfiles.git
git fetch
```

## 手作業のチェックリスト

bootstrap で自動化できないもの。上から順に。

- [ ] 1Password にサインインする
- [ ] 1Password: 設定 → 開発者 → SSH エージェントを使用 を有効化
- [ ] GitHub 署名鍵を生成する（`mise run git-signing-key`）
- [ ] 出力された公開鍵を https://github.com/settings/keys に **Signing key** として登録
- [ ] AeroSpace にアクセシビリティ権限を付与（システム設定 → プライバシーとセキュリティ → アクセシビリティ）
- [ ] Docker Sandboxes の初回起動と権限付与
- [ ] Google 日本語入力を入力ソースに追加し、ライブ変換などを設定
- [ ] ターミナルのフォントを Moralerspace に変更
- [ ] Raycast の初期設定とホットキー割り当て

## 構成

| 対象 | 管理方法 |
|---|---|
| GUI アプリ・フォント | `[bootstrap.packages]`（mise の brew-cask バックエンド） |
| AeroSpace / Docker Sandboxes | `[tasks]` から brew CLI 経由（タップが API メタデータ未公開のため） |
| CLI ツール | `[tools]`（グローバルは `.config/mise/config.toml`） |
| 設定ファイル | `[dotfiles]` |

### 鍵の使い分け

- 認証（clone / push）: 1Password SSH agent。生体認証あり
- 署名（commit / tag）: Secure Enclave。認証なし

## 検証

半年に一度、初期化リハーサルを行う。手順は上記のセットアップをそのまま実行する。
不足が見つかったらチェックリストか `mise.toml` に反映する。
