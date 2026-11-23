# The final keymap is the single enforcement point for reserved keys.

_mpz_bind_all() {
  local sequence="$1"
  local widget="$2"
  local keymap
  for keymap in emacs viins vicmd; do
    bindkey -M "$keymap" "$sequence" "$widget"
  done
}

if (( $+functions[_atuin_search] )); then
  bindkey -M emacs '^R' atuin-search
  bindkey -M viins '^R' atuin-search-viins
  bindkey -M vicmd '^R' atuin-search
elif (( $+functions[fzf-history-widget] )); then
  _mpz_bind_all '^R' fzf-history-widget
else
  _mpz_bind_all '^R' undefined-key
fi

if (( $+functions[fzf-file-widget] )); then
  _mpz_bind_all '^T' fzf-file-widget
else
  _mpz_bind_all '^T' undefined-key
fi

if (( $+functions[fzf-cd-widget] )); then
  _mpz_bind_all '\ec' fzf-cd-widget
else
  _mpz_bind_all '\ec' undefined-key
fi

if (( $+commands[fzf] )) && (( $+functions[fzf-tab-complete] )); then
  _mpz_bind_all '^I' fzf-tab-complete
else
  _mpz_bind_all '^I' expand-or-complete
fi

_mpz_bind_all '^[[A' up-line-or-history

# Atuin's AI binding is disabled. Preserve normal insertion in insert modes and
# native vi reverse/forward history search in command mode.
bindkey -M emacs '\?' self-insert
bindkey -M viins '\?' self-insert
bindkey -M vicmd '\?' vi-history-search-forward
bindkey -M vicmd '/' vi-history-search-backward

# Portable line-editing conveniences.
bindkey -M emacs '^H' backward-kill-word
bindkey -M emacs '^[[3;5~' kill-word
bindkey -M emacs '^[[3~' delete-char
bindkey -M emacs '^[[H' beginning-of-line
bindkey -M emacs '^[[F' end-of-line

if [[ "${widgets[accept-line]:-}" == user:* ]]; then
  local original_accept_line="${widgets[accept-line]#user:}"
  functions[_mpz_original_accept_line]=$functions[$original_accept_line]
else
  unfunction _mpz_original_accept_line 2>/dev/null || true
fi
zle -N accept-line _mpz_privacy_accept_line

unfunction _mpz_bind_all
