# Local history policy: bounded, append-only, duplicate-resistant, and private.

typeset -g HISTFILE="$XDG_STATE_HOME/zsh/history"
typeset -g HISTSIZE=50000
typeset -g SAVEHIST=50000

# A machine-local history size wins over the core bound; the bounded-history
# policy itself stays with the core.
_mpz_reapply_local_override HISTSIZE

setopt APPEND_HISTORY
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_FIND_NO_DUPS
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS
setopt HIST_SAVE_NO_DUPS

unsetopt SHARE_HISTORY

# HIST_IGNORE_SPACE only covers a literal leading space. The hook closes the
# remaining gap for tabs and other whitespace without changing ordinary
# commands. Returning non-zero prevents Zsh from adding the logical entry.
_mpz_zshaddhistory() {
  local first_line="${1%%$'\n'*}"
  [[ "$first_line" == [[:space:]]* ]] && return 1
  return 0
}

autoload -Uz add-zsh-hook
add-zsh-hook zshaddhistory _mpz_zshaddhistory

# Zsh stores hook function names. Unsetting the function after registration
# removes the hook, so the policy must remain defined for the shell's lifetime.

# Zsh strips leading whitespace before it runs preexec hooks. Atuin records from
# preexec, so the raw line must be inspected by the ZLE accept-line wrapper
# before that transformation and communicated to the preexec wrapper through
# this one-command flag.
typeset -g MPZ_PRIVATE_LINE=0

_mpz_privacy_precmd() {
  MPZ_PRIVATE_LINE=0
}
add-zsh-hook precmd _mpz_privacy_precmd

# The original accept-line widget, if any, is installed before this widget by
# modules/keys.zsh. It preserves the line editor/syntax-highlighting chain.
_mpz_privacy_accept_line() {
  MPZ_PRIVATE_LINE=0
  if [[ "$BUFFER" == [[:space:]]* ]]; then
    MPZ_PRIVATE_LINE=1
  fi
  if (( $+functions[_mpz_original_accept_line] )); then
    _mpz_original_accept_line "$@"
  else
    zle .accept-line
  fi
}
