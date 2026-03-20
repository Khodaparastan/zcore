#!/usr/bin/env zsh

###############################################################################
# ZLOG FRAMEWORK DEMONSTRATION
###############################################################################
# This script demonstrates all features of the zlog logging framework
# Run with: zsh demo_zlog.zsh
###############################################################################

# Source the logging framework
source "${0:a:h}/zlog.zsh"

# Color output for section headers
print_section() {
  print "\n${(l:80::=:)}"
  print "=== $1"
  print "${(l:80::=:)}\n"
}

print_subsection() {
  print "\n--- $1 ---\n"
}

###############################################################################
# 1. BASIC SETUP AND CONFIGURATION
###############################################################################

print_section "1. BASIC SETUP AND CONFIGURATION"

print_subsection "1.1 Quick Start"
print "Setting up logging with quick_start:"
print '  z::log::quick_start "/tmp/demo.log" info text'
print ""

# Note: Using "-" for console-only in demo
z::log::quick_start "-" info text

print_subsection "1.2 Show Current Configuration"
z::log::show_config

print_subsection "1.3 Manual Configuration"
print "Setting individual options:"
print '  z::log::set_level debug'
print '  z::log::set_format text'
print '  z::log::set_file "/tmp/demo.log"'
print ""

z::log::set_level debug
z::log::set_format text
z::log::set_file "/tmp/demo.log"

print "Current level: $(z::log::get_level)"

###############################################################################
# 2. BASIC LOGGING
###############################################################################

print_section "2. BASIC LOGGING - ALL LEVELS"

print_subsection "2.1 Simple Messages"
z::log::error "This is an ERROR message"
z::log::warn "This is a WARN message"
z::log::info "This is an INFO message"
z::log::debug "This is a DEBUG message"

print_subsection "2.2 Messages with Context Fields"
z::log::info "User logged in" "user" "alice" "ip" "192.168.1.100"
z::log::warn "High memory usage" "usage" "85%" "threshold" "80%"
z::log::error "Database connection failed" "host" "localhost" "port" "5432" "error" "timeout"

print_subsection "2.3 Testing Level Filtering"
print "Setting level to WARN (should hide INFO and DEBUG):"
z::log::set_level warn
z::log::error "ERROR: visible"
z::log::warn "WARN: visible"
z::log::info "INFO: hidden"
z::log::debug "DEBUG: hidden"

# Reset to debug
z::log::set_level debug

###############################################################################
# 3. PRINTF-STYLE FORMATTING
###############################################################################

print_section "3. PRINTF-STYLE FORMATTING"

print_subsection "3.1 Basic Printf Formatting"
z::log::infof "Processing %d items out of %d (%.1f%% complete)" 75 100 75.0
z::log::warnf "Disk usage: %d MB (%.2f%%)" 8500 85.5
z::log::errorf "Failed to connect to %s:%d after %d attempts" "api.example.com" 443 3

print_subsection "3.2 Complex Formatting"
local user="bob"
local action="delete"
local count=42
z::log::infof "User '%s' performed '%s' on %d records" "$user" "$action" "$count"

print_subsection "3.3 Printf Error Handling"
print "Testing invalid format string:"
z::log::infof "Invalid format: %d %s" "not_a_number"

###############################################################################
# 4. CONDITIONAL LOGGING
###############################################################################

print_section "4. CONDITIONAL LOGGING"

print_subsection "4.1 Level Checkers"
if z::log::if_error; then
  print "Error logging is enabled"
fi

if z::log::if_debug; then
  print "Debug logging is enabled"
  z::log::debug "This debug message only runs if debug is enabled"
fi

print_subsection "4.2 Expensive Operations Guard"
print "Simulating expensive debug data collection:"

if z::log::if_debug; then
  # This expensive operation only runs if debug logging is enabled
  local debug_data="$(print 'Expensive data collection'; sleep 0.1; print 'Complete')"
  z::log::debug "Debug data collected" "data" "$debug_data"
fi

print_subsection "4.3 Level Check Before Logging"
z::log::set_level warn
print "Level set to WARN - checking if info is active:"
if z::log::if_info; then
  print "  Info is active (this shouldn't print)"
else
  print "  Info is NOT active (correct)"
fi

z::log::set_level debug

###############################################################################
# 5. CONTEXT LOGGING
###############################################################################

print_section "5. CONTEXT LOGGING"

print_subsection "5.1 Creating Context Loggers"
print "Creating context for HTTP request:"
z::log::with_context "request_id" "req-12345" "method" "POST" "path" "/api/users"
local ctx1="$REPLY"
print "Context ID: $ctx1"

print_subsection "5.2 Using Context Loggers"
${ctx1}::info "Request received"
${ctx1}::debug "Validating input"
${ctx1}::info "Processing request"
${ctx1}::info "Request completed" "status" "200" "duration" "45ms"

print_subsection "5.3 Multiple Contexts"
print "Creating second context for database operation:"
z::log::with_context "db" "postgres" "table" "users" "operation" "SELECT"
local ctx2="$REPLY"
print "Context ID: $ctx2"

${ctx2}::debug "Executing query"
${ctx2}::info "Query completed" "rows" "150" "time" "12ms"

print_subsection "5.4 Context with Printf Formatting"
${ctx1}::infof "Processed %d records in %.2f seconds" 100 1.23
${ctx2}::debugf "Cache hit rate: %.1f%% (%d/%d)" 85.5 855 1000

print_subsection "5.5 Listing Active Contexts"
z::log::list_contexts

print_subsection "5.6 Removing Contexts"
print "Removing first context:"
z::log::remove_context "$ctx1"
print "Remaining contexts:"
z::log::list_contexts

print "Removing all contexts:"
z::log::remove_all_contexts
z::log::list_contexts

###############################################################################
# 6. BENCHMARKING
###############################################################################

print_section "6. BENCHMARKING"

print_subsection "6.1 Simple Command Benchmark"
z::log::benchmark "sleep_test" sleep 0.1

print_subsection "6.2 Function Benchmark"
expensive_function() {
  local sum=0
  for i in {1..1000}; do
    (( sum += i ))
  done
  return 0
}

z::log::benchmark "calculation" expensive_function

print_subsection "6.3 Manual Timer (Start/End)"
print "Starting manual timer:"
z::log::benchmark_start "data_processing"
local timer="$REPLY"
print "Timer ID: $timer"

# Simulate work
sleep 0.15
print "Doing some work..."

print "Ending timer:"
z::log::benchmark_end "$timer"

print_subsection "6.4 Multiple Concurrent Timers"
z::log::benchmark_start "task1"
local t1="$REPLY"

z::log::benchmark_start "task2"
local t2="$REPLY"

z::log::benchmark_start "task3"
local t3="$REPLY"

print "Active timers:"
z::log::list_timers

sleep 0.05
z::log::benchmark_end "$t1"

sleep 0.05
z::log::benchmark_end "$t2"

sleep 0.05
z::log::benchmark_end "$t3"

print_subsection "6.5 Benchmark Block"
z::log::benchmark_block "loop_test" <<'END'
  local result=0
  for i in {1..500}; do
    (( result += i * 2 ))
  done
END

print_subsection "6.6 Nested Benchmarks"
z::log::benchmark_start "outer_operation"
local outer="$REPLY"

sleep 0.05
z::log::benchmark "inner_operation_1" sleep 0.03
sleep 0.02
z::log::benchmark "inner_operation_2" sleep 0.04

z::log::benchmark_end "$outer"

###############################################################################
# 7. OUTPUT FORMATS
###############################################################################

print_section "7. OUTPUT FORMATS"

print_subsection "7.1 Text Format (Current)"
z::log::set_format text
z::log::info "This is text format" "key1" "value1" "key2" "value2"

print_subsection "7.2 JSON Format"
z::log::set_format json
z::log::info "This is JSON format" "key1" "value1" "key2" "value2"
z::log::error "JSON error message" "error_code" "500" "details" "Internal server error"

print_subsection "7.3 JSON with Special Characters"
z::log::info "Testing JSON escaping" "message" 'Quote: "test"' "newline" $'Line1\nLine2' "tab" $'Col1\tCol2'

# Reset to text
z::log::set_format text

###############################################################################
# 8. BUFFERING
###############################################################################

print_section "8. BUFFERING"

print_subsection "8.1 Enable Buffering"
print "Enabling buffer with size 5:"
z::log::enable_buffering 5

print_subsection "8.2 Buffered Writes"
print "Writing 3 messages (buffered):"
z::log::info "Buffered message 1"
z::log::info "Buffered message 2"
z::log::info "Buffered message 3"

print "\nCurrent buffer size: ${#_zcore_log_buffer}"

print_subsection "8.3 Auto-flush on Buffer Full"
print "Writing 2 more messages (will trigger auto-flush at 5):"
z::log::info "Buffered message 4"
z::log::info "Buffered message 5 - triggers flush"

print "\nBuffer size after auto-flush: ${#_zcore_log_buffer}"

print_subsection "8.4 Manual Flush"
z::log::info "Another message"
print "Buffer size before flush: ${#_zcore_log_buffer}"
z::log::flush
print "Buffer size after flush: ${#_zcore_log_buffer}"

print_subsection "8.5 Error Auto-flush"
print "Errors always flush immediately:"
z::log::info "Buffered info"
z::log::error "This error triggers immediate flush"
print "Buffer size: ${#_zcore_log_buffer}"

print_subsection "8.6 Disable Buffering"
z::log::disable_buffering
print "Buffering disabled"

###############################################################################
# 9. FILE ROTATION
###############################################################################

print_section "9. FILE ROTATION"

print_subsection "9.1 Configure Rotation"
print "Setting rotation: enabled, 1KB max size, keep 3 files:"
z::log::set_rotation 1 1024 3

print_subsection "9.2 Generate Large Log"
print "Writing messages to trigger rotation..."
for i in {1..50}; do
  z::log::info "Log message $i - $(print ${(l:50::X:)})"
done

print_subsection "9.3 Check Rotated Files"
print "Log files created:"
ls -lh /tmp/demo.log* 2>/dev/null || print "No log files found"

###############################################################################
# 10. MESSAGE SIZE LIMITS
###############################################################################

print_section "10. MESSAGE SIZE LIMITS"

print_subsection "10.1 Set Message Size Limit"
print "Setting max message size to 50 bytes:"
z::log::set_max_message_size 50

print_subsection "10.2 Test Truncation"
z::log::info "This is a very long message that should be truncated because it exceeds the maximum message size limit that we configured"

print_subsection "10.3 Disable Limit"
z::log::set_max_message_size 0
z::log::info "This is a very long message that will NOT be truncated because we disabled the size limit"

###############################################################################
# 11. ADVANCED FEATURES
###############################################################################

print_section "11. ADVANCED FEATURES"

print_subsection "11.1 Timestamp Cache Control"
print "Disabling timestamp cache (for high-precision logging):"
z::log::disable_timestamp_cache
z::log::info "Message with fresh timestamp"
z::log::info "Another message with fresh timestamp"

print "Re-enabling timestamp cache:"
z::log::enable_timestamp_cache

print_subsection "11.2 Debug Mode"
print "Enabling internal debug mode:"
z::log::enable_debug_mode
z::log::info "This will show internal debug messages"
z::log::disable_debug_mode

print_subsection "11.3 File Level vs Console Level"
print "Setting different levels for console and file:"
z::log::set_level warn
z::log::set_file_level debug

print "Console level: WARN, File level: DEBUG"
z::log::debug "This goes to file only (not console)"
z::log::warn "This goes to both console and file"

# Reset
z::log::set_level debug
z::log::set_file_level -1

###############################################################################
# 12. ERROR HANDLING AND EDGE CASES
###############################################################################

print_section "12. ERROR HANDLING AND EDGE CASES"

print_subsection "12.1 Invalid Inputs"
print "Testing invalid level:"
z::log::set_level "invalid_level" 2>&1 | head -1

print "\nTesting invalid format:"
z::log::set_format "invalid_format" 2>&1 | head -1

print "\nTesting invalid buffer size:"
z::log::enable_buffering "not_a_number" 2>&1 | head -1

print_subsection "12.2 Empty Context Keys"
print "Testing context with empty key:"
z::log::with_context "" "value" "key2" "value2" 2>&1 | head -1

print_subsection "12.3 Odd Number of Context Arguments"
print "Testing odd number of context arguments:"
z::log::info "Test message" "key1" "value1" "key2"

print_subsection "12.4 Invalid Timer Operations"
print "Testing end of non-existent timer:"
z::log::benchmark_end "invalid_timer_id" 2>&1 | head -1

print_subsection "12.5 Context Limit"
print "Testing context limit (creating many contexts):"
for i in {1..5}; do
  z::log::with_context "test_ctx_$i" "value_$i" >/dev/null
done
print "Created 5 contexts"
z::log::list_contexts | wc -l

z::log::remove_all_contexts

###############################################################################
# 13. REAL-WORLD USAGE EXAMPLES
###############################################################################

print_section "13. REAL-WORLD USAGE EXAMPLES"

print_subsection "13.1 Web Server Request Handler"

# Helper function for sleep using zsh builtins
__demo_sleep() {
  # Use read with timeout (works in all zsh versions)
  read -t "$1" -u 1 < /dev/null 2>/dev/null || true
}

handle_request() {
  local method="$1"
  local path="$2"
  local user="$3"
  
  # Create request context - use EPOCHSECONDS instead of date
  local request_id="req-${EPOCHSECONDS}-${RANDOM}"
  z::log::with_context "request_id" "$request_id" "method" "$method" "path" "$path" "user" "$user"
  local ctx="$REPLY"
  
  # Start benchmark
  z::log::benchmark_start "request_processing"
  local timer="$REPLY"
  
  ${ctx}::info "Request started"
  
  # Simulate processing
  ${ctx}::debug "Authenticating user"
  __demo_sleep 0.02
  
  ${ctx}::debug "Fetching data"
  __demo_sleep 0.03
  
  if [[ "$path" == "/error" ]]; then
    ${ctx}::error "Route not found" "status" "404"
    z::log::benchmark_end "$timer"
    z::log::remove_context "$ctx"
    return 1
  fi
  
  ${ctx}::debug "Rendering response"
  __demo_sleep 0.02
  
  ${ctx}::info "Request completed" "status" "200"
  
  z::log::benchmark_end "$timer"
  z::log::remove_context "$ctx"
  
  return 0
}

print "Handling successful request:"
handle_request "GET" "/api/users" "alice"

print "\nHandling failed request:"
handle_request "GET" "/error" "bob"

print_subsection "13.2 Database Migration Script"

run_migration() {
  local migration_name="$1"
  
  z::log::info "Starting migration: $migration_name"
  
  z::log::benchmark_start "migration_$migration_name"
  local timer="$REPLY"
  
  z::log::debug "Backing up database"
  __demo_sleep 0.05
  
  z::log::info "Running migration scripts"
  __demo_sleep 0.1
  
  z::log::debug "Verifying migration"
  __demo_sleep 0.03
  
  z::log::info "Migration completed successfully" "migration" "$migration_name"
  
  z::log::benchmark_end "$timer"
}

run_migration "add_user_table"
run_migration "add_indexes"

print_subsection "13.3 Batch Processing with Progress"

process_batch() {
  local total=10
  local batch_size=3
  
  z::log::info "Starting batch processing" "total_items" "$total" "batch_size" "$batch_size"
  
  z::log::benchmark_start "batch_processing"
  local timer="$REPLY"
  
  for (( i=1; i<=total; i+=batch_size )); do
    local end=$(( i + batch_size - 1 ))
    (( end > total )) && end=$total
    
    z::log::infof "Processing batch %d-%d of %d" $i $end $total
    
    # Simulate processing
    __demo_sleep 0.05
    
    local processed=$(( end < total ? end : total ))
    local percent=$(( processed * 100 / total ))
    z::log::debugf "Progress: %d%% (%d/%d)" $percent $processed $total
  done
  
  z::log::info "Batch processing completed"
  z::log::benchmark_end "$timer"
}

process_batch

run_migration() {
  local migration_name="$1"
  
  z::log::info "Starting migration: $migration_name"
  
  z::log::benchmark_start "migration_$migration_name"
  local timer="$REPLY"
  
  z::log::debug "Backing up database"
  sleep 0.05
  
  z::log::info "Running migration scripts"
  sleep 0.1
  
  z::log::debug "Verifying migration"
  sleep 0.03
  
  z::log::info "Migration completed successfully" "migration" "$migration_name"
  
  z::log::benchmark_end "$timer"
}

run_migration "add_user_table"
run_migration "add_indexes"

print_subsection "13.3 Batch Processing with Progress"

process_batch() {
  local total=10
  local batch_size=3
  
  z::log::info "Starting batch processing" "total_items" "$total" "batch_size" "$batch_size"
  
  z::log::benchmark_start "batch_processing"
  local timer="$REPLY"
  
  for (( i=1; i<=total; i+=batch_size )); do
    local end=$(( i + batch_size - 1 ))
    (( end > total )) && end=$total
    
    z::log::infof "Processing batch %d-%d of %d" $i $end $total
    
    # Simulate processing
    sleep 0.05
    
    local processed=$(( end < total ? end : total ))
    local percent=$(( processed * 100 / total ))
    z::log::debugf "Progress: %d%% (%d/%d)" $percent $processed $total
  done
  
  z::log::info "Batch processing completed"
  z::log::benchmark_end "$timer"
}

process_batch

###############################################################################
# 14. CLEANUP AND SUMMARY
###############################################################################

print_section "14. CLEANUP AND SUMMARY"

print_subsection "14.1 Current State"
z::log::show_config

print_subsection "14.2 Active Resources"
print "Active contexts:"
z::log::list_contexts

print "\nActive timers:"
z::log::list_timers

print_subsection "14.3 Cleanup"
print "Clearing all timers:"
z::log::clear_timers

print "\nRemoving all contexts:"
z::log::remove_all_contexts

print "\nFlushing buffers:"
z::log::flush

print_subsection "14.4 Reset Configuration"
print "Resetting to defaults:"
z::log::reset
z::log::show_config

print_subsection "14.5 Log File Summary"
if [[ -f /tmp/demo.log ]]; then
  print "Log file size: $(wc -c < /tmp/demo.log) bytes"
  print "Log file lines: $(wc -l < /tmp/demo.log)"
  print "\nFirst 5 lines:"
  head -5 /tmp/demo.log
  print "\nLast 5 lines:"
  tail -5 /tmp/demo.log
else
  print "No log file created"
fi

###############################################################################
# FINALE
###############################################################################

print_section "DEMONSTRATION COMPLETE"

print "This demonstration covered:"
print "  ✓ Basic logging (error, warn, info, debug)"
print "  ✓ Printf-style formatting"
print "  ✓ Conditional logging"
print "  ✓ Context logging"
print "  ✓ Benchmarking (command, timer, block)"
print "  ✓ Output formats (text, JSON)"
print "  ✓ Buffering"
print "  ✓ File rotation"
print "  ✓ Message size limits"
print "  ✓ Advanced features"
print "  ✓ Error handling"
print "  ✓ Real-world examples"
print ""
print "Check /tmp/demo.log for the complete log output"
print "Check /tmp/demo.log.* for rotated log files"
print ""

###############################################################################
