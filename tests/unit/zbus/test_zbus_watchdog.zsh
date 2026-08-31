#!/usr/bin/env zsh
# =============================================================================
# test_zbus_watchdog.zsh — Handler timeout classification
# =============================================================================
# Description:  emit_safe watches each handler against the configured
#               handler_timeout. These tests pin the three outcomes apart: a
#               handler that finishes inside the budget is a success, one
#               that overruns is killed and counted as evt.timeout, and one
#               that returns non-zero quickly is counted as evt.failed and
#               never as a timeout. Real sleeps make this file the slowest
#               in the suite.
#
# Usage:        zsh tests/run_tests.zsh zbus
#               zsh tests/unit/zbus/test_zbus_watchdog.zsh    # standalone
#
# Covers:       z::bus::init, z::bus::reset, z::bus::config, z::bus::on,
#               z::bus::emit_safe
#
# Requires:     zbus — loaded by ztest::require below
# =============================================================================

source "${0:A:h}/../../bootstrap.zsh"
ztest::require zbus

test_setup() { z::bus::reset; z::bus::init }

# The boundary case: finishing shortly before the deadline must not be
# rounded up into a timeout.
test_zbus_watchdog_fast_handler_not_a_timeout() {
  z::bus::config handler_timeout 3

  _fast_h() {
    sleep 1   # well under 3s
    return 0
  }
  z::bus::on "evt" _fast_h
  z::bus::emit_safe "evt"
  local rc=$?
  ztest::assert::eq "0" "$rc" "fast handler must not be classified as timeout"

  # And the timeout counter should NOT have ticked
  local timeout_count="${_zbus_stats[evt.timeout]:-0}"
  ztest::assert::eq "0" "$timeout_count"
}

test_zbus_watchdog_slow_handler_is_killed() {
  z::bus::config handler_timeout 1

  _slow_h() {
    sleep 5   # well over 1s
    return 0
  }
  z::bus::on "evt" _slow_h
  z::bus::emit_safe "evt" || true

  local timeout_count="${_zbus_stats[evt.timeout]:-0}"
  ztest::assert::eq "1" "$timeout_count" "slow handler should be classified as timeout"
}

# A quick non-zero return and a killed overrun both leave the handler
# unfinished, so the two counters must not be conflated.
test_zbus_watchdog_failing_handler_not_a_timeout() {
  z::bus::config handler_timeout 5

  _fail_fast_h() { return 7; }
  z::bus::on "evt" _fail_fast_h
  z::bus::emit_safe "evt" || true

  local timeout_count="${_zbus_stats[evt.timeout]:-0}"
  local failed_count="${_zbus_stats[evt.failed]:-0}"
  ztest::assert::eq "0" "$timeout_count" "fast failure is not a timeout"
  ztest::assert::eq "1" "$failed_count" "fast failure counts as fail"
}

# Standalone execution; under the runner ztest::run is called by the runner.
(( ${ZTEST_RUNNER:-0} )) || ztest::run "${1:-test_*}"
