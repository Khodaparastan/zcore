#!/usr/bin/env zsh
# =============================================================================
# test_zkv_ttl.zsh — Key expiry
# =============================================================================
# Description:  Covers the TTL sentinels — the remaining seconds for a key
#               set with --ttl, -1 for a key with no expiry, -2 for a key
#               that does not exist — and checks that expiry applies to
#               container types as well as strings and that persist strips
#               it again.
#
# Usage:        zsh tests/run_tests.zsh zkv
#               zsh tests/unit/zkv/test_zkv_ttl.zsh    # standalone
#
# Covers:       z::kv::ttl, z::kv::expire, z::kv::persist, z::kv::set,
#               z::kv::lpush
#
# Requires:     zkv — loaded by ztest::require below
# =============================================================================

source "${0:A:h}/../../bootstrap.zsh"
ztest::require zkv

test_setup() { z::kv::open _ttl_test }
test_teardown() { z::kv::close _ttl_test }

test_zkv_ttl_string_set_with_ttl() {
  z::kv::set _ttl_test "k" "v" --ttl 60
  z::kv::ttl _ttl_test "k"
  (( REPLY > 55 && REPLY <= 60 )) || ztest::fail "expected 55 < REPLY <= 60, got $REPLY"
}

test_zkv_ttl_no_ttl_returns_minus_one() {
  z::kv::set _ttl_test "k" "v"
  z::kv::ttl _ttl_test "k"
  ztest::assert::eq "-1" "$REPLY"
}

test_zkv_ttl_missing_key_returns_minus_two() {
  z::kv::ttl _ttl_test "absent"
  ztest::assert::eq "-2" "$REPLY"
}

test_zkv_ttl_applies_to_list_v4() {
  z::kv::lpush _ttl_test "mylist" "x"
  z::kv::expire _ttl_test "mylist" 60
  z::kv::ttl _ttl_test "mylist"
  (( REPLY > 55 )) || ztest::fail "expected REPLY > 55, got $REPLY"
}

test_zkv_ttl_persist_clears_ttl() {
  z::kv::set _ttl_test "k" "v" --ttl 60
  z::kv::persist _ttl_test "k"
  z::kv::ttl _ttl_test "k"
  ztest::assert::eq "-1" "$REPLY"
}

# Standalone execution; under the runner ztest::run is called by the runner.
(( ${ZTEST_RUNNER:-0} )) || ztest::run "${1:-test_*}"
