# Navigation owns zoxide and fzf's Ctrl-T/Alt-C widgets.

if (( $+commands[zoxide] )); then
  typeset -g _mpz_zoxide_init="$(zoxide init zsh 2>/dev/null)"
  if [[ -n "$_mpz_zoxide_init" ]]; then
    eval "$_mpz_zoxide_init"
  fi
  unset _mpz_zoxide_init
fi

if (( $+commands[fzf] )) && [[ -r "$MPZ_VENDOR_DIR/fzf/shell/key-bindings.zsh" ]]; then
  # fzf must not claim Ctrl-R. Its history function is retained as the
  # fallback used later only when Atuin is unavailable.
  typeset -g FZF_CTRL_R_COMMAND=''
  # The pinned script restores the `zle` option at the end. In a non-terminal
  # interactive shell that option cannot be enabled, so hide only that known
  # diagnostic while keeping the widget definitions intact.
  source "$MPZ_VENDOR_DIR/fzf/shell/key-bindings.zsh" 2>/dev/null
  unset FZF_CTRL_R_COMMAND
fi
