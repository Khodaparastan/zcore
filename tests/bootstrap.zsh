#!/usr/bin/env zsh
# =============================================================================
# bootstrap.zsh — Shared fixture for every zcore test file
# =============================================================================
# Description:  Locates the repository root, loads the ztest framework, and
#               loads framework modules on demand. Every test file sources
#               this once and then declares what it needs with
#               ztest::require, so a suite states its own prerequisites
#               instead of inheriting whatever the runner happened to load.
#               Loading is idempotent and dependency-ordered: requiring `z`
#               pulls in zlog, zbase and zkv first, and a module already
#               present in the shell is never sourced twice.
#
#               Sourcing this file is also what makes a suite runnable on
#               its own, without the runner.
#
# Usage:        source "${0:A:h}/../../bootstrap.zsh"  # tests/unit/*/
#               source "${0:A:h}/../bootstrap.zsh"     # tests/integration/
#               ztest::require zkv
#
# Public API:   ztest::require, ztest::child_prelude
# Private API:  _ztest_bootstrap_*  (internal — no compatibility guarantee)
#
# Requires:     tests/ztest — sourced here
#               the repository root — inferred from this file's location
#
# Provides:     ZCORE_ROOT — absolute path of the repository root
#               ZCORE_MODULES — the module chain in dependency order
#
# Version:      0.6.0
# License:      MIT
# =============================================================================

# Sourcing twice must not re-source the modules already in the shell.
if (( ${_ztest_bootstrap_loaded:-0} )); then
  return 0
fi
typeset -gi _ztest_bootstrap_loaded=1

# This file lives at <root>/tests/, so the root is two levels up. The probe
# keeps a moved or copied checkout from failing later with a confusing
# "command not found" instead of here.
typeset -g ZCORE_ROOT="${0:A:h:h}"
if [[ ! -f ${ZCORE_ROOT}/zbase ]]; then
  print -u2 -r -- "bootstrap: cannot locate the repository root from ${0:A}"
  return 1
fi

source "${ZCORE_ROOT}/tests/ztest" \
  || { print -u2 -r -- "bootstrap: failed to source tests/ztest"; return 1; }


# =============================================================================
# MODULE REGISTRY
# =============================================================================
# Load order is fixed by the chain below; the two maps describe each module's
# hard prerequisites and the function that proves it is already loaded.
# Optional relationships (ui and zbus for z) are deliberately absent — a
# suite that wants them asks for them by name.

typeset -ga ZCORE_MODULES=( zlog zbase ui zkv zbus z )

typeset -gA _ztest_bootstrap_deps=(
  [zlog]=''
  [zbase]='zlog'
  [ui]='zlog'
  [zkv]='zlog zbase'
  [zbus]='zlog zbase zkv'
  [z]='zlog zbase zkv'
)

typeset -gA _ztest_bootstrap_probe=(
  [zlog]='zlog::info'
  [zbase]='z::is::int'
  [ui]='z::progress::show'
  [zkv]='z::kv::set'
  [zbus]='z::bus::emit'
  [z]='z::cache::set'
)


# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# _ztest_bootstrap_resolve <module> [<module> ...]
# Expand the requested modules into the full prerequisite closure and set
# `reply` to it in ZCORE_MODULES order, which is the order it must be sourced
# in. Returns 1 on an unknown module name, leaving `reply` undefined.
_ztest_bootstrap_resolve() {
  emulate -L zsh
  local -A want
  local -a queue
  local module dep

  queue=( "$@" )
  while (( ${#queue} )); do
    module="${queue[1]}"
    shift queue
    if [[ -z ${_ztest_bootstrap_probe[$module]:-} ]]; then
      print -u2 -r -- "ztest: unknown module: $module"
      return 1
    fi
    (( ${+want[$module]} )) && continue
    want[$module]=1
    for dep in ${=_ztest_bootstrap_deps[$module]}; do
      queue+=( "$dep" )
    done
  done

  reply=()
  for module in "${ZCORE_MODULES[@]}"; do
    (( ${+want[$module]} )) && reply+=( "$module" )
  done
  return 0
}


# =============================================================================
# PUBLIC API
# =============================================================================

# ztest::require <module> [<module> ...]
# Source the named modules and their prerequisites into the current shell, in
# dependency order, skipping any that are already loaded. Silences zlog once
# zlog is present, so module diagnostics do not drown out assertion output.
# Clobbers `reply`. Returns 1 on an unknown module name or a failed source.
ztest::require() {
  emulate -L zsh
  local module
  local -a chain

  _ztest_bootstrap_resolve "$@" || return 1
  chain=( "${reply[@]}" )

  for module in "${chain[@]}"; do
    (( ${+functions[${_ztest_bootstrap_probe[$module]}]} )) && continue
    source "${ZCORE_ROOT}/${module}" \
      || { print -u2 -r -- "ztest::require: failed to source $module"; return 1 }
    [[ $module == zlog ]] && zlog::set_level error
  done

  return 0
}

# ztest::child_prelude <module> [<module> ...]
# Set REPLY to a snippet that loads the named modules in a clean child shell,
# for tests that need real process isolation (`zsh -f -c "$REPLY; ..."`).
# The chain is resolved exactly as ztest::require resolves it, and paths are
# quoted, so a checkout in a path with spaces still works. Clobbers `reply`.
# Returns 1 on an unknown module name.
ztest::child_prelude() {
  emulate -L zsh
  local module
  local -a lines

  _ztest_bootstrap_resolve "$@" || return 1

  for module in "${reply[@]}"; do
    lines+=( "source ${(q)ZCORE_ROOT}/${module}" )
  done
  lines+=( 'zlog::set_level error' )

  REPLY="${(j:; :)lines}"
  return 0
}
