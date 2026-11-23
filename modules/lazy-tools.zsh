# Lazy tools expose stable commands without paying their initialization cost.

fuck() {
  local initialization init_status wrapper_body
  if (( ! $+commands[thefuck] )); then
    print -u2 -- "fuck: thefuck is not installed"
    return 127
  fi

  wrapper_body="$functions[fuck]"
  initialization=$(command thefuck --shell zsh 2>/dev/null)
  init_status=$?
  if (( init_status != 0 )); then
    return "$init_status"
  fi
  [[ -n "$initialization" ]] || return 127

  eval "$initialization"
  if (( ! $+functions[fuck] )) || [[ "$functions[fuck]" == "$wrapper_body" ]]; then
    print -u2 -- "fuck: thefuck did not initialize successfully"
    return 127
  fi
  fuck "$@"
}

extract() {
  local wrapper_body
  if [[ ! -r "$MPZ_ROOT/lib/extract.zsh" ]]; then
    print -u2 -- "extract: bundled implementation is missing"
    return 127
  fi

  wrapper_body="$functions[extract]"
  source "$MPZ_ROOT/lib/extract.zsh"
  if (( ! $+functions[extract] )) || [[ "$functions[extract]" == "$wrapper_body" ]]; then
    print -u2 -- "extract: bundled implementation did not initialize successfully"
    return 127
  fi
  extract "$@"
}

sysinfo() {
  if (( $+commands[fastfetch] )); then
    command fastfetch
  elif (( $+commands[fetch] )); then
    command fetch --frames 1
  else
    print -u2 -- "sysinfo: neither fastfetch nor fetch is installed"
    return 127
  fi
}

alias x=extract
