#!/usr/bin/env zsh
source zlog.zsh
print "=== Conditional Logging & Utility Functions Test ==="

# Setup
z::log::quick_start "/tmp/test_utilities.log" "info" "text"

# Test conditional logging
print "\n--- Conditional Logging ---"
if z::log::if_error; then
  print "✓ Error level is active"
fi

if z::log::if_debug; then
  print "✓ Debug level is active"
else
  print "✗ Debug level is NOT active (expected at info level)"
fi

# Test with_level
print "\n--- Temporary Level Change ---"
z::log::with_level debug z::log::debug "This debug message SHOULD appear"
z::log::debug "This debug message should NOT appear (back to info level)"

# Test silent
print "\n--- Silent Logging ---"
z::log::info "Before silent"
z::log::silent z::log::info "This should NOT appear"
z::log::info "After silent"

# Test always
print "\n--- Always Log ---"
z::log::set_level "error"  # Very restrictive
z::log::always "This MUST appear despite error-only level" "critical" "true"
z::log::set_level "info"  # Reset

# Test log once
print "\n--- Log Once ---"
for i in {1..5}; do
  z::log::once "test_key" "info" "This should only appear once" "iteration" "$i"
done
print "Clearing once marker..."
z::log::clear_once "test_key"
z::log::once "test_key" "info" "After clear, this should appear again"

# Test rate limiting
print "\n--- Rate Limiting ---"
print "Logging 10 times (limit: 3 per 5 seconds)..."
local logged=0
local limited=0
for i in {1..10}; do
  if z::log::rate_limit "test_rate" 3 5 "info" "Rate limited message $i"; then
    (( logged++ ))
  else
    (( limited++ ))
  fi
  sleep 0.1
done
print "Logged: $logged, Limited: $limited"

# Wait for window to expire
print "\nWaiting 6 seconds for rate limit window to expire..."
sleep 6
print "After window expiry:"
z::log::rate_limit "test_rate" 3 5 "info" "This should appear (new window)"

# Clear rate limits
z::log::clear_rate_limits

# Show log contents
print "\n--- Log File Contents ---"
if [[ -f "/tmp/test_utilities.log" ]]; then
  cat /tmp/test_utilities.log
else
  print "Log file not found!"
fi

# Cleanup
rm -f /tmp/test_utilities.log*
