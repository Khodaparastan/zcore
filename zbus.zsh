#!/usr/bin/env zsh

################################################################################
# ZCORE EVENT BUS  (zbus)
################################################################################
#
# A production-grade pub/sub event system for Zsh with:
#   - Event registration and emission
#   - Priority-based handler ordering (0–100, higher runs first)
#   - One-time event handlers
#   - Event namespacing and wildcard patterns
#   - Handler removal and full cleanup
#   - Event history and statistics
#   - Async event emission (fire-and-forget)
#   - Safe emission with per-handler subshell + hard timeout isolation
#   - Error isolation (a failing handler never crashes the bus)
#   - Full zlog integration for structured, leveled diagnostics
#
# Requires: zlog.zsh (z::log::*), z.zsh (z::config::*, z::validate::*, z::probe::*)
# System:   timeout(1) — GNU coreutils, for hard per-handler timeout in emit_safe
# Version: 2.1.0
################################################################################

# Guard against double-sourcing
if [[ ${_zcore_event_bus_loaded:-} == 1 ]]; then return 0 2>/dev/null || exit 0; fi
typeset -g _zcore_event_bus_loaded=1

################################################################################
# STATE
################################################################################

# Handler storage — split for O(1) exact vs O(n) wildcard
typeset -gA _zcore_event_handlers_exact     # event_name  -> pipe-separated handler IDs
typeset -gA _zcore_event_handlers_wildcard  # pattern     -> pipe-separated handler IDs

# Per-handler metadata: "${id}.{key}" -> value
typeset -gA _zcore_event_handler_meta

# Event history (ring-buffer maintained by __z::event::add_to_history)
typeset -ga _zcore_event_history

# Monotonic handler ID counter
typeset -gi _zcore_event_handler_id=0

# Emission statistics: "${event}.{emitted|handled|failed}" -> count
typeset -gA _zcore_event_stats

################################################################################
# PRIORITY CONSTANTS  (read-only globals)
################################################################################

typeset -gri ZCORE_EVENT_PRIORITY_HIGHEST=100
typeset -gri ZCORE_EVENT_PRIORITY_HIGH=75
typeset -gri ZCORE_EVENT_PRIORITY_NORMAL=50
typeset -gri ZCORE_EVENT_PRIORITY_LOW=25
typeset -gri ZCORE_EVENT_PRIORITY_LOWEST=0

################################################################################
# DEFAULT CONFIGURATION  (via z::config, overridable at runtime)
################################################################################

# Hard-coded default constants — used as fallback when z::config::get is
# unavailable (e.g. z::kv backend not loaded) to prevent arithmetic errors.
typeset -gri ZCORE_EVENT_MAX_HISTORY=100
typeset -gri ZCORE_EVENT_HANDLER_TIMEOUT=5
typeset -gri ZCORE_EVENT_MAX_HANDLERS_PER_EVENT=50

# Register the same values with the config system for runtime overrides.
z::config::set event_max_history            $ZCORE_EVENT_MAX_HISTORY
z::config::set event_handler_timeout        $ZCORE_EVENT_HANDLER_TIMEOUT
z::config::set event_max_handlers_per_event $ZCORE_EVENT_MAX_HANDLERS_PER_EVENT
z::config::set event_enable_history         true
z::config::set event_enable_stats           true
z::config::set event_enable_wildcards       true

################################################################################
# PRIVATE HELPERS
################################################################################

###
# Generate the next unique handler ID.
# Sets the variable named by $1 in the caller's scope.
# @private
###
__z::event::generate_id() {
  emulate -L zsh
  setopt localoptions no_unset warn_create_global
  (( _zcore_event_handler_id += 1 ))
  : ${(P)1::=handler_${_zcore_event_handler_id}}
}

###
# Validate event name — alphanumeric plus _ : * -
# @private  @return 0 valid | ZCORE_ERROR_INVALID_INPUT invalid
###
__z::event::validate_event_name() {
  emulate -L zsh
  setopt localoptions no_unset extended_glob

  local event_name="$1"
  z::validate::nonempty "$event_name" "Event name" || return $ZCORE_ERROR_INVALID_INPUT

  if [[ ! $event_name =~ ^[a-zA-Z0-9_:*-]+$ ]]; then
    z::log::error "Invalid event name format" \
      name "$event_name" allowed "a-zA-Z0-9_:*-"
    return $ZCORE_ERROR_INVALID_INPUT
  fi
}

###
# Validate that a handler function is defined.
# @private  @return 0 exists | ZCORE_ERROR_NOT_FOUND missing
###
__z::event::validate_handler() {
  emulate -L zsh
  setopt localoptions no_unset

  local handler="$1"
  z::validate::nonempty "$handler" "Handler" || return $ZCORE_ERROR_INVALID_INPUT

  if ! z::probe::func "$handler"; then
    z::log::error "Handler function not defined" handler "$handler"
    return $ZCORE_ERROR_NOT_FOUND
  fi
}

# Public alias used by framework probe machinery
z::probe::event_handler() { emulate -L zsh; __z::event::validate_handler "${1:-}"; }

################################################################################
# PUBLIC API — CONVENIENCE ALIASES
################################################################################

###
# Convenience aliases — idiomatic short-hand for subscribe / unsubscribe.
# These are the names used throughout examples, tests, and documentation.
###

# z::event::on  — identical to z::event::subscribe
z::event::on() {
  emulate -L zsh
  setopt localoptions no_unset
  z::event::subscribe "$@"
}

# z::event::once — subscribe a handler that fires only once
z::event::once() {
  emulate -L zsh
  setopt localoptions no_unset
  z::event::subscribe_once "$@"
}

# z::event::off  — identical to z::event::unsubscribe
z::event::off() {
  emulate -L zsh
  setopt localoptions no_unset
  z::event::unsubscribe "$@"
}

###
# Parse a pipe-separated handler list into the named array.
# @private
###
__z::event::parse_handler_list() {
  emulate -L zsh
  setopt localoptions no_unset

  local handler_list="$1"
  local output_array="$2"

  if [[ -z $handler_list ]]; then
    : ${(PA)output_array::=()}
    return 0
  fi

  : ${(PA)output_array::=${(s:|:)handler_list}}
}

###
# Sort the named array of handler IDs descending by priority (in-place).
# @private
###
__z::event::sort_handlers_by_priority() {
  emulate -L zsh
  setopt localoptions no_unset

  local array_name="$1"
  local -a handlers=("${(@P)array_name}")
  local -a sortable
  local handler_id
  typeset -i priority_val

  for handler_id in "${handlers[@]}"; do
    (( priority_val = ${_zcore_event_handler_meta[${handler_id}.priority]:-50} ))
    sortable+=("${priority_val}:${handler_id}")
  done

  # Numeric descending sort, then strip the priority prefix
  handlers=("${(@)${(@On)sortable}#*:}")
  : ${(PA)array_name::=${handlers[@]}}
}

###
# Match event_name against pattern, honouring wildcard config.
# @private  @return 0 matches | 1 no match
###
__z::event::match_pattern() {
  emulate -L zsh
  setopt localoptions extended_glob no_unset

  local event_name="$1"
  local pattern="$2"

  [[ $event_name == $pattern ]] && return 0

  if { __z::event::cfg_flag event_enable_wildcards true; [[ $REPLY == true ]] }; then
    [[ $event_name == ${~pattern} ]] && return 0
  fi

  return 1
}

###
# Collect all handler IDs that match event_name into the named array.
# Fills exact matches first (O(1)), then wildcard patterns (O(w)).
# @private
###
__z::event::collect_handlers() {
  emulate -L zsh
  setopt localoptions no_unset

  local event_name="$1"
  local output_array="$2"
  local -a result
  local handler_list pattern

  # O(1) exact-match lookup
  handler_list="${_zcore_event_handlers_exact[$event_name]:-}"
  if [[ -n $handler_list ]]; then
    local -a exact_ids
    __z::event::parse_handler_list "$handler_list" exact_ids
    result+=("${exact_ids[@]}")
  fi

  # O(w) wildcard scan
  if { __z::event::cfg_flag event_enable_wildcards true; [[ $REPLY == true ]] }; then
    for pattern in "${(@k)_zcore_event_handlers_wildcard}"; do
      if __z::event::match_pattern "$event_name" "$pattern"; then
        handler_list="${_zcore_event_handlers_wildcard[$pattern]:-}"
        if [[ -n $handler_list ]]; then
          local -a wc_ids
          __z::event::parse_handler_list "$handler_list" wc_ids
          result+=("${wc_ids[@]}")
        fi
      fi
    done
  fi

  : ${(PA)output_array::=${result[@]}}
}

###
# Read a zbus config flag, returning the provided default when z::config::get
# returns empty (e.g. when the z::kv backend is not loaded).
# Usage: __z::event::cfg_flag KEY DEFAULT_VALUE
# Sets REPLY to the resolved value.
# @private
###
__z::event::cfg_flag() {
  local _raw
  _raw="$(z::config::get "$1" 2>/dev/null)"
  REPLY="${_raw:-$2}"
}

###
# Append event to the ring-buffer history.
# @private
###
__z::event::add_to_history() {
  emulate -L zsh
  setopt localoptions no_unset

  { __z::event::cfg_flag event_enable_history true; [[ $REPLY != true ]] } && return 0

  local event_name="$1"
  shift

  local timestamp="${EPOCHSECONDS:-0}"
  _zcore_event_history+=("${timestamp}|${event_name}|$*")

  # Trim to max_history (keep tail)
  typeset -i max_history current_size
  local _max_history_raw
  _max_history_raw="$(z::config::get event_max_history 2>/dev/null)"
  (( max_history = ${_max_history_raw:-$ZCORE_EVENT_MAX_HISTORY} ))
  (( current_size = ${#_zcore_event_history} ))

  if (( current_size > max_history )); then
    _zcore_event_history=("${(@)_zcore_event_history[current_size - max_history + 1,-1]}")
  fi
}

###
# Increment a named statistic counter for an event.
# @private
###
__z::event::update_stats() {
  emulate -L zsh
  setopt localoptions no_unset

  { __z::event::cfg_flag event_enable_stats true; [[ $REPLY != true ]] } && return 0

  local key="${1}.${2}"
  typeset -i n
  (( n = ${_zcore_event_stats[$key]:-0} + 1 ))
  _zcore_event_stats[$key]=$n
}

###
# Remove a single handler by its internal ID from all state tables.
# @private
###
__z::event::remove_handler_by_id() {
  emulate -L zsh
  setopt localoptions no_unset

  local handler_id="$1"
  local event_pattern="${_zcore_event_handler_meta[${handler_id}.event]:-}"
  [[ -z $event_pattern ]] && return 0

  local handler_list
  if [[ $event_pattern == *'*'* ]]; then
    handler_list="${_zcore_event_handlers_wildcard[$event_pattern]:-}"
  else
    handler_list="${_zcore_event_handlers_exact[$event_pattern]:-}"
  fi

  if [[ -n $handler_list ]]; then
    local -a handlers
    __z::event::parse_handler_list "$handler_list" handlers
    handlers=("${(@)handlers:#$handler_id}")

    if (( ${#handlers} > 0 )); then
      if [[ $event_pattern == *'*'* ]]; then
        _zcore_event_handlers_wildcard[$event_pattern]="${(j:|:)handlers}"
      else
        _zcore_event_handlers_exact[$event_pattern]="${(j:|:)handlers}"
      fi
    else
      if [[ $event_pattern == *'*'* ]]; then
        unset "_zcore_event_handlers_wildcard[${event_pattern}]"
      else
        unset "_zcore_event_handlers_exact[${event_pattern}]"
      fi
    fi
  fi

  unset \
    "_zcore_event_handler_meta[${handler_id}.function]" \
    "_zcore_event_handler_meta[${handler_id}.priority]" \
    "_zcore_event_handler_meta[${handler_id}.once]"     \
    "_zcore_event_handler_meta[${handler_id}.event]"
}

################################################################################
# PUBLIC API — SUBSCRIPTION
################################################################################

###
# Subscribe a handler function to an event.
#
# Usage:
#   z::event::subscribe "plugin:loaded"  my_handler
#   z::event::subscribe "plugin:*"       my_wildcard_handler
#   z::event::subscribe "app:start"      my_handler --priority 100
#   z::event::subscribe "user:login"     my_once_handler --once
#
# @param 1  Event name (supports wildcard * patterns)
# @param 2  Handler function name (must be defined at call time)
# @param …  --priority N (0–100, default 50)  --once
# @return 0 success | ZCORE_ERROR_* on failure
###
z::event::subscribe() {
  emulate -L zsh
  setopt localoptions no_unset warn_create_global

  local event_name="$1"
  local handler="$2"
  shift 2

  __z::event::validate_event_name "$event_name" || return $?
  __z::event::validate_handler    "$handler"    || return $?

  typeset -i priority=$ZCORE_EVENT_PRIORITY_NORMAL
  local once=false

  while (( $# > 0 )); do
    case "$1" in
      --priority)
        z::validate::integer       "${2:-}" "Priority" || return $ZCORE_ERROR_INVALID_INPUT
        (( priority = 10#${2} ))
        z::validate::integer::range "$priority" 0 100 "Priority" || return $ZCORE_ERROR_INVALID_INPUT
        shift 2
        ;;
      --once)
        once=true
        shift
        ;;
      *)
        z::log::warn "z::event::subscribe: unknown option" option "$1"
        shift
        ;;
    esac
  done

  local existing_handlers
  if [[ $event_name == *'*'* ]]; then
    existing_handlers="${_zcore_event_handlers_wildcard[$event_name]:-}"
  else
    existing_handlers="${_zcore_event_handlers_exact[$event_name]:-}"
  fi

  local -a handler_array
  __z::event::parse_handler_list "$existing_handlers" handler_array

  typeset -i max_handlers
  local _max_handlers_raw
  _max_handlers_raw="$(z::config::get event_max_handlers_per_event 2>/dev/null)"
  (( max_handlers = ${_max_handlers_raw:-$ZCORE_EVENT_MAX_HANDLERS_PER_EVENT} ))
  if (( ${#handler_array} >= max_handlers )); then
    z::log::error "Handler limit reached for event" \
      event "$event_name" limit "$max_handlers"
    return $ZCORE_ERROR_INVALID_INPUT
  fi

  local handler_id
  __z::event::generate_id handler_id

  _zcore_event_handler_meta[${handler_id}.function]="$handler"
  _zcore_event_handler_meta[${handler_id}.priority]="$priority"
  _zcore_event_handler_meta[${handler_id}.once]="$once"
  _zcore_event_handler_meta[${handler_id}.event]="$event_name"

  local new_list
  if [[ -n $existing_handlers ]]; then
    new_list="${existing_handlers}|${handler_id}"
  else
    new_list="$handler_id"
  fi

  if [[ $event_name == *'*'* ]]; then
    _zcore_event_handlers_wildcard[$event_name]="$new_list"
  else
    _zcore_event_handlers_exact[$event_name]="$new_list"
  fi

  z::log::debug "Handler subscribed" \
    handler "$handler" event "$event_name" \
    id "$handler_id" priority "$priority" once "$once"
}

###
# Subscribe a one-time handler (sugar for --once).
#
# @param 1  Event name
# @param 2  Handler function name
# @param …  Additional options (--priority N)
###
z::event::subscribe_once() {
  emulate -L zsh
  setopt localoptions no_unset
  z::event::subscribe "$1" "$2" "${@:3}" --once
}

################################################################################
# PUBLIC API — EMISSION
################################################################################

###
# Emit an event — call all registered handlers in priority order.
#
# Handlers receive: handler_func <event_name> <args…>
# A failing handler is logged but does not abort remaining handlers.
#
# @param 1  Event name
# @param …  Arguments forwarded verbatim to every handler
# @return 0 all handlers succeeded | 1 one or more handlers failed
###
z::event::emit() {
  emulate -L zsh
  setopt localoptions no_unset warn_create_global

  local event_name="$1"
  shift

  __z::event::validate_event_name "$event_name" || return $?

  z::log::debug "Emitting event" event "$event_name" argc "$#"

  __z::event::update_stats "$event_name" emitted
  __z::event::add_to_history "$event_name" "$@"

  local -a all_handler_ids
  __z::event::collect_handlers "$event_name" all_handler_ids

  if (( ${#all_handler_ids} == 0 )); then
    z::log::debug "No handlers for event" event "$event_name"
    return 0
  fi

  __z::event::sort_handlers_by_priority all_handler_ids

  z::log::debug "Dispatching event" \
    event "$event_name" handlers "${#all_handler_ids}"

  typeset -i failed=0 handled=0 exit_code
  local -a handlers_to_remove
  local handler_id handler_func once_flag

  for handler_id in "${all_handler_ids[@]}"; do
    handler_func="${_zcore_event_handler_meta[${handler_id}.function]:-}"
    once_flag="${_zcore_event_handler_meta[${handler_id}.once]:-false}"

    if [[ -z $handler_func ]]; then
      z::log::warn "Missing handler metadata" id "$handler_id"
      continue
    fi

    if ! z::probe::func "$handler_func"; then
      z::log::warn "Handler no longer defined" handler "$handler_func" id "$handler_id"
      handlers_to_remove+=("$handler_id")
      continue
    fi

    z::log::debug "Calling handler" handler "$handler_func" id "$handler_id"

    exit_code=0
    "$handler_func" "$event_name" "$@" || exit_code=$?

    if (( exit_code != 0 )); then
      (( failed += 1 ))
      z::log::warn "Handler failed" \
        handler "$handler_func" event "$event_name" exit_code "$exit_code"
      __z::event::update_stats "$event_name" failed
    else
      (( handled += 1 ))
      __z::event::update_stats "$event_name" handled
    fi

    if [[ $once_flag == true ]]; then
      handlers_to_remove+=("$handler_id")
      z::log::debug "Removing one-time handler" handler "$handler_func"
    fi
  done

  local remove_id
  for remove_id in "${handlers_to_remove[@]}"; do
    __z::event::remove_handler_by_id "$remove_id"
  done

  z::log::debug "Event dispatch complete" \
    event "$event_name" handled "$handled" failed "$failed"

  (( failed == 0 ))
}

###
# Emit an event with per-handler subshell isolation and hard timeout.
#
# Each handler runs in its own subshell wrapped by the `timeout` command.
# Handlers cannot modify parent-scope variables.
# Use for untrusted or potentially blocking handlers.
#
# @param 1  Event name
# @param …  Arguments forwarded to every handler
# @return 0 all succeeded | 1 failures | ZCORE_ERROR_TIMEOUT on timeout
###
z::event::emit_safe() {
  emulate -L zsh
  setopt localoptions no_unset warn_create_global

  local event_name="$1"
  shift

  __z::event::validate_event_name "$event_name" || return $?

  z::log::debug "Emitting safe event" event "$event_name" argc "$#"

  __z::event::update_stats "$event_name" emitted
  __z::event::add_to_history "$event_name" "$@"

  local -a all_handler_ids
  __z::event::collect_handlers "$event_name" all_handler_ids

  if (( ${#all_handler_ids} == 0 )); then
    z::log::debug "No handlers for event" event "$event_name"
    return 0
  fi

  __z::event::sort_handlers_by_priority all_handler_ids

  typeset -i failed=0 handled=0 exit_code timeout_val
  local _timeout_raw
  _timeout_raw="$(z::config::get event_handler_timeout 2>/dev/null)"
  (( timeout_val = ${_timeout_raw:-$ZCORE_EVENT_HANDLER_TIMEOUT} ))
  local -a handlers_to_remove
  local handler_id handler_func once_flag

  z::log::debug "Dispatching safe event" \
    event "$event_name" handlers "${#all_handler_ids}" timeout "${timeout_val}s"

  for handler_id in "${all_handler_ids[@]}"; do
    handler_func="${_zcore_event_handler_meta[${handler_id}.function]:-}"
    once_flag="${_zcore_event_handler_meta[${handler_id}.once]:-false}"

    if [[ -z $handler_func ]]; then
      z::log::warn "Missing handler metadata" id "$handler_id"
      continue
    fi

    if ! z::probe::func "$handler_func"; then
      z::log::warn "Handler no longer defined" handler "$handler_func" id "$handler_id"
      handlers_to_remove+=("$handler_id")
      continue
    fi

    z::log::debug "Calling handler (safe)" \
      handler "$handler_func" id "$handler_id" timeout "${timeout_val}s"

    exit_code=0
    # Run handler in a subshell with a hard wall-clock timeout.
    # Strategy: background the subshell, then wait with a watchdog.
    #   - If handler finishes in time: kill the watchdog, capture exit code.
    #   - If watchdog fires first:     kill the handler, report timeout.
    local __bg_pid __wdog_pid
    ( "$handler_func" "$event_name" "$@" ) &
    __bg_pid=$!
    ( sleep "$timeout_val" && kill "$__bg_pid" 2>/dev/null ) &
    __wdog_pid=$!

    wait "$__bg_pid" 2>/dev/null
    exit_code=$?

    # Handler finished — cancel watchdog if still alive
    kill "$__wdog_pid" 2>/dev/null && wait "$__wdog_pid" 2>/dev/null || true

    if (( exit_code == ZCORE_ERROR_TIMEOUT || exit_code == 143 )); then
      # 143 = 128+15 = killed by SIGTERM from watchdog
      (( failed += 1 ))
      z::log::error "Handler timed out" \
        handler "$handler_func" event "$event_name" timeout "${timeout_val}s"
      __z::event::update_stats "$event_name" failed
    elif (( exit_code != 0 )); then
      (( failed += 1 ))
      z::log::warn "Handler failed" \
        handler "$handler_func" event "$event_name" exit_code "$exit_code"
      __z::event::update_stats "$event_name" failed
    else
      (( handled += 1 ))
      __z::event::update_stats "$event_name" handled
    fi

    if [[ $once_flag == true ]]; then
      handlers_to_remove+=("$handler_id")
      z::log::debug "Removing one-time handler" handler "$handler_func"
    fi
  done

  local remove_id
  for remove_id in "${handlers_to_remove[@]}"; do
    __z::event::remove_handler_by_id "$remove_id"
  done

  z::log::debug "Safe event dispatch complete" \
    event "$event_name" handled "$handled" failed "$failed"

  (( failed == 0 ))
}

###
# Emit an event asynchronously (fire-and-forget).
#
# The emission runs in a detached background job.
# No error feedback; no job tracking. Use sparingly for non-critical
# notifications where latency matters more than delivery guarantees.
#
# @param 1  Event name
# @param …  Arguments forwarded to handlers
# @return 0 always (does not wait for handlers)
###
z::event::emit_async() {
  emulate -L zsh
  setopt localoptions no_unset

  local event_name="$1"
  shift

  __z::event::validate_event_name "$event_name" || return $?

  z::log::debug "Emitting async event" event "$event_name"

  { z::event::emit "$event_name" "$@" } &!
}

################################################################################
# PUBLIC API — SUBSCRIPTION MANAGEMENT
################################################################################

###
# Unsubscribe from one or more events.
#
# Usage:
#   z::event::unsubscribe "plugin:loaded" my_handler   # specific handler
#   z::event::unsubscribe "plugin:loaded"              # all handlers on event
#   z::event::unsubscribe "*"              my_handler  # handler from all events
#
# @param 1  Event name / pattern
# @param 2  Handler function name (optional; omit to remove all on the event)
# @return 0 success | ZCORE_ERROR_* on failure
###
z::event::unsubscribe() {
  emulate -L zsh
  setopt localoptions no_unset

  local event_pattern="$1"
  local handler_func="${2:-}"

  __z::event::validate_event_name "$event_pattern" || return $?

  typeset -i removed=0
  local pattern handler_list

  local -a all_patterns
  all_patterns=(
    "${(@k)_zcore_event_handlers_exact}"
    "${(@k)_zcore_event_handlers_wildcard}"
  )

  for pattern in "${all_patterns[@]}"; do
    __z::event::match_pattern "$pattern" "$event_pattern" || continue

    if [[ $pattern == *'*'* ]]; then
      handler_list="${_zcore_event_handlers_wildcard[$pattern]:-}"
    else
      handler_list="${_zcore_event_handlers_exact[$pattern]:-}"
    fi

    [[ -z $handler_list ]] && continue

    local -a handlers
    __z::event::parse_handler_list "$handler_list" handlers

    local handler_id stored_func
    for handler_id in "${handlers[@]}"; do
      stored_func="${_zcore_event_handler_meta[${handler_id}.function]:-}"

      if [[ -z $handler_func || $stored_func == $handler_func ]]; then
        __z::event::remove_handler_by_id "$handler_id"
        (( removed += 1 ))
        z::log::debug "Handler unsubscribed" \
          handler "$stored_func" id "$handler_id" event "$pattern"
      fi
    done
  done

  z::log::debug "Unsubscribe complete" \
    pattern "$event_pattern" removed "$removed"
}

################################################################################
# PUBLIC API — INTROSPECTION
################################################################################

###
# Return 0 if the event has at least one registered handler.
#
# @param 1  Event name (supports wildcards)
# @return 0 handlers exist | 1 none
###
z::event::has_handlers() {
  emulate -L zsh
  setopt localoptions no_unset

  local event_name="$1"
  __z::event::validate_event_name "$event_name" || return 1

  [[ -n ${_zcore_event_handlers_exact[$event_name]:-} ]] && return 0

  if { __z::event::cfg_flag event_enable_wildcards true; [[ $REPLY == true ]] }; then
    local pattern
    for pattern in "${(@k)_zcore_event_handlers_wildcard}"; do
      __z::event::match_pattern "$event_name" "$pattern" &&
        [[ -n ${_zcore_event_handlers_wildcard[$pattern]:-} ]] && return 0
    done
  fi

  return 1
}

###
# Print the total number of handlers registered for an event.
#
# @param 1  Event name (supports wildcards)
# @stdout   Integer count
###
z::event::count() {
  emulate -L zsh
  setopt localoptions no_unset

  local event_name="$1"
  __z::event::validate_event_name "$event_name" || { print 0; return 1; }

  typeset -i total=0
  local handler_list pattern
  local -a handlers

  handler_list="${_zcore_event_handlers_exact[$event_name]:-}"
  if [[ -n $handler_list ]]; then
    __z::event::parse_handler_list "$handler_list" handlers
    (( total += ${#handlers} ))
  fi

  if { __z::event::cfg_flag event_enable_wildcards true; [[ $REPLY == true ]] }; then
    for pattern in "${(@k)_zcore_event_handlers_wildcard}"; do
      if __z::event::match_pattern "$event_name" "$pattern"; then
        handlers=()
        handler_list="${_zcore_event_handlers_wildcard[$pattern]:-}"
        if [[ -n $handler_list ]]; then
          __z::event::parse_handler_list "$handler_list" handlers
          (( total += ${#handlers} ))
        fi
      fi
    done
  fi

  print $total
}

###
# List all registered event handlers (optionally filtered by pattern).
#
# Usage:
#   z::event::list
#   z::event::list "plugin:*"
#
# @param 1  Optional event pattern filter (default: * = all)
###
z::event::list() {
  emulate -L zsh
  setopt localoptions no_unset no_xtrace no_verbose

  local filter_pattern="${1:-*}"
  local event_pattern handler_list
  local -a all_events handlers
  typeset -i total=0 i

  print "\nRegistered Event Handlers:"
  print "========================="

  all_events=(
    "${(@k)_zcore_event_handlers_exact}"
    "${(@k)_zcore_event_handlers_wildcard}"
  )

  if (( ${#all_events} == 0 )); then
    print "No handlers registered."
    print ""
    return 0
  fi

  for event_pattern in "${all_events[@]}"; do
    __z::event::match_pattern "$event_pattern" "$filter_pattern" || continue

    if [[ $event_pattern == *'*'* ]]; then
      handler_list="${_zcore_event_handlers_wildcard[$event_pattern]:-}"
    else
      handler_list="${_zcore_event_handlers_exact[$event_pattern]:-}"
    fi

    [[ -z $handler_list ]] && continue

    __z::event::parse_handler_list "$handler_list" handlers

    local colored_event
    z::log::colorize blue "$event_pattern"; colored_event="$REPLY"
    print "\nEvent: ${colored_event}"
    print "  Handlers: ${#handlers}"

    for (( i = 1; i <= ${#handlers}; i++ )); do
      local hid="${handlers[i]}"
      local func_name="${_zcore_event_handler_meta[${hid}.function]:-unknown}"
      local prio="${_zcore_event_handler_meta[${hid}.priority]:-50}"
      local once="${_zcore_event_handler_meta[${hid}.once]:-false}"
      local line="    - ${func_name} (priority: ${prio})"
      if [[ $once == true ]]; then
        local colored_once; z::log::colorize yellow "[once]"; colored_once="$REPLY"
        line+= " ${colored_once}"
      fi
      print "$line"
      (( total += 1 ))
    done
  done

  print "\nTotal handlers: $total"
  print ""
}

###
# Show aggregated emission statistics.
#
# Usage:
#   z::event::stats
#   z::event::stats "plugin:loaded"
#
# @param 1  Optional event name filter substring
###
z::event::stats() {
  emulate -L zsh
  setopt localoptions no_unset

  local filter="${1:-}"

  print "\nEvent Statistics:"
  print "================="

  if { __z::event::cfg_flag event_enable_stats true; [[ $REPLY != true ]] }; then
    print "Statistics disabled."
    print ""
    return 0
  fi

  if (( ${#_zcore_event_stats} == 0 )); then
    print "No statistics collected."
    print ""
    return 0
  fi

  local -a unique_events
  local key event_name

  for key in "${(@k)_zcore_event_stats}"; do
    event_name="${key%.*}"
    [[ -n $filter && $event_name != *${filter}* ]] && continue
    (( ${unique_events[(Ie)$event_name]} )) && continue
    unique_events+=("$event_name")
  done

  if (( ${#unique_events} == 0 )); then
    print "No matching statistics."
    print ""
    return 0
  fi

  for event_name in "${unique_events[@]}"; do
    local emitted="${_zcore_event_stats[${event_name}.emitted]:-0}"
    local handled="${_zcore_event_stats[${event_name}.handled]:-0}"
    local failed="${_zcore_event_stats[${event_name}.failed]:-0}"
    local colored_name; z::log::colorize blue "$event_name"; colored_name="$REPLY"
    print "\n${colored_name}"
    print "  Emitted: $emitted"
    print "  Handled: $handled"
    print "  Failed:  $failed"
  done
  print ""
}

###
# Display recent event history.
#
# Usage:
#   z::event::history
#   z::event::history 20
#   z::event::history 10 "plugin:*"
#
# @param 1  Number of entries to show (default 20)
# @param 2  Optional event name filter pattern
###
z::event::history() {
  emulate -L zsh
  setopt localoptions no_unset no_xtrace no_verbose

  typeset -i limit
  (( limit = 10#${1:-20} ))
  local filter="${2:-}"

  print "\nEvent History (last $limit):"
  print "============================"

  if { __z::event::cfg_flag event_enable_history true; [[ $REPLY != true ]] }; then
    print "History disabled."
    print ""
    return 0
  fi

  if (( ${#_zcore_event_history} == 0 )); then
    print "No history available."
    print ""
    return 0
  fi

  typeset -i start display_idx
  (( start = ${#_zcore_event_history} - limit + 1 ))
  (( start < 1 )) && (( start = 1 ))

  local -a recent
  recent=("${(@)_zcore_event_history[start,-1]}")

  local entry ts remainder evt arg formatted_time
  (( display_idx = ${#recent} ))

  for entry in "${(@Oa)recent}"; do
    ts="${entry%%|*}"
    remainder="${entry#*|}"
    evt="${remainder%%|*}"
    arg="${remainder#*|}"

    if [[ -n $filter ]]; then
      __z::event::match_pattern "$evt" "$filter" || { (( display_idx -= 1 )); continue; }
    fi

    # Format timestamp portably via zlog
    formatted_time="$ts"
    if [[ $ts == <-> ]]; then
      z::log::format_epoch "$ts" human
      formatted_time="$REPLY"
    fi

    local colored_evt; z::log::colorize blue "$evt"; colored_evt="$REPLY"
    print "${display_idx}. [${formatted_time}] ${colored_evt}"
    [[ -n $arg && $arg != "$evt" ]] && print "   Args: $arg"
    (( display_idx -= 1 ))
  done
  print ""
}

################################################################################
# PUBLIC API — MAINTENANCE
################################################################################

###
# Clear all recorded event history.
###
z::event::clear_history() {
  emulate -L zsh
  setopt localoptions no_unset
  _zcore_event_history=()
  z::log::debug "Event history cleared"
}

###
# Clear all emission statistics.
###
z::event::clear_stats() {
  emulate -L zsh
  setopt localoptions no_unset
  _zcore_event_stats=()
  z::log::debug "Event statistics cleared"
}

###
# Full reset — remove all handlers, history, and statistics.
# Uses z::log::always so the reset is always audited regardless of log level.
###
z::event::reset() {
  emulate -L zsh
  setopt localoptions no_unset

  _zcore_event_handlers_exact=()
  _zcore_event_handlers_wildcard=()
  _zcore_event_handler_meta=()
  _zcore_event_history=()
  _zcore_event_stats=()
  (( _zcore_event_handler_id = 0 ))

  z::log::always "Event bus reset" component "zbus"
}

################################################################################
# PUBLIC API — RUNTIME CONFIGURATION
################################################################################

###
# Update a runtime configuration key for the event bus.
#
# Supported keys:
#   max_history              (integer)
#   handler_timeout          (integer, seconds)
#   max_handlers_per_event   (integer)
#   enable_history           (true|false)
#   enable_stats             (true|false)
#   enable_wildcards         (true|false)
#
# Usage:
#   z::event::configure max_history 200
#   z::event::configure enable_wildcards false
#
# @param 1  Config key (without "event_" prefix)
# @param 2  New value
# @return 0 success | 1 unknown key
###
z::event::configure() {
  emulate -L zsh
  setopt localoptions no_unset

  local key="$1"
  local value="$2"

  # Map the public key to the z::config namespace key
  local cfg_key="event_${key}"

  # Verify the key is one we own by checking the initial defaults
  case "$key" in
    max_history|handler_timeout|max_handlers_per_event| \
    enable_history|enable_stats|enable_wildcards) ;;
    *)
      z::log::error "Unknown event configuration key" key "$key"
      return 1
      ;;
  esac

  z::config::set "$cfg_key" "$value" || return $?
  z::log::debug "Event config updated" key "$cfg_key" value "$value"
}

###
# Retrieve a runtime configuration value.
#
# @param 1  Config key (without "event_" prefix)
# @stdout   Current value
# @return 0 success | 1 unknown key
###
z::event::get_config() {
  emulate -L zsh
  setopt localoptions no_unset

  local key="$1"

  case "$key" in
    max_history|handler_timeout|max_handlers_per_event| \
    enable_history|enable_stats|enable_wildcards) ;;
    *)
      z::log::error "Unknown event configuration key" key "$key"
      return 1
      ;;
  esac

  z::config::get "event_${key}"
}
