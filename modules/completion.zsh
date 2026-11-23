# Completion owns compinit, styles, fzf-tab, and deferred tool completion.

zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' menu select
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$XDG_CACHE_HOME/zsh"
zstyle ':completion:*' group-name ''
zstyle ':completion:*' use-compctl false
zstyle ':completion:*' verbose false

if [[ -n ${LS_COLORS-} ]]; then
  zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
fi

typeset -g ZSH_COMPDUMP="$XDG_CACHE_HOME/zsh/zcompdump-$ZSH_VERSION"
autoload -Uz compinit
compinit -d "$ZSH_COMPDUMP"

if [[ -r "$MPZ_VENDOR_DIR/fzf-tab/fzf-tab.plugin.zsh" ]]; then
  source "$MPZ_VENDOR_DIR/fzf-tab/fzf-tab.plugin.zsh"
fi

# Bun completion is deferred until the first completion request. The first
# invocation replaces this stub in the parent shell with Bun's own function.
if (( $+commands[bun] )); then
  # Some distributions ship an autoload marker named `_bun`. Replace that
  # marker, but preserve a real user-defined completion function.
  if (( ! $+functions[_bun] )) || [[ ${functions[_bun]-} == *autoload* ]]; then
    _bun() {
      local completion completion_status stub_body
      if (( ! $+commands[bun] )); then
        return 127
      fi

      stub_body="$functions[_bun]"
      completion=$(command bun completions 2>/dev/null)
      completion_status=$?
      if (( completion_status != 0 )) || [[ -z "$completion" ]]; then
        return 1
      fi

      eval "$completion"
      if (( ! $+functions[_bun] )) || [[ "$functions[_bun]" == "$stub_body" ]]; then
        print -u2 -- "_bun: Bun completion did not initialize successfully"
        return 1
      fi
      compdef _bun bun
      _bun "$@"
    }
    compdef _bun bun
  fi
fi
