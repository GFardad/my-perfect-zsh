#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
failed=0

while IFS= read -r -d '' file; do
  if ! zsh -n "$file"; then
    printf 'syntax: failed: %s\n' "$file" >&2
    failed=1
  fi
done < <(find "$ROOT" \
  -path "$ROOT/vendor" -prune -o \
  -path "$ROOT/audit" -prune -o \
  -path "$ROOT/config/local.d" -prune -o \
  -type f \( -name '*.zsh' -o -name '.zshrc' -o -name '.zshenv' \) -print0)

if (( failed )); then
  exit 1
fi
printf 'syntax: all Zsh files passed zsh -n\n'
