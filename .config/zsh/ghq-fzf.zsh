function _fzf_cd_ghq() {
  local root repo dir
  root="$(ghq root)"
  repo="$(ghq list | FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS} --reverse --height=50%" \
    fzf --preview="ls -AFG ${root}/{1}")" || return
  [ -z "$repo" ] && return
  dir="${root}/${repo}"
  BUFFER="cd ${(q)dir}"
  zle accept-line
}

zle -N _fzf_cd_ghq
bindkey "^g" _fzf_cd_ghq
