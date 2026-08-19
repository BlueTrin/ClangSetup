#!/usr/bin/env bash
#
# where-called.sh -- show the call stack the first time a function is reached.
#
# Answers "who actually calls this?" without editing source or rebuilding.
# Use it to confirm a call path before assuming one from reading the code.
#
# Usage:
#   ./where-called.sh <config> <symbol> [program args...]
#
# Example:
#   ./where-called.sh checked Discounter::df --trade 12345
#   ./where-called.sh optimised 'OisDiscounter::*' --trade 12345
#
# The symbol is matched inside the target module only. Wildcards are allowed.

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_cdb-common.sh"

if [[ $# -lt 2 ]]; then
  printf 'usage: %s <config> <symbol> [program args...]\n' "$(basename "$0")" >&2
  printf 'example: %s checked Discounter::df --trade 12345\n' "$(basename "$0")" >&2
  exit 2
fi

use_config "$1"
symbol="$2"
shift 2

check_prereqs
module="$(module_name)"

# bm  -- set breakpoints on every symbol matching the pattern
# g   -- run until one is hit
# k   -- print the call stack at that point
# q   -- quit, killing the target
run_cdb_script "$@" <<CDB
.echo === breakpoints set on ${module}!${symbol} ===
bm ${module}!${symbol}
g
.echo === STOP REASON (breakpoint, exception, or exit) ===
.lastevent
.echo === STACK AT STOP ===
k
q
CDB
