eval "$(mise activate zsh)"
eval "$(starship init zsh)"
eval "$(zoxide init zsh --cmd cd)"
eval "$(atuin init zsh --disable-up-arrow)"

source ~/.config/zsh/ghq-fzf.zsh
source ~/.config/zsh/dotenvx.zsh
source ~/.config/zsh/aws.zsh
source ~/.config/zsh/op.zsh

alias lg='lazygit'
alias ls='eza'
alias la='eza -a'
alias ll='eza -la --git'
alias lt='eza --tree --level=2'
alias dx='dotenvx run --'

# pnpm
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME/bin:"*) ;;
  *) export PATH="$PNPM_HOME/bin:$PATH" ;;
esac
# pnpm end

# pi-coding-agent (xande0812/agent, ghq管理)
export PATH="$(ghq root)/github.com/xande0812/agent/pi-coding-agent/bin:$PATH"
