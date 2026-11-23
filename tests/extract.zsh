#!/usr/bin/env zsh
# Archive extraction confinement and path-safety regression tests.

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

assert_file() {
  local path="$1"
  local message="$2"
  if [[ -f "$path" ]]; then
    pass "$message"
  else
    fail "$message"
  fi
}

assert_absent() {
  local path="$1"
  local message="$2"
  if [[ ! -e "$path" && ! -L "$path" ]]; then
    pass "$message"
  else
    fail "$message"
  fi
}

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/mpz-extract.XXXXXX") || exit 1
trap 'rm -rf -- "$TEMP_ROOT"' EXIT INT TERM

mkdir -p "$TEMP_ROOT/source" "$TEMP_ROOT/output" "$TEMP_ROOT/victim"
printf 'safe payload\n' > "$TEMP_ROOT/source/payload"
printf 'must remain unchanged\n' > "$TEMP_ROOT/victim/keep"

source "$ROOT/lib/extract.zsh"

tar -czf "$TEMP_ROOT/safe-tar.tar.gz" -C "$TEMP_ROOT/source" payload
extract -t "$TEMP_ROOT/output" "$TEMP_ROOT/safe-tar.tar.gz" \
  > "$TEMP_ROOT/safe-tar.out" 2> "$TEMP_ROOT/safe-tar.err"
SAFE_TAR_RC=$?
assert_eq 0 "$SAFE_TAR_RC" 'extract accepts a safe tar archive'
assert_eq 0 "$(wc -c < "$TEMP_ROOT/safe-tar.out")" \
  'safe tar extraction emits no stdout'
assert_eq 0 "$(wc -c < "$TEMP_ROOT/safe-tar.err")" \
  'safe tar extraction emits no stderr'
assert_file "$TEMP_ROOT/output/safe-tar/payload" \
  'safe tar extraction publishes the payload'

/usr/bin/python3 - "$TEMP_ROOT" <<'PY'
from __future__ import annotations

import pathlib
import stat
import sys
import tarfile
import zipfile

root = pathlib.Path(sys.argv[1])
with zipfile.ZipFile(root / "safe-zip.zip", "w") as archive:
    archive.writestr("payload", "safe payload\n")

with tarfile.open(root / "traversal-tar.tar.gz", "w:gz") as archive:
    fixture_root = root / "fixtures"
    fixture_root.mkdir(exist_ok=True)
    payload = fixture_root / "outside-tar"
    payload.write_text("owned\n", encoding="utf-8")
    archive.add(payload, arcname="../outside-tar")

with tarfile.open(root / "symlink-tar.tar.gz", "w:gz") as archive:
    info = tarfile.TarInfo("escape")
    info.type = tarfile.SYMTYPE
    info.linkname = str(root / "victim")
    archive.addfile(info)

with zipfile.ZipFile(root / "traversal-zip.zip", "w") as archive:
    archive.writestr("../outside-zip", "owned\n")

with zipfile.ZipFile(root / "symlink-zip.zip", "w") as archive:
    info = zipfile.ZipInfo("escape")
    info.create_system = 3
    info.external_attr = (stat.S_IFLNK | 0o777) << 16
    archive.writestr(info, str(root / "victim"))
PY

extract -t "$TEMP_ROOT/output" "$TEMP_ROOT/safe-zip.zip" \
  > "$TEMP_ROOT/safe-zip.out" 2> "$TEMP_ROOT/safe-zip.err"
SAFE_ZIP_RC=$?
assert_eq 0 "$SAFE_ZIP_RC" 'extract accepts a safe zip archive'
assert_file "$TEMP_ROOT/output/safe-zip/payload" \
  'safe zip extraction publishes the payload'

for archive in traversal-tar.tar.gz symlink-tar.tar.gz traversal-zip.zip symlink-zip.zip; do
  TAR_OPTIONS=--absolute-names extract -t "$TEMP_ROOT/output" \
    "$TEMP_ROOT/$archive" > "$TEMP_ROOT/$archive.out" 2> "$TEMP_ROOT/$archive.err"
  ATTACK_RC=$?
  assert_eq 1 "$ATTACK_RC" "extract rejects $archive"
  assert_eq 0 "$(wc -c < "$TEMP_ROOT/$archive.out")" \
    "rejected $archive emits no stdout"
done

assert_eq 'must remain unchanged' "$(<"$TEMP_ROOT/victim/keep")" \
  'malicious archives do not modify files outside the output directory'
assert_absent "$TEMP_ROOT/output/traversal-tar" \
  'rejected tar traversal publishes no output directory'
assert_absent "$TEMP_ROOT/output/symlink-tar" \
  'rejected tar symlink publishes no output directory'
assert_absent "$TEMP_ROOT/output/traversal-zip" \
  'rejected zip traversal publishes no output directory'
assert_absent "$TEMP_ROOT/output/symlink-zip" \
  'rejected zip symlink publishes no output directory'
assert_absent "$TEMP_ROOT/outside-tar" \
  'rejected tar traversal does not write beside the output directory'
assert_absent "$TEMP_ROOT/outside-zip" \
  'rejected zip traversal does not write beside the output directory'

print -r -- "extract: ${PASSED} passed, ${FAILED} failed"
(( FAILED == 0 ))
