#!/usr/bin/env zsh
# Legacy history import regression tests.

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

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/mpz-history.XXXXXX") || exit 1
trap 'rm -rf -- "$TEMP_ROOT"' EXIT INT TERM

OLD_HISTORY="$TEMP_ROOT/.zsh_history"
NEW_HISTORY="$TEMP_ROOT/state/zsh/history"
MARKER="$TEMP_ROOT/state/zsh/.legacy-history-imported"
mkdir -p "$TEMP_ROOT/state/zsh"
cat > "$OLD_HISTORY" <<'EOF'
: 1700000000:0;echo MPZ_IMPORT_VISIBLE
: 1700000001:0; echo MPZ_IMPORT_SECRET
echo MPZ_IMPORT_SIMPLE
 echo MPZ_IMPORT_SIMPLE_SECRET
	echo MPZ_IMPORT_TAB_SECRET
: 1700000002:0; echo "MPZ_IMPORT_PRIVATE_FIRST\
MPZ_IMPORT_PRIVATE_CONTINUATION"
: 1700000003:0;echo "MPZ_IMPORT_VISIBLE_MULTI_FIRST\
 MPZ_IMPORT_VISIBLE_MULTI_CONTINUATION"
: 1700000004:0;printf 'MPZ_IMPORT_BACKSLASH\\'
: 1700000005:0;echo MPZ_IMPORT_AFTER_BACKSLASH
EOF
printf '\377\n' >> "$OLD_HISTORY"
printf 'echo MPZ_CURRENT_HISTORY\n' > "$NEW_HISTORY"

OUTPUT=$(HOME="$TEMP_ROOT" XDG_STATE_HOME="$TEMP_ROOT/state" \
  "$ROOT/scripts/import-history" "$OLD_HISTORY" 2>&1)
RC=$?
assert_eq 0 "$RC" 'history importer succeeds'
assert_contains "$OUTPUT" 'imported 6 commands' 'history importer reports imported count'
assert_contains "$OUTPUT" 'excluded 4 leading-whitespace commands' \
  'history importer reports excluded count'
assert_not_contains "$OUTPUT" 'Invalid multibyte data' \
  'history importer handles non-UTF-8 bytes without diagnostics'
IMPORTED_HISTORY=$(<"$NEW_HISTORY")
assert_contains "$IMPORTED_HISTORY" 'MPZ_IMPORT_VISIBLE' \
  'history importer keeps ordinary extended-history commands'
assert_contains "$IMPORTED_HISTORY" 'MPZ_IMPORT_SIMPLE' \
  'history importer keeps ordinary simple-history commands'
assert_contains "$IMPORTED_HISTORY" 'MPZ_CURRENT_HISTORY' \
  'history importer preserves existing current history'
assert_not_contains "$IMPORTED_HISTORY" 'MPZ_IMPORT_SECRET' \
  'history importer excludes leading-whitespace extended commands'
assert_not_contains "$IMPORTED_HISTORY" 'MPZ_IMPORT_SIMPLE_SECRET' \
  'history importer excludes leading-whitespace simple commands'
assert_not_contains "$IMPORTED_HISTORY" 'MPZ_IMPORT_TAB_SECRET' \
  'history importer excludes tab-prefixed commands'
assert_not_contains "$IMPORTED_HISTORY" 'MPZ_IMPORT_PRIVATE_FIRST' \
  'history importer excludes the first line of a private multiline command'
assert_not_contains "$IMPORTED_HISTORY" 'MPZ_IMPORT_PRIVATE_CONTINUATION' \
  'history importer excludes continuations of private multiline commands'
assert_contains "$IMPORTED_HISTORY" 'MPZ_IMPORT_VISIBLE_MULTI_FIRST' \
  'history importer keeps the first line of a visible multiline command'
assert_contains "$IMPORTED_HISTORY" 'MPZ_IMPORT_VISIBLE_MULTI_CONTINUATION' \
  'history importer keeps continuations of visible multiline commands'
assert_contains "$IMPORTED_HISTORY" 'MPZ_IMPORT_BACKSLASH' \
  'history importer keeps commands ending in an escaped backslash'
assert_contains "$IMPORTED_HISTORY" 'MPZ_IMPORT_AFTER_BACKSLASH' \
  'history importer does not merge the command after an escaped-backslash command'
if [[ $(<"$NEW_HISTORY") == *MPZ_IMPORT_VISIBLE*MPZ_CURRENT_HISTORY* ]]; then
  pass 'history importer keeps legacy entries before current entries'
else
  fail 'history importer keeps legacy entries before current entries'
fi
assert_eq 600 "$(stat -c '%a' "$NEW_HISTORY")" 'imported history has mode 600'
assert_eq 600 "$(stat -c '%a' "$MARKER")" 'history import marker has mode 600'
if [[ -r "$OLD_HISTORY" ]]; then
  pass 'history importer preserves the legacy history file'
else
  fail 'history importer preserves the legacy history file'
fi

BEFORE_SECOND=$(cksum < "$NEW_HISTORY")
SECOND_OUTPUT=$(HOME="$TEMP_ROOT" XDG_STATE_HOME="$TEMP_ROOT/state" \
  "$ROOT/scripts/import-history" "$OLD_HISTORY" 2>&1)
SECOND_RC=$?
assert_eq 0 "$SECOND_RC" 'repeat history import succeeds'
assert_contains "$SECOND_OUTPUT" 'already imported' 'repeat history import is skipped'
assert_eq "$BEFORE_SECOND" "$(cksum < "$NEW_HISTORY")" \
  'repeat history import does not duplicate entries'

MISSING_OUTPUT=$(HOME="$TEMP_ROOT" XDG_STATE_HOME="$TEMP_ROOT/missing-state" \
  "$ROOT/scripts/import-history" "$TEMP_ROOT/does-not-exist" 2>&1)
MISSING_RC=$?
assert_eq 0 "$MISSING_RC" 'missing legacy history is not an error'
assert_contains "$MISSING_OUTPUT" 'nothing to import' 'missing legacy history is reported'

# A crash after publishing the history but before the marker is recoverable.
# The retry finalizes the marker without importing the legacy entries again or
# replacing the original pre-import backup.
CRASH_ROOT="$TEMP_ROOT/crash"
mkdir -p "$CRASH_ROOT/state/zsh"
cat > "$CRASH_ROOT/legacy" <<'EOF'
: 1700000100:0;echo MPZ_CRASH_IMPORTED
: 1700000101:0;echo MPZ_CRASH_ORIGINAL
EOF
printf 'echo MPZ_CRASH_CURRENT\n' > "$CRASH_ROOT/state/zsh/history"
CRASH_CURRENT_CHECKSUM=$(cksum < "$CRASH_ROOT/state/zsh/history")
HOME="$CRASH_ROOT" XDG_STATE_HOME="$CRASH_ROOT/state" \
  MPZ_HISTORY_IMPORT_TEST_CRASH=after-history \
  "$ROOT/scripts/import-history" "$CRASH_ROOT/legacy" >/dev/null 2>&1
CRASH_RC=$?
assert_eq 137 "$CRASH_RC" 'history importer exposes the injected crash point'
assert_eq "$CRASH_CURRENT_CHECKSUM" \
  "$(cksum < "$CRASH_ROOT/state/zsh/history.pre-import")" \
  'crash recovery preserves the original pre-import backup'
CRASH_RETRY_OUTPUT=$(HOME="$CRASH_ROOT" XDG_STATE_HOME="$CRASH_ROOT/state" \
  "$ROOT/scripts/import-history" "$CRASH_ROOT/legacy" 2>&1)
CRASH_RETRY_RC=$?
assert_eq 0 "$CRASH_RETRY_RC" 'history importer recovers after a crash'
assert_contains "$CRASH_RETRY_OUTPUT" 'recovered' \
  'history importer reports crash recovery'
CRASH_HISTORY=$(<"$CRASH_ROOT/state/zsh/history")
CRASH_IMPORT_COUNT=$(grep -o 'MPZ_CRASH_IMPORTED' <<< "$CRASH_HISTORY" | wc -l)
assert_eq 1 "$CRASH_IMPORT_COUNT" 'crash recovery does not duplicate imported entries'
assert_eq "$CRASH_CURRENT_CHECKSUM" \
  "$(cksum < "$CRASH_ROOT/state/zsh/history.pre-import")" \
  'crash recovery does not overwrite the original pre-import backup'
if [[ -r "$CRASH_ROOT/state/zsh/.legacy-history-imported" ]]; then
  pass 'crash recovery finalizes the import marker'
else
  fail 'crash recovery finalizes the import marker'
fi

print -r -- "history: ${PASSED} passed, ${FAILED} failed"
(( FAILED == 0 ))
