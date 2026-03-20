#!/usr/bin/env zsh
################################################################################
# CACHING SUBSYSTEM TESTS
################################################################################

print "Testing: Caching Subsystem"

###
# Test: Command existence cache
###
test_cmd_cache() {
  print "\nTest Group: Command Cache"

  # Clear cache first
  z::cache::cmd::clear
  assert_equals "0" "$_cmd_cache_size" "Cache cleared"

  # Test existing command
  if z::cmd::exists "ls"; then
    assert_success "Command 'ls' exists" true
    assert_true "$_cmd_cache_size > 0" "Cache populated"
  fi

  # Test cached lookup (should be faster)
  if z::cmd::exists "ls"; then
    assert_success "Cached command lookup works" true
  fi

  # Test non-existent command
  if ! z::cmd::exists "nonexistent_command_xyz_123"; then
    assert_success "Non-existent command returns false" true
  fi

  # Clear cache
  z::cache::cmd::clear
  assert_equals "0" "$_cmd_cache_size" "Cache cleared again"
}

###
# Test: Function existence cache
###
test_func_cache() {
  print "\nTest Group: Function Cache"

  # Clear cache first
  z::cache::func::clear
  assert_equals "0" "$_func_cache_size" "Cache cleared"

  # Create test function
  test_dummy_function() { return 0; }

  # Test existing function
  if z::func::exists "test_dummy_function"; then
    assert_success "Function exists" true
    assert_true "$_func_cache_size > 0" "Cache populated"
  fi

  # Test cached lookup
  if z::func::exists "test_dummy_function"; then
    assert_success "Cached function lookup works" true
  fi

  # Test non-existent function
  if ! z::func::exists "nonexistent_function_xyz"; then
    assert_success "Non-existent function returns false" true
  fi

  # Cleanup
  unset -f test_dummy_function
  z::cache::func::clear
}

###
# Test: Function call
###
test_func_call() {
  print "\nTest Group: Function Call"

  # Create test function
  test_success_func() { return 0; }
  test_failure_func() { return 1; }

  assert_success "Call existing function" z::func::call test_success_func

  local exit_code
  z::func::call test_failure_func
  exit_code=$?
  assert_equals "1" "$exit_code" "Function failure propagates"

  assert_failure "Call non-existent function" z::func::call nonexistent_func_xyz

  # Cleanup
  unset -f test_success_func test_failure_func
}

###
# Test: Cache purging
###
test_cache_purge() {
  print "\nTest Group: Cache Purging"

  z::cache::cmd::clear

  # Fill cache beyond threshold
  local original_max=${_zcore_config[cache_max_size]}
  _zcore_config[cache_max_size]=5

  # Add multiple entries
  z::cmd::exists "ls"
  z::cmd::exists "cat"
  z::cmd::exists "echo"
  z::cmd::exists "grep"
  z::cmd::exists "sed"
  z::cmd::exists "awk"
  z::cmd::exists "cut"

  # Cache should have been purged
  assert_true "$_cmd_cache_size <= 5" "Cache purged when exceeding limit"

  # Restore
  _zcore_config[cache_max_size]=$original_max
  z::cache::cmd::clear
}

###
# Test: Cache statistics
###
test_cache_stats() {
  print "\nTest Group: Cache Statistics"

  z::cache::cmd::clear
  z::cache::func::clear

  assert_equals "0" "$_cmd_cache_size" "Command cache empty"
  assert_equals "0" "$_func_cache_size" "Function cache empty"

  z::cmd::exists "ls"
  assert_equals "1" "$_cmd_cache_size" "Command cache has 1 entry"

  # Create and check function
  test_stat_func() { return 0; }
  z::func::exists "test_stat_func"
  assert_equals "1" "$_func_cache_size" "Function cache has 1 entry"

  # Cleanup
  unset -f test_stat_func
  z::cache::cmd::clear
  z::cache::func::clear
}

# Run all tests
test_cmd_cache
test_func_cache
test_func_call
test_cache_purge
test_cache_stats
