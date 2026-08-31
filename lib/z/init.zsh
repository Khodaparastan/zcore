#!/usr/bin/env zsh
# =============================================================================
# z/init.zsh — On-source initialization
# =============================================================================
# Description:  Runs after every definition is in place: seeds configuration
#               defaults, records the active subsystems, installs the
#               interrupt trap, and logs the startup banner.
#
# Part of:      z — assembled by bin/zbundle; see lib/z/parts
#
# Requires:     zlog, zkv; zbus when the bus subsystem is active
# =============================================================================

# Runs on source, after every definition above is in place.

# The KV-backed config store; zkv is a hard prerequisite, so this is a
# formality that also records the subsystem as active.
if (( ${+functions[z::kv::open]} )); then
  _zcore_subsys[kv]=1
  __z::config::init_defaults
fi
_zcore_subsys[cache]=1

if (( _zcore_subsys[bus] == 1 )); then
  z::bus::init 2>/dev/null || zlog::warn "zbus init failed; event integration disabled"
  z::event::emit "zcore:initialized" "$ZCORE_VERSION" 2>/dev/null || true
fi

# Scripts must opt in via ZCORE_INSTALL_TRAPS: installing an INT/TERM trap
# unasked would override whatever handler the embedding script has set.
if [[ -o interactive ]] || [[ ${ZCORE_INSTALL_TRAPS:-} == true ]]; then
  trap '__z::sys::handle_interrupt' INT TERM
fi

# PERF: plain assignments rather than inline `$( ... && echo ✓ || echo ✗ )`,
# which would fork three subshells on every shell startup.
typeset _zcore_mark_cache='✗' _zcore_mark_kv='✗' _zcore_mark_bus='✗'
(( _zcore_subsys[cache] == 1 )) && _zcore_mark_cache='✓'
(( _zcore_subsys[kv]    == 1 )) && _zcore_mark_kv='✓'
(( _zcore_subsys[bus]   == 1 )) && _zcore_mark_bus='✓'
zlog::info "zCore initialized .::. Cache ${_zcore_mark_cache} | KV Store ${_zcore_mark_kv} | Event Bus ${_zcore_mark_bus}"
unset _zcore_mark_cache _zcore_mark_kv _zcore_mark_bus
