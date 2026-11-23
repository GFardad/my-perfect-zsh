#!/usr/bin/env zsh
# Interface, privacy, fallback, and parent-shell regression tests.

set -u

ROOT=${0:A:h:h}
typeset -g PASSED=0
typeset -g FAILED=0

pass() {
  (( PASSED++ ))
  print -r -- "ok - $1"
}

fail() {
  (( FAILED++ ))
  print -u2 -- "not ok - $1"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass "$message"
  else
    fail "$message (expected '$expected', got '$actual')"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$message"
  else
    fail "$message (missing '$needle')"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    pass "$message"
  else
    fail "$message (unexpected '$needle')"
  fi
}

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/mpz-smoke.XXXXXX") || exit 1
trap 'rm -rf -- "$TEMP_ROOT"' EXIT INT TERM

typeset -g HAVE_ATUIN=0
typeset -g HAVE_FZF=0
typeset -g HAVE_ZOXIDE=0
typeset -g HAVE_BUN=0
(( $+commands[atuin] )) && HAVE_ATUIN=1
(( $+commands[fzf] )) && HAVE_FZF=1
(( $+commands[zoxide] )) && HAVE_ZOXIDE=1
(( $+commands[bun] )) && HAVE_BUN=1

export ATUIN_HOME="$TEMP_ROOT/atuin-home"
export ATUIN_CONFIG_DIR="$TEMP_ROOT/config/atuin"
export XDG_DATA_HOME="$TEMP_ROOT/data"
mkdir -p "$ATUIN_HOME" "$TEMP_ROOT/config/atuin" "$TEMP_ROOT/data"
cp "$ROOT/config/atuin/config.toml" "$TEMP_ROOT/config/atuin/config.toml"

mkdir -p \
  "$TEMP_ROOT/home" \
  "$TEMP_ROOT/zdot" \
  "$TEMP_ROOT/config" \
  "$TEMP_ROOT/cache" \
  "$TEMP_ROOT/state" \
  "$TEMP_ROOT/shims" \
  "$TEMP_ROOT/config/my-perfect-zsh"
cat > "$TEMP_ROOT/config/my-perfect-zsh/local.zsh" <<'EOF'
typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(dir)
typeset -g POWERLEVEL9K_MPZ_LOCAL_PROMPT_MARKER=preserved
EOF
ln -s "$ROOT/.zshrc" "$TEMP_ROOT/zdot/.zshrc"
ln -s "$ROOT/.zshenv" "$TEMP_ROOT/zdot/.zshenv"

# Instrument commands that must never run during startup. The shims are
# discoverable so optional integrations initialize, but they log any call.
for command_name in fetch fastfetch bun thefuck python python3 fzf curl wget; do
  cat > "$TEMP_ROOT/shims/$command_name" <<'EOF'
#!/bin/sh
printf '%s\n' "${0##*/}" >> "$MPZ_TEST_LOG"
exit 127
EOF
  chmod +x "$TEMP_ROOT/shims/$command_name"
done

run_test_shell() {
  HOME="$TEMP_ROOT/home" \
  XDG_CONFIG_HOME="$TEMP_ROOT/config" \
  XDG_CACHE_HOME="$TEMP_ROOT/cache" \
  XDG_STATE_HOME="$TEMP_ROOT/state" \
  XDG_DATA_HOME="$TEMP_ROOT/data" \
  ATUIN_HOME="$TEMP_ROOT/atuin-home" \
  ATUIN_CONFIG_DIR="$TEMP_ROOT/config/atuin" \
  ZDOTDIR="$TEMP_ROOT/zdot" \
  PATH="$TEMP_ROOT/shims:$PATH" \
  MPZ_TEST_LOG="$TEMP_ROOT/startup.log" \
  command /usr/bin/zsh -lic "$1"
}

run_test_shell 'exit' > "$TEMP_ROOT/startup.out" 2> "$TEMP_ROOT/startup.err"
STARTUP_RC=$?
assert_eq 0 "$STARTUP_RC" 'isolated startup exits successfully'
assert_eq 0 "$(wc -c < "$TEMP_ROOT/startup.out")" 'startup emits no stdout'
assert_eq 0 "$(wc -c < "$TEMP_ROOT/startup.err")" 'startup emits no stderr'
assert_eq 700 "$(stat -c '%a' "$TEMP_ROOT/config/my-perfect-zsh")" \
  'machine-local configuration directory has mode 700'
assert_eq 600 "$(stat -c '%a' "$TEMP_ROOT/cache/fast-syntax-highlighting/secondary_theme.zsh")" \
  'fast-syntax-highlighting theme cache has mode 600'
if [[ -s "$TEMP_ROOT/startup.log" ]]; then
  fail 'startup does not run fetch, fastfetch, Bun, Python, fzf, thefuck, curl, or wget'
else
  pass 'startup does not run fetch, fastfetch, Bun, Python, fzf, thefuck, curl, or wget'
fi

cat > "$TEMP_ROOT/probe.zsh" <<'EOF'
for keymap in emacs viins vicmd; do
  for entry in 'ctrl_r|^R' 'ctrl_t|^T' 'alt_c|\ec' 'tab|^I' 'up|^[[A' 'question|\?' 'slash|/'; do
    key_name=${entry%%|*}
    sequence=${entry#*|}
    binding=$(bindkey -M "$keymap" "$sequence")
    print -r -- "binding|$keymap|$key_name|${binding##* }"
  done
done
print -r -- "function|atuin|$(( $+functions[_atuin_search] ))"
print -r -- "function|zoxide|$(( $+functions[z] ))"
print -r -- "function|lazy_fuck|$(( $+functions[fuck] ))"
print -r -- "function|lazy_extract|$(( $+functions[extract] ))"
print -r -- "function|bun|$(( $+functions[_bun] ))"
print -r -- "function|fzf_history|$(( $+functions[fzf-history-widget] ))"
print -r -- "function|fzf_completion|$(( $+functions[fzf-completion] ))"
print -r -- "function|fast_syntax|$(( $+functions[_zsh_highlight] ))"
print -r -- "function|gitstatus_daemon|$(( $+functions[gitstatus_start_p9k_] ))"
print -r -- "setting|gitstatus_auto_install|${GITSTATUS_AUTO_INSTALL-unset}"
print -r -- "setting|disable_gitstatus|${POWERLEVEL9K_DISABLE_GITSTATUS-unset}"
print -r -- "local|prompt_marker|${POWERLEVEL9K_MPZ_LOCAL_PROMPT_MARKER-unset}"
print -r -- "local|left_prompt|${POWERLEVEL9K_LEFT_PROMPT_ELEMENTS[*]}"
EOF
run_test_shell "source '$TEMP_ROOT/probe.zsh'" > "$TEMP_ROOT/probe.out" 2> "$TEMP_ROOT/probe.err"
PROBE=$(<"$TEMP_ROOT/probe.out")

typeset -a EXPECTED_BINDINGS
EXPECTED_BINDINGS=(
  'binding|emacs|up|up-line-or-history'
  'binding|viins|up|up-line-or-history'
  'binding|vicmd|up|up-line-or-history'
  'binding|emacs|question|self-insert'
  'binding|viins|question|self-insert'
  'binding|vicmd|question|vi-history-search-forward'
  'binding|vicmd|slash|vi-history-search-backward'
)
if (( HAVE_ATUIN )); then
  EXPECTED_BINDINGS+=(
    'binding|emacs|ctrl_r|atuin-search'
    'binding|viins|ctrl_r|atuin-search-viins'
    'binding|vicmd|ctrl_r|atuin-search'
  )
elif (( HAVE_FZF )); then
  EXPECTED_BINDINGS+=(
    'binding|emacs|ctrl_r|fzf-history-widget'
    'binding|viins|ctrl_r|fzf-history-widget'
    'binding|vicmd|ctrl_r|fzf-history-widget'
  )
else
  EXPECTED_BINDINGS+=(
    'binding|emacs|ctrl_r|undefined-key'
    'binding|viins|ctrl_r|undefined-key'
    'binding|vicmd|ctrl_r|undefined-key'
  )
fi
if (( HAVE_FZF )); then
  EXPECTED_BINDINGS+=(
    'binding|emacs|ctrl_t|fzf-file-widget'
    'binding|viins|ctrl_t|fzf-file-widget'
    'binding|vicmd|ctrl_t|fzf-file-widget'
    'binding|emacs|alt_c|fzf-cd-widget'
    'binding|viins|alt_c|fzf-cd-widget'
    'binding|vicmd|alt_c|fzf-cd-widget'
  )
else
  EXPECTED_BINDINGS+=(
    'binding|emacs|ctrl_t|undefined-key'
    'binding|viins|ctrl_t|undefined-key'
    'binding|vicmd|ctrl_t|undefined-key'
    'binding|emacs|alt_c|undefined-key'
    'binding|viins|alt_c|undefined-key'
    'binding|vicmd|alt_c|undefined-key'
  )
fi
if (( HAVE_FZF )); then
  EXPECTED_BINDINGS+=(
    'binding|emacs|tab|fzf-tab-complete'
    'binding|viins|tab|fzf-tab-complete'
    'binding|vicmd|tab|fzf-tab-complete'
  )
else
  EXPECTED_BINDINGS+=(
    'binding|emacs|tab|expand-or-complete'
    'binding|viins|tab|expand-or-complete'
    'binding|vicmd|tab|expand-or-complete'
  )
fi
for expected_line in "${EXPECTED_BINDINGS[@]}"; do
  assert_contains "$PROBE" "$expected_line" "binding ownership: $expected_line"
done
if (( HAVE_ATUIN )); then
  assert_contains "$PROBE" 'function|atuin|1' 'Atuin state exists in the parent shell'
else
  assert_contains "$PROBE" 'function|atuin|0' 'Atuin state is absent without Atuin'
fi
if (( HAVE_ZOXIDE )); then
  assert_contains "$PROBE" 'function|zoxide|1' 'zoxide state exists in the parent shell'
else
  assert_contains "$PROBE" 'function|zoxide|0' 'zoxide state is absent without zoxide'
fi
assert_contains "$PROBE" 'function|lazy_fuck|1' 'lazy fuck wrapper exists in the parent shell'
assert_contains "$PROBE" 'function|lazy_extract|1' 'lazy extract wrapper exists in the parent shell'
if (( HAVE_BUN )); then
  assert_contains "$PROBE" 'function|bun|1' 'deferred Bun completion exists in the parent shell'
else
  assert_contains "$PROBE" 'function|bun|0' 'deferred Bun completion is absent without Bun'
fi
if (( HAVE_FZF )); then
  assert_contains "$PROBE" 'function|fzf_history|1' 'fzf history fallback function is available'
else
  assert_contains "$PROBE" 'function|fzf_history|0' 'fzf history fallback is absent without fzf'
fi
assert_contains "$PROBE" 'function|fzf_completion|0' 'fzf completion widget is absent'
assert_contains "$PROBE" 'function|fast_syntax|1' \
  'fast-syntax-highlighting is active in the parent shell'
assert_contains "$PROBE" 'function|gitstatus_daemon|0' \
  'Powerlevel10k does not load the gitstatus daemon'
assert_contains "$PROBE" 'setting|gitstatus_auto_install|0' \
  'Powerlevel10k gitstatus auto-installation is disabled'
assert_contains "$PROBE" 'setting|disable_gitstatus|true' \
  'Powerlevel10k uses the local vcs_info fallback'
assert_contains "$PROBE" 'local|prompt_marker|preserved' \
  'machine-local prompt policy survives the project baseline'
assert_contains "$PROBE" 'local|left_prompt|dir' \
  'machine-local prompt elements remain authoritative'
assert_not_contains "$PROBE" 'atuin-ai' 'Atuin AI is not bound'

# Atuin's absence activates the fzf history fallback.
mkdir -p "$TEMP_ROOT/no-atuin"
cat > "$TEMP_ROOT/no-atuin/atuin" <<'EOF'
#!/bin/sh
exit 127
EOF
chmod +x "$TEMP_ROOT/no-atuin/atuin"
FALLBACK=$(HOME="$TEMP_ROOT/home" \
  XDG_CONFIG_HOME="$TEMP_ROOT/config" \
  XDG_CACHE_HOME="$TEMP_ROOT/cache" \
  XDG_STATE_HOME="$TEMP_ROOT/state" \
  XDG_DATA_HOME="$TEMP_ROOT/data" \
  ATUIN_HOME="$TEMP_ROOT/atuin-home" \
  ATUIN_CONFIG_DIR="$TEMP_ROOT/config/atuin" \
  ZDOTDIR="$TEMP_ROOT/zdot" \
  PATH="$TEMP_ROOT/no-atuin:$TEMP_ROOT/shims:$PATH" \
  MPZ_TEST_LOG="$TEMP_ROOT/fallback.log" \
  /usr/bin/zsh -lic 'bindkey -M emacs "^R"' 2>/dev/null)
if (( HAVE_FZF )); then
  assert_contains "$FALLBACK" 'fzf-history-widget' 'Ctrl-R falls back to fzf history without Atuin'
else
  assert_contains "$FALLBACK" 'undefined-key' 'Ctrl-R is unbound without Atuin or fzf'
fi

# A minimal PATH proves every external integration degrades cleanly.
mkdir -p "$TEMP_ROOT/essential-path"
for command_name in awk sed grep mkdir chmod cp rm date sort tail head uname git ps pgrep \
  mktemp ln touch stat id tr cut basename dirname readlink find env bash sh tput hostname realpath; do
  source_path=$(command -v "$command_name" 2>/dev/null) || continue
  ln -s "$source_path" "$TEMP_ROOT/essential-path/$command_name"
done
HOME="$TEMP_ROOT/home" \
XDG_CONFIG_HOME="$TEMP_ROOT/config" \
XDG_CACHE_HOME="$TEMP_ROOT/cache" \
XDG_STATE_HOME="$TEMP_ROOT/state" \
ZDOTDIR="$TEMP_ROOT/zdot" \
PATH="$TEMP_ROOT/essential-path" \
/usr/bin/zsh -lic 'exit' > "$TEMP_ROOT/minimal.out" 2> "$TEMP_ROOT/minimal.err"
MINIMAL_RC=$?
assert_eq 0 "$MINIMAL_RC" 'startup succeeds without optional integrations'
assert_eq 0 "$(wc -c < "$TEMP_ROOT/minimal.err")" 'missing optional integrations emit no stderr'
MINIMAL_BINDINGS=$(HOME="$TEMP_ROOT/home" \
  XDG_CONFIG_HOME="$TEMP_ROOT/config" \
  XDG_CACHE_HOME="$TEMP_ROOT/cache" \
  XDG_STATE_HOME="$TEMP_ROOT/state" \
  XDG_DATA_HOME="$TEMP_ROOT/data" \
  ATUIN_HOME="$TEMP_ROOT/atuin-home" \
  ATUIN_CONFIG_DIR="$TEMP_ROOT/config/atuin" \
  ZDOTDIR="$TEMP_ROOT/zdot" \
  PATH="$TEMP_ROOT/essential-path" \
  /usr/bin/zsh -lic '
    for keymap in emacs viins vicmd; do
      print -r -- "${keymap}|$(bindkey -M $keymap "^R")|$(bindkey -M $keymap "^T")|$(bindkey -M $keymap "\\ec")|$(bindkey -M $keymap "^I")"
    done
  ' 2>/dev/null)
assert_contains "$MINIMAL_BINDINGS" \
  'emacs|"^R" undefined-key|"^T" undefined-key|"^[c" undefined-key|"^I" expand-or-complete' \
  'missing optional integrations unbind navigation keys and retain native Tab'
assert_contains "$MINIMAL_BINDINGS" \
  'vicmd|"^R" undefined-key|"^T" undefined-key|"^[c" undefined-key|"^I" expand-or-complete' \
  'missing optional integrations unbind reserved keys in vi command mode'

# Thefuck keeps its wrapper after a transient failure, then replaces it in the
# parent shell when initialization succeeds.
cat > "$TEMP_ROOT/shims/thefuck" <<'EOF'
#!/bin/sh
if [ "${1-}" = '--shell' ] && [ -f "${MPZ_THEFUCK_READY-}" ]; then
  printf '%s\n' 'fuck() { print -r -- THEFUCK_DEFERRED_OK; }'
  exit 0
fi
exit 127
EOF
chmod +x "$TEMP_ROOT/shims/thefuck"
THEFUCK_RESULT=$(HOME="$TEMP_ROOT/home" \
  XDG_CONFIG_HOME="$TEMP_ROOT/config" \
  XDG_CACHE_HOME="$TEMP_ROOT/cache" \
  XDG_STATE_HOME="$TEMP_ROOT/state" \
  ZDOTDIR="$TEMP_ROOT/zdot" \
  PATH="$TEMP_ROOT/shims:$PATH" \
  MPZ_TEST_LOG="$TEMP_ROOT/lazy.log" \
  MPZ_THEFUCK_READY="$TEMP_ROOT/thefuck.ready" \
  /usr/bin/zsh -lic '
    fuck
    print -r -- "first=$?"
    print -r -- "defined=${+functions[fuck]}"
    touch "$MPZ_THEFUCK_READY"
    fuck
    print -r -- "second=$?"
  ' 2>/dev/null)
assert_contains "$THEFUCK_RESULT" 'first=127' 'thefuck reports a transient initialization failure'
assert_contains "$THEFUCK_RESULT" 'defined=1' 'thefuck wrapper remains available for retry'
assert_contains "$THEFUCK_RESULT" 'THEFUCK_DEFERRED_OK' \
  'thefuck replaces its wrapper after a successful retry'
assert_contains "$THEFUCK_RESULT" 'second=0' 'thefuck retry succeeds'

# Bun completion also remains retryable after a transient initializer failure.
cat > "$TEMP_ROOT/shims/bun" <<'EOF'
#!/bin/sh
if [ "${1-}" = 'completions' ] && [ -f "${MPZ_BUN_READY-}" ]; then
  printf '%s\n' '_bun() { print -r -- BUN_DEFERRED_OK; }' 'compdef _bun bun'
  exit 0
fi
exit 127
EOF
chmod +x "$TEMP_ROOT/shims/bun"
BUN_RESULT=$(HOME="$TEMP_ROOT/home" \
  XDG_CONFIG_HOME="$TEMP_ROOT/config" \
  XDG_CACHE_HOME="$TEMP_ROOT/cache" \
  XDG_STATE_HOME="$TEMP_ROOT/state" \
  ZDOTDIR="$TEMP_ROOT/zdot" \
  PATH="$TEMP_ROOT/shims:$PATH" \
  MPZ_TEST_LOG="$TEMP_ROOT/lazy.log" \
  MPZ_BUN_READY="$TEMP_ROOT/bun.ready" \
  /usr/bin/zsh -lic '
    _bun
    print -r -- "first=$?"
    print -r -- "defined=${+functions[_bun]}"
    touch "$MPZ_BUN_READY"
    _bun
    print -r -- "second=$?"
  ' 2>/dev/null)
assert_contains "$BUN_RESULT" 'first=1' 'Bun completion reports a transient initialization failure'
assert_contains "$BUN_RESULT" 'defined=1' 'Bun completion stub remains available for retry'
assert_contains "$BUN_RESULT" 'BUN_DEFERRED_OK' \
  'Bun completion replaces its stub after a successful retry'
assert_contains "$BUN_RESULT" 'second=0' 'Bun completion retry succeeds'

# Extract initializes in the parent shell and extracts a real archive.
mkdir -p "$TEMP_ROOT/archive-source"
print -r -- payload > "$TEMP_ROOT/archive-source/payload"
tar -czf "$TEMP_ROOT/archive.tar.gz" -C "$TEMP_ROOT/archive-source" payload
EXTRACT_RESULT=$(HOME="$TEMP_ROOT/home" \
  XDG_CONFIG_HOME="$TEMP_ROOT/config" \
  XDG_CACHE_HOME="$TEMP_ROOT/cache" \
  XDG_STATE_HOME="$TEMP_ROOT/state" \
  ZDOTDIR="$TEMP_ROOT/zdot" \
  PATH="$TEMP_ROOT/shims:$PATH" \
  MPZ_TEST_LOG="$TEMP_ROOT/lazy.log" \
  /usr/bin/zsh -lic "cd '$TEMP_ROOT'; extract '$TEMP_ROOT/archive.tar.gz'" 2>/dev/null)
assert_eq '' "$EXTRACT_RESULT" 'extract wrapper produces no unexpected stdout'
if [[ -f "$TEMP_ROOT/archive/payload" ]]; then
  pass 'extract wrapper initializes and extracts in the parent shell'
else
  fail 'extract wrapper initializes and extracts in the parent shell'
fi

# PTY-backed tests verify that leading-space commands are absent from both
# Zsh and Atuin history and that the reserved keys work under ZLE.
if (( HAVE_ATUIN )); then
  assert_eq false "$(ATUIN_CONFIG_DIR="$TEMP_ROOT/config/atuin" atuin config get auto_sync)" \
  'Atuin automatic sync is disabled by default'
assert_eq false "$(ATUIN_CONFIG_DIR="$TEMP_ROOT/config/atuin" atuin config get update_check)" \
  'Atuin update checks are disabled by default'
assert_eq true "$(ATUIN_CONFIG_DIR="$TEMP_ROOT/config/atuin" atuin config get secrets_filter)" \
  'Atuin secret filtering is enabled by default'
assert_eq 'history_filter = ["^\\s+"]' \
  "$(grep -E '^[[:space:]]*history_filter[[:space:]]*=' "$TEMP_ROOT/config/atuin/config.toml")" \
  'Atuin default uses the exact anchored whitespace filter'
ATUIN_PRIVACY_HOME="$TEMP_ROOT/atuin-privacy-home"
mkdir -p "$ATUIN_PRIVACY_HOME"
ATUIN_TAB_ID=$(HOME="$ATUIN_PRIVACY_HOME" \
  ATUIN_HOME="$ATUIN_PRIVACY_HOME/.atuin" \
  XDG_DATA_HOME="$ATUIN_PRIVACY_HOME/data" \
  ATUIN_CONFIG_DIR="$TEMP_ROOT/config/atuin" \
  atuin history start --hook -- $'\techo MPZ_ATUIN_TAB_SECRET' 2>/dev/null)
assert_eq '' "$ATUIN_TAB_ID" 'Atuin excludes tab-prefixed commands'
ATUIN_VISIBLE_ID=$(HOME="$ATUIN_PRIVACY_HOME" \
  ATUIN_HOME="$ATUIN_PRIVACY_HOME/.atuin" \
  XDG_DATA_HOME="$ATUIN_PRIVACY_HOME/data" \
  ATUIN_CONFIG_DIR="$TEMP_ROOT/config/atuin" \
  atuin history start --hook -- 'echo MPZ_ATUIN_VISIBLE' 2>/dev/null)
if [[ -n "$ATUIN_VISIBLE_ID" ]]; then
  pass 'Atuin accepts an ordinary command'
else
  fail 'Atuin accepts an ordinary command'
fi
fi

HISTORY_HOOK_RESULT=$(HOME="$TEMP_ROOT/home" \
  XDG_CONFIG_HOME="$TEMP_ROOT/config" \
  XDG_CACHE_HOME="$TEMP_ROOT/cache" \
  XDG_STATE_HOME="$TEMP_ROOT/state" \
  ZDOTDIR="$TEMP_ROOT/zdot" \
  PATH="$TEMP_ROOT/shims:$PATH" \
  MPZ_TEST_LOG="$TEMP_ROOT/lazy.log" \
  /usr/bin/zsh -lic '
    print -r -- "defined=${+functions[_mpz_zshaddhistory]}"
    print -r -- "registered=${zshaddhistory_functions[(r)_mpz_zshaddhistory]:-}"
  ' 2>/dev/null)
assert_contains "$HISTORY_HOOK_RESULT" 'defined=1' \
  'Zsh history hook function remains defined after startup'
assert_contains "$HISTORY_HOOK_RESULT" 'registered=_mpz_zshaddhistory' \
  'Zsh history hook remains registered after startup'

# The published runtime contains no machine-specific policy.
MACHINE_MATCHES=''
for runtime_file in \
  "$ROOT/.zshrc" "$ROOT/.zshenv" "$ROOT"/modules/*.zsh "$ROOT"/lib/*.zsh \
  "$ROOT/config/p10k.zsh" "$ROOT/config/atuin/config.toml" "$ROOT/config/local.zsh.example"; do
  file_matches=$(grep -Eni '/home/gfardad|/opt/cuda|/opt/miniconda|nordvpn|(^|[^[:alnum:]_])opam([^[:alnum:]_]|$)|pasted\.ir|pycharm|kitty|GOPROXY=direct|GOSUMDB=off|(^|[^[:alnum:]_])conda([^[:alnum:]_]|$)' "$runtime_file" 2>/dev/null) || true
  if [[ -n "$file_matches" ]]; then
    MACHINE_MATCHES+="$file_matches"$'\n'
  fi
done
assert_eq '' "$MACHINE_MATCHES" 'runtime files contain no machine-specific policy'

# Syntax and dependency lock checks.
for runtime_file in \
  "$ROOT/.zshrc" "$ROOT/.zshenv" "$ROOT"/modules/*.zsh "$ROOT"/lib/*.zsh \
  "$ROOT"/tests/*.zsh; do
  if zsh -n "$runtime_file"; then
    pass "syntax: ${runtime_file:t}"
  else
    fail "syntax: ${runtime_file:t}"
  fi
done
if "$ROOT/scripts/install" --check > "$TEMP_ROOT/install-check.out" 2>&1; then
  pass 'vendored dependencies match deps.lock'
else
  fail 'vendored dependencies match deps.lock'
  sed -n '1,120p' "$TEMP_ROOT/install-check.out" >&2
fi

print -r -- "smoke: ${PASSED} passed, ${FAILED} failed"
(( FAILED == 0 ))
