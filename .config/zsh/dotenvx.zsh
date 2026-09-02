# dotenvx の秘密鍵を 1Password から取り出して渡すラッパー。
#
# 鍵の解決順:
#   1. "dotenvx <owner>"  — ghq パス (github.com/<owner>/<repo>) の owner 単位の鍵
#   2. "dotenvx global"   — 上が無ければこれ
# 鍵は `dotenvx-newkey` で明示的に作る（global は `dotenvx-newkey global`、
# 組織鍵はその組織のリポジトリ内で引数なし）。.env.keys はローカルに残さない。

_dotenvx_owner() {
  local root rel
  root=$(git rev-parse --show-toplevel 2>/dev/null) || root=$PWD
  rel=${root#$(ghq root)/}
  print -r -- "${${rel#github.com/}%%/*}"
}

# 1Password 上の dotenvx タグ付き項目のタイトル一覧。op 自体の失敗（未認証など）は非0で返す
_dotenvx_items() {
  setopt localoptions pipefail
  op item list --vault Private --tags dotenvx --format json | jq -r '.[].title'
}

_dotenvx_field() {  # $1=item $2=label
  op item get "$1" --vault Private --fields "label=$2" --reveal
}

# 使う項目名を出力する。該当なしなら空文字、op の失敗なら非0
_dotenvx_resolve_item() {
  local items owner
  items=$(_dotenvx_items) || return 1
  owner=$(_dotenvx_owner)
  if print -r -- "$items" | grep -qxF "dotenvx $owner"; then
    print -r -- "dotenvx $owner"
  elif print -r -- "$items" | grep -qxF "dotenvx global"; then
    print -r -- "dotenvx global"
  fi
}

# 既存鍵で暗号化させるため、ヘッダが無ければ公開鍵を先頭に書く。
# 別の鍵のヘッダが既にある場合は、鍵の混在を防ぐため失敗させる
_dotenvx_inject_public_key() {  # $1=public key
  local tmp current
  if [[ ! -f .env ]]; then
    printf 'DOTENV_PUBLIC_KEY="%s"\n' "$1" > .env
    return
  fi
  current=$(sed -n 's/^DOTENV_PUBLIC_KEY="\(.*\)"$/\1/p' .env)
  if [[ -n $current ]]; then
    [[ $current == "$1" ]] && return 0
    print -u2 -- "dotenvx: .env is encrypted with a different key; decrypt it with the old key and re-encrypt"
    return 1
  fi
  tmp=$(mktemp .env.XXXXXX) || return 1
  {
    cp -p .env "$tmp" \
      && { printf 'DOTENV_PUBLIC_KEY="%s"\n' "$1"; cat .env; } > "$tmp" \
      && mv "$tmp" .env
  } always {
    [[ -e $tmp ]] && rm -f "$tmp"
  }
}

# 秘密鍵はプロセス引数に載せず、jq の標準入力から渡す
_dotenvx_save_keypair() {  # $1=item $2=private $3=public
  setopt localoptions pipefail
  [[ -n $2 && -n $3 ]] || { print -u2 -- "dotenvx: keypair is empty, not saving '$1'"; return 1; }
  printf '%s\n' "$2" | jq -nR --arg t "$1" --arg u "$3" '{
    title: $t, category: "SECURE_NOTE",
    fields: [
      {id:"private", type:"CONCEALED", label:"DOTENV_PRIVATE_KEY", value:input},
      {id:"public",  type:"STRING",    label:"DOTENV_PUBLIC_KEY",  value:$u}
    ]}' | op item create --vault Private --tags dotenvx - >/dev/null \
    && print -u2 -- "dotenvx: keypair saved to 1Password as '$1'"
}

# owner 用の鍵ペアを新規作成して 1Password に登録する（以後その owner 配下はこの鍵になる）
dotenvx-newkey() {
  local owner=${1:-$(_dotenvx_owner)} items tmp priv pub
  local item="dotenvx $owner"
  items=$(_dotenvx_items) || { print -u2 -- "dotenvx: 1Password lookup failed"; return 1; }
  print -r -- "$items" | grep -qxF "$item" && { print -u2 -- "dotenvx: '$item' already exists"; return 1; }
  tmp=$(mktemp -d) || return 1
  {
    ( cd "$tmp" && : > .env && command dotenvx encrypt -q ) || return 1
    priv=$(sed -n 's/^DOTENV_PRIVATE_KEY=//p' "$tmp/.env.keys")
    pub=$(sed -n 's/^DOTENV_PUBLIC_KEY="\(.*\)"$/\1/p' "$tmp/.env")
    _dotenvx_save_keypair "$item" "$priv" "$pub"
  } always {
    rm -rf "$tmp"
  }
}

dotenvx() {
  local item key pub
  item=$(_dotenvx_resolve_item) || { print -u2 -- "dotenvx: 1Password lookup failed"; return 1; }
  if [[ -n $item ]]; then
    key=$(_dotenvx_field "$item" DOTENV_PRIVATE_KEY) && [[ -n $key ]] \
      || { print -u2 -- "dotenvx: failed to read DOTENV_PRIVATE_KEY from '$item'"; return 1; }
  fi
  case $1 in
    encrypt|set)
      [[ -n $item ]] \
        || { print -u2 -- "dotenvx: no key in 1Password; run 'dotenvx-newkey global' (or 'dotenvx-newkey' for this owner) first"; return 1; }
      pub=$(_dotenvx_field "$item" DOTENV_PUBLIC_KEY) && [[ -n $pub ]] \
        || { print -u2 -- "dotenvx: failed to read DOTENV_PUBLIC_KEY from '$item'"; return 1; }
      _dotenvx_inject_public_key "$pub" \
        || { print -u2 -- "dotenvx: failed to write DOTENV_PUBLIC_KEY header to .env"; return 1; }
      ;;
  esac
  DOTENV_PRIVATE_KEY="$key" command dotenvx "$@"
}
