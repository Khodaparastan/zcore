#!/usr/bin/env zsh
################################################################################
# ZCORE TEST RUNNER
################################################################################
#
# Comprehensive test framework for zcore library
#
# Usage:
#   ./tests/test-runner.zsh                    # Run all tests
#   ./tests/test-runner.zsh test-logging.zsh   # Run specific test
#
################################################################################

# Determine script directory
SCRIPT_DIR="${0:A:h}"
ZCORE_ROOT="${SCRIPT_DIR:h}"

# Load zcore
if ! source "${ZCORE_ROOT}/zcore.zsh"; then
  print -u2 "ERROR: Failed to load zcore"
  exit 1
fi

# Disable progress bars for testing
z::config::set show_progress false

################################################################################
# TEST FRAMEWORK GLOBALS
################################################################################
typeset -gi _test_total=0
typeset -gi _test_passed=0
typeset -gi _test_failed=0
typeset -g _current_test_suite=""

################################################################################
# ASSERTION FUNCTIONS
################################################################################

###
# Assert two values are equal
#
# @param $1 string - Expected value
# @param $2 string - Actual value
# @param $3 string - Message (optional)
# @return 0 if equal, 1 otherwise
###
assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="${3:-Assertion failed}"

  (( _test_total += 1 ))

  if [[ $expected == $actual ]]; then
    (( _test_passed += 1 ))
    print "  ✓ $message"
    return 0
  else
    (( _test_failed += 1 ))
    print "  ✗ $message"
    print "    Expected: '$expected'"
    print "    Actual:   '$actual'"
    return 1
  fi
}

###
# Assert command succeeds
#
# @param $1 string - Message
# @param $@ any - Command to execute
# @return 0 if command succeeds, 1 otherwise
###
assert_success() {
  local message="${1:-Command should succeed}"
  shift

  (( _test_total += 1 ))

  if "$@" >/dev/null 2>&1; then
    (( _test_passed += 1 ))
    print "  ✓ $message"
    return 0
  else
    (( _test_failed += 1 ))
    print "  ✗ $message (exit code: $?)"
    return 1
  fi
}

###
# Assert command fails
#
# @param $1 string - Message
# @param $@ any - Command to execute
# @return 0 if command fails, 1 otherwise
###
assert_failure() {
  local message="${1:-Command should fail}"
  shift

  (( _test_total += 1 ))

  if ! "$@" >/dev/null 2>&1; then
    (( _test_passed += 1 ))
    print "  ✓ $message"
    return 0
  else
    (( _test_failed += 1 ))
    print "  ✗ $message (expected failure but succeeded)"
    return 1
  fi
}

###
# Assert value is true (non-zero integer)
#
# @param $1 integer - Value to check
# @param $2 string - Message (optional)
# @return 0 if true, 1 otherwise
###
assert_true() {
  local value="$1"
  local message="${2:-Value should be true}"

  (( _test_total += 1 ))

  if (( value )); then
    (( _test_passed += 1 ))
    print "  ✓ $message"
    return 0
  else
    (( _test_failed += 1 ))
    print "  ✗ $message (value: $value)"
    return 1
  fi
}

###
# Assert value is false (zero integer)
#
# @param $1 integer - Value to check
# @param $2 string - Message (optional)
# @return 0 if false, 1 otherwise
###
assert_false() {
  local value="$1"
  local message="${2:-Value should be false}"

  (( _test_total += 1 ))

  if (( ! value )); then
    (( _test_passed += 1 ))
    print "  ✓ $message"
    return 0
  else
    (( _test_failed += 1 ))
    print "  ✗ $message (value: $value)"
    return 1
  fi
}

###
# Assert string contains substring
#
# @param $1 string - Haystack
# @param $2 string - Needle
# @param $3 string - Message (optional)
# @return 0 if contains, 1 otherwise
###
assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="${3:-String should contain substring}"

  (( _test_total += 1 ))

  if [[ $haystack == *"$needle"* ]]; then
    (( _test_passed += 1 ))
    print "  ✓ $message"
    return 0
  else
    (( _test_failed += 1 ))
    print "  ✗ $message"
    print "    Haystack: '$haystack'"
    print "    Needle:   '$needle'"
    return 1
  fi
}

################################################################################
# TEST SUITE RUNNER
################################################################################

###
# Run a single test suite
#
# @param $1 string - Test suite file path
# @return 0 always
###
run_test_suite() {
  local suite_file="$1"

  _current_test_suite="${suite_file:t}"

  print "\n========================================="
  print "Running: $_current_test_suite"
  print "=========================================\n"

  typeset -i suite_start_total=$_test_total
  typeset -i suite_start_passed=$_test_passed
  typeset -i suite_start_failed=$_test_failed

  # Source the test suite
  if ! source "$suite_file"; then
    print "\n✗ ERROR: Failed to load test suite: $suite_file"
    (( _test_failed += 1 ))
    return 1
  fi

  typeset -i suite_total=$(( _test_total - suite_start_total ))
  typeset -i suite_passed=$(( _test_passed - suite_start_passed ))
  typeset -i suite_failed=$(( _test_failed - suite_start_failed ))

  print "\n-----------------------------------------"
  print "Suite Results: $suite_passed passed, $suite_failed failed ($suite_total total)"
  print "-----------------------------------------"

  return 0
}

################################################################################
# MAIN EXECUTION
################################################################################

print "╔════════════════════════════════════════╗"
print "║      ZCORE TEST SUITE v${ZCORE_VERSION}         ║"
print "╚════════════════════════════════════════╝"

# Determine which tests to run
typeset -a test_suites=()

if (( $# > 0 )); then
  # Run specific test files
  for arg in "$@"; do
    if [[ -f ${SCRIPT_DIR}/${arg} ]]; then
      test_suites+=("${SCRIPT_DIR}/${arg}")
    elif [[ -f $arg ]]; then
      test_suites+=("$arg")
    else
      print -u2 "WARNING: Test file not found: $arg"
    fi
  done
else
  # Run all test files
  test_suites=("${SCRIPT_DIR}"/test-*.zsh)
fi

# Remove test-runner.zsh from list
test_suites=(${test_suites:#*/test-runner.zsh})

if (( ${#test_suites} == 0 )); then
  print -u2 "ERROR: No test suites found"
  exit 1
fi

# Run each test suite
for suite in "${test_suites[@]}"; do
  run_test_suite "$suite"
done

# Final summary
print "\n╔════════════════════════════════════════╗"
print "║           FINAL RESULTS                ║"
print "╠════════════════════════════════════════╣"
printf "║ Total:  %-30s ║\n" "$_test_total"
printf "║ Passed: %-30s ║\n" "$_test_passed"
printf "║ Failed: %-30s ║\n" "$_test_failed"
print "╚════════════════════════════════════════╝"

if (( _test_failed == 0 )); then
  print "\n✓ All tests passed!"
  exit 0
else
  print "\n✗ Some tests failed"
  exit 1
fi
