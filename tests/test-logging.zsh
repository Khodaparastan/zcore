#!/usr/bin/env zsh
################################################################################
# LOGGING SUBSYSTEM TESTS
################################################################################

print "Testing: Logging Subsystem"

###
# Test: Level name conversion
###
test_level_names() {
  print "\nTest Group: Level Names"

  local result

  result=$(z::log::_level_name 0)
  assert_equals "error" "$result" "Level 0 = 'error'"

  result=$(z::log::_level_name 1)
  assert_equals "warn" "$result" "Level 1 = 'warn'"

  result=$(z::log::_level_name 2)
  assert_equals "info" "$result" "Level 2 = 'info'"

  result=$(z::log::_level_name 3)
  assert_equals "debug" "$result" "Level 3 = 'debug'"

  result=$(z::log::_level_name 999)
  assert_equals "unknown" "$result" "Invalid level = 'unknown'"
}

###
# Test: Level parsing
###
test_level_parsing() {
  print "\nTest Group: Level Parsing"

  local result

  result=$(z::log::_parse_level "error")
  assert_equals "0" "$result" "Parse 'error' → 0"

  result=$(z::log::_parse_level "warn")
  assert_equals "1" "$result" "Parse 'warn' → 1"

  result=$(z::log::_parse_level "info")
  assert_equals "2" "$result" "Parse 'info' → 2"

  result=$(z::log::_parse_level "debug")
  assert_equals "3" "$result" "Parse 'debug' → 3"

  result=$(z::log::_parse_level "2")
  assert_equals "2" "$result" "Parse '2' → 2"

  assert_failure "Parse invalid level" z::log::_parse_level "invalid"
}

###
# Test: Set level
###
test_set_level() {
  print "\nTest Group: Set Level"

  # Save original level
  local original_level=$_zcore_verbose_level

  assert_success "Set level to debug" z::log::set_level debug
  assert_equals "3" "$_zcore_verbose_level" "Level should be 3"

  assert_success "Set level to error" z::log::set_level 0
  assert_equals "0" "$_zcore_verbose_level" "Level should be 0"

  assert_success "Set level to info" z::log::set_level info
  assert_equals "2" "$_zcore_verbose_level" "Level should be 2"

  assert_failure "Set invalid level" z::log::set_level invalid_level

  # Restore original level
  (( _zcore_verbose_level = original_level ))
}

###
# Test: Get level
###
test_get_level() {
  print "\nTest Group: Get Level"

  local result

  # Save and set known level
  local original_level=$_zcore_verbose_level
  (( _zcore_verbose_level = 2 ))

  result=$(z::log::get_level --numeric)
  assert_equals "2" "$result" "Get numeric level"

  result=$(z::log::get_level)
  assert_contains "$result" "Current verbosity level: 2" "Get level with name"

  # Restore
  (( _zcore_verbose_level = original_level ))
}

###
# Test: Logging functions
###
test_logging_functions() {
  print "\nTest Group: Logging Functions"

  # Save original level
  local original_level=$_zcore_verbose_level
  z::log::set_level debug

  assert_success "Error logging" z::log::error "Test error message"
  assert_success "Warn logging" z::log::warn "Test warning message"
  assert_success "Info logging" z::log::info "Test info message"
  assert_success "Debug logging" z::log::debug "Test debug message"

  # Test multi-argument logging
  assert_success "Multi-arg logging" z::log::info "Test" "multiple" "arguments"

  # Restore
  (( _zcore_verbose_level = original_level ))
}

###
# Test: Verbosity filtering
###
test_verbosity_filtering() {
  print "\nTest Group: Verbosity Filtering"

  local original_level=$_zcore_verbose_level

  # Set to error level (0) - only errors should log
  z::log::set_level error

  # These should all succeed (not crash), but only error actually logs
  assert_success "Error logs at error level" z::log::error "Error message"
  assert_success "Warn silent at error level" z::log::warn "Warn message"
  assert_success "Info silent at error level" z::log::info "Info message"
  assert_success "Debug silent at error level" z::log::debug "Debug message"

  # Restore
  (( _zcore_verbose_level = original_level ))
}

# Run all tests
test_level_names
test_level_parsing
test_set_level
test_get_level
test_logging_functions
test_verbosity_filtering
