#!/usr/bin/env zsh
# run_tests.zsh — discover and execute all test files
emulate -L zsh
setopt extendedglob warncreateglobal typesetsilent

SCRIPT_DIR="${0:A:h}"
TESTS_DIR="${SCRIPT_DIR}/tests"

# Source the framework chain in dependency order
source "${SCRIPT_DIR}/../zlog"   || { print -u2 "failed to source zlog"; exit 1; }
source "${SCRIPT_DIR}/../zbase"  || { print -u2 "failed to source zbase"; exit 1; }
source "${SCRIPT_DIR}/../zkv.zsh"    || { print -u2 "failed to source zkv"; exit 1; }
source "${SCRIPT_DIR}/../zbus.zsh"   || { print -u2 "failed to source zbus"; exit 1; }
source "${SCRIPT_DIR}/ztest.zsh"     || { print -u2 "failed to source ztest"; exit 1; }

# Quiet zlog while tests run; uncomment for verbose mode
z::log::set_level error

# Per-file run: source each test file in a subshell and run its tests.
# Subshell prevents test_setup/teardown name collisions across files.
typeset -i total_pass=0 total_fail=0 total_skip=0 total_assertions=0

for test_file in "${TESTS_DIR}"/test_*.zsh; do
  [[ -f $test_file ]] || continue
  print
  print "═══ ${test_file:t} ═══"
  (
    source "$test_file"
    ztest::run
  )
  local rc=$?
  (( rc != 0 )) && (( total_fail += 1 ))
done

print
print "════════════════════════════════════════"
if (( total_fail == 0 )); then
  print "✓ All test files passed"
  exit 0
else
  print "✗ ${total_fail} test file(s) had failures"
  exit 1
fi
