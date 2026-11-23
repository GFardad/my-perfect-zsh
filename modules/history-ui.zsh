# History UI owns Atuin and autosuggestions.

typeset -g MPZ_ATUIN_PRIVACY_WRAPPED=

if (( $+commands[atuin] )); then
  # Atuin registers ZLE widgets unconditionally. A non-terminal interactive
  # shell (`zsh -ic`) has no ZLE, so discard only that registration diagnostic.
  eval "$(atuin init zsh --disable-up-arrow --disable-ai 2>/dev/null)" 2>/dev/null

  # Atuin's preexec hook receives the command after Zsh has stripped leading
  # whitespace, which would defeat `history_filter`. Preserve its hook while
  # skipping a command that the accept-line wrapper flagged as private.
  if [[ -z "$MPZ_ATUIN_PRIVACY_WRAPPED" ]] && (( $+functions[_atuin_preexec] )); then
    functions[_mpz_original_atuin_preexec]=$functions[_atuin_preexec]
    _atuin_preexec() {
      if [[ "${MPZ_PRIVATE_LINE:-0}" == 1 ]]; then
        return 0
      fi
      _mpz_original_atuin_preexec "$@"
    }
    MPZ_ATUIN_PRIVACY_WRAPPED=1
  fi
fi

if [[ -r "$MPZ_VENDOR_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  source "$MPZ_VENDOR_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh"
  ZSH_AUTOSUGGEST_STRATEGY=(history)
  typeset -g ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
fi
