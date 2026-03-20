#!/usr/bin/env zsh

###############################################################################
# Example: Web Server Request Logger
###############################################################################

# Source the logging framework
SCRIPT_DIR="${0:A:h}"
source "${SCRIPT_DIR}/zlog.zsh"

# Application configuration
typeset -g APP_NAME="WebServer"
typeset -g APP_VERSION="1.0.0"
typeset -g LOG_DIR="/tmp/webserver_logs"
typeset -g ACCESS_LOG="$LOG_DIR/access.log"
typeset -g ERROR_LOG="$LOG_DIR/error.log"
typeset -g APP_LOG="$LOG_DIR/app.log"

###############################################################################
# Application Setup
###############################################################################

setup_logging() {
  # Create log directory
  mkdir -p "$LOG_DIR"

  # Configure main application log
  z::log::quick_start "$APP_LOG" "info" "text"
  z::log::set_rotation 1 "10MB" 5
  z::log::enable_buffering 100

  # Register cleanup
  z::log::register_cleanup

  z::log::info "Application starting" \
    "name" "$APP_NAME" \
    "version" "$APP_VERSION" \
    "log_dir" "$LOG_DIR"
}

###############################################################################
# Request Handling
###############################################################################

# Simulate request ID generation
generate_request_id() {
  REPLY="req_${RANDOM}${RANDOM}_${EPOCHREALTIME/./}"
}

# Log access (Apache Combined Log Format style)
log_access() {
  local method="$1"
  local path="$2"
  local status="$3"
  local duration_ms="$4"
  local client_ip="$5"
  local user_agent="$6"

  # Write to access log (separate file)
  local timestamp=$(z::log::get_timestamp human)
  print "$timestamp - $client_ip \"$method $path\" $status ${duration_ms}ms \"$user_agent\"" \
    >> "$ACCESS_LOG"
}

# Handle HTTP request
handle_request() {
  local method="$1"
  local path="$2"
  local client_ip="$3"
  local user_agent="${4:-Mozilla/5.0}"

  # Generate request ID for tracking
  generate_request_id
  local request_id="$REPLY"

  # Create context logger for this request
  z::log::with_context \
    "request_id" "$request_id" \
    "method" "$method" \
    "path" "$path" \
    "client_ip" "$client_ip"
  local ctx="$REPLY"

  # Log request received
  ${ctx}::info "Request received"

  # Simulate request processing
  local start_time=$EPOCHREALTIME

  # Route handling
  local status=200
  case "$path" in
    /api/users)
      ${ctx}::debug "Handling users API"
      simulate_database_query "$ctx" "users"
      ;;
    /api/products)
      ${ctx}::debug "Handling products API"
      simulate_database_query "$ctx" "products"
      ;;
    /api/slow)
      ${ctx}::warn "Slow endpoint accessed"
      sleep 0.5
      ;;
    /api/error)
      ${ctx}::error "Simulated error endpoint"
      status=500
      ;;
    *)
      ${ctx}::warn "Unknown endpoint"
      status=404
      ;;
  esac

  # Calculate duration
  local end_time=$EPOCHREALTIME
  local duration_ms=$(( (end_time - start_time) * 1000 ))

  # Log slow requests
  if (( duration_ms > 100 )); then
    ${ctx}::warn "Slow request detected" "duration_ms" "$duration_ms"
  fi

  # Log completion
  ${ctx}::info "Request completed" "status" "$status" "duration_ms" "$duration_ms"

  # Write to access log
  log_access "$method" "$path" "$status" "$duration_ms" "$client_ip" "$user_agent"

  # Cleanup context
  z::log::remove_context "$ctx"

  return $status
}

# Simulate database query
simulate_database_query() {
  local ctx="$1"
  local table="$2"

  ${ctx}::debug "Executing database query" "table" "$table"

  # Simulate query time
  sleep 0.0$((RANDOM % 5))

  local rows=$((RANDOM % 100))
  ${ctx}::debug "Query completed" "rows" "$rows"
}

###############################################################################
# Error Handling
###############################################################################

handle_error() {
  local error_type="$1"
  local error_msg="$2"
  shift 2

  # Log to error log file
  local timestamp=$(z::log::get_timestamp iso)
  print "$timestamp [$error_type] $error_msg" >> "$ERROR_LOG"

  # Also log to main log
  z::log::error "$error_msg" "error_type" "$error_type" "$@"
}

###############################################################################
# Monitoring and Stats
###############################################################################

log_system_stats() {
  # Get memory usage
  local mem_usage=$(ps -o rss= -p $$ 2>/dev/null || echo "0")

  # Get log file sizes
  local app_log_size=0
  [[ -f "$APP_LOG" ]] && app_log_size=$(wc -c < "$APP_LOG")

  local access_log_size=0
  [[ -f "$ACCESS_LOG" ]] && access_log_size=$(wc -c < "$ACCESS_LOG")

  # Format sizes
  __z::log::format_size "$app_log_size"
  local app_log_human="$REPLY"

  __z::log::format_size "$access_log_size"
  local access_log_human="$REPLY"

  z::log::info "System statistics" \
    "memory_kb" "$mem_usage" \
    "app_log_size" "$app_log_human" \
    "access_log_size" "$access_log_human" \
    "buffer_count" "$(z::log::get_buffer_count)"
}

###############################################################################
# Main Application
###############################################################################

run_webserver_simulation() {
  setup_logging

  print "╔════════════════════════════════════════════════════════════════╗"
  print "║              Web Server Logger - Example Application          ║"
  print "╠════════════════════════════════════════════════════════════════╣"
  print "║ Application Log: $(printf '%-43s' "$APP_LOG") ║"
  print "║ Access Log:      $(printf '%-43s' "$ACCESS_LOG") ║"
  print "║ Error Log:       $(printf '%-43s' "$ERROR_LOG") ║"
  print "╚════════════════════════════════════════════════════════════════╝"
  print

  # Simulate various requests
  local -a methods=(GET POST PUT DELETE)
  local -a paths=(
    /api/users
    /api/products
    /api/orders
    /api/slow
    /api/error
    /api/unknown
  )
  local -a ips=(
    192.168.1.100
    192.168.1.101
    203.0.113.42
    198.51.100.50
  )

  print "Simulating 50 HTTP requests..."
  local i
  for i in {1..50}; do
    local method="${methods[$((RANDOM % ${#methods} + 1))]}"
    local path="${paths[$((RANDOM % ${#paths} + 1))]}"
    local ip="${ips[$((RANDOM % ${#ips} + 1))]}"

    handle_request "$method" "$path" "$ip" "Mozilla/5.0"

    # Occasional error
    if (( RANDOM % 10 == 0 )); then
      handle_error "DatabaseError" "Connection timeout" "retry_count" "3"
    fi

    # Log stats every 10 requests
    if (( i % 10 == 0 )); then
      log_system_stats
      print -n "."
    fi

    # Small delay
    sleep 0.01
  done

  print "\n\nSimulation complete!"

  # Final stats
  print "\n$(z::log::colorize 'bold' 'Final Statistics:')"
  log_system_stats

  # Show log samples
  print "\n$(z::log::colorize 'bold' 'Application Log Sample (last 10 lines):')"
  print "$(z::log::colorize 'dim' '────────────────────────────────────────────────────────────────')"
  tail -10 "$APP_LOG" 2>/dev/null
  print "$(z::log::colorize 'dim' '────────────────────────────────────────────────────────────────')"

  print "\n$(z::log::colorize 'bold' 'Access Log Sample (last 10 lines):')"
  print "$(z::log::colorize 'dim' '────────────────────────────────────────────────────────────────')"
  tail -10 "$ACCESS_LOG" 2>/dev/null
  print "$(z::log::colorize 'dim' '────────────────────────────────────────────────────────────────')"

  # Cleanup
  z::log::cleanup

  print "\n$(z::log::colorize 'green' '✓ Example completed!')"
  print "Logs saved to: $LOG_DIR"
}

# Run if executed directly
if [[ "${ZSH_EVAL_CONTEXT}" == "toplevel" ]]; then
  run_webserver_simulation
fi
