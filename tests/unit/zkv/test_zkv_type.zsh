#!/usr/bin/env zsh
# =============================================================================
# test_zkv_type.zsh — Per-key type tagging
# =============================================================================
# Description:  A key carries the type of its first write, and a later
#               operation belonging to a different type family must be
#               refused with Z_ERR_PERM until the key is deleted. Also checks
#               that z::kv::get reports the stored type in REPLY2 for the
#               scalar types that decode on read.
#
# Usage:        zsh tests/run_tests.zsh zkv
#               zsh tests/unit/zkv/test_zkv_type.zsh    # standalone
#
# Covers:       z::kv::set, z::kv::set_int, z::kv::set_bool, z::kv::get,
#               z::kv::del, z::kv::lpush, z::kv::llen, z::kv::sadd,
#               z::kv::hset
#
# Requires:     zkv — loaded by ztest::require below
# =============================================================================

source "${0:A:h}/../../bootstrap.zsh"
ztest::require zkv

test_setup() { z::kv::open _ty_test }
test_teardown() { z::kv::close _ty_test }

test_zkv_type_collision_string_then_list() {
  z::kv::set _ty_test "k" "string"
  ztest::assert::returns $Z_ERR_PERM \
    z::kv::lpush _ty_test "k" "boom"
}

test_zkv_type_collision_list_then_string() {
  z::kv::lpush _ty_test "k" "item"
  ztest::assert::returns $Z_ERR_PERM \
    z::kv::set _ty_test "k" "boom"
}

test_zkv_type_collision_set_then_hash() {
  z::kv::sadd _ty_test "k" "m"
  ztest::assert::returns $Z_ERR_PERM \
    z::kv::hset _ty_test "k" "f" "v"
}

test_zkv_type_after_del_any_type_allowed() {
  z::kv::set _ty_test "k" "first"
  z::kv::del _ty_test "k"
  ztest::assert::returns 0 z::kv::lpush _ty_test "k" "second"
  z::kv::llen _ty_test "k"
  ztest::assert::eq "1" "$REPLY"
}

test_zkv_get_sets_reply2_with_type() {
  z::kv::set_int _ty_test "n" "42"
  z::kv::get _ty_test "n"
  ztest::assert::eq "42" "$REPLY"
  ztest::assert::eq "int" "$REPLY2"
}

test_zkv_get_reply2_for_bool() {
  z::kv::set_bool _ty_test "flag" "yes"
  z::kv::get _ty_test "flag"
  ztest::assert::eq "true" "$REPLY"
  ztest::assert::eq "bool" "$REPLY2"
}

# Standalone execution; under the runner ztest::run is called by the runner.
(( ${ZTEST_RUNNER:-0} )) || ztest::run "${1:-test_*}"
