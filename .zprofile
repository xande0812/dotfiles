export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_STATE_HOME="$HOME/.local/state"

eval "$(/opt/homebrew/bin/brew shellenv zsh)"
export PATH="$HOME/.local/bin:$PATH"
eval "$(mise activate zsh --shims)"

export FZF_DEFAULT_OPTS="--height=50% --reverse --border"
