# --- Prompt ---
eval "$(starship init zsh)"

# --- Zinit Plugin Manager ---
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
if [ ! -d "$ZINIT_HOME" ]; then
   mkdir -p "$(dirname $ZINIT_HOME)"
   git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi
source "${ZINIT_HOME}/zinit.zsh"

# --- Completion ---
autoload -Uz compinit
compinit -d ~/.zcompdump-$HOST

# WP-CLI completion (requires wp-completion.bash to exist)
# if [ -f ~/.wp-cli/wp-completion.bash ]; then
#   source ~/.wp-cli/wp-completion.bash
# fi

# --- Plugins via zinit ---
zinit light zsh-users/zsh-autosuggestions
zinit light zsh-users/zsh-completions
zinit light Aloxaf/fzf-tab
zinit light zsh-users/zsh-syntax-highlighting

# --- History ---
HISTFILE=~/.histfile
HISTSIZE=10000
SAVEHIST=$HISTSIZE
HISTDUP=erase

# History behavior options
setopt APPEND_HISTORY           # append to the history file, don’t overwrite it
setopt SHARE_HISTORY            # share command history across all sessions
setopt HIST_IGNORE_ALL_DUPS     # ignore duplicate commands in history
setopt HIST_IGNORE_DUPS         # ignore consecutive duplicate commands
setopt HIST_IGNORE_SPACE        # don't record commands that start with a space
setopt HIST_SAVE_NO_DUPS        # don't write duplicate entries to the history file
setopt HIST_FIND_NO_DUPS        # do not display duplicates during history search
# setopt HIST_REDUCE_BLANKS       # remove extra spaces from commands

# --- Zsh Options ---
setopt autocd extendedglob nomatch
bindkey -e

# --- Completion styling ---
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'ls --color $realpath'

# --- Aliases ---
# exa/ls
if command -v exa >/dev/null 2>&1; then
  alias ls='exa --color=always --group-directories-first'
  alias ll='exa -lh --group-directories-first'
  alias la='exa -lha --group-directories-first'
  alias lt='exa -lT --level=2 --group-directories-first'   # Tree view
  alias lg='exa -l --git --group-directories-first'        # Git info
else
  alias ls='ls --color=auto'
  alias ll='ls -lhF --color=auto'
  alias la='ls -la --color=auto'
  alias l='ls -CF --color=auto'
fi

# Common navigation
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias df='df -h'
alias du='du -h'
alias vim='nvim'
alias c='clear'

# --- Keybindings ---
bindkey '^R' history-incremental-search-backward
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward
bindkey '^[w' kill-region

# --- Environment ---
export EDITOR="nvim"
export VISUAL="nvim"
export PAGER="less"

# --- Path ---
export PATH="$HOME/.local/bin:$PATH"

# --- Golang ---
export GOPATH="$HOME/go"
export GOBIN="$GOPATH/bin"
export PATH="$GOBIN:$PATH"

# --- fzf and zoxide integration ---
if command -v fzf >/dev/null 2>&1; then
  eval "$(fzf --zsh)"
fi
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init --cmd cd zsh)"
fi