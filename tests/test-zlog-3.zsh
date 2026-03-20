#!/usr/bin/env zsh
source zlog.zsh
print "=== ZLOG Framework - Final Integration Test ==="

# Test 1: Configuration Display
print "\n--- Configuration Display ---"
z::log::show_config

# Test 2: Quick Start
print "\n--- Quick Start ---"
z::log::quick_start "/tmp/zlog_final_test.log" "debug" "text"

# Test 3: All logging functions
print "\n--- All Logging Functions ---"
z::log::error "Error message"
z::log::warn "Warning message"
z::log::info "Info message"
z::log::debug "Debug message"

# Test 4: With context
z::log::info "Context test" "key1" "value1" "key2" "value2"

# Test 5: Printf-style
z::log::infof "Printf test: %d items processed" 42

# Test 6: Show updated config
print "\n--- Updated Configuration ---"
z::log::show_config

# Test 7: Cleanup
print "\n--- Cleanup ---"
z::log::cleanup

print "\n✓ All tests completed successfully!"
