#!/usr/bin/env zsh
# test_event.zsh - Example application using Zcore event system

source zcore_v2.zsh

#
# Configuration
#

typeset -g APP_NAME="MyApp"
typeset -g APP_VERSION="1.0.0"
typeset -gA config
typeset -gA sessions
typeset -gi request_count=0

#
# Event Handlers
#

# Application lifecycle handlers
handle_app_init() {
  local event_name="$1"
  z::log::info "[$event_name] Initializing $APP_NAME v$APP_VERSION"

  # Set default config
  config[database]="localhost:5432"
  config[cache_size]="100"
  config[max_sessions]="50"

  return 0
}

handle_config_load() {
  local event_name="$1"
  local config_file="$2"

  z::log::info "[$event_name] Loading configuration from $config_file"

  # Simulate config loading
  if [[ -f $config_file ]]; then
    z::log::debug "Config file found, loading..."
    # In real app: source or parse config file
  else
    z::log::warn "Config file not found, using defaults"
  fi

  return 0
}

handle_app_ready() {
  local event_name="$1"

  z::log::info "[$event_name] $APP_NAME is ready"
  z::log::info "  Database: ${config[database]}"
  z::log::info "  Cache size: ${config[cache_size]}"
  z::log::info "  Max sessions: ${config[max_sessions]}"

  return 0
}

handle_app_shutdown() {
  local event_name="$1"

  z::log::info "[$event_name] Application shutdown initiated"

  # Cleanup resources
  typeset -i active_sessions
  (( active_sessions = ${#sessions} ))

  if (( active_sessions > 0 )); then
    z::log::warn "Forcing logout of $active_sessions active session(s)"
  fi

  return 0
}

# User management handlers
handle_user_login() {
  local event_name="$1"
  local username="$2"
  local timestamp="$3"

  z::log::info "[$event_name] User logged in: $username at $timestamp"

  # Check session limit
  typeset -i max_sessions
  (( max_sessions = ${config[max_sessions]:-50} ))

  if (( ${#sessions} >= max_sessions )); then
    z::log::error "Session limit reached ($max_sessions)"
    z::event::emit "error:session_limit" "Cannot create session for $username"
    return 1
  fi

  # Create session - use local timestamp variable
  local session_id="session_${RANDOM}_${timestamp}"
  sessions[$session_id]="$username"

  z::event::emit "session:created" "$session_id" "$username"
  return 0
}

handle_session_created() {
  local event_name="$1"
  local session_id="$2"
  local username="$3"

  z::log::debug "[$event_name] Session created: $session_id for $username"

  # Track analytics asynchronously
  z::event::emit_async "analytics:track" "session_created" "$username"

  return 0
}

handle_user_logout() {
  local event_name="$1"
  local session_id="$2"

  local username="${sessions[$session_id]:-unknown}"

  z::log::info "[$event_name] User logged out: $username (session: $session_id)"

  if [[ -z ${sessions[$session_id]:-} ]]; then
    z::log::warn "Session not found: $session_id"
    return 1
  fi

  unset "sessions[$session_id]"
  z::event::emit "session:destroyed" "$session_id" "$username"

  return 0
}

handle_session_destroyed() {
  local event_name="$1"
  local session_id="$2"
  local username="$3"

  z::log::debug "[$event_name] Session destroyed: $session_id"

  # Track analytics
  z::event::emit_async "analytics:track" "session_destroyed" "$username"

  return 0
}

# Request handling
handle_request() {
  local event_name="$1"
  local session_id="$2"
  local endpoint="$3"

  (( request_count += 1 ))

  local username="${sessions[$session_id]:-anonymous}"
  z::log::debug "[$event_name] Request #$request_count: $endpoint by $username"

  # Validate session
  if [[ -z ${sessions[$session_id]:-} ]]; then
    z::event::emit "error:unauthorized" "Invalid session: $session_id"
    return 1
  fi

  return 0
}

# Analytics handler (runs async)
handle_analytics() {
  local event_name="$1"
  local event_type="$2"
  local data="$3"

  z::log::debug "[$event_name] Analytics: $event_type - $data"

  # Simulate sending to analytics service
  sleep 0.1

  return 0
}

# Error handlers (wildcard pattern)
handle_error() {
  local event_name="$1"
  local error_msg="$2"
  local context="${3:-}"

  # Extract error type from event name (e.g., "error:critical" -> "critical")
  local error_type="${event_name#error:}"

  z::log::error "[$error_type] $error_msg"
  [[ -n $context ]] && z::log::debug "Context: $context"

  # Emit critical alert if needed
  if [[ $error_type == "critical" ]]; then
    z::event::emit "alert:critical" "$error_msg"
  fi

  return 0
}

handle_critical_alert() {
  local event_name="$1"
  local message="$2"

  z::log::error "[$event_name] CRITICAL ALERT: $message"

  # In real app: send email, SMS, PagerDuty, etc.
  print "\n🚨 CRITICAL ALERT: $message\n" >&2

  return 0
}

# Monitoring handlers
handle_monitor_check() {
  local event_name="$1"

  typeset -i active_sessions
  (( active_sessions = ${#sessions} ))

  z::log::debug "[$event_name] Monitor check:"
  z::log::debug "  Active sessions: $active_sessions"
  z::log::debug "  Total requests: $request_count"

  # Check thresholds
  typeset -i max_sessions
  (( max_sessions = ${config[max_sessions]:-50} ))

  if (( active_sessions > max_sessions * 0.8 )); then
    z::event::emit "alert:high_load" "Sessions: $active_sessions / $max_sessions"
  fi

  return 0
}

handle_high_load_alert() {
  local event_name="$1"
  local details="$2"

  z::log::warn "[$event_name] High load detected: $details"

  return 0
}

# Plugin system example
handle_plugin_loaded() {
  local event_name="$1"
  local plugin_name="$2"

  z::log::info "[$event_name] Plugin loaded: $plugin_name"

  return 0
}

handle_plugin_event() {
  local event_name="$1"
  shift
  local -a args=("$@")

  # This handler catches all plugin:* events
  z::log::debug "[$event_name] Plugin event with ${#args} arg(s)"

  return 0
}

# One-time initialization handler
handle_database_init() {
  local event_name="$1"

  z::log::info "[$event_name] Initializing database connection..."

  # Simulate database initialization
  sleep 0.2

  z::log::info "Database initialized successfully"

  return 0
}

# Slow handler for testing timeout protection
handle_slow_operation() {
  local event_name="$1"
  local duration="${2:-10}"

  z::log::warn "[$event_name] Starting slow operation (${duration}s)..."

  sleep "$duration"

  z::log::info "Slow operation completed"

  return 0
}

#
# Register Event Handlers
#

register_handlers() {
  z::log::info "Registering event handlers..."

  # Lifecycle events (high priority)
  z::event::subscribe "app:init" handle_app_init --priority $ZCORE_EVENT_PRIORITY_HIGHEST
  z::event::subscribe "app:config_load" handle_config_load --priority $ZCORE_EVENT_PRIORITY_HIGH
  z::event::subscribe "app:ready" handle_app_ready --priority $ZCORE_EVENT_PRIORITY_NORMAL
  z::event::subscribe "app:shutdown" handle_app_shutdown --priority $ZCORE_EVENT_PRIORITY_HIGHEST

  # One-time database initialization
  z::event::subscribe_once "app:ready" handle_database_init --priority $ZCORE_EVENT_PRIORITY_HIGH

  # User events
  z::event::subscribe "user:login" handle_user_login
  z::event::subscribe "user:logout" handle_user_logout
  z::event::subscribe "session:created" handle_session_created
  z::event::subscribe "session:destroyed" handle_session_destroyed

  # Request handling
  z::event::subscribe "request:api" handle_request

  # Analytics (async, low priority)
  z::event::subscribe "analytics:track" handle_analytics --priority $ZCORE_EVENT_PRIORITY_LOW

  # Error handling (wildcard pattern, highest priority)
  z::event::subscribe "error:*" handle_error --priority $ZCORE_EVENT_PRIORITY_HIGHEST
  z::event::subscribe "alert:critical" handle_critical_alert --priority $ZCORE_EVENT_PRIORITY_HIGHEST
  z::event::subscribe "alert:high_load" handle_high_load_alert

  # Monitoring
  z::event::subscribe "monitor:check" handle_monitor_check

  # Plugin system (wildcard)
  z::event::subscribe "plugin:loaded" handle_plugin_loaded
  z::event::subscribe "plugin:*" handle_plugin_event --priority $ZCORE_EVENT_PRIORITY_LOW

  # Slow operation (for testing timeout)
  z::event::subscribe "test:slow" handle_slow_operation

  z::log::info "Event handlers registered"

  return 0
}

#
# Application Functions
#

init_app() {
  z::log::info "Starting $APP_NAME..."

  # Register all handlers
  register_handlers

  # Emit initialization events
  z::event::emit "app:init"
  z::event::emit "app:config_load" "/etc/myapp/config.conf"
  z::event::emit "app:ready"

  # Note: handle_database_init runs only once due to subscribe_once

  return 0
}

simulate_user_activity() {
  z::log::info "Simulating user activity..."

  # Get current timestamp once
  local current_time="${EPOCHSECONDS:-$(date +%s)}"

  # User logins
  z::event::emit "user:login" "alice" "$current_time"
  sleep 0.5

  (( current_time += 1 ))
  z::event::emit "user:login" "bob" "$current_time"
  sleep 0.5

  (( current_time += 1 ))
  z::event::emit "user:login" "charlie" "$current_time"
  sleep 0.5

  # Check if we have handlers before emitting
  if z::event::has_handlers "monitor:check"; then
    local count
    count=$(z::event::count "monitor:check")
    z::log::info "Found $count handler(s) for monitor:check"
    z::event::emit "monitor:check"
  fi

  sleep 0.5

  # Simulate API requests
  if (( ${#sessions} > 0 )); then
    local -a session_keys
    session_keys=("${(@k)sessions}")

    local session_id="${session_keys[1]}"
    z::event::emit "request:api" "$session_id" "/api/users"
    sleep 0.3

    z::event::emit "request:api" "$session_id" "/api/posts"
    sleep 0.3
  fi

  # Simulate plugin loading
  z::event::emit "plugin:loaded" "auth-plugin"
  z::event::emit "plugin:enabled" "auth-plugin"

  sleep 0.5

  # Simulate error
  z::event::emit "error:validation" "Invalid input data" "user_id=123"

  sleep 0.5

  # User logouts
  if (( ${#sessions} > 0 )); then
    local -a session_keys
    session_keys=("${(@k)sessions}")

    local session_id
    for session_id in "${session_keys[@]}"; do
      z::event::emit "user:logout" "$session_id"
      sleep 0.3
    done
  else
    z::log::warn "No active sessions to logout"
  fi

  return 0
}

test_timeout_protection() {
  z::log::info "Testing timeout protection..."

  # This will timeout (default: 5s)
  z::log::info "Emitting slow event with emit_safe (should timeout)..."
  if z::event::emit_safe "test:slow" 10; then
    z::log::info "Slow event completed"
  else
    z::log::warn "Slow event failed or timed out (expected)"
  fi

  return 0
}

test_wildcard_handlers() {
  z::log::info "Testing wildcard handlers..."

  # These should all trigger the error:* handler
  z::event::emit "error:database" "Connection failed"
  z::event::emit "error:network" "Timeout"
  z::event::emit "error:critical" "System failure"

  return 0
}

show_stats() {
  print ""
  z::log::info "========================================="
  z::log::info "Event System Statistics"
  z::log::info "========================================="

  # Show registered handlers
  z::event::list

  # Show event statistics
  z::event::stats

  # Show recent history
  z::event::history 15

  # Show handler counts for specific events
  print ""
  z::log::info "Handler Counts:"
  local event count
  for event in "user:login" "error:*" "plugin:*" "app:ready"; do
    if z::event::has_handlers "$event"; then
      count=$(z::event::count "$event")
      z::log::info "  $event: $count handler(s)"
    else
      z::log::info "  $event: no handlers"
    fi
  done

  return 0
}


shutdown_app() {
  z::log::info "Shutting down $APP_NAME..."

  # Emit shutdown event
  z::event::emit "app:shutdown"

  # Logout all remaining users
  if (( ${#sessions} > 0 )); then
    local session_id
    for session_id in "${(@k)sessions}"; do
      z::event::emit "user:logout" "$session_id"
    done
  fi

  # Clear event system (optional)
  # z::event::reset

  z::log::info "Goodbye!"

  return 0
}

#
# Main
#

main() {
  # Set log level
  z::log::set_level info

  # Initialize application
  init_app

  # Simulate user activity
  simulate_user_activity

  # Test wildcard handlers
  test_wildcard_handlers

  # Test timeout protection (uncomment to test - adds 5s delay)
  # test_timeout_protection

  # Show statistics
  show_stats

  # Shutdown
  shutdown_app

  return 0
}

# Handle interrupts gracefully
cleanup_on_interrupt() {
  z::log::warn "Interrupt received, cleaning up..."
  shutdown_app
  exit 130
}

trap 'cleanup_on_interrupt' INT TERM

# Run application
main "$@"
