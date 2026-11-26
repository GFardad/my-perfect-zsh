#!/usr/bin/env zsh
# Reproducible cold/warm startup benchmark.

set -u
zmodload zsh/datetime

ROOT=${0:A:h:h}
WARMUPS=${MPZ_BENCH_WARMUPS:-3}
COLD_BUDGET_MS=${MPZ_COLD_BUDGET_MS:-300}
P50_BUDGET_MS=${MPZ_P50_BUDGET_MS:-60}
P95_BUDGET_MS=${MPZ_P95_BUDGET_MS:-80}

IGNORE_LOAD=0
while (($#)); do
  case "$1" in
    --ignore-load)
      IGNORE_LOAD=1
      shift
      ;;
    *)
      break
      ;;
  esac
done
ITERATIONS=${1:-30}

if [[ "$ITERATIONS" != <-> ]] || (( ITERATIONS < 5 )); then
  print -u2 -- 'perf: iterations must be an integer of at least 5'
  exit 2
fi

# A startup budget is only evidence when the machine is quiet enough for the
# sample to describe the configuration rather than competing load. A loaded
# machine produces numbers that look like a regression, so the measurement is
# refused instead of reported, and the load is printed alongside any result.
typeset -g LOAD1='' LOAD_CORES=0
load_snapshot() {
  local line cores
  line=$(</proc/loadavg 2>/dev/null) || return 1
  cores=$(command nproc 2>/dev/null) || cores=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null) || return 1
  [[ "$line" == *' '* && "$cores" == <-> ]] || return 1
  (( cores >= 1 )) || return 1
  LOAD1=${line%% *}
  LOAD_CORES=$cores
  return 0
}

if load_snapshot; then
  # zsh compares decimal load averages with <-> only for integers, so the
  # comparison is done in awk with an exact threshold.
  refuse_after=$(awk -v cores="$LOAD_CORES" -v factor="${MPZ_LOAD_REFUSE_FACTOR:-2}" \
    'BEGIN { printf "%.1f", cores * factor }')
  warn_after=$(awk -v cores="$LOAD_CORES" -v factor="${MPZ_LOAD_WARN_FACTOR:-1}" \
    'BEGIN { printf "%.1f", cores * factor }')
  if awk -v avg="$LOAD1" -v limit="$refuse_after" 'BEGIN { exit !(avg > limit) }'; then
    if (( IGNORE_LOAD )); then
      print -u2 -- "perf: warning: load ${LOAD1} exceeds ${refuse_after}; continuing because --ignore-load was given"
    else
      print -u2 -- "perf: refusing to measure: load ${LOAD1} exceeds ${refuse_after} (${LOAD_CORES} cores)"
      print -u2 -- 'perf: a loaded machine measures contention, not startup. Retry when idle, or use'
      print -u2 -- 'perf: --ignore-load to force, or set MPZ_LOAD_REFUSE_FACTOR to change the limit.'
      exit 1
    fi
  elif awk -v avg="$LOAD1" -v limit="$warn_after" 'BEGIN { exit !(avg > limit) }'; then
    print -u2 -- "perf: note: load ${LOAD1} is above ${warn_after}; numbers include some contention"
  fi
else
  print -u2 -- 'perf: note: load average unavailable; numbers cannot be qualified'
fi

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/mpz-benchmark.XXXXXX") || exit 1
trap 'rm -rf -- "$TEMP_ROOT"' EXIT INT TERM

mkdir -p \
  "$TEMP_ROOT/home" \
  "$TEMP_ROOT/zdot" \
  "$TEMP_ROOT/config" \
  "$TEMP_ROOT/cache" \
  "$TEMP_ROOT/state" \
  "$TEMP_ROOT/data" \
  "$TEMP_ROOT/atuin-home" \
  "$TEMP_ROOT/config/atuin"
ln -s "$ROOT/.zshrc" "$TEMP_ROOT/zdot/.zshrc"
ln -s "$ROOT/.zshenv" "$TEMP_ROOT/zdot/.zshenv"
cp "$ROOT/config/atuin/config.toml" "$TEMP_ROOT/config/atuin/config.toml"

run_shell() {
  HOME="$TEMP_ROOT/home" \
  XDG_CONFIG_HOME="$TEMP_ROOT/config" \
  XDG_CACHE_HOME="$TEMP_ROOT/cache" \
  XDG_STATE_HOME="$TEMP_ROOT/state" \
  XDG_DATA_HOME="$TEMP_ROOT/data" \
  ATUIN_HOME="$TEMP_ROOT/atuin-home" \
  ATUIN_CONFIG_DIR="$TEMP_ROOT/config/atuin" \
  ZDOTDIR="$TEMP_ROOT/zdot" \
  command zsh -lic exit >/dev/null 2>"$TEMP_ROOT/stderr"
}

measure_shell() {
  local start=$EPOCHREALTIME
  local end
  run_shell || return 1
  end=$EPOCHREALTIME
  printf -v REPLY '%.0f' "$(( (end - start) * 1000 ))"
}

rm -f -- "$TEMP_ROOT/cache/zsh/zcompdump-$ZSH_VERSION"
if ! measure_shell; then
  print -u2 -- 'perf: cold startup failed'
  sed -n '1,120p' "$TEMP_ROOT/stderr" >&2
  exit 1
fi
COLD_MS=$REPLY
[[ ! -s "$TEMP_ROOT/stderr" ]] || {
  print -u2 -- 'perf: cold startup emitted diagnostics'
  sed -n '1,120p' "$TEMP_ROOT/stderr" >&2
  exit 1
}

for (( index = 1; index <= WARMUPS; index++ )); do
  run_shell || {
    print -u2 -- 'perf: warmup failed'
    exit 1
  }
done

typeset -a samples
for (( index = 1; index <= ITERATIONS; index++ )); do
  if ! measure_shell; then
    print -u2 -- 'perf: warm startup failed'
    exit 1
  fi
  samples+=("$REPLY")
  [[ ! -s "$TEMP_ROOT/stderr" ]] || {
    print -u2 -- 'perf: warm startup emitted diagnostics'
    sed -n '1,120p' "$TEMP_ROOT/stderr" >&2
    exit 1
  }
done

printf '%s\n' "${samples[@]}" | sort -n > "$TEMP_ROOT/samples"
P50_INDEX=$(( (ITERATIONS + 1) / 2 ))
P95_INDEX=$(( (95 * ITERATIONS + 99) / 100 ))
P50_MS=$(sed -n "${P50_INDEX}p" "$TEMP_ROOT/samples")
P95_MS=$(sed -n "${P95_INDEX}p" "$TEMP_ROOT/samples")
MAX_MS=$(tail -n 1 "$TEMP_ROOT/samples")

print -r -- "cold: ${COLD_MS} ms (budget ${COLD_BUDGET_MS} ms)"
print -r -- "warm p50: ${P50_MS} ms (budget ${P50_BUDGET_MS} ms)"
print -r -- "warm p95: ${P95_MS} ms (budget ${P95_BUDGET_MS} ms)"
print -r -- "warm max: ${MAX_MS} ms across ${ITERATIONS} samples"

failed=0
(( COLD_MS <= COLD_BUDGET_MS )) || failed=1
(( P50_MS <= P50_BUDGET_MS )) || failed=1
(( P95_MS <= P95_BUDGET_MS )) || failed=1
exit "$failed"
