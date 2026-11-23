# Machine-owned configuration is loaded through one quiet, ordered seam.
# stdout is suppressed so a local file cannot corrupt Powerlevel10k's instant
# prompt. stderr remains visible for genuine configuration errors.

_mpz_source_local_file() {
  local file="$1"
  [[ -r "$file" ]] || return 0
  source "$file" >/dev/null
}

_mpz_source_local_dir() {
  local directory="$1"
  local file
  [[ -d "$directory" ]] || return 0
  for file in "$directory"/*.zsh(N); do
    _mpz_source_local_file "$file"
  done
}

_mpz_source_local_dir "$MPZ_ROOT/config/local.d"
_mpz_source_local_file "$MPZ_USER_CONFIG_DIR/local.zsh"
_mpz_source_local_dir "$MPZ_USER_CONFIG_DIR/local.d"

# Preserve prompt declarations made by machine-local files. The repository's
# prompt baseline is loaded later and resets every POWERLEVEL9K_* parameter;
# these declarations are re-applied after that baseline so local prompt policy
# remains authoritative without sourcing local files twice.
typeset -ga _MPZ_PROMPT_OVERRIDES=()
_mpz_capture_prompt_override() {
  local parameter declaration
  for parameter in ${(k)parameters[(I)POWERLEVEL9K_*]}; do
    declaration=$(typeset -p "$parameter")
    _MPZ_PROMPT_OVERRIDES+=("$declaration")
  done
}
_mpz_capture_prompt_override
unfunction _mpz_capture_prompt_override

unfunction _mpz_source_local_file _mpz_source_local_dir
