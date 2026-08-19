#!/usr/bin/env bash
#
# on-crash.sh -- run to completion and dump diagnostics if it faults or throws.
#
# Use when the program crashes or exits on an unhandled exception and you need
# to know where. Exits quietly if the run is clean.
#
# Usage:
#   ./on-crash.sh <config> [program args...]
#
# Example:
#   ./on-crash.sh checked --trade 12345
#
# Options (environment):
#   TRACE_THROWS=1   also print the stack at every C++ throw, not just the
#                    unhandled one. Shows the raise site before unwinding,
#                    but is noisy if the code throws as part of normal flow.
#   DUMP_PATH=file   write a full memory dump for offline analysis.

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_cdb-common.sh"

if [[ $# -lt 1 ]]; then
  printf 'usage: %s <config> [program args...]\n' "$(basename "$0")" >&2
  printf 'example: %s checked --trade 12345\n' "$(basename "$0")" >&2
  exit 2
fi

use_config "$1"
shift

check_prereqs

# sxe eh  -- break on the C++ EH exception (0xe06d7363) at the throw site
# kb      -- stack there
# gn      -- "go not handled": resume so normal handling still runs
throw_hook=""
if [[ "${TRACE_THROWS:-0}" == "1" ]]; then
  throw_hook='sxe -c "kb; gn" eh'
fi

dump_cmd=""
if [[ -n "${DUMP_PATH:-}" ]]; then
  dump_cmd=".dump /ma $(cygpath -w "${DUMP_PATH}")"
fi

# g          -- run; cdb stops automatically on an unhandled exception
# .lastevent -- why we stopped: breakpoint, exception, or process exit
# .exr -1    -- the exception record (code and faulting address)
# kp         -- stack with named arguments (needs good PDBs)
# ~*kb       -- every thread's stack, in case the fault is on a worker
run_cdb_script "$@" <<CDB
${throw_hook}
g
.echo === STOP REASON ===
.lastevent
.echo === EXCEPTION RECORD ===
.exr -1
.echo === ANALYSIS ===
!analyze -v
.echo === FAULTING THREAD ===
kp
.echo === ALL THREADS ===
~*kb
${dump_cmd}
q
CDB
