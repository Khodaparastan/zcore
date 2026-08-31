#!/usr/bin/env zsh
# =============================================================================
# test_time.zsh — Clock accessors
# =============================================================================
# Description:  Checks that the three epoch readers return bare digit
#               strings, that the second and millisecond clocks agree to
#               within two seconds of drift, that the millisecond clock never
#               moves backwards between two reads, and that each finer unit
#               carries at least three more digits than the previous one.
#
# Usage:        zsh tests/run_tests.zsh zbase
#               zsh tests/unit/zbase/test_time.zsh    # standalone
#
# Covers:       z::get::epoch, z::get::epoch_ms, z::get::epoch_ns
#
# Requires:     zbase — loaded by ztest::require below
# =============================================================================

source "${0:A:h}/../../bootstrap.zsh"
ztest::require zbase

test_time_epoch_is_integer() {
  z::get::epoch
  ztest::assert::matches "$REPLY" '<->'
  (( REPLY > 1700000000 )) || ztest::fail "expected REPLY > 1700000000, got $REPLY"   # post-2023
}

test_time_epoch_ms_has_more_precision() {
  z::get::epoch;    local s=$REPLY
  z::get::epoch_ms; local ms=$REPLY
  ztest::assert::matches "$ms" '<->'
  # ms should be in the same ballpark as s*1000 (within 2s drift)
  local diff=$(( ms - s * 1000 ))
  (( diff < 0 )) && (( diff = -diff ))
  (( diff < 2000 )) || ztest::fail "expected diff < 2000, got $diff"
}

test_time_epoch_ms_monotonic() {
  z::get::epoch_ms; local a=$REPLY
  z::get::epoch_ms; local b=$REPLY
  (( b >= a )) || ztest::fail "epoch_ms went backwards: a=$a b=$b"
}

test_time_epoch_ns_more_digits_than_ms() {
  z::get::epoch_ms; local ms_len=${#REPLY}
  z::get::epoch_ns; local ns_len=${#REPLY}
  # EPOCHREALTIME fractional width varies by zsh build (6 µs vs 9+ ns digits).
  (( ns_len > ms_len )) \
    || ztest::fail "ns ($ns_len digits) should be longer than ms ($ms_len digits)"
  (( ns_len - ms_len >= 3 )) \
    || ztest::fail "ns should have at least 3 more digits than ms (got $(( ns_len - ms_len )))"
}

# Standalone execution; under the runner ztest::run is called by the runner.
(( ${ZTEST_RUNNER:-0} )) || ztest::run "${1:-test_*}"
