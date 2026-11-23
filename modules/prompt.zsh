# Powerlevel10k is the sole prompt owner.

if [[ -r "$MPZ_VENDOR_DIR/powerlevel10k/powerlevel10k.zsh-theme" ]]; then
  source "$MPZ_VENDOR_DIR/powerlevel10k/powerlevel10k.zsh-theme"
  if [[ -r "$MPZ_CONFIG_DIR/p10k.zsh" ]]; then
    source "$MPZ_CONFIG_DIR/p10k.zsh"
  fi
fi

if (( ${#_MPZ_PROMPT_OVERRIDES-} )); then
  typeset -g _mpz_prompt_override
  for _mpz_prompt_override in "${_MPZ_PROMPT_OVERRIDES[@]}"; do
    eval "$_mpz_prompt_override"
  done
  unset _mpz_prompt_override
fi
unset _MPZ_PROMPT_OVERRIDES
