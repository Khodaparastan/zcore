#!/usr/bin/env zsh
source zlog.zsh
# Test the core logging engine
print "=== Core Logging Engine Test ==="

# Setup
z::log::quick_start "/tmp/test_core_engine.log" "debug" "text"

# Test basic logging
print "\n--- Basic Logging ---"
z::log::error "This is an error"
z::log::warn "This is a warning"
z::log::info "This is info"
z::log::debug "This is debug"

# Test with context
print "\n--- Logging with Context ---"
z::log::info "User logged in" "user" "john" "ip" "192.168.1.1" "session" "abc123"
z::log::error "Database error" "code" "1045" "message" "Access denied"

# Test printf-style
print "\n--- Printf-Style Logging ---"
z::log::infof "Processed %d out of %d items (%.1f%%)" 75 100 75.0
z::log::warnf "Memory usage: %d MB (%.1f%% of total)" 1500 75.5
z::log::errorf "Failed to connect to %s:%d" "localhost" 5432

# Test generic log function
print "\n--- Generic Log Function ---"
z::log::log "info" "Using generic log function"
z::log::log 2 "Using numeric level"
z::log::log "debug" "Debug via generic function" "key" "value"

# Test level filtering
print "\n--- Level Filtering ---"
z::log::set_level "warn"
z::log::debug "This should NOT appear (debug disabled)"
z::log::info "This should NOT appear (info disabled)"
z::log::warn "This SHOULD appear (warn enabled)"
z::log::error "This SHOULD appear (error enabled)"

z::log::set_level "debug"  # Reset

# Test empty message handling
print "\n--- Edge Cases ---"
z::log::info ""  # Empty message
z::log::info "Message with special chars: \$HOME, \"quotes\", 'apostrophes'"

# Test JSON format
print "\n--- JSON Format ---"
z::log::set_format "json"
z::log::info "JSON formatted message" "key1" "value1" "key2" "value2"

z::log::set_format "text"  # Reset

# Show log file contents
print "\n--- Log File Contents ---"
if [[ -f "/tmp/test_core_engine.log" ]]; then
  print "First 20 lines:"
  head -20 /tmp/test_core_engine.log
else
  print "Log file not found!"
fi

# Cleanup
rm -f /tmp/test_core_engine.log*
