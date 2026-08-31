#!/usr/bin/env zsh
# =============================================================================
# zcore.zsh — Single-file loader for the zcore framework
# =============================================================================
# Description:  Sources the six zcore modules in dependency order so a
#               consumer can `source zcore.zsh` instead of hand-ordering
#               zlog, zbase, ui, zkv, zbus, and z. Loading is idempotent:
#               a second source, or a source after the modules are already
#               present, is a no-op. A missing or failed module aborts with
#               a fatal message on stderr.
#
# Usage:        source /path/to/zcore/zcore.zsh
#               source ~/.local/share/zcore/zcore.zsh
#
# Public API:   none — sources the six modules; their APIs become available
# Private API:  _zcore_zsh_loaded  (internal — no compatibility guarantee)
#
# Requires:     zlog, zbase, ui, zkv, zbus, z — files next to this loader
#
# Version:      0.6.0
# License:      MIT
# =============================================================================


# =============================================================================
# IDEMPOTENT LOAD GUARD
# =============================================================================
# Set only after every module has sourced successfully, so a failed load
# can be retried. Each module has its own guard, so sourcing this file
# after a manual load is still a no-op at the module level.

if (( ${_zcore_zsh_loaded:-0} )); then return 0; fi


# =============================================================================
# MODULE LOAD
# =============================================================================
# %x is this file even when sourced, so the modules resolve next to the
# loader rather than next to whatever script performed the source.

typeset -g _zcore_zsh_root="${${(%):-%x}:A:h}"
typeset -g _zcore_zsh_mod

for _zcore_zsh_mod in zlog zbase ui zkv zbus z; do
  if [[ ! -r ${_zcore_zsh_root}/${_zcore_zsh_mod} ]]; then
    print -u2 "zcore.zsh: fatal: missing module: ${_zcore_zsh_root}/${_zcore_zsh_mod}"
    unset _zcore_zsh_root _zcore_zsh_mod
    return 1 2>/dev/null || exit 1
  fi
  if ! source "${_zcore_zsh_root}/${_zcore_zsh_mod}"; then
    print -u2 "zcore.zsh: fatal: failed to load ${_zcore_zsh_mod}"
    unset _zcore_zsh_root _zcore_zsh_mod
    return 1 2>/dev/null || exit 1
  fi
done

unset _zcore_zsh_root _zcore_zsh_mod
typeset -gi _zcore_zsh_loaded=1
