eval "$(mise activate zsh)"
eval "$(starship init zsh)"
eval "$(zoxide init zsh --cmd cd)"
eval "$(atuin init zsh)"

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
