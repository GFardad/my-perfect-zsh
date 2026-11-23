# Syntax highlighting is sourced last. Seed its optional theme from the pinned
# checkout so the upstream plugin never reaches its network fallback.

typeset -g FAST_WORK_DIR="$XDG_CACHE_HOME/fast-syntax-highlighting"
command mkdir -p "$FAST_WORK_DIR"
command chmod 700 "$FAST_WORK_DIR"

typeset -g _mpz_fast_syntax_ready=1
_mpz_prepare_fast_syntax_theme() {
  local theme_file="$FAST_WORK_DIR/secondary_theme.zsh"
  local theme_source="$MPZ_VENDOR_DIR/fast-syntax-highlighting/share/free_theme.zsh"
  local temporary=''

  [[ -r "$theme_file" ]] && return 0

  if ! temporary=$(command mktemp "$FAST_WORK_DIR/secondary_theme.XXXXXX" 2>/dev/null); then
    print -u2 -- 'syntax: could not prepare the local theme; highlighter disabled'
    typeset -g _mpz_fast_syntax_ready=0
    return 1
  fi

  if [[ -r "$theme_source" ]]; then
    if ! command cp "$theme_source" "$temporary" 2>/dev/null; then
      rm -f -- "$temporary"
      print -u2 -- 'syntax: could not seed the local theme; highlighter disabled'
      typeset -g _mpz_fast_syntax_ready=0
      return 1
    fi
  else
    if ! : > "$temporary" 2>/dev/null; then
      rm -f -- "$temporary"
      print -u2 -- 'syntax: could not create the local theme; highlighter disabled'
      typeset -g _mpz_fast_syntax_ready=0
      return 1
    fi
  fi

  if ! command chmod 600 "$temporary" 2>/dev/null || \
    ! command mv -f "$temporary" "$theme_file" 2>/dev/null; then
    rm -f -- "$temporary"
    print -u2 -- 'syntax: could not install the local theme; highlighter disabled'
    typeset -g _mpz_fast_syntax_ready=0
    return 1
  fi
}

_mpz_prepare_fast_syntax_theme
unfunction _mpz_prepare_fast_syntax_theme

if (( _mpz_fast_syntax_ready )) && \
  [[ -r "$MPZ_VENDOR_DIR/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh" ]]; then
  source "$MPZ_VENDOR_DIR/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh"
fi
unset _mpz_fast_syntax_ready
