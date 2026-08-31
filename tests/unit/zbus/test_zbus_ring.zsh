#!/usr/bin/env zsh
# =============================================================================
# test_zbus_ring.zsh — Event history ring buffer
# =============================================================================
# Description:  The history buffer is bounded by --max-history and must drop
#               the oldest entry rather than the newest once full. Checks
#               that the length stays capped after twice as many emits as the
#               capacity, that the retained window is the most recent one,
#               and that a snapshot is returned oldest-first.
#
# Usage:        zsh tests/run_tests.zsh zbus
#               zsh tests/unit/zbus/test_zbus_ring.zsh    # standalone
#
# Covers:       z::bus::init, z::bus::reset, z::bus::on, z::bus::emit,
#               _z::bus::history_snapshot
#
# Requires:     zbus — loaded by ztest::require below
# =============================================================================

source "${0:A:h}/../../bootstrap.zsh"
ztest::require zbus

# A capacity of 5 keeps the wrap-around visible in a handful of emits.
test_setup() { z::bus::reset; z::bus::init --max-history 5 }

test_zbus_ring_buffer_wraps() {
  _h() { :; }
  z::bus::on "evt" _h

  local i
  for (( i = 1; i <= 10; i++ )); do
    z::bus::emit "evt" "msg$i"
  done

  _z::bus::history_snapshot
  ztest::assert::eq "5" "${#reply}" "ring buffer capped at max_history"

  # The oldest entry should be msg6 (10 emits, ring of 5)
  local first="${reply[1]}"
  ztest::assert::contains "$first" "msg6"
  local last="${reply[5]}"
  ztest::assert::contains "$last" "msg10"
}

test_zbus_ring_buffer_chronological_order() {
  _h() { :; }
  z::bus::on "evt" _h
  z::bus::emit "evt" "a"
  z::bus::emit "evt" "b"
  z::bus::emit "evt" "c"

  _z::bus::history_snapshot
  ztest::assert::eq "3" "${#reply}"
  ztest::assert::contains "${reply[1]}" "a"
  ztest::assert::contains "${reply[2]}" "b"
  ztest::assert::contains "${reply[3]}" "c"
}

# Standalone execution; under the runner ztest::run is called by the runner.
(( ${ZTEST_RUNNER:-0} )) || ztest::run "${1:-test_*}"
