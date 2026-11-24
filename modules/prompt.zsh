# Powerlevel10k is the sole prompt owner.

if [[ -r "$MPZ_VENDOR_DIR/powerlevel10k/powerlevel10k.zsh-theme" ]]; then
  source "$MPZ_VENDOR_DIR/powerlevel10k/powerlevel10k.zsh-theme"
  if [[ -r "$MPZ_CONFIG_DIR/p10k.zsh" ]]; then
    source "$MPZ_CONFIG_DIR/p10k.zsh"
  fi
fi

# Machine-local prompt declarations were recorded before the baseline reset them.
if (( ${#_MPZ_LOCAL_OVERRIDES} )); then
  typeset -g _mpz_parameter
  for _mpz_parameter in "${(@k)_MPZ_LOCAL_OVERRIDES[(I)POWERLEVEL9K_*]}"; do
    eval "${_MPZ_LOCAL_OVERRIDES[$_mpz_parameter]}"
  done
  unset _mpz_parameter
fi

# The prompt is the last core module that reads machine-local declarations.
unset _MPZ_LOCAL_OVERRIDES
unfunction _mpz_reapply_local_override 2>/dev/null
