# ~/vault/.envs/<name>.env (op:// 参照込み) を op run で解決し、注入した状態でコマンドを実行する。
# 例: opr loomdebug -- ecsk exec
opr() {
  emulate -L zsh

  local name="$1"
  shift
  [[ "$1" == "--" ]] && shift
  if [[ -z "$name" || $# -eq 0 ]]; then
    print -u2 "usage: opr <env-name> -- <command> [args...]"
    return 1
  fi

  local env_file="$HOME/vault/.envs/${name}.env"
  if [[ ! -f "$env_file" ]]; then
    print -u2 "opr: env file not found: $env_file"
    return 1
  fi

  # .envs/*.env はアクセスキーのみで region を持たないことが多いので、
  # 未設定ならデフォルトを補う (ファイル側で AWS_REGION を定義すれば上書きされる)。
  AWS_REGION="${AWS_REGION:-ap-northeast-1}" op run --env-file="$env_file" -- "$@"
}
