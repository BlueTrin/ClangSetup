#!/usr/bin/env bash
#
# Shared configuration and helpers for the cdb wrapper scripts.
# Sourced by where-called.sh and trace-calls.sh -- not meant to be run directly.
#
# Override any of these from the environment:
#   TARGET_EXE   full path to the executable under investigation
#   CDB_EXE      full path to cdb.exe
#   SYMBOL_PATH  directory containing the .pdb files (defaults to the exe's dir)

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

: "${BUILD_ROOT:=${repo_root}/build}"
: "${EXE_NAME:=pricer.exe}"
: "${CDB_EXE:=/c/Program Files (x86)/Windows Kits/10/Debuggers/x64/cdb.exe}"

# Resolve TARGET_EXE and SYMBOL_PATH from a build config name (e.g. "checked").
# Layout assumed: ${BUILD_ROOT}/<config>/${EXE_NAME}
# Override BUILD_ROOT or EXE_NAME from the environment if yours differs.
use_config() {
  local config="$1"
  [[ -n "${config}" ]] || die "no build config given"

  local dir="${BUILD_ROOT}/${config}"
  [[ -d "${dir}" ]] || die "no such build config: ${config} (looked in ${dir})"

  TARGET_EXE="${dir}/${EXE_NAME}"
  : "${SYMBOL_PATH:=${dir}}"
  export TARGET_EXE SYMBOL_PATH

  # Per-config environment, if the config needs one. Optional.
  local env_file="${dir}/debug-env.sh"
  [[ -f "${env_file}" ]] && source "${env_file}"

  return 0
}

: "${TARGET_EXE:=${BUILD_ROOT}/checked/${EXE_NAME}}"
: "${SYMBOL_PATH:=$(dirname "${TARGET_EXE}")}"

# Git Bash rewrites arguments that look like POSIX paths before handing them to
# a native .exe. cdb command strings contain characters MSYS likes to mangle, so
# turn the conversion off for everything we launch from here.
export MSYS2_ARG_CONV_EXCL='*'

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# Verify the tools and inputs exist before we launch anything, so failures are
# a clear message rather than a confusing cdb error.
check_prereqs() {
  [[ -x "${CDB_EXE}" ]] || die "cdb not found at: ${CDB_EXE} (set CDB_EXE)"
  [[ -f "${TARGET_EXE}" ]] || die "target exe not found at: ${TARGET_EXE} (set TARGET_EXE)"

  local pdb_count
  pdb_count="$(find "${SYMBOL_PATH}" -maxdepth 1 -name '*.pdb' 2>/dev/null | wc -l)"
  if [[ "${pdb_count}" -eq 0 ]]; then
    printf 'warning: no .pdb files under %s -- output will show addresses, not function names\n' \
      "${SYMBOL_PATH}" >&2
  fi

  export _NT_SYMBOL_PATH="$(cygpath -w "${SYMBOL_PATH}")"
}

# Split a comma-separated symbol/pattern list into one pattern per line.
#
# The caller quotes the whole list as a single argument, so 'ns1::*,ns2::*'
# arrives here intact. Surrounding whitespace is trimmed and empty elements are
# dropped, which makes 'ns1::* , ns2::*' and 'ns1::*,,ns2::*' both yield two
# patterns. Returns non-zero if nothing usable is left, so callers can die with
# a message naming the original input.
#
# read -a does the splitting rather than an unquoted expansion, because the
# patterns contain * and would otherwise be glob-expanded against the cwd.
split_patterns() {
  local list="$1" item
  local -a parts=() out=()

  IFS=',' read -r -a parts <<< "${list}"

  for item in "${parts[@]}"; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    if [[ -n "${item}" ]]; then
      out+=("${item}")
    fi
  done

  (( ${#out[@]} )) || return 1
  printf '%s\n' "${out[@]}"
}

# Module name as cdb sees it: the exe basename without extension.
module_name() { basename "${TARGET_EXE}" .exe; }

# Run a cdb command script (read from stdin) against TARGET_EXE.
#
# Using a script file via -cf avoids the nested-quoting nightmare of passing
# cdb commands through -c from bash. Remaining arguments are forwarded to the
# target program.
run_cdb_script() {
  local cdb_script tmp_out rc
  cdb_script="$(mktemp --suffix=.cdb)"
  tmp_out="$(mktemp --suffix=.log)"
  trap 'rm -f "${cdb_script}" "${tmp_out}"' RETURN

  cat > "${cdb_script}"

  set +e
  "${CDB_EXE}" \
    -lines \
    -cf "$(cygpath -w "${cdb_script}")" \
    "$(cygpath -w "${TARGET_EXE}")" "$@" \
    > "${tmp_out}" 2>&1
  rc=$?
  set -e

  cat "${tmp_out}"
  return "${rc}"
}
