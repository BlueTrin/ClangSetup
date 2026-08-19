#!/usr/bin/env bash
#
# where-called.sh -- show the call stack the first time a function is reached.
#
# Answers "who actually calls this?" without editing source or rebuilding.
# Use it to confirm a call path before assuming one from reading the code.
#
# Usage:
#   ./where-called.sh <config> <symbols> [program args...]
#
# <symbols> is one symbol, or several separated by commas and quoted as a
# single argument. Note what several symbols means here: the run stops at the
# FIRST hit of ANY of them and prints that one stack. It does not stop once per
# symbol. Use it to find whichever of several candidates is reached first; use
# trace-calls.sh if you need every hit.
#
# Example:
#   ./where-called.sh checked Discounter::df --trade 12345
#   ./where-called.sh optimised 'OisDiscounter::*' --trade 12345
#   ./where-called.sh checked 'ns1::Foo::bar,ns2::Baz::qux' --trade 12345
#
# Symbols are matched inside the target module only. Wildcards are allowed.

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_cdb-common.sh"

if [[ $# -lt 2 ]]; then
  printf 'usage: %s <config> <symbols> [program args...]\n' "$(basename "$0")" >&2
  printf 'example: %s checked Discounter::df --trade 12345\n' "$(basename "$0")" >&2
  printf "example: %s checked 'ns1::Foo::bar,ns2::Baz::qux' --trade 12345\n" "$(basename "$0")" >&2
  exit 2
fi

use_config "$1"
symbol_arg="$2"
shift 2

check_prereqs
module="$(module_name)"

patterns_out="$(split_patterns "${symbol_arg}")" \
  || die "no symbol to break on in: ${symbol_arg}"
mapfile -t patterns <<< "${patterns_out}"

printf -v pattern_list '%s, ' "${patterns[@]}"
pattern_list="${pattern_list%, }"

# One bm per symbol. cdb accumulates them into a single breakpoint set, which
# is why g below stops at whichever symbol the program reaches first.
bm_lines=""
for pattern in "${patterns[@]}"; do
  bm_lines+="bm ${module}!${pattern}"$'\n'
done
bm_lines="${bm_lines%$'\n'}"

# bm  -- set breakpoints on every symbol matching the pattern
# g   -- run until one is hit
# k   -- print the call stack at that point
# q   -- quit, killing the target
run_cdb_script "$@" <<CDB
.echo === breakpoints set on ${module}: ${pattern_list} ===
${bm_lines}
g
.echo === STOP REASON (breakpoint, exception, or exit) ===
.lastevent
.echo === STACK AT STOP ===
k
q
CDB
