#!/usr/bin/env zsh
# Installer, Atuin privacy, and rollback regression tests.

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

assert_file_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"
  if [[ -r "$file" ]] && grep -Fq -- "$needle" "$file"; then
    pass "$message"
  else
    fail "$message (missing '$needle' in $file)"
  fi
}

atuin_tab_id() {
  local config="$1"
  local test_home
  local identifier

  test_home=$(mktemp -d "${TMPDIR:-/tmp}/mpz-atuin-policy.XXXXXX") || return 1
  identifier=$(HOME="$test_home" \
    ATUIN_HOME="$test_home" \
    XDG_DATA_HOME="$test_home/data" \
    ATUIN_CONFIG_DIR="$config" \
    atuin history start --hook -- $'\techo MPZ_INSTALLER_TAB_SECRET' \
    2>/dev/null || true)
  rm -rf -- "$test_home"
  print -r -- "$identifier"
}

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/mpz-installer.XXXXXX") || exit 1
trap 'rm -rf -- "$TEMP_ROOT"' EXIT INT TERM

run_install() {
  local home="$1"
  local config="$2"
  shift 2
  env -u ATUIN_CONFIG_DIR \
    HOME="$home" \
    XDG_CONFIG_HOME="$config" \
    XDG_CACHE_HOME="$home/.cache" \
    XDG_STATE_HOME="$home/.local/state" \
    XDG_DATA_HOME="$home/.local/share" \
    ATUIN_HOME="$home/.local/share/atuin" \
    "$ROOT/scripts/install" --no-deps "$@"
}

# Atuin-specific cases require the tested binary. The runtime and installer
# remain valid without it, so the rest of the installer suite still runs.
if (( $+commands[atuin] )); then
  # Existing Atuin filters are merged, not replaced, and remain top-level TOML.
  CASE_ROOT="$TEMP_ROOT/merge"
mkdir -p "$CASE_ROOT/home" "$CASE_ROOT/config/atuin"
cat > "$CASE_ROOT/config/atuin/config.toml" <<'EOF'
# user comment must survive
auto_sync = true
update_check = true
secrets_filter = false
search_mode = "prefix"
history_filter = [
  "^keep-me",
  "^also-keep[0-9]+",
]

[stats]
ignored_commands = ["cd"]
EOF
ORIGINAL_ATUIN_CHECKSUM=$(cksum < "$CASE_ROOT/config/atuin/config.toml")
INSTALL_OUTPUT=$(run_install "$CASE_ROOT/home" "$CASE_ROOT/config" --no-link 2>&1)
INSTALL_RC=$?
assert_eq 0 "$INSTALL_RC" 'installer merges an existing Atuin configuration'
assert_not_contains "$INSTALL_OUTPUT" 'warning:' 'successful installer emits no warnings'
assert_not_contains "$INSTALL_OUTPUT" 'error:' 'successful installer emits no errors'
ATUIN_CONFIG="$CASE_ROOT/config/atuin"
RESOLVED_FILTERS=$(ATUIN_CONFIG_DIR="$ATUIN_CONFIG" atuin config get history_filter 2>/dev/null)
assert_contains "$RESOLVED_FILTERS" '^keep-me' 'installer preserves custom Atuin filters'
assert_contains "$RESOLVED_FILTERS" '^also-keep[0-9]+' 'installer preserves filters containing brackets'
assert_eq '' "$(atuin_tab_id "$ATUIN_CONFIG")" \
  'installer adds leading-whitespace exclusion to Atuin filters'
assert_eq false "$(ATUIN_CONFIG_DIR="$ATUIN_CONFIG" atuin config get auto_sync)" \
  'installer disables Atuin automatic sync'
assert_eq false "$(ATUIN_CONFIG_DIR="$ATUIN_CONFIG" atuin config get update_check)" \
  'installer disables Atuin update checks'
assert_eq true "$(ATUIN_CONFIG_DIR="$ATUIN_CONFIG" atuin config get secrets_filter)" \
  'installer enables Atuin secret filtering'
assert_eq fuzzy "$(ATUIN_CONFIG_DIR="$ATUIN_CONFIG" atuin config get search_mode)" \
  'installer selects fuzzy Atuin search'
assert_file_contains "$ATUIN_CONFIG/config.toml" '# user comment must survive' \
  'installer preserves Atuin configuration comments'
FILTER_COUNT=$(grep -Ec '^[[:space:]]*history_filter[[:space:]]*=' "$ATUIN_CONFIG/config.toml")
assert_eq 1 "$FILTER_COUNT" 'installer writes exactly one active history_filter'
if awk '
  /^[[:space:]]*\[/ { if (!found) bad = 1 }
  /^[[:space:]]*history_filter[[:space:]]*=/ { found = 1 }
  END { exit(bad ? 1 : 0) }
' "$ATUIN_CONFIG/config.toml"; then
  pass 'installer writes history_filter at TOML top level'
else
  fail 'installer writes history_filter at TOML top level'
fi
if awk '
  /^[[:space:]]*\[/ { in_table = 1 }
  in_table && /^[[:space:]]*history_filter[[:space:]]*=/ { bad = 1 }
  END { exit(bad ? 1 : 0) }
' "$ATUIN_CONFIG/config.toml"; then
  pass 'installer removes table-scoped history_filter entries'
else
  fail 'installer removes table-scoped history_filter entries'
fi
assert_eq "$ORIGINAL_ATUIN_CHECKSUM" "$(cksum < "$ATUIN_CONFIG/config.toml.pre-mpz")" \
  'installer preserves the original Atuin configuration backup'

# A second run is idempotent and does not overwrite the first backup.
SECOND_OUTPUT=$(run_install "$CASE_ROOT/home" "$CASE_ROOT/config" --no-link 2>&1)
SECOND_RC=$?
assert_eq 0 "$SECOND_RC" 'installer is idempotent'
assert_not_contains "$SECOND_OUTPUT" 'warning:' 'idempotent installer emits no warnings'
assert_not_contains "$SECOND_OUTPUT" 'error:' 'idempotent installer emits no errors'
assert_eq 1 "$(grep -Ec '^[[:space:]]*history_filter[[:space:]]*=' "$ATUIN_CONFIG/config.toml")" \
  'idempotent installer does not duplicate history_filter'
assert_eq "$ORIGINAL_ATUIN_CHECKSUM" "$(cksum < "$ATUIN_CONFIG/config.toml.pre-mpz")" \
  'idempotent installer does not overwrite the Atuin backup'

# A table-scoped filter from an older buggy install is removed and repaired.
CASE_ROOT="$TEMP_ROOT/repair"
mkdir -p "$CASE_ROOT/home" "$CASE_ROOT/config/atuin"
cat > "$CASE_ROOT/config/atuin/config.toml" <<'EOF'
auto_sync = false

[search]
filters = ["global", "host"]
history_filter = ["old-table-scoped-filter"]
EOF
REPAIR_OUTPUT=$(run_install "$CASE_ROOT/home" "$CASE_ROOT/config" --no-link 2>&1)
REPAIR_RC=$?
assert_eq 0 "$REPAIR_RC" 'installer repairs a table-scoped Atuin history filter'
assert_not_contains "$REPAIR_OUTPUT" 'warning:' 'Atuin repair emits no warnings'
assert_not_contains "$REPAIR_OUTPUT" 'error:' 'Atuin repair emits no errors'
REPAIRED_FILTERS=$(ATUIN_CONFIG_DIR="$CASE_ROOT/config/atuin" atuin config get history_filter 2>/dev/null)
assert_eq '' "$(atuin_tab_id "$CASE_ROOT/config/atuin")" \
  'repaired Atuin filter excludes leading whitespace'
if grep -Eq '^[[:space:]]*history_filter[[:space:]]*=.*old-table-scoped-filter' \
  "$CASE_ROOT/config/atuin/config.toml"; then
  fail 'installer removes the old table-scoped filter value'
else
  pass 'installer removes the old table-scoped filter value'
fi

# Brackets inside TOML comments do not confuse the array parser.
CASE_ROOT="$TEMP_ROOT/comment"
mkdir -p "$CASE_ROOT/home" "$CASE_ROOT/config/atuin"
cat > "$CASE_ROOT/config/atuin/config.toml" <<'EOF'
history_filter = [ # comment with ]
  "^keep-me",
  '^literal]hash#value',
  "^double]hash#value",
]

[stats]
ignored_commands = ["cd"]
EOF
COMMENT_OUTPUT=$(run_install "$CASE_ROOT/home" "$CASE_ROOT/config" --no-link 2>&1)
COMMENT_RC=$?
assert_eq 0 "$COMMENT_RC" 'installer handles brackets inside TOML comments'
assert_not_contains "$COMMENT_OUTPUT" 'error:' 'comment-aware Atuin rewrite emits no errors'
COMMENT_FILTERS=$(ATUIN_CONFIG_DIR="$CASE_ROOT/config/atuin" atuin config get history_filter 2>/dev/null)
assert_contains "$COMMENT_FILTERS" '^keep-me' 'comment-aware Atuin rewrite preserves filters'
assert_contains "$COMMENT_FILTERS" 'literal]hash#value' \
  'comment-aware Atuin rewrite preserves brackets and hashes in literal strings'
assert_contains "$COMMENT_FILTERS" 'double]hash#value' \
  'comment-aware Atuin rewrite preserves brackets and hashes in basic strings'
assert_eq '' "$(atuin_tab_id "$CASE_ROOT/config/atuin")" \
  'comment-aware Atuin rewrite adds the exact whitespace filter'

# An unrelated whitespace regex must not be mistaken for the anchored filter.
CASE_ROOT="$TEMP_ROOT/unrelated-filter"
mkdir -p "$CASE_ROOT/home" "$CASE_ROOT/config/atuin"
cat > "$CASE_ROOT/config/atuin/config.toml" <<'EOF'
history_filter = ["password\\s+"]
EOF
UNRELATED_OUTPUT=$(run_install "$CASE_ROOT/home" "$CASE_ROOT/config" --no-link 2>&1)
UNRELATED_RC=$?
assert_eq 0 "$UNRELATED_RC" 'installer accepts an unrelated whitespace filter'
assert_not_contains "$UNRELATED_OUTPUT" 'error:' 'unrelated-filter rewrite emits no errors'
UNRELATED_FILTERS=$(ATUIN_CONFIG_DIR="$CASE_ROOT/config/atuin" atuin config get history_filter 2>/dev/null)
assert_contains "$UNRELATED_FILTERS" 'password' 'unrelated-filter rewrite preserves the original filter'
assert_eq '' "$(atuin_tab_id "$CASE_ROOT/config/atuin")" \
  'unrelated-filter rewrite adds the exact anchored whitespace filter'

# A deceptive filter that merely contains the expected text is not accepted as
# the exact policy. The installer must add a real element and verify behavior.
CASE_ROOT="$TEMP_ROOT/deceptive-filter"
mkdir -p "$CASE_ROOT/home" "$CASE_ROOT/config/atuin"
cat > "$CASE_ROOT/config/atuin/config.toml" <<'EOF'
history_filter = ["x'^\\s+'"]
EOF
DECEPTIVE_OUTPUT=$(run_install "$CASE_ROOT/home" "$CASE_ROOT/config" --no-link 2>&1)
DECEPTIVE_RC=$?
assert_eq 0 "$DECEPTIVE_RC" 'installer repairs a deceptive Atuin filter'
assert_not_contains "$DECEPTIVE_OUTPUT" 'error:' 'deceptive-filter repair emits no errors'
DECEPTIVE_FILTERS=$(ATUIN_CONFIG_DIR="$CASE_ROOT/config/atuin" atuin config get history_filter 2>/dev/null)
assert_contains "$DECEPTIVE_FILTERS" "x'^" \
  'deceptive-filter repair preserves the original filter'
assert_eq '' "$(atuin_tab_id "$CASE_ROOT/config/atuin")" \
  'deceptive-filter repair enforces leading-whitespace exclusion'

# An explicit Atuin configuration directory is the installer's active target.
CASE_ROOT="$TEMP_ROOT/custom-atuin-dir"
mkdir -p "$CASE_ROOT/home"
CUSTOM_OUTPUT=$(HOME="$CASE_ROOT/home" \
  XDG_CONFIG_HOME="$CASE_ROOT/config" \
  XDG_CACHE_HOME="$CASE_ROOT/home/.cache" \
  XDG_STATE_HOME="$CASE_ROOT/home/.local/state" \
  ATUIN_CONFIG_DIR="$CASE_ROOT/custom/atuin" \
  "$ROOT/scripts/install" --no-deps --no-link 2>&1)
CUSTOM_RC=$?
assert_eq 0 "$CUSTOM_RC" 'installer accepts an explicit Atuin configuration directory'
assert_not_contains "$CUSTOM_OUTPUT" 'install: error:' \
  'custom Atuin directory install emits no errors'
if [[ -r "$CASE_ROOT/custom/atuin/config.toml" ]]; then
  pass 'installer configures the explicit Atuin configuration directory'
else
  fail 'installer configures the explicit Atuin configuration directory'
fi
if [[ ! -e "$CASE_ROOT/config/atuin/config.toml" ]]; then
  pass 'installer does not create a second default Atuin configuration'
else
  fail 'installer does not create a second default Atuin configuration'
fi

# A failed isolated rewrite must leave the active Atuin configuration intact.
CASE_ROOT="$TEMP_ROOT/invalid-candidate"
mkdir -p "$CASE_ROOT/home" "$CASE_ROOT/config/atuin"
cat > "$CASE_ROOT/config/atuin/config.toml" <<'EOF'
auto_sync = true
this is not valid toml =
EOF
INVALID_CHECKSUM=$(cksum < "$CASE_ROOT/config/atuin/config.toml")
INVALID_OUTPUT=$(run_install "$CASE_ROOT/home" "$CASE_ROOT/config" --no-link 2>&1)
INVALID_RC=$?
assert_eq 1 "$INVALID_RC" 'installer rejects an invalid Atuin candidate'
assert_contains "$INVALID_OUTPUT" 'install: error:' \
  'invalid Atuin candidate reports an installer error'
assert_eq "$INVALID_CHECKSUM" \
  "$(cksum < "$CASE_ROOT/config/atuin/config.toml")" \
  'invalid Atuin candidate preserves the active configuration byte-for-byte'
assert_eq "$INVALID_CHECKSUM" \
  "$(cksum < "$CASE_ROOT/config/atuin/config.toml.pre-mpz")" \
  'invalid Atuin candidate preserves the original backup'
if [[ -z "$(find "$CASE_ROOT/config/atuin" -maxdepth 1 -type d -name '.rewrite.*' -print -quit)" ]]; then
  pass 'invalid Atuin candidate removes its isolated working directory'
else
  fail 'invalid Atuin candidate removes its isolated working directory'
fi

# A dangling preferred Atuin backup path is preserved, while the original
# configuration is retained in a collision-proof fallback backup.
CASE_ROOT="$TEMP_ROOT/dangling-atuin-backup"
mkdir -p "$CASE_ROOT/home" "$CASE_ROOT/config/atuin"
cat > "$CASE_ROOT/config/atuin/config.toml" <<'EOF'
auto_sync = true
history_filter = ["^keep-me"]
EOF
DANGLING_CHECKSUM=$(cksum < "$CASE_ROOT/config/atuin/config.toml")
ln -s "$CASE_ROOT/config/atuin/missing-target" \
  "$CASE_ROOT/config/atuin/config.toml.pre-mpz"
DANGLING_OUTPUT=$(run_install "$CASE_ROOT/home" "$CASE_ROOT/config" --no-link 2>&1)
DANGLING_RC=$?
assert_eq 0 "$DANGLING_RC" 'installer handles a dangling preferred Atuin backup path'
assert_not_contains "$DANGLING_OUTPUT" 'install: error:' \
  'dangling Atuin backup install emits no errors'
if [[ -L "$CASE_ROOT/config/atuin/config.toml.pre-mpz" ]]; then
  pass 'installer preserves a dangling preferred Atuin backup path'
else
  fail 'installer preserves a dangling preferred Atuin backup path'
fi
DANGLING_FALLBACK=$(find "$CASE_ROOT/config/atuin" -maxdepth 1 -type f \
  -name 'config.toml.pre-mpz.*' -print -quit)
assert_eq "$DANGLING_CHECKSUM" "$(cksum < "$DANGLING_FALLBACK")" \
  'dangling Atuin backup path gets a content-preserving fallback backup'
DANGLING_FILTERS=$(ATUIN_CONFIG_DIR="$CASE_ROOT/config/atuin" atuin config get history_filter 2>/dev/null)
assert_contains "$DANGLING_FILTERS" '^keep-me' \
  'dangling-backup rewrite preserves the original Atuin filters'
fi

# A directory at a startup-file path is rejected without being replaced.
CASE_ROOT="$TEMP_ROOT/directory-startup-path"
mkdir -p "$CASE_ROOT/home/.zshrc"
DIRECTORY_OUTPUT=$(run_install "$CASE_ROOT/home" "$CASE_ROOT/config" 2>&1)
DIRECTORY_RC=$?
assert_eq 1 "$DIRECTORY_RC" 'installer rejects a directory at a startup-file path'
assert_contains "$DIRECTORY_OUTPUT" 'refusing to replace' \
  'directory startup path reports a clear error'
if [[ -d "$CASE_ROOT/home/.zshrc" ]]; then
  pass 'installer preserves a directory at a startup-file path'
else
  fail 'installer preserves a directory at a startup-file path'
fi
if [[ ! -e "$CASE_ROOT/config/atuin/config.toml" ]]; then
  pass 'startup-path preflight prevents unrelated configuration changes'
else
  fail 'startup-path preflight prevents unrelated configuration changes'
fi

# A problem with the second startup path must not partially link the first.
CASE_ROOT="$TEMP_ROOT/second-directory-startup-path"
mkdir -p "$CASE_ROOT/home/.zshenv"
printf 'original zshrc\n' > "$CASE_ROOT/home/.zshrc"
SECOND_DIRECTORY_OUTPUT=$(run_install "$CASE_ROOT/home" "$CASE_ROOT/config" 2>&1)
SECOND_DIRECTORY_RC=$?
assert_eq 1 "$SECOND_DIRECTORY_RC" \
  'installer rejects a directory at the second startup-file path'
assert_eq 'original zshrc' "$(<"$CASE_ROOT/home/.zshrc")" \
  'second-path preflight leaves the first startup file unchanged'
if [[ -d "$CASE_ROOT/home/.zshenv" ]]; then
  pass 'installer preserves a directory at the second startup-file path'
else
  fail 'installer preserves a directory at the second startup-file path'
fi

# Special files are rejected before any read or replacement can block.
CASE_ROOT="$TEMP_ROOT/fifo-startup-path"
mkdir -p "$CASE_ROOT/home"
mkfifo "$CASE_ROOT/home/.zshrc"
FIFO_OUTPUT=$(run_install "$CASE_ROOT/home" "$CASE_ROOT/config" 2>&1)
FIFO_RC=$?
assert_eq 1 "$FIFO_RC" 'installer rejects a FIFO at a startup-file path'
assert_contains "$FIFO_OUTPUT" 'regular file' \
  'FIFO startup path reports a clear error'
if [[ -p "$CASE_ROOT/home/.zshrc" ]]; then
  pass 'installer preserves a FIFO at a startup-file path'
else
  fail 'installer preserves a FIFO at a startup-file path'
fi
if [[ ! -e "$CASE_ROOT/config/atuin/config.toml" ]]; then
  pass 'FIFO startup preflight prevents unrelated configuration changes'
else
  fail 'FIFO startup preflight prevents unrelated configuration changes'
fi

if (( $+commands[atuin] )); then
  CASE_ROOT="$TEMP_ROOT/fifo-atuin-config"
  mkdir -p "$CASE_ROOT/home" "$CASE_ROOT/config/atuin"
  mkfifo "$CASE_ROOT/config/atuin/config.toml"
  ATUIN_FIFO_OUTPUT=$(run_install "$CASE_ROOT/home" "$CASE_ROOT/config" --no-link 2>&1)
  ATUIN_FIFO_RC=$?
  assert_eq 1 "$ATUIN_FIFO_RC" 'installer rejects a FIFO at the Atuin configuration path'
  assert_contains "$ATUIN_FIFO_OUTPUT" 'regular file' \
    'FIFO Atuin configuration reports a clear error'
  if [[ -p "$CASE_ROOT/config/atuin/config.toml" ]]; then
    pass 'installer preserves a FIFO at the Atuin configuration path'
  else
    fail 'installer preserves a FIFO at the Atuin configuration path'
  fi
fi

# A failure while staging a later checkout leaves every active checkout at its
# previous revision. The complete vendor set is published only after staging.
CASE_ROOT="$TEMP_ROOT/vendor-transaction"
mkdir -p "$CASE_ROOT/project/scripts" "$CASE_ROOT/project/vendor" \
  "$CASE_ROOT/source-one" "$CASE_ROOT/source-two"
cp -p "$ROOT/scripts/install" "$CASE_ROOT/project/scripts/install"
printf 'old\n' > "$CASE_ROOT/source-one/content"
git -C "$CASE_ROOT/source-one" init -q
git -C "$CASE_ROOT/source-one" config user.name 'MPZ Test'
git -C "$CASE_ROOT/source-one" config user.email 'mpz@example.invalid'
git -C "$CASE_ROOT/source-one" add content
git -C "$CASE_ROOT/source-one" commit -qm old
OLD_COMMIT=$(git -C "$CASE_ROOT/source-one" rev-parse HEAD)
printf 'new\n' > "$CASE_ROOT/source-one/content"
git -C "$CASE_ROOT/source-one" commit -qam new
NEW_COMMIT=$(git -C "$CASE_ROOT/source-one" rev-parse HEAD)
printf 'two\n' > "$CASE_ROOT/source-two/content"
git -C "$CASE_ROOT/source-two" init -q
git -C "$CASE_ROOT/source-two" config user.name 'MPZ Test'
git -C "$CASE_ROOT/source-two" config user.email 'mpz@example.invalid'
git -C "$CASE_ROOT/source-two" add content
git -C "$CASE_ROOT/source-two" commit -qm initial
SECOND_COMMIT=$(git -C "$CASE_ROOT/source-two" rev-parse HEAD)
printf 'two-new\n' > "$CASE_ROOT/source-two/content"
git -C "$CASE_ROOT/source-two" commit -qam new
SECOND_NEW_COMMIT=$(git -C "$CASE_ROOT/source-two" rev-parse HEAD)
git clone -q "$CASE_ROOT/source-one" "$CASE_ROOT/project/vendor/one"
git -C "$CASE_ROOT/project/vendor/one" checkout -q --detach "$OLD_COMMIT"
git clone -q "$CASE_ROOT/source-two" "$CASE_ROOT/project/vendor/two"
git -C "$CASE_ROOT/project/vendor/two" checkout -q --detach "$SECOND_COMMIT"
cat > "$CASE_ROOT/project/deps.lock" <<EOF
git one file://$CASE_ROOT/source-one $NEW_COMMIT
git two file://$CASE_ROOT/missing-source $SECOND_NEW_COMMIT
EOF
TRANSACTION_OUTPUT=$("$CASE_ROOT/project/scripts/install" \
  --no-link --no-configure-atuin 2>&1)
TRANSACTION_RC=$?
assert_eq 1 "$TRANSACTION_RC" 'installer rejects a failed later vendor staging step'
assert_contains "$TRANSACTION_OUTPUT" 'cannot fetch two' \
  'vendor transaction reports the failed checkout'
assert_eq "$OLD_COMMIT" \
  "$(git -C "$CASE_ROOT/project/vendor/one" rev-parse HEAD)" \
  'vendor staging failure preserves the first active checkout'
assert_eq "$SECOND_COMMIT" \
  "$(git -C "$CASE_ROOT/project/vendor/two" rev-parse HEAD)" \
  'vendor staging failure preserves the second active checkout'
if [[ -z "$(find "$CASE_ROOT/project/vendor" -maxdepth 1 -type d \
  -name '.mpz-stage.*' -print -quit)" ]]; then
  pass 'vendor staging failure removes its temporary transaction'
else
  fail 'vendor staging failure removes its temporary transaction'
fi

# Startup-file links are atomic, backed up, and reversible.
CASE_ROOT="$TEMP_ROOT/links"
mkdir -p "$CASE_ROOT/home"
printf 'old zshrc\n' > "$CASE_ROOT/home/.zshrc"
printf 'old zshenv\n' > "$CASE_ROOT/home/.zshenv"
LINK_OUTPUT=$(run_install "$CASE_ROOT/home" "$CASE_ROOT/config" 2>&1)
LINK_RC=$?
assert_eq 0 "$LINK_RC" 'installer links both startup files'
assert_not_contains "$LINK_OUTPUT" 'warning:' 'successful linking emits no warnings'
assert_not_contains "$LINK_OUTPUT" 'error:' 'successful linking emits no errors'
assert_eq "$ROOT/.zshrc" "$(readlink "$CASE_ROOT/home/.zshrc")" \
  'installer links .zshrc to the repository'
assert_eq "$ROOT/.zshenv" "$(readlink "$CASE_ROOT/home/.zshenv")" \
  'installer links .zshenv to the repository'
assert_eq 'old zshrc' "$(<"$CASE_ROOT/home/.zshrc.pre-mpz")" \
  'installer backs up the previous .zshrc'
assert_eq 'old zshenv' "$(<"$CASE_ROOT/home/.zshenv.pre-mpz")" \
  'installer backs up the previous .zshenv'

UNINSTALL_OUTPUT=$(HOME="$CASE_ROOT/home" XDG_CONFIG_HOME="$CASE_ROOT/config" \
  "$ROOT/scripts/uninstall" 2>&1)
UNINSTALL_RC=$?
assert_eq 0 "$UNINSTALL_RC" 'uninstaller succeeds'
assert_contains "$UNINSTALL_OUTPUT" 'restored' 'uninstaller reports restored startup files'
assert_eq 'old zshrc' "$(<"$CASE_ROOT/home/.zshrc")" 'uninstaller restores .zshrc'
assert_eq 'old zshenv' "$(<"$CASE_ROOT/home/.zshenv")" 'uninstaller restores .zshenv'
if [[ -r "$CASE_ROOT/config/atuin/config.toml" ]]; then
  pass 'uninstaller preserves Atuin configuration'
else
  fail 'uninstaller preserves Atuin configuration'
fi

# A stale rollback record cannot restore a file that was absent when the
# startup-file link was created.
CASE_ROOT="$TEMP_ROOT/stale-rollback-record"
mkdir -p "$CASE_ROOT/home" "$CASE_ROOT/config/my-perfect-zsh"
printf 'stale backup\n' > "$CASE_ROOT/stale-backup"
printf '%s\n' "$CASE_ROOT/stale-backup" > \
  "$CASE_ROOT/config/my-perfect-zsh/rollback-.zshrc-path"
STALE_OUTPUT=$(run_install "$CASE_ROOT/home" "$CASE_ROOT/config" 2>&1)
STALE_RC=$?
assert_eq 0 "$STALE_RC" 'installer links over a stale rollback record'
assert_not_contains "$STALE_OUTPUT" 'install: error:' \
  'stale-rollback install emits no errors'
HOME="$CASE_ROOT/home" XDG_CONFIG_HOME="$CASE_ROOT/config" \
  "$ROOT/scripts/uninstall" >/dev/null 2>&1
if [[ ! -e "$CASE_ROOT/home/.zshrc" && ! -L "$CASE_ROOT/home/.zshrc" ]]; then
  pass 'uninstaller does not restore a stale backup over an absent file'
else
  fail 'uninstaller does not restore a stale backup over an absent file'
fi

# Backup names are collision-proof, including when the preferred backup path
# is a dangling symlink.
CASE_ROOT="$TEMP_ROOT/backup-collisions"
mkdir -p "$CASE_ROOT/home"
printf 'original zshrc\n' > "$CASE_ROOT/home/.zshrc"
ln -s "$CASE_ROOT/home/missing-target" "$CASE_ROOT/home/.zshrc.pre-mpz"
COLLISION_FIRST=$(run_install "$CASE_ROOT/home" "$CASE_ROOT/config" 2>&1)
COLLISION_FIRST_RC=$?
assert_eq 0 "$COLLISION_FIRST_RC" 'installer handles a dangling preferred backup path'
assert_not_contains "$COLLISION_FIRST" 'error:' 'dangling-backup install emits no errors'
FIRST_RECORD="$CASE_ROOT/config/my-perfect-zsh/rollback-.zshrc-path"
FIRST_BACKUP=$(<"$FIRST_RECORD")
assert_eq 'original zshrc' "$(<"$FIRST_BACKUP")" 'first collision-proof backup preserves .zshrc'
if [[ -L "$CASE_ROOT/home/.zshrc.pre-mpz" ]]; then
  pass 'installer does not overwrite a dangling preferred backup path'
else
  fail 'installer does not overwrite a dangling preferred backup path'
fi

rm -- "$CASE_ROOT/home/.zshrc"
printf 'intermediate zshrc\n' > "$CASE_ROOT/home/.zshrc"
COLLISION_SECOND=$(run_install "$CASE_ROOT/home" "$CASE_ROOT/config" 2>&1)
COLLISION_SECOND_RC=$?
assert_eq 0 "$COLLISION_SECOND_RC" 'second rapid install succeeds'
assert_not_contains "$COLLISION_SECOND" 'error:' 'second rapid install emits no errors'
SECOND_RECORD="$CASE_ROOT/config/my-perfect-zsh/rollback-.zshrc-path"
SECOND_BACKUP=$(<"$SECOND_RECORD")
if [[ "$SECOND_BACKUP" != "$FIRST_BACKUP" ]]; then
  pass 'rapid installs use distinct backup paths'
else
  fail 'rapid installs use distinct backup paths'
fi
assert_eq 'intermediate zshrc' "$(<"$SECOND_BACKUP")" 'second collision-proof backup preserves .zshrc'

rm -- "$CASE_ROOT/home/.zshrc"
printf 'latest zshrc\n' > "$CASE_ROOT/home/.zshrc"
COLLISION_THIRD=$(run_install "$CASE_ROOT/home" "$CASE_ROOT/config" 2>&1)
COLLISION_THIRD_RC=$?
assert_eq 0 "$COLLISION_THIRD_RC" 'third rapid install succeeds'
assert_not_contains "$COLLISION_THIRD" 'error:' 'third rapid install emits no errors'
THIRD_RECORD="$CASE_ROOT/config/my-perfect-zsh/rollback-.zshrc-path"
THIRD_BACKUP=$(<"$THIRD_RECORD")
if [[ "$THIRD_BACKUP" != "$SECOND_BACKUP" && "$THIRD_BACKUP" != "$FIRST_BACKUP" ]]; then
  pass 'all rapid-install backup paths are distinct'
else
  fail 'all rapid-install backup paths are distinct'
fi
assert_eq 'latest zshrc' "$(<"$THIRD_BACKUP")" 'third collision-proof backup preserves .zshrc'

HOME="$CASE_ROOT/home" XDG_CONFIG_HOME="$CASE_ROOT/config" \
  "$ROOT/scripts/uninstall" >/dev/null 2>&1
assert_eq 'latest zshrc' "$(<"$CASE_ROOT/home/.zshrc")" \
  'uninstaller restores the most recent collision-proof backup'

print -r -- "installer: ${PASSED} passed, ${FAILED} failed"
(( FAILED == 0 ))
