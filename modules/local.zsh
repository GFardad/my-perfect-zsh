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

# Parameters the core modules own. A machine-local file may set one of these
# before the core baseline runs, so both sides of the seam are recorded.
_mpz_local_candidate_parameters() {
  local -a candidates
  candidates=("${(@k)parameters[(I)POWERLEVEL9K_*]}" \
    HISTSIZE ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE)
  print -rl -- "${candidates[@]}"
}

typeset -gA _MPZ_LOCAL_BASELINE=()
typeset -gA _MPZ_LOCAL_OVERRIDES=()

_mpz_capture_local_baseline() {
  local parameter declaration
  for parameter in "${(@f)$( _mpz_local_candidate_parameters )}"; do
    [[ -n "$parameter" ]] || continue
    (( ${+parameters[$parameter]} )) || continue
    declaration=$(typeset -p "$parameter" 2>/dev/null) || continue
    _MPZ_LOCAL_BASELINE[$parameter]="$declaration"
  done
}
_mpz_capture_local_baseline
unfunction _mpz_capture_local_baseline

_mpz_source_local_dir "$MPZ_ROOT/config/local.d"
_mpz_source_local_file "$MPZ_USER_CONFIG_DIR/local.zsh"
_mpz_source_local_dir "$MPZ_USER_CONFIG_DIR/local.d"

# Preserve declarations machine-local files made. Core modules are loaded after
# this seam and reset the parameters they own (history bounds, the autosuggestion
# style, and every POWERLEVEL9K_* prompt parameter); each one re-applies the
# recorded declaration after its own baseline, so machine-local policy remains
# authoritative without sourcing local files twice. The record holds parameter
# names, so a module can re-apply only what it owns.
_mpz_capture_local_override() {
  local parameter declaration
  for parameter in "${(@f)$( _mpz_local_candidate_parameters )}"; do
    [[ -n "$parameter" ]] || continue
    (( ${+parameters[$parameter]} )) || continue
    declaration=$(typeset -p "$parameter" 2>/dev/null) || continue
    if [[ -n "${_MPZ_LOCAL_BASELINE[$parameter]-}" && \
      "$declaration" == "${_MPZ_LOCAL_BASELINE[$parameter]}" ]]; then
      # Zsh defines defaults such as HISTSIZE before startup files run. A value
      # no local file changed is not machine-local policy, so the core default
      # stays in force instead of the environment's value.
      unset "_MPZ_LOCAL_OVERRIDES[$parameter]"
      continue
    fi
    _MPZ_LOCAL_OVERRIDES[$parameter]="$declaration"
  done
}
_mpz_capture_local_override
unfunction _mpz_capture_local_override _mpz_local_candidate_parameters
unset _MPZ_LOCAL_BASELINE

# Re-apply the machine-local declaration for each named parameter. Called by the
# core module that owns the parameter's default value.
_mpz_reapply_local_override() {
  local parameter declaration
  for parameter in "$@"; do
    declaration=${_MPZ_LOCAL_OVERRIDES[$parameter]-}
    [[ -n "$declaration" ]] || continue
    eval "$declaration"
  done
}

unfunction _mpz_source_local_file _mpz_source_local_dir
