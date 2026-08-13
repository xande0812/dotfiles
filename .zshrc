eval "$(mise activate zsh)"
eval "$(starship init zsh)"

source ~/.config/zsh/ghq-fzf.zsh

alias lg='lazygit'
alias ls='eza'
alias la='eza -a'
alias ll='eza -l --git'
alias lt='eza --tree --level=2'
