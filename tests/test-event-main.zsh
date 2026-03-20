#!/usr/bin/env zsh

################################################################################
# ZCORE EVENT SYSTEM
################################################################################
#
# A robust pub/sub event system for zsh with:
#   - Event registration and emission
#   - Priority-based handler ordering
#   - One-time event handlers
#   - Event namespacing and wildcards
#   - Handler removal and cleanup
#   - Event history and replay
#   - Async event emission
#   - Error isolation (handlers don't crash system)
#   - Performance monitoring
#
# Version: 1.0.0
################################################################################

################################################################################
# EVENT SYSTEM STATE
################################################################################


# Event handler storage: split for performance
typeset -gA _zcore_event_handlers_exact     # Exact event matches (O(1) lookup)
typeset -gA _zcore_event_handlers_wildcard  # Wildcard patterns (O(n) scan)

# Handler metadata: handler_id -> metadata (priority, once, etc.)
typeset -gA _zcore_event_handler_meta

# Event history: stores recent events for replay/debugging
typeset -ga _zcore_event_history

# Handler ID counter for unique identification
typeset -gi _zcore_event_handler_id=0

# Event statistics
typeset -gA _zcore_event_stats

# Event handler priorities (higher = runs first)
typeset -gri ZCORE_EVENT_PRIORITY_HIGHEST=100
typeset -gri ZCORE_EVENT_PRIORITY_HIGH=75
typeset -gri ZCORE_EVENT_PRIORITY_NORMAL=50
typeset -gri ZCORE_EVENT_PRIORITY_LOW=25
typeset -gri ZCORE_EVENT_PRIORITY_LOWEST=0

# Initialize event system configuration with validation
z::config::set event_max_history 100
z::config::set event_handler_timeout 5
z::config::set event_max_handlers_per_event 50
z::config::set event_enable_history true
z::config::set event_enable_stats true
z::config::set event_enable_wildcards true

###
# Generate unique handler ID
# @param 1: string - Name of variable to store ID in
# @private
# @return 0 always
###
__z::event::generate_id() {
  emulate -L zsh
  setopt localoptions no_unset warn_create_global

  local output_var="$1"

  # Increment counter atomically
  (( _zcore_event_handler_id += 1 ))

  # Set output variable in caller's scope
  : ${(P)output_var::=handler_${_zcore_event_handler_id}}

  return 0
}

###
# Validate event name format
# @param 1: string - Event name
# @private
# @return 0 if valid, ZCORE_ERROR_INVALID_INPUT if invalid
###
__z::event::validate_event_name() {
  emulate -L zsh
  setopt localoptions no_unset extended_glob

  local event_name="$1"

  # Use Zcore validation
  z::validate::nonempty "$event_name" "Event name" || return $ZCORE_ERROR_INVALID_INPUT

  # Allow alphanumeric, underscore, colon, asterisk, hyphen
  if [[ ! $event_name =~ ^[a-zA-Z0-9_:*-]+$ ]]; then
    z::log::error "Invalid event name format: $event_name (allowed: a-z A-Z 0-9 _ : * -)"
    return $ZCORE_ERROR_INVALID_INPUT
  fi

  return 0
}

###
# Validate handler function exists
# @param 1: string - Handler function name
# @private
# @return 0 if valid, ZCORE_ERROR_NOT_FOUND if invalid
###
__z::event::validate_handler() {
  emulate -L zsh
  setopt localoptions no_unset

  local handler="$1"

  z::validate::nonempty "$handler" "Handler" || return $ZCORE_ERROR_INVALID_INPUT

  if ! z::func::probe "$handler"; then
    z::log::error "Handler function does not exist: $handler"
    return $ZCORE_ERROR_NOT_FOUND
  fi

  return 0
}

###
# Parse handler list into array
# @param 1: string - Pipe-separated handler list
# @param 2: string - Output array name
# @private
# @return 0 always
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

  # Direct parameter expansion - no eval
  : ${(PA)output_array::=${(s:|:)handler_list}}
  return 0
}

###
# Sort handlers by priority (descending)
# @param 1: string - Array name containing handler IDs
# @private
# @return 0 always
###
__z::event::sort_handlers_by_priority() {
  emulate -L zsh
  setopt localoptions no_unset

  local array_name="$1"

  # Build sortable array: "priority:handler_id"
  local -a sortable_handlers
  local handler_id priority_val

  # Use nameref to avoid eval
  local -a handlers=("${(@P)array_name}")

  for handler_id in "${handlers[@]}"; do
    (( priority_val = ${_zcore_event_handler_meta[${handler_id}.priority]:-50} ))
    sortable_handlers+=("${priority_val}:${handler_id}")
  done

  # Sort numerically descending, extract handler IDs
  local -a sorted_entries
  sorted_entries=("${(@On)sortable_handlers}")

  # Extract handler IDs (everything after first colon)
  handlers=("${(@)sorted_entries#*:}")

  # Update caller's array
  : ${(PA)array_name::=${handlers[@]}}

  return 0
}

###
# Match event name against pattern (supports wildcards)
# @param 1: string - Event name
# @param 2: string - Pattern (may contain *)
# @private
# @return 0 if matches, 1 if not
###
__z::event::match_pattern() {
  emulate -L zsh
  setopt localoptions extended_glob no_unset

  local event_name="$1"
  local pattern="$2"

  # Exact match first (fast path)
  [[ $event_name == $pattern ]] && return 0

  # Wildcard matching if enabled
  if [[ $(z::config::get event_enable_wildcards) == true ]]; then
    [[ $event_name == ${~pattern} ]] && return 0
  fi

  return 1
}

###
# Add event to history with timestamp caching
# @param 1: string - Event name
# @param ...: any - Event arguments
# @private
# @return 0 always
###
__z::event::add_to_history() {
  emulate -L zsh
  setopt localoptions no_unset

  [[ $(z::config::get event_enable_history) != true ]] && return 0

  local event_name="$1"
  shift

  # Prefer EPOCHSECONDS (no external process)
  local timestamp="${EPOCHSECONDS:-$(date +%s 2>/dev/null || print 0)}"

  local entry="${timestamp}|${event_name}|$*"
  _zcore_event_history+=("$entry")

  # Trim history if needed
  typeset -i max_history current_size to_remove
  (( max_history = $(z::config::get event_max_history) ))
  (( current_size = ${#_zcore_event_history} ))

  if (( current_size > max_history )); then
    (( to_remove = current_size - max_history ))
    _zcore_event_history=("${(@)_zcore_event_history[to_remove+1,-1]}")
  fi

  return 0
}

###
# Update event statistics
# @param 1: string - Event name
# @param 2: string - Stat type (emitted|handled|failed)
# @private
# @return 0 always
###
__z::event::update_stats() {
  emulate -L zsh
  setopt localoptions no_unset

  [[ $(z::config::get event_enable_stats) != true ]] && return 0

  local event_name="$1"
  local stat_type="$2"

  local key="${event_name}.${stat_type}"
  typeset -i current
  (( current = ${_zcore_event_stats[$key]:-0} + 1 ))
  _zcore_event_stats[$key]=$current

  return 0
}

###
# Remove handler by internal ID
# @param 1: string - Handler ID
# @private
# @return 0 always
###
__z::event::remove_handler_by_id() {
  emulate -L zsh
  setopt localoptions no_unset

  local handler_id="$1"

  local event_pattern="${_zcore_event_handler_meta[${handler_id}.event]:-}"
  [[ -z $event_pattern ]] && return 0

  # Determine which storage map and get handler list
  local handler_list
  if [[ $event_pattern == *'*'* ]]; then
    handler_list="${_zcore_event_handlers_wildcard[$event_pattern]:-}"
  else
    handler_list="${_zcore_event_handlers_exact[$event_pattern]:-}"
  fi

  if [[ -n $handler_list ]]; then
    local -a handlers
    __z::event::parse_handler_list "$handler_list" handlers

    # Filter out this handler
    handlers=("${(@)handlers:#$handler_id}")

    # Update or remove
    if (( ${#handlers} > 0 )); then
      if [[ $event_pattern == *'*'* ]]; then
        _zcore_event_handlers_wildcard[$event_pattern]="${(j:|:)handlers}"
      else
        _zcore_event_handlers_exact[$event_pattern]="${(j:|:)handlers}"
      fi
    else
      # Remove the key entirely
      if [[ $event_pattern == *'*'* ]]; then
        unset "_zcore_event_handlers_wildcard[${event_pattern}]"
      else
        unset "_zcore_event_handlers_exact[${event_pattern}]"
      fi
    fi
  fi

  # Remove metadata
  unset "_zcore_event_handler_meta[${handler_id}.function]"
  unset "_zcore_event_handler_meta[${handler_id}.priority]"
  unset "_zcore_event_handler_meta[${handler_id}.once]"
  unset "_zcore_event_handler_meta[${handler_id}.event]"

  return 0
}

###
# Subscribe to an event
#
# Usage:
#   z::event::subscribe "plugin:loaded" my_handler
#   z::event::subscribe "plugin:*" my_wildcard_handler
#   z::event::subscribe "app:start" my_handler --priority 100
#   z::event::subscribe "user:login" my_once_handler --once
#
# @param 1: string - Event name (supports wildcards with *)
# @param 2: string - Handler function name
# @param 3: string - --priority N (optional, default: 50)
# @param 4: string - --once (optional, handler runs only once)
# @return 0 on success, ZCORE_ERROR_* on failure
###
z::event::subscribe() {
  emulate -L zsh
  setopt localoptions no_unset warn_create_global

  local event_name="$1"
  local handler="$2"
  shift 2

  __z::event::validate_event_name "$event_name" || return $?
  __z::event::validate_handler "$handler" || return $?

  typeset -i priority=$ZCORE_EVENT_PRIORITY_NORMAL
  local once=false

  # Parse options
  while (( $# > 0 )); do
    case "$1" in
      --priority)
        z::validate::integer "${2:-}" "Priority" || return $ZCORE_ERROR_INVALID_INPUT
        (( priority = 10#${2} ))
        z::validate::integer::range "$priority" 0 100 "Priority" || return $ZCORE_ERROR_INVALID_INPUT
        shift 2
        ;;
      --once)
        once=true
        shift
        ;;
      *)
        z::log::warn "Unknown option: $1"
        shift
        ;;
    esac
  done

  # Determine which storage to use and get existing handlers
  local existing_handlers
  if [[ $event_name == *'*'* ]]; then
    # Wildcard pattern
    existing_handlers="${_zcore_event_handlers_wildcard[$event_name]:-}"
  else
    # Exact match
    existing_handlers="${_zcore_event_handlers_exact[$event_name]:-}"
  fi

  # Check handler limit
  local -a handler_array
  __z::event::parse_handler_list "$existing_handlers" handler_array

  typeset -i max_handlers
  (( max_handlers = $(z::config::get event_max_handlers_per_event) ))

  if (( ${#handler_array} >= max_handlers )); then
    z::log::error "Maximum handlers ($max_handlers) reached for event: $event_name"
    return $ZCORE_ERROR_INVALID_INPUT
  fi

  # Generate unique ID and store metadata
  local handler_id
  __z::event::generate_id handler_id

  _zcore_event_handler_meta[${handler_id}.function]="$handler"
  _zcore_event_handler_meta[${handler_id}.priority]="$priority"
  _zcore_event_handler_meta[${handler_id}.once]="$once"
  _zcore_event_handler_meta[${handler_id}.event]="$event_name"

  # Append to handler list in appropriate storage
  local new_handler_list
  if [[ -n $existing_handlers ]]; then
    new_handler_list="${existing_handlers}|${handler_id}"
  else
    new_handler_list="$handler_id"
  fi

  if [[ $event_name == *'*'* ]]; then
    _zcore_event_handlers_wildcard[$event_name]="$new_handler_list"
  else
    _zcore_event_handlers_exact[$event_name]="$new_handler_list"
  fi

  z::log::debug "Subscribed handler '$handler' to event '$event_name' (id: $handler_id, priority: $priority, once: $once)"

  return 0
}

###
# Subscribe to an event (one-time handler)
#
# Usage:
#   z::event::subscribe_once "app:ready" my_init_handler
#   z::event::subscribe_once "app:ready" my_init_handler --priority 100
#
# @param 1: string - Event name
# @param 2: string - Handler function name
# @param ...: any - Additional options (--priority N)
# @return 0 on success, ZCORE_ERROR_* on failure
###
z::event::subscribe_once() {
  emulate -L zsh
  setopt localoptions no_unset

  z::event::subscribe "$1" "$2" "${@:3}" --once
}

###
# Emit an event and call all registered handlers
#
# Usage:
#   z::event::emit "plugin:loaded" "git-helper"
#   z::event::emit "user:login" "$username" "$timestamp"
#
# Handlers receive: handler_func <event_name> <args...>
#
# @param 1: string - Event name
# @param ...: any - Event arguments (passed to handlers after event name)
# @return 0 on success, 1 if any handler failed, 130 if interrupted
###
z::event::emit() {
  emulate -L zsh
  setopt localoptions no_unset warn_create_global

  local event_name="$1"
  shift

  __z::event::validate_event_name "$event_name" || return $?

  z::log::debug "Emitting event: $event_name (args: $#)"

  __z::event::update_stats "$event_name" "emitted"
  __z::event::add_to_history "$event_name" "$@"

  z::sys::interrupted || return $?

  # Collect matching handlers
  local -a all_handler_ids
  local pattern handler_list

  # Fast path: exact match (O(1))
  handler_list="${_zcore_event_handlers_exact[$event_name]:-}"
  if [[ -n $handler_list ]]; then
    __z::event::parse_handler_list "$handler_list" all_handler_ids
  fi

  # Slow path: wildcard matching (O(n) where n = wildcard patterns)
  if [[ $(z::config::get event_enable_wildcards) == true ]]; then
    for pattern in "${(@k)_zcore_event_handlers_wildcard}"; do
      if __z::event::match_pattern "$event_name" "$pattern"; then
        handler_list="${_zcore_event_handlers_wildcard[$pattern]:-}"
        if [[ -n $handler_list ]]; then
          local -a pattern_handlers
          __z::event::parse_handler_list "$handler_list" pattern_handlers
          all_handler_ids+=("${pattern_handlers[@]}")
        fi
      fi
    done
  fi

  if (( ${#all_handler_ids} == 0 )); then
    z::log::debug "No handlers registered for event: $event_name"
    return 0
  fi

  # Sort by priority
  __z::event::sort_handlers_by_priority all_handler_ids

  z::log::debug "Found ${#all_handler_ids} handler(s) for event: $event_name"

  typeset -i failed=0 handled=0
  local -a handlers_to_remove

  # Execute handlers
  local handler_id handler_func once_flag
  for handler_id in "${all_handler_ids[@]}"; do
    z::sys::interrupted || return $?

    handler_func="${_zcore_event_handler_meta[${handler_id}.function]:-}"
    once_flag="${_zcore_event_handler_meta[${handler_id}.once]:-false}"

    if [[ -z $handler_func ]]; then
      z::log::warn "Handler metadata missing for ID: $handler_id"
      continue
    fi

    # Verify handler still exists
    if ! z::func::probe "$handler_func"; then
      z::log::warn "Handler function no longer exists: $handler_func"
      handlers_to_remove+=("$handler_id")
      continue
    fi

    z::log::debug "Calling handler: $handler_func (id: $handler_id)"

    # Execute handler with event name as first argument
    typeset -i exit_code=0
    {
      "$handler_func" "$event_name" "$@"
      exit_code=$?
    } always {
      # Ensure exit code is captured even on interrupt
      (( exit_code == 0 )) || true
    }

    if (( exit_code != 0 )); then
      (( failed += 1 ))
      z::log::warn "Handler '$handler_func' failed with exit code: $exit_code"
      __z::event::update_stats "$event_name" "failed"
    else
      (( handled += 1 ))
      __z::event::update_stats "$event_name" "handled"
    fi

    # Mark for removal if one-time handler
    if [[ $once_flag == true ]]; then
      handlers_to_remove+=("$handler_id")
      z::log::debug "One-time handler will be removed: $handler_func"
    fi
  done

  # Cleanup one-time handlers
  if (( ${#handlers_to_remove} > 0 )); then
    local remove_id
    for remove_id in "${handlers_to_remove[@]}"; do
      __z::event::remove_handler_by_id "$remove_id"
    done
  fi

  z::log::debug "Event '$event_name' completed: $handled handled, $failed failed"

  (( failed == 0 ))
}

###
# Emit an event with timeout protection (subshell overhead)
#
# Usage:
#   z::event::emit_safe "external:hook" "$untrusted_data"
#
# Handlers run in subshells with TMOUT protection.
# Note: Handlers cannot modify parent scope variables.
#
# @param 1: string - Event name
# @param ...: any - Event arguments
# @return 0 on success, 1 if any handler failed, ZCORE_ERROR_TIMEOUT if timeout
###
z::event::emit_safe() {
  emulate -L zsh
  setopt localoptions no_unset warn_create_global

  local event_name="$1"
  shift

  __z::event::validate_event_name "$event_name" || return $?

  z::log::debug "Emitting safe event: $event_name (args: $#)"

  __z::event::update_stats "$event_name" "emitted"
  __z::event::add_to_history "$event_name" "$@"

  z::sys::interrupted || return $?

  # Collect matching handlers (same logic as emit)
  local -a all_handler_ids
  local pattern handler_list

  handler_list="${_zcore_event_handlers_exact[$event_name]:-}"
  if [[ -n $handler_list ]]; then
    __z::event::parse_handler_list "$handler_list" all_handler_ids
  fi

  if [[ $(z::config::get event_enable_wildcards) == true ]]; then
    for pattern in "${(@k)_zcore_event_handlers_wildcard}"; do
      if __z::event::match_pattern "$event_name" "$pattern"; then
        handler_list="${_zcore_event_handlers_wildcard[$pattern]:-}"
        if [[ -n $handler_list ]]; then
          local -a pattern_handlers
          __z::event::parse_handler_list "$handler_list" pattern_handlers
          all_handler_ids+=("${pattern_handlers[@]}")
        fi
      fi
    done
  fi

  if (( ${#all_handler_ids} == 0 )); then
    z::log::debug "No handlers registered for event: $event_name"
    return 0
  fi

  __z::event::sort_handlers_by_priority all_handler_ids

  z::log::debug "Found ${#all_handler_ids} handler(s) for event: $event_name (safe mode)"

  typeset -i failed=0 handled=0 timeout_val
  (( timeout_val = $(z::config::get event_handler_timeout) ))
  local -a handlers_to_remove

  local handler_id handler_func once_flag
  for handler_id in "${all_handler_ids[@]}"; do
    z::sys::interrupted || return $?

    handler_func="${_zcore_event_handler_meta[${handler_id}.function]:-}"
    once_flag="${_zcore_event_handler_meta[${handler_id}.once]:-false}"

    if [[ -z $handler_func ]]; then
      z::log::warn "Handler metadata missing for ID: $handler_id"
      continue
    fi

    if ! z::func::probe "$handler_func"; then
      z::log::warn "Handler function no longer exists: $handler_func"
      handlers_to_remove+=("$handler_id")
      continue
    fi

    z::log::debug "Calling handler (safe): $handler_func (id: $handler_id, timeout: ${timeout_val}s)"

    # Execute in subshell with timeout
    typeset -i exit_code=0
    (
      TMOUT=$timeout_val
      "$handler_func" "$event_name" "$@"
    )
    exit_code=$?

    if (( exit_code == 142 )); then
      # SIGALRM - timeout
      (( failed += 1 ))
      z::log::error "Handler '$handler_func' timed out after ${timeout_val}s"
      __z::event::update_stats "$event_name" "failed"
    elif (( exit_code != 0 )); then
      (( failed += 1 ))
      z::log::warn "Handler '$handler_func' failed with exit code: $exit_code"
      __z::event::update_stats "$event_name" "failed"
    else
      (( handled += 1 ))
      __z::event::update_stats "$event_name" "handled"
    fi

    if [[ $once_flag == true ]]; then
      handlers_to_remove+=("$handler_id")
      z::log::debug "One-time handler will be removed: $handler_func"
    fi
  done

  if (( ${#handlers_to_remove} > 0 )); then
    local remove_id
    for remove_id in "${handlers_to_remove[@]}"; do
      __z::event::remove_handler_by_id "$remove_id"
    done
  fi

  z::log::debug "Safe event '$event_name' completed: $handled handled, $failed failed"

  (( failed == 0 ))
}

###
# Emit event asynchronously (non-blocking)
#
# Usage:
#   z::event::emit_async "metrics:updated" "$stats"
#
# Limitations:
# - No error reporting from handlers
# - No job tracking or cancellation
# - Arguments must be serializable
# - Potential resource exhaustion with high volume
# - Use sparingly for non-critical notifications
#
# @param 1: string - Event name
# @param ...: any - Event arguments
# @return 0 always (does not wait for handlers)
###
z::event::emit_async() {
  emulate -L zsh
  setopt localoptions no_unset

  local event_name="$1"
  shift

  __z::event::validate_event_name "$event_name" || return $?

  z::log::debug "Emitting async event: $event_name"

  # Background execution with cleanup
  {
    z::event::emit "$event_name" "$@"
  } &!

  return 0
}

###
# Unsubscribe from event(s)
#
# Usage:
#   z::event::unsubscribe "plugin:loaded" my_handler
#   z::event::unsubscribe "plugin:loaded"
#   z::event::unsubscribe "*" my_handler
#
# @param 1: string - Event name (supports wildcards)
# @param 2: string - Handler function name (optional, removes all if omitted)
# @return 0 on success, ZCORE_ERROR_* on failure
###
z::event::unsubscribe() {
  emulate -L zsh
  setopt localoptions no_unset

  local event_pattern="$1"
  local handler_func="${2:-}"

  __z::event::validate_event_name "$event_pattern" || return $?

  typeset -i removed=0
  local pattern handler_list

  # Check both storage maps
  local -a all_patterns
  all_patterns=(
    "${(@k)_zcore_event_handlers_exact}"
    "${(@k)_zcore_event_handlers_wildcard}"
  )

  for pattern in "${all_patterns[@]}"; do
    z::sys::interrupted || return $?

    __z::event::match_pattern "$pattern" "$event_pattern" || continue

    # Get handler list from appropriate storage
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
        z::log::debug "Unsubscribed handler: $stored_func (id: $handler_id) from event: $pattern"
      fi
    done
  done

  if (( removed > 0 )); then
    z::log::debug "Unsubscribed $removed handler(s)"
  else
    z::log::debug "No handlers unsubscribed"
  fi

  return 0
}

###
# Check if event has registered handlers
#
# Usage:
#   if z::event::has_handlers "plugin:loaded"; then
#     z::log::info "Has handlers"
#   fi
#
# @param 1: string - Event name (supports wildcards)
# @return 0 if handlers exist, 1 if none
###
z::event::has_handlers() {
  emulate -L zsh
  setopt localoptions no_unset

  local event_name="$1"

  __z::event::validate_event_name "$event_name" || return 1

  # Check exact match
  [[ -n ${_zcore_event_handlers_exact[$event_name]:-} ]] && return 0

  # Check wildcards if enabled
  if [[ $(z::config::get event_enable_wildcards) == true ]]; then
    local pattern
    for pattern in "${(@k)_zcore_event_handlers_wildcard}"; do
      if __z::event::match_pattern "$event_name" "$pattern"; then
        [[ -n ${_zcore_event_handlers_wildcard[$pattern]:-} ]] && return 0
      fi
    done
  fi

  return 1
}

###
# Count handlers for an event
#
# Usage:
#   count=$(z::event::count "plugin:loaded")
#   echo "Handlers: $count"
#
# @param 1: string - Event name (supports wildcards)
# @return 0 always, outputs count to stdout
###
z::event::count() {
  emulate -L zsh
  setopt localoptions no_unset

  local event_name="$1"

  __z::event::validate_event_name "$event_name" || { print 0; return 1; }

  typeset -i total=0
  local -a handlers
  local handler_list

  # Count exact match
  handler_list="${_zcore_event_handlers_exact[$event_name]:-}"
  if [[ -n $handler_list ]]; then
    __z::event::parse_handler_list "$handler_list" handlers
    (( total += ${#handlers} ))
  fi

  # Count wildcard matches
  if [[ $(z::config::get event_enable_wildcards) == true ]]; then
    local pattern
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
  return 0
}

###
# List all registered event handlers
#
# Usage:
#   z::event::list
#   z::event::list "plugin:*"
#
# @param 1: string - Event pattern filter (optional)
# @return 0 always
###
z::event::list() {
  emulate -L zsh
  setopt localoptions no_unset no_xtrace no_verbose

  local filter_pattern="${1:-*}"

  print "\nRegistered Event Handlers:"
  print "=========================="

  typeset -i total=0

  # Declare ALL variables at function scope to prevent leakage
  local event_pattern handler_list
  local color_blue="${_zcore_colors[blue]:-}"
  local color_yellow="${_zcore_colors[yellow]:-}"
  local color_reset="${_zcore_colors[reset]:-}"
  local current_handler func_name priority_val once_val marker
  local -a all_events handlers
  typeset -i i

  # Collect all event patterns from both storage maps
  all_events=(
    "${(@k)_zcore_event_handlers_exact}"
    "${(@k)_zcore_event_handlers_wildcard}"
  )

  if (( ${#all_events} == 0 )); then
    print "No handlers registered.\n"
    return 0
  fi

  for event_pattern in "${all_events[@]}"; do
    __z::event::match_pattern "$event_pattern" "$filter_pattern" || continue

    # Get handler list from appropriate storage
    if [[ $event_pattern == *'*'* ]]; then
      handler_list="${_zcore_event_handlers_wildcard[$event_pattern]:-}"
    else
      handler_list="${_zcore_event_handlers_exact[$event_pattern]:-}"
    fi

    [[ -z $handler_list ]] && continue

    __z::event::parse_handler_list "$handler_list" handlers

    print "\nEvent: ${color_blue}${event_pattern}${color_reset}"
    print "  Handlers: ${#handlers}"

    # Process handlers with pre-declared variables
    for (( i = 1; i <= ${#handlers}; i++ )); do
      current_handler="${handlers[i]}"
      func_name="${_zcore_event_handler_meta[${current_handler}.function]:-unknown}"
      priority_val="${_zcore_event_handler_meta[${current_handler}.priority]:-50}"
      once_val="${_zcore_event_handler_meta[${current_handler}.once]:-false}"

      marker=""
      [[ $once_val == true ]] && marker=" ${color_yellow}[once]${color_reset}"

      print "    - ${func_name} (priority: ${priority_val})${marker}"
      (( total += 1 ))
    done
  done

  print "\nTotal handlers: $total\n"
  return 0
}

###
# Show event statistics
#
# Usage:
#   z::event::stats
#   z::event::stats "plugin:loaded"
#
# @param 1: string - Event name filter (optional)
# @return 0 always
###
z::event::stats() {
  emulate -L zsh
  setopt localoptions no_unset

  local filter="${1:-}"

  print "\nEvent Statistics:"
  print "================="

  if [[ $(z::config::get event_enable_stats) != true ]]; then
    print "Statistics disabled.\n"
    return 0
  fi

  if (( ${#_zcore_event_stats} == 0 )); then
    print "No statistics available.\n"
    return 0
  fi

  # Collect unique event names
  local -a unique_events
  local key event_name

  for key in "${(@k)_zcore_event_stats}"; do
    event_name="${key%.*}"

    [[ -n $filter && $event_name != *${filter}* ]] && continue

    # Check if already processed
    (( ${unique_events[(Ie)$event_name]} )) && continue
    unique_events+=("$event_name")
  done

  if (( ${#unique_events} == 0 )); then
    print "No matching statistics.\n"
    return 0
  fi

  local color_blue="${_zcore_colors[blue]:-}"
  local color_reset="${_zcore_colors[reset]:-}"

  for event_name in "${unique_events[@]}"; do
    local emitted="${_zcore_event_stats[${event_name}.emitted]:-0}"
    local handled="${_zcore_event_stats[${event_name}.handled]:-0}"
    local failed="${_zcore_event_stats[${event_name}.failed]:-0}"

    print "\n${color_blue}${event_name}${color_reset}"
    print "  Emitted: $emitted"
    print "  Handled: $handled"
    print "  Failed:  $failed"
  done

  print ""
  return 0
}

###
# Show event history
#
# Usage:
#   z::event::history
#   z::event::history 20
#   z::event::history 10 "plugin:*"
#
# @param 1: integer - Number of recent events to show (optional, default: 20)
# @param 2: string - Event name filter (optional)
# @return 0 always
###
z::event::history() {
  emulate -L zsh
  setopt localoptions no_unset no_xtrace no_verbose

  typeset -i limit
  (( limit = 10#${1:-20} ))
  local filter="${2:-}"

  print "\nEvent History (last $limit):"
  print "============================"

  if [[ $(z::config::get event_enable_history) != true ]]; then
    print "History disabled.\n"
    return 0
  fi

  if (( ${#_zcore_event_history} == 0 )); then
    print "No history available.\n"
    return 0
  fi

  # Get recent entries
  typeset -i start display_idx
  (( start = ${#_zcore_event_history} - limit + 1 ))
  (( start < 1 )) && (( start = 1 ))

  local -a recent_history
  recent_history=("${(@)_zcore_event_history[start,-1]}")

  # Declare ALL variables at function scope
  local color_blue="${_zcore_colors[blue]:-}"
  local color_reset="${_zcore_colors[reset]:-}"
  local entry ts remainder evt arg formatted_time

  # Display in reverse order (newest first)
  (( display_idx = ${#recent_history} ))

  for entry in "${(@Oa)recent_history}"; do
    z::sys::interrupted || return $?

    ts="${entry%%|*}"
    remainder="${entry#*|}"
    evt="${remainder%%|*}"
    arg="${remainder#*|}"

    # Apply filter
    if [[ -n $filter ]]; then
      __z::event::match_pattern "$evt" "$filter" || { (( display_idx -= 1 )); continue; }
    fi

    # Format timestamp
    if [[ $ts == <-> ]]; then
      formatted_time=$(date -r "$ts" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || print "$ts")
    else
      formatted_time="$ts"
    fi

    print "${display_idx}. [${formatted_time}] ${color_blue}${evt}${color_reset}"
    [[ -n $arg ]] && print "   Args: $arg"

    (( display_idx -= 1 ))
  done

  print ""
  return 0
}

###
# Clear event history
#
# Usage:
#   z::event::clear_history
#
# @return 0 always
###
z::event::clear_history() {
  emulate -L zsh
  setopt localoptions no_unset

  _zcore_event_history=()
  z::log::info "Event history cleared"
  return 0
}

###
# Clear event statistics
#
# Usage:
#   z::event::clear_stats
#
# @return 0 always
###
z::event::clear_stats() {
  emulate -L zsh
  setopt localoptions no_unset

  _zcore_event_stats=()
  z::log::info "Event statistics cleared"
  return 0
}

###
# Reset entire event system
#
# Usage:
#   z::event::reset
#
# @return 0 always
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

  z::log::info "Event system reset"
  return 0
}
################################################################################
# CONFIGURATION
################################################################################

###
# Configure event system
#
# Usage:
#   z::event::configure max_history 200
#   z::event::configure enable_history false
#
# @param 1: string - Configuration key
# @param 2: any - Configuration value
# @return 0 on success, 1 on invalid key
###
z::event::configure() {
  emulate -L zsh
  local key="$1"
  local value="$2"

  if (( ! ${+_zcore_event_config[$key]} )); then
    z::log::error "Unknown event configuration key: $key"
    return 1
  fi

  _zcore_event_config[$key]="$value"
  z::log::debug "Event config updated: $key = $value"
  return 0
}

###
# Get event system configuration
#
# Usage:
#   z::event::get_config max_history
#
# @param 1: string - Configuration key
# @stdout Configuration value
# @return 0 on success, 1 on invalid key
###
z::event::get_config() {
  emulate -L zsh
  local key="$1"

  if (( ! ${+_zcore_event_config[$key]} )); then
    z::log::error "Unknown event configuration key: $key"
    return 1
  fi

  print -r -- "${_zcore_event_config[$key]}"
  return 0
}

################################################################################
# INITIALIZATION COMPLETE
################################################################################

z::log::debug "Event system initialized"
print "loaded: Logging ✓ | Cache ✓ | KV Store ✓ | EventBus ✓" >&2
