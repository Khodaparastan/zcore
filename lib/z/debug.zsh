#!/usr/bin/env zsh
# =============================================================================
# z/debug.zsh — Tracing, profiling, and assertions
# =============================================================================
# Description:  Call-stack tracing, a zkv-backed profiling timer, and an
#               assertion helper that unwinds through z::sys::die.
#
# Part of:      z — assembled by bin/zbundle; see lib/z/parts
#
# Requires:     zlog, zkv (the ephemeral `profiling` store), zbase
#               (z::is::int), and z::config::show for the dump helper
# =============================================================================


# z::debug::trace
# Print the current function call stack to stderr, innermost caller first.
# Always returns 0.
z::debug::trace() {
  emulate -L zsh
  local -i i
  print "Stack trace:" >&2
  # funcstack[1] is this function; start at 1 to include the immediate caller.
  for (( i = 1; i < ${#funcstack[@]}; i++ )); do
    print "  $i: ${funcstack[i]} (${funcfiletrace[i]})" >&2
  done
  return 0
}


# z::debug::dump
# Print the full configuration table to stdout — an alias for z::config::show
# kept for symmetry with the rest of the z::debug:: namespace.
z::debug::dump() {
  emulate -L zsh
  z::config::show
  return 0
}


# z::debug::profile_start [<operation>]
# Record a high-resolution start timestamp for a named operation in the
# ephemeral zkv `profiling` store. Returns Z_ERR_GENERAL when that store
# cannot be opened.
z::debug::profile_start() {
  emulate -L zsh
  setopt extendedglob warncreateglobal typesetsilent noshortloops nopromptsubst
  local operation="${1:-operation}"
  z::kv::open profiling 2>/dev/null || return $Z_ERR_GENERAL
  z::kv::set profiling "${operation}.start" "${EPOCHREALTIME:-0}"
  zlog::debug "Profiling started" operation "$operation"
  return 0
}


# z::debug::profile_end [<operation>]
# Close the profiling session opened by z::debug::profile_start, storing
# `<operation>.end` and `<operation>.duration` and logging the elapsed time.
# Emits `debug:profile` when the bus is active. Returns Z_ERR_NOTFOUND when no
# start timestamp was recorded for the operation.
z::debug::profile_end() {
  emulate -L zsh
  setopt extendedglob warncreateglobal typesetsilent noshortloops nopromptsubst

  local operation="${1:-operation}"
  local -F start end duration

  if ! z::kv::get profiling "${operation}.start" 2>/dev/null; then
    zlog::warn "No profiling start time recorded" operation "$operation"
    return $Z_ERR_NOTFOUND
  fi
  # Must be read before the next zlog call — every zlog helper clobbers REPLY.
  start=$REPLY
  end=${EPOCHREALTIME:-0}
  (( duration = end - start ))

  z::kv::set profiling "${operation}.end" "$end"
  z::kv::set profiling "${operation}.duration" "$duration"
  zlog::debug "Profiling finished" operation "$operation" \
    duration_s "$(printf '%.3f' "$duration")"

  # Emit a profiling event only when the bus subsystem is active.
  if (( _zcore_subsys[bus] == 1 )); then
    z::event::emit "debug:profile" "$operation" "$duration" || true
  fi

  return 0
}


# z::debug::assert <condition> [<message>]
# Fail loudly when <condition> is a non-zero integer: print a stack trace and
# hand the message to z::sys::die. Shell truth is inverted here — 0 passes,
# mirroring a command's exit status. Returns Z_ERR_INPUT when <condition> is
# not an integer.
z::debug::assert() {
  emulate -L zsh
  local raw_condition="${1:-1}"
  local message="${2:-Assertion failed}"

  # SAFETY: validate before arithmetic. Feeding a non-integer straight into
  # `(( condition = ... ))` either raises a math error or silently evaluates
  # to 0, passing an assertion that was never actually checked.
  if ! z::is::int "$raw_condition"; then
    zlog::error "z::debug::assert: condition must be an integer" \
      condition "$raw_condition"
    return $Z_ERR_INPUT
  fi
  typeset -i condition=$raw_condition

  if (( condition != 0 )); then
    z::debug::trace
    z::sys::die "$message" $Z_ERR_GENERAL
  fi
  return 0
}


