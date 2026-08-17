eval "$(mise activate zsh)"
eval "$(starship init zsh)"
eval "$(zoxide init zsh --cmd cd)"

source ~/.config/zsh/ghq-fzf.zsh
source ~/.config/zsh/dotenvx.zsh

alias lg='lazygit'
alias ls='eza'
alias la='eza -a'
alias ll='eza -la --git'
alias lt='eza --tree --level=2'
alias dx='dotenvx run --'
