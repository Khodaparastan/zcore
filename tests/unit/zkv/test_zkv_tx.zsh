#!/usr/bin/env zsh
# =============================================================================
# test_zkv_tx.zsh — Transaction semantics
# =============================================================================
# Description:  Covers begin/commit/rollback for strings and for every
#               container type, the visibility of uncommitted writes to reads
#               inside the same transaction, set-then-delete and
#               delete-then-set collapsing within one transaction, and the
#               z::kv::tx wrapper rolling back when its callback fails.
#
# Usage:        zsh tests/run_tests.zsh zkv
#               zsh tests/unit/zkv/test_zkv_tx.zsh    # standalone
#
# Covers:       z::kv::begin, z::kv::commit, z::kv::rollback, z::kv::tx
#
# Requires:     zkv — loaded by ztest::require below
# =============================================================================

source "${0:A:h}/../../bootstrap.zsh"
ztest::require zkv

test_setup() {
  z::kv::open _tx_test
}

test_teardown() {
  z::kv::close _tx_test
}

test_zkv_tx_string_rollback() {
  z::kv::set _tx_test "k" "original"
  z::kv::begin _tx_test
  z::kv::set _tx_test "k" "modified"
  z::kv::get _tx_test "k"
  ztest::assert::eq "modified" "$REPLY" "in-tx read"
  z::kv::rollback _tx_test
  z::kv::get _tx_test "k"
  ztest::assert::eq "original" "$REPLY" "post-rollback"
}

test_zkv_tx_string_commit() {
  z::kv::set _tx_test "k" "original"
  z::kv::begin _tx_test
  z::kv::set _tx_test "k" "modified"
  z::kv::commit _tx_test
  z::kv::get _tx_test "k"
  ztest::assert::eq "modified" "$REPLY"
}

# Rollback must restore container contents, not just scalar values: the
# journal has to capture the whole list, not the key's presence.
test_zkv_tx_list_rollback() {
  z::kv::lpush _tx_test "mylist" "live1"
  z::kv::begin _tx_test
  z::kv::lpush _tx_test "mylist" "tx1"
  z::kv::llen _tx_test "mylist"
  ztest::assert::eq "2" "$REPLY" "in-tx list length"
  z::kv::rollback _tx_test
  z::kv::llen _tx_test "mylist"
  ztest::assert::eq "1" "$REPLY" "post-rollback list length"
  z::kv::lindex _tx_test "mylist" 0
  ztest::assert::eq "live1" "$REPLY"
}

test_zkv_tx_set_rollback() {
  z::kv::sadd _tx_test "myset" "a"
  z::kv::begin _tx_test
  z::kv::sadd _tx_test "myset" "b"
  z::kv::scard _tx_test "myset"
  ztest::assert::eq "2" "$REPLY"
  z::kv::rollback _tx_test
  z::kv::scard _tx_test "myset"
  ztest::assert::eq "1" "$REPLY" "set rollback restores cardinality"
}

test_zkv_tx_hash_rollback() {
  z::kv::hset _tx_test "myhash" "field1" "live"
  z::kv::begin _tx_test
  z::kv::hset _tx_test "myhash" "field1" "modified"
  z::kv::hset _tx_test "myhash" "field2" "new"
  z::kv::commit _tx_test
  z::kv::hget _tx_test "myhash" "field1"
  ztest::assert::eq "modified" "$REPLY"
  z::kv::hget _tx_test "myhash" "field2"
  ztest::assert::eq "new" "$REPLY"
}

test_zkv_tx_set_then_delete_in_same_tx() {
  z::kv::begin _tx_test
  z::kv::set _tx_test "k" "v"
  z::kv::del _tx_test "k"
  z::kv::commit _tx_test
  ztest::assert::returns $Z_ERR_NOTFOUND z::kv::get _tx_test "k"
}

test_zkv_tx_delete_then_set_in_same_tx() {
  z::kv::set _tx_test "k" "old"
  z::kv::begin _tx_test
  z::kv::del _tx_test "k"
  z::kv::set _tx_test "k" "new"
  z::kv::commit _tx_test
  z::kv::get _tx_test "k"
  ztest::assert::eq "new" "$REPLY"
}

test_zkv_tx_tx_helper_rolls_back_on_failure() {
  z::kv::set _tx_test "k" "original"
  _failing_callback() {
    z::kv::set "$1" "k" "modified"
    return 1   # triggers rollback
  }
  z::kv::tx _tx_test _failing_callback
  ztest::assert::eq "1" "$?"
  z::kv::get _tx_test "k"
  ztest::assert::eq "original" "$REPLY" "tx() rolls back on cb failure"
}

# Standalone execution; under the runner ztest::run is called by the runner.
(( ${ZTEST_RUNNER:-0} )) || ztest::run "${1:-test_*}"
