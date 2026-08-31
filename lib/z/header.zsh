#!/usr/bin/env zsh
# =============================================================================
# z — Framework integration layer
# =============================================================================
# Description:  Wires the framework pillars — logging, validation, KV store,
#               event bus — into one runtime and exposes them as five
#               namespaces: cache, config, sys, event, debug. Initialises on
#               source: seeds configuration defaults into the KV `config`
#               store, installs the interrupt trap, and binds the z::event::*
#               wrappers when zbus is loaded. Sourcing twice is a no-op.
#
# Usage:        source z              # after zlog, zbase, zkv (ui/zbus opt.)
#               z::cache::set "api:token" "$token" --ttl 3600
#               z::config::get log_level        # value lands in $REPLY
#
# Public API:   z::cache::*   — process-scoped TTL cache and memoization
#               z::config::*  — KV-backed configuration
#               z::sys::*     — platform detection, interrupts, fatal exits
#               z::event::*   — thin wrappers over zbus, bound when present
#               z::debug::*   — profiling, assertions, diagnostics
#               z::help::*    — API listing
# Private API:  __z::*, _zcore_*  (internal — no compatibility guarantee)
#
# Requires:     zlog  — structured logging; must be sourced first
#               zbase — validation, probes, Z_ERR_* codes
#               zkv   — KV store backing z::config::*
#               ui    — progress bars; optional, absence is tolerated
#               zbus  — event bus; optional, enables z::event::*
#
# Provides:     ZCORE_VERSION, ZCORE_SUCCESS, ZCORE_ERROR_TIMEOUT,
#               ZCORE_ERROR_INTERRUPTED, and the IS_MACOS / IS_LINUX / IS_BSD
#               / IS_CYGWIN / IS_WSL / IS_TERMUX / IS_UNKNOWN platform flags
#
# Version:      0.6.0
# License:      MIT
# =============================================================================


# =============================================================================
# LOAD GUARD AND VERSION
# =============================================================================

# Re-initialisation within a session is a no-op. `return` covers the sourced
# case, `exit` the executed one.
if [[ ${_zcore_loaded:-} == 1 ]]; then return 0 2>/dev/null || exit 0; fi
typeset -g _zcore_loaded=1
# Keep in sync with the file header and ./VERSION.
typeset -gr ZCORE_VERSION="0.6.0"


# =============================================================================
# RUNTIME DEPENDENCY CHECKS
# =============================================================================
# Hard prerequisites only: `ui` and `zbus` are optional and their absence is
# handled at each call site. `return` works in a sourced context; fall back to
# `exit` when executed.
if (( ! ${+functions[zlog::info]} )); then
  print -u2 "z: fatal: zlog must be sourced before z"; return 1 2>/dev/null || exit 1
fi
if (( ! ${+functions[z::ensure::nonempty]} )); then
  print -u2 "z: fatal: zbase must be sourced before z"; return 1 2>/dev/null || exit 1
fi
if (( ! ${+functions[z::kv::open]} )); then
  print -u2 "z: fatal: zkv must be sourced before z"; return 1 2>/dev/null || exit 1
fi
if (( ! ${+Z_ERR_GENERAL} )); then
  print -u2 "z: fatal: zbase error codes missing — zbase too old"; return 1 2>/dev/null || exit 1
fi

# Ensure EPOCHSECONDS is available when possible (no-op if unavailable).
zmodload -F zsh/datetime b:EPOCHSECONDS 2>/dev/null || true


# =============================================================================
# CONSTANTS
# =============================================================================
# z-only return codes; the shared Z_ERR_* set belongs to zbase and must never
# be redefined here.
typeset -gri ZCORE_SUCCESS=0
typeset -gri ZCORE_ERROR_TIMEOUT=124
typeset -gri ZCORE_ERROR_INTERRUPTED=130

# Per-subsystem availability flags (1 = active), populated by the
# INITIALIZATION section at the foot of this file. Every optional-subsystem
# call site is gated on these rather than on ${+functions[...]}.
typeset -gA _zcore_subsys
_zcore_subsys[kv]=0; _zcore_subsys[bus]=0; _zcore_subsys[cache]=0;


