#!/usr/bin/env bash
#
# trace-calls.sh -- log every function matching a pattern, in execution order.
#
# The no-rebuild replacement for adding a log line to find out where control
# actually goes. Prints one line per call and lets the program run to the end.
#
# Usage:
#   ./trace-calls.sh <config> <patterns> [program args...]
#
# <patterns> is one pattern, or several separated by commas and quoted as a
# single argument. Every pattern is traced in the same run, so calls from
# different namespaces appear interleaved in the order they actually happened.
#
# Example:
#   ./trace-calls.sh checked 'Discounter::*'   --trade 12345
#   ./trace-calls.sh checked '*Curve*::build*' --trade 12345
#   ./trace-calls.sh checked 'ns1::*,ns2::*'   --trade 12345
#
# Warning: broad patterns are slow. '*::*' will set tens of thousands of
# breakpoints and take minutes. Start narrow and widen only if you must. A
# comma-separated list costs roughly the sum of its parts, so prefer two narrow
# patterns over one wide one that happens to cover both.

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_cdb-common.sh"

if [[ $# -lt 2 ]]; then
  printf 'usage: %s <config> <patterns> [program args...]\n' "$(basename "$0")" >&2
  printf "example: %s checked 'Discounter::*' --trade 12345\n" "$(basename "$0")" >&2
  printf "example: %s checked 'ns1::*,ns2::*' --trade 12345\n" "$(basename "$0")" >&2
  exit 2
fi

use_config "$1"
pattern_arg="$2"
shift 2

check_prereqs
module="$(module_name)"

patterns_out="$(split_patterns "${pattern_arg}")" \
  || die "no pattern to trace in: ${pattern_arg}"
mapfile -t patterns <<< "${patterns_out}"

printf -v pattern_list '%s, ' "${patterns[@]}"
pattern_list="${pattern_list%, }"

# The action attached to every breakpoint. Single-quoted so bash leaves the
# backslashes and $scopeip untouched -- cdb, not bash, expands them:
#
#   bm with a command  -- set breakpoints and attach an action to each
#   .printf "%y"       -- print the symbol at the current instruction pointer
#   gc                 -- "go from conditional breakpoint": resume immediately
trace_action='".printf \"CALL %y\n\", @$scopeip; gc"'

# One bm per pattern. cdb accumulates them, so a call matching any pattern is
# logged, and g then runs the whole program to completion.
bm_lines=""
for pattern in "${patterns[@]}"; do
  bm_lines+="bm ${module}!${pattern} ${trace_action}"$'\n'
done
bm_lines="${bm_lines%$'\n'}"

run_cdb_script "$@" <<CDB
.echo === tracing ${module}: ${pattern_list} ===
${bm_lines}
g
.echo === STOP REASON (exception, or clean exit) ===
.lastevent
.echo === STACK AT STOP (meaningless if the process exited cleanly) ===
k
q
CDB
