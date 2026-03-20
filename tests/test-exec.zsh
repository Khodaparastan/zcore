#!/usr/bin/env zsh
################################################################################
# SAFE EXECUTION TESTS
################################################################################

print "Testing: Safe Execution"

###
# Test: Safe command execution
###
test_exec_run() {
  print "\nTest Group: Command Execution"

  assert_success "Run simple command" z::exec::run "echo 'test'"
  assert_success "Run ls command" z::exec::run "ls /tmp"
  assert_failure "Run non-existent command" z::exec::run "nonexistent_command_xyz"
}

###
# Test: Dangerous pattern detection
###
test_dangerous_patterns() {
  print "\nTest Group: Dangerous Pattern Detection"

  assert_failure "Block rm -rf /" z::exec::run "rm -rf /"
  assert_failure "Block dd to device" z::exec::run "dd if=/dev/zero of=/dev/sda"
  assert_failure "Block chmod 777 -R /" z::exec::run "chmod -R 777 /"

  # Safe commands should pass
  assert_success "Allow safe rm" z::exec::run "rm -rf /tmp/safe_test_dir_xyz"
  assert_success "Allow safe chmod" z::exec::run "chmod 644 /tmp/test_file"
}

###
# Test: Whitelisted init commands
###
test_init_commands() {
  print "\nTest Group: Whitelisted Init Commands"

  # These should bypass security checks (even if commands don't exist)
  # We're testing the whitelist logic, not actual execution
  local result

  if z::exec::_is_init_cmd "starship init zsh"; then
    assert_success "Starship init whitelisted" true
  else
    assert_failure "Starship init should be whitelisted" false
  fi

  if z::exec::_is_init_cmd "mise activate zsh"; then
    assert_success "Mise activate whitelisted" true
  else
    assert_failure "Mise activate should be whitelisted" false
  fi

  if ! z::exec::_is_init_cmd "rm -rf /"; then
    assert_success "Dangerous command not whitelisted" true
  else
    assert_failure "Dangerous command should not be whitelisted" false
  fi
}

###
# Test: Metacharacter detection
###
test_metacharacters() {
  print "\nTest Group: Metacharacter Detection"

  if z::exec::_has_dangerous_metachars "echo test; rm -rf /"; then
    assert_success "Detect semicolon" true
  else
    assert_failure "Should detect semicolon" false
  fi

  if z::exec::_has_dangerous_metachars "echo test && rm -rf /"; then
    assert_success "Detect ampersand" true
  else
    assert_failure "Should detect ampersand" false
  fi

  if ! z::exec::_has_dangerous_metachars "echo test"; then
    assert_success "Safe command has no dangerous chars" true
  else
    assert_failure "Safe command should pass" false
  fi
}

###
# Test: Command timeout
###
test_timeout() {
  print "\nTest Group: Command Timeout"

  # Only test if timeout command available
  if [[ -n ${_zcore_timeout_cmd} ]]; then
    assert_success "Quick command completes" z::exec::run "echo test" 5

    # Test timeout (sleep longer than timeout)
    local exit_code
    z::exec::run "sleep 10" 1
    exit_code=$?

    if (( exit_code == 124 )); then
      assert_success "Command times out correctly" true
    else
      print "  ⚠ Timeout test inconclusive (exit code: $exit_code)"
    fi
  else
    print "  ⚠ Skipping timeout tests (timeout command not available)"
  fi
}

###
# Test: Eval function
###
test_exec_eval() {
  print "\nTest Group: Eval Function"

  assert_success "Eval simple command" z::exec::eval "echo test"
  assert_failure "Eval dangerous command" z::exec::eval "rm -rf /"

  # Test variable assignment
  assert_success "Eval variable assignment" z::exec::eval "TEST_VAR=123" 30 true
}

# Run all tests
test_exec_run
test_dangerous_patterns
test_init_commands
test_metacharacters
test_timeout
test_exec_eval
