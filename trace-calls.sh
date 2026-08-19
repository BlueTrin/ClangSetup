#!/usr/bin/env bash
#
# trace-calls.sh -- log every function matching a pattern, in execution order.
#
# The no-rebuild replacement for adding a log line to find out where control
# actually goes. Prints one line per call and lets the program run to the end.
#
# Usage:
#   ./trace-calls.sh <config> <pattern> [program args...]
#
# Example:
#   ./trace-calls.sh checked 'Discounter::*'   --trade 12345
#   ./trace-calls.sh checked '*Curve*::build*' --trade 12345
#
# Warning: broad patterns are slow. '*::*' will set tens of thousands of
# breakpoints and take minutes. Start narrow and widen only if you must.

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_cdb-common.sh"

if [[ $# -lt 2 ]]; then
  printf 'usage: %s <config> <pattern> [program args...]\n' "$(basename "$0")" >&2
  printf "example: %s checked 'Discounter::*' --trade 12345\n" "$(basename "$0")" >&2
  exit 2
fi

use_config "$1"
pattern="$2"
shift 2

check_prereqs
module="$(module_name)"

# bm with a command  -- set breakpoints and attach an action to each
# .printf "%y"       -- print the symbol at the current instruction pointer
# gc                 -- "go from conditional breakpoint": resume immediately
# g                  -- run to completion
#
# \$scopeip is escaped so bash leaves it for cdb to expand.
run_cdb_script "$@" <<CDB
.echo === tracing ${module}!${pattern} ===
bm ${module}!${pattern} ".printf \"CALL %y\\n\", @\$scopeip; gc"
g
.echo === STOP REASON (exception, or clean exit) ===
.lastevent
.echo === STACK AT STOP (meaningless if the process exited cleanly) ===
k
q
CDB
