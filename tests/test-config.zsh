#!/usr/bin/env zsh
################################################################################
# CONFIGURATION MANAGEMENT TESTS
################################################################################

print "Testing: Configuration Management"

###
# Test: Get configuration
###
test_config_get() {
  print "\nTest Group: Get Configuration"

  local result

  result=$(z::config::get cache_max_size)
  assert_equals "100" "$result" "Get cache_max_size"

  result=$(z::config::get timeout_default)
  assert_equals "30" "$result" "Get timeout_default"

  assert_failure "Get invalid key" z::config::get nonexistent_key
}

###
# Test: Set configuration
###
test_config_set() {
  print "\nTest Group: Set Configuration"

  # Save original value
  local original_cache_size=${_zcore_config[cache_max_size]}

  assert_success "Set cache_max_size to 200" z::config::set cache_max_size 200
  assert_equals "200" "${_zcore_config[cache_max_size]}" "Value updated"

  assert_failure "Set invalid integer" z::config::set cache_max_size "not_a_number"
  assert_failure "Set out of range" z::config::set cache_max_size 99999

  # Restore
  _zcore_config[cache_max_size]=$original_cache_size
}

###
# Test: Type-safe setters
###
test_config_type_safe() {
  print "\nTest Group: Type-Safe Setters"

  local original_perf=${_zcore_config[performance_mode]}
  local original_cache=${_zcore_config[cache_max_size]}

  assert_success "Set boolean true" z::config::set_bool performance_mode true
  assert_equals "true" "${_zcore_config[performance_mode]}" "Boolean set correctly"

  assert_failure "Set boolean with invalid value" z::config::set_bool performance_mode "yes"

  assert_success "Set integer" z::config::set_int cache_max_size 150
  assert_equals "150" "${_zcore_config[cache_max_size]}" "Integer set correctly"

  assert_failure "Set integer with string" z::config::set_int cache_max_size "abc"

  # Restore
  _zcore_config[performance_mode]=$original_perf
  _zcore_config[cache_max_size]=$original_cache
}

###
# Test: Configuration validation
###
test_config_validate() {
  print "\nTest Group: Configuration Validation"

  assert_success "Validate default config" z::config::validate

  # Test invalid configuration
  local original_cache=${_zcore_config[cache_max_size]}
  _zcore_config[cache_max_size]=5  # Below minimum

  assert_failure "Validate invalid config" z::config::validate

  # Restore
  _zcore_config[cache_max_size]=$original_cache
}

###
# Test: Configuration export
###
test_config_export() {
  print "\nTest Group: Configuration Export"

  local temp_file="/tmp/zcore-test-config-$$.txt"

  assert_success "Export configuration" z::config::export "$temp_file"
  assert_true "-f $temp_file" "Export file created"

  # Check file contains expected content
  local content=$(<"$temp_file")
  assert_contains "$content" "cache_max_size" "Export contains cache_max_size"
  assert_contains "$content" "timeout_default" "Export contains timeout_default"

  # Cleanup
  rm -f "$temp_file"
}

###
# Test: Configuration locking
###
test_config_locking() {
  print "\nTest Group: Configuration Locking"

  # Unlock for testing
  (( _zcore_config_locked = 0 ))

  local original_cache=${_zcore_config[cache_max_size]}

  assert_success "Set before lock" z::config::set cache_max_size 150

  z::config::lock_critical

  assert_failure "Set after lock" z::config::set cache_max_size 200
  assert_equals "150" "${_zcore_config[cache_max_size]}" "Value unchanged after lock"

  # Restore
  _zcore_config[cache_max_size]=$original_cache
}

# Run all tests
test_config_get
test_config_set
test_config_type_safe
test_config_validate
test_config_export
test_config_locking
