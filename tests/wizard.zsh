#!/usr/bin/env zsh
# Regression tests for the on-demand machine-local configuration wizard.

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

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/mpz-wizard.XXXXXX") || exit 1
trap 'rm -rf -- "$TEMP_ROOT"' EXIT INT TERM

CONFIG_DIR="$TEMP_ROOT/config/my-perfect-zsh"
mkdir -p "$CONFIG_DIR/local.d"

# Steam 1: applying selected values produces a machine-local file that the
# runtime can source silently and that carries the user's choices.
APPLY_OUTPUT=$(HOME="$TEMP_ROOT/home" \
  MPZ_USER_CONFIG_DIR="$CONFIG_DIR" \
  "$ROOT/scripts/wizard" \
    --config "$CONFIG_DIR" \
    --apply \
    --set history_size=1234 \
    --set autosuggest_highlight=fg=9 \
    --set prompt_left_elements=os_icon,dir \
    --set prompt_right_elements=status,time \
    2>&1)
APPLY_RC=$?
assert_eq 0 "$APPLY_RC" 'wizard applies valid customizations without errors'
assert_contains "$APPLY_OUTPUT" 'wizard: wrote' 'wizard reports the managed file location'

GENERATED="$CONFIG_DIR/local.d/50-wizard.zsh"
assert_contains "$APPLY_OUTPUT" "$GENERATED" 'wizard target is under machine-local configuration'
[[ -f "$GENERATED" ]] && pass 'wizard creates the managed machine-local file' || fail 'wizard creates the managed machine-local file'
assert_eq 600 "$(stat -c '%a' "$GENERATED")" 'wizard file has mode 600'

assert_contains "$(<"$GENERATED")" 'typeset -g HISTSIZE=1234' 'wizard applies history size'
assert_contains "$(<"$GENERATED")" 'typeset -g ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=9"' 'wizard applies autosuggestion style'
assert_contains "$(<"$GENERATED")" 'typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(os_icon dir)' 'wizard applies prompt left elements'
assert_contains "$(<"$GENERATED")" 'typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status time)' 'wizard applies prompt right elements'

SOURCE_OUTPUT=$(HOME="$TEMP_ROOT/home" /usr/bin/zsh -f -c "source '$GENERATED'; print -r -- \"\$HISTSIZE|\$ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE|\${POWERLEVEL9K_LEFT_PROMPT_ELEMENTS[*]}\"" 2>&1)
assert_eq '1234|fg=9|os_icon dir' "$SOURCE_OUTPUT" 'wizard file is sourceable and carries user choices'

# Steam 2: preview mode never changes the active file.
BEFORE=$(sha256sum < "$GENERATED")
PRINT_OUTPUT=$(HOME="$TEMP_ROOT/home" MPZ_USER_CONFIG_DIR="$CONFIG_DIR" \
  "$ROOT/scripts/wizard" --config "$CONFIG_DIR" --print --set history_size=4321 2>&1)
PRINT_RC=$?
AFTER=$(sha256sum < "$GENERATED")
assert_eq 0 "$PRINT_RC" 'wizard preview succeeds'
assert_eq "$BEFORE" "$AFTER" 'wizard preview leaves the managed file unchanged'
assert_contains "$PRINT_OUTPUT" 'typeset -g HISTSIZE=4321"' 'wizard preview shows proposed changes'

# Steam 3: invalid values fail closed and do not overwrite a managed file.
INVALID_OUTPUT=$(HOME="$TEMP_ROOT/home" MPZ_USER_CONFIG_DIR="$CONFIG_DIR" \
  "$ROOT/scripts/wizard" --config "$CONFIG_DIR" --apply --set history_size=not-a-number 2>&1)
INVALID_RC=$?
assert_eq 1 "$INVALID_RC" 'wizard rejects an invalid history size'
assert_contains "$INVALID_OUTPUT" 'history_size must be a positive integer' 'wizard reports the invalid field'
assert_eq '1234' "$(grep -o 'HISTSIZE=[0-9]*' "$GENERATED" | cut -d= -f2)" 'wizard rejects an invalid value without changes'

print -r -- "wizard: ${PASSED} passed, ${FAILED} failed"
(( FAILED == 0 ))