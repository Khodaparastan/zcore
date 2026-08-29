test_setup() { z::bus::reset; z::bus::init }

# Regression: v2 reported handlers finishing just before timeout as TIMEOUT.
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
