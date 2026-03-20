#!/usr/bin/env zsh

###############################################################################
# ZLOG Interactive Demonstration
###############################################################################

# Source the logging framework
SCRIPT_DIR="${0:A:h}"
source "${SCRIPT_DIR}/zlog.zsh"

# Demo configuration
typeset -g DEMO_LOG="/tmp/zlog_demo.log"

# Print demo header
print_header() {
  print "\n╔════════════════════════════════════════════════════════════════╗"
  print "║          ZLOG Framework - Interactive Demonstration           ║"
  print "╚════════════════════════════════════════════════════════════════╝\n"
}

# Wait for user
wait_for_user() {
  print -n "\n$(z::log::colorize 'cyan' 'Press Enter to continue...')"
  read
}

# Demo 1: Basic Logging
demo_basic_logging() {
  print "\n$(z::log::colorize 'bold' '━━━ Demo 1: Basic Logging ━━━')"
  print "Setting up logging to file and console..."

  z::log::quick_start "$DEMO_LOG" "debug" "text"

  print "\nLogging at all levels:"
  z::log::error "This is an error message"
  z::log::warn "This is a warning message"
  z::log::info "This is an info message"
  z::log::debug "This is a debug message"

  wait_for_user
}

# Demo 2: Context Logging
demo_context_logging() {
  print "\n$(z::log::colorize 'bold' '━━━ Demo 2: Context Logging ━━━')"
  print "Adding structured context to log messages..."

  print "\nUser login event:"
  z::log::info "User logged in" \
    "user" "john.doe" \
    "ip" "192.168.1.100" \
    "session" "abc123xyz" \
    "method" "password"

  print "\nDatabase query:"
  z::log::debug "Query executed" \
    "query" "SELECT * FROM users" \
    "duration_ms" "45" \
    "rows" "150"

  print "\nAPI request:"
  z::log::info "API request received" \
    "method" "POST" \
    "path" "/api/v1/users" \
    "status" "201" \
    "response_time_ms" "120"

  wait_for_user
}

# Demo 3: Printf-Style Formatting
demo_printf_formatting() {
  print "\n$(z::log::colorize 'bold' '━━━ Demo 3: Printf-Style Formatting ━━━')"
  print "Using printf-style format strings..."

  local total=100
  local processed=75
  local percent=$(( processed * 100.0 / total ))

  print "\nProgress reporting:"
  z::log::infof "Processed %d out of %d items (%.1f%% complete)" \
    $processed $total $percent

  print "\nMemory usage:"
  z::log::warnf "Memory usage: %d MB (%.1f%% of available)" 1500 75.5

  print "\nConnection error:"
  z::log::errorf "Failed to connect to %s:%d (timeout: %ds)" \
    "database.example.com" 5432 30

  wait_for_user
}

# Demo 4: JSON Format
demo_json_format() {
  print "\n$(z::log::colorize 'bold' '━━━ Demo 4: JSON Format ━━━')"
  print "Switching to JSON output format..."

  z::log::set_format "json"

  print "\nJSON formatted logs:"
  z::log::info "Application started" "version" "1.0.0" "environment" "production"
  z::log::warn "High memory usage detected" "usage_mb" "1500" "threshold_mb" "1200"
  z::log::error "Database connection failed" "error" "timeout" "retry_count" "3"

  z::log::set_format "text"  # Reset

  wait_for_user
}

# Demo 5: Level Filtering
demo_level_filtering() {
  print "\n$(z::log::colorize 'bold' '━━━ Demo 5: Level Filtering ━━━')"
  print "Demonstrating log level filtering..."

  print "\n1. Setting level to ERROR (only errors will show):"
  z::log::set_level "error"
  z::log::error "This ERROR will appear"
  z::log::warn "This WARN will NOT appear"
  z::log::info "This INFO will NOT appear"
  z::log::debug "This DEBUG will NOT appear"

  print "\n2. Setting level to WARN (errors and warnings):"
  z::log::set_level "warn"
  z::log::error "This ERROR will appear"
  z::log::warn "This WARN will appear"
  z::log::info "This INFO will NOT appear"

  print "\n3. Setting level to DEBUG (everything):"
  z::log::set_level "debug"
  z::log::error "This ERROR will appear"
  z::log::warn "This WARN will appear"
  z::log::info "This INFO will appear"
  z::log::debug "This DEBUG will appear"

  z::log::set_level "info"  # Reset

  wait_for_user
}

# Demo 6: Conditional Logging
demo_conditional_logging() {
  print "\n$(z::log::colorize 'bold' '━━━ Demo 6: Conditional Logging ━━━')"
  print "Using conditional logging to avoid expensive operations..."

  z::log::set_level "info"

  print "\nChecking if debug is enabled before expensive operation:"
  if z::log::if_debug; then
    print "  Debug is enabled - would gather debug info"
    z::log::debug "Debug information gathered"
  else
    print "  Debug is disabled - skipping expensive debug gathering"
  fi

  print "\nChecking if info is enabled:"
  if z::log::if_info; then
    print "  Info is enabled - logging info message"
    z::log::info "Info message logged"
  fi

  wait_for_user
}

# Demo 7: Rate Limiting
demo_rate_limiting() {
  print "\n$(z::log::colorize 'bold' '━━━ Demo 7: Rate Limiting ━━━')"
  print "Preventing log floods with rate limiting..."

  print "\nLogging 20 messages (limit: 5 per 10 seconds):"
  local logged=0
  local limited=0

  for i in {1..20}; do
    if z::log::rate_limit "demo_rate" 5 10 "info" "Rate limited message $i"; then
      (( logged++ ))
      print -n "."
    else
      (( limited++ ))
      print -n "x"
    fi
  done

  print "\n\nResults:"
  print "  Logged:  $logged messages"
  print "  Limited: $limited messages"

  z::log::clear_rate_limits

  wait_for_user
}

# Demo 8: Log Once
demo_log_once() {
  print "\n$(z::log::colorize 'bold' '━━━ Demo 8: Log Once ━━━')"
  print "Logging a message only once, even in loops..."

  print "\nSimulating a loop with repeated condition:"
  for i in {1..10}; do
    z::log::once "loop_warning" "warn" "This warning appears only once" "iteration" "$i"
    print -n "."
    sleep 0.1
  done

  print "\n\nThe warning was logged only on the first iteration!"

  z::log::clear_once

  wait_for_user
}

# Demo 9: Buffering
demo_buffering() {
  print "\n$(z::log::colorize 'bold' '━━━ Demo 9: Buffering for Performance ━━━')"
  print "Using buffering for high-performance logging..."

  print "\n1. Without buffering:"
  local start=$EPOCHREALTIME
  for i in {1..50}; do
    z::log::info "Unbuffered message $i"
  done
  local end=$EPOCHREALTIME
  local duration_nobuf=$(( (end - start) * 1000 ))

  print "\n2. With buffering:"
  z::log::enable_buffering 25
  start=$EPOCHREALTIME
  for i in {1..50}; do
    z::log::info "Buffered message $i"
  done
  z::log::flush
  end=$EPOCHREALTIME
  local duration_buf=$(( (end - start) * 1000 ))
  z::log::disable_buffering

  print "\nPerformance comparison:"
  print "  Without buffering: ${duration_nobuf}ms"
  print "  With buffering:    ${duration_buf}ms"
  print "  Improvement:       $(( (duration_nobuf - duration_buf) * 100 / duration_nobuf ))%"

  wait_for_user
}

# Demo 10: File Rotation
demo_file_rotation() {
  print "\n$(z::log::colorize 'bold' '━━━ Demo 10: File Rotation ━━━')"
  print "Demonstrating automatic file rotation..."

  local rotation_log="/tmp/zlog_rotation_demo.log"
  z::log::set_file "$rotation_log"
  z::log::set_rotation 1 "5KB" 3

  print "\nWriting messages to trigger rotation (max size: 5KB)..."
  for i in {1..200}; do
    z::log::info "Rotation test message $i with some padding to increase file size"
    print -n "."
    if (( i % 50 == 0 )); then
      print " ($i messages)"
    fi
  done

  print "\n\nChecking rotated files:"
  ls -lh /tmp/zlog_rotation_demo.log* 2>/dev/null | while read line; do
    print "  $line"
  done

  rm -f /tmp/zlog_rotation_demo.log*
  z::log::set_file "$DEMO_LOG"

  wait_for_user
}

# Demo 11: Configuration Display
demo_configuration() {
  print "\n$(z::log::colorize 'bold' '━━━ Demo 11: Configuration Display ━━━')"
  print "Viewing current logging configuration..."

  print
  z::log::show_config

  wait_for_user
}

# Demo 12: Real-World Scenario
demo_real_world() {
  print "\n$(z::log::colorize 'bold' '━━━ Demo 12: Real-World Scenario ━━━')"
  print "Simulating a web application request handler..."

  print "\nIncoming HTTP request:"
  z::log::info "Request received" \
    "method" "POST" \
    "path" "/api/v1/users" \
    "client_ip" "203.0.113.42" \
    "user_agent" "Mozilla/5.0"

  print "\nValidating request:"
  z::log::debug "Validating request body" "content_type" "application/json"

  print "\nDatabase operation:"
  z::log::debug "Executing database query" "table" "users" "operation" "INSERT"

  print "\nSimulating slow query warning:"
  z::log::warn "Slow query detected" "duration_ms" "1250" "threshold_ms" "1000"

  print "\nResponse sent:"
  z::log::info "Request completed" \
    "status" "201" \
    "response_time_ms" "1350" \
    "bytes_sent" "256"

  wait_for_user
}

# Main demo runner
run_demo() {
  print_header

  print "This demonstration will showcase all major features of ZLOG."
  print "Log output will be written to: $(z::log::colorize 'cyan' "$DEMO_LOG")"

  wait_for_user

  # Run all demos
  demo_basic_logging
  demo_context_logging
  demo_printf_formatting
  demo_json_format
  demo_level_filtering
  demo_conditional_logging
  demo_rate_limiting
  demo_log_once
  demo_buffering
  demo_file_rotation
  demo_configuration
  demo_real_world

  # Show log file
  print "\n$(z::log::colorize 'bold' '━━━ Log File Contents ━━━')"
  print "\nShowing first 30 lines of $DEMO_LOG:"
  print "$(z::log::colorize 'dim' '────────────────────────────────────────────────────────────────')"
  head -30 "$DEMO_LOG" 2>/dev/null || print "Log file not found"
  print "$(z::log::colorize 'dim' '────────────────────────────────────────────────────────────────')"

  print "\n$(z::log::colorize 'green' '✓ Demo completed successfully!')"
  print "\nLog file saved to: $DEMO_LOG"
  print "You can view the full log with: $(z::log::colorize 'cyan' "cat $DEMO_LOG")"

  # Cleanup
  z::log::cleanup
}

# Run demo if executed directly
if [[ "${ZSH_EVAL_CONTEXT}" == "toplevel" ]]; then
  run_demo
fi
