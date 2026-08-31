#!/usr/bin/env zsh
# =============================================================================
# z/event.zsh — Event bus integration
# =============================================================================
# Description:  Binds thin z::event::* wrappers over z::bus::* when zbus was
#               sourced first, and records the bus subsystem as active.
#
# Part of:      z — assembled by bin/zbundle; see lib/z/parts
#
# Requires:     zbus — optional; nothing is defined when it is absent
# =============================================================================

# Thin z::event::* wrappers over z::bus::*, bound only when zbus was sourced
# first. They keep subsystem code decoupled from the bus module's namespace;
# arguments are passed through unchanged, so zbus documents the semantics.
# When zbus is absent these functions do not exist and every internal emission
# is gated on _zcore_subsys[bus].

if (( ${+functions[z::bus::emit]} )); then
  _zcore_subsys[bus]=1

  z::event::emit()        { z::bus::emit "$@"; }
  z::event::emit_safe()   { z::bus::emit_safe "$@"; }
  z::event::emit_async()  { z::bus::emit_async "$@"; }
  z::event::on()          { z::bus::on "$@"; }
  z::event::once()        { z::bus::once "$@"; }
  z::event::off()         { z::bus::off "$@"; }
  z::event::off_id()      { z::bus::off_id "$@"; }
  z::event::has()         { z::bus::has "$@"; }
  z::event::subscribe()   { z::bus::subscribe "$@"; }
  z::event::unsubscribe() { z::bus::unsubscribe "$@"; }
  z::event::publish()     { z::bus::publish "$@"; }
fi


