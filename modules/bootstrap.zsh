# Bootstrap establishes the runtime paths and the dependency seam.

if [[ -z ${MPZ_ROOT-} ]]; then
  typeset -g MPZ_ROOT="${${(%):-%N}:A:h:h}"
fi

typeset -g MPZ_VENDOR_DIR="$MPZ_ROOT/vendor"
typeset -g MPZ_CONFIG_DIR="$MPZ_ROOT/config"
typeset -g MPZ_USER_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/my-perfect-zsh"

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

# Recompute the user config path after normalizing XDG_CONFIG_HOME.
typeset -g MPZ_USER_CONFIG_DIR="$XDG_CONFIG_HOME/my-perfect-zsh"

command mkdir -p \
  "$XDG_CACHE_HOME/zsh" \
  "$XDG_STATE_HOME/zsh" \
  "$MPZ_USER_CONFIG_DIR"
command chmod 700 \
  "$XDG_CACHE_HOME/zsh" \
  "$XDG_STATE_HOME/zsh" \
  "$MPZ_USER_CONFIG_DIR"

_mpz_prepend_path() {
  local directory="$1"
  [[ -d "$directory" ]] || return 0
  case ":$PATH:" in
    *":$directory:"*) return 0 ;;
  esac
  typeset -g PATH="$directory:$PATH"
}

_mpz_prepend_path "$HOME/.local/bin"
_mpz_prepend_path "$HOME/.cargo/bin"
_mpz_prepend_path "$HOME/go/bin"
unfunction _mpz_prepend_path

# New users receive the repository's privacy-safe Atuin defaults. An existing
# user configuration remains authoritative; the installer updates only the
# documented privacy keys.
if [[ -z ${ATUIN_CONFIG_DIR-} ]]; then
  if [[ -r "$XDG_CONFIG_HOME/atuin/config.toml" ]]; then
    typeset -g ATUIN_CONFIG_DIR="$XDG_CONFIG_HOME/atuin"
  else
    typeset -g ATUIN_CONFIG_DIR="$MPZ_CONFIG_DIR/atuin"
  fi
  export ATUIN_CONFIG_DIR
fi
