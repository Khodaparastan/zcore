#!/usr/bin/env zsh
# =============================================================================
# test_zkv_list_set_ops.zsh — List pops and set algebra return their own result
# =============================================================================
# Description:  Lists and sets are stored as one encoded string per key, so
#               almost every operation calls _z::kv::join_encoded or
#               _z::kv::split_decoded — and both of those return through the
#               same REPLY/reply channel the operation itself uses. Four
#               functions were overwriting their own result that way: lpop
#               and rpop published the popped element before the write-back
#               replaced REPLY with the remainder, while sdiff and sunion
#               accumulated into reply only for the next decode to wipe it.
#
#               A related shape is covered here too: llen, scard and zcard
#               resolve their storage map through REPLY, so an early return
#               on a missing key handed back the internal map name instead
#               of 0.
#
#               The transaction cases matter because pops resolve through
#               tx_resolve_write, a second code path with the same exposure.
#
# Usage:        zsh tests/run_tests.zsh zkv
#               zsh tests/unit/zkv/test_zkv_list_set_ops.zsh    # standalone
#
# Covers:       z::kv::lpush, z::kv::rpush, z::kv::lpop, z::kv::rpop,
#               z::kv::lrange, z::kv::llen, z::kv::lindex, z::kv::sadd,
#               z::kv::scard, z::kv::smembers, z::kv::sunion, z::kv::sinter,
#               z::kv::sdiff, z::kv::zcard, z::kv::begin, z::kv::commit,
#               z::kv::rollback
#
# Requires:     zkv — loaded by ztest::require below
# =============================================================================

source "${0:A:h}/../../bootstrap.zsh"
ztest::require zkv

test_setup() { z::kv::open _ls_test }
test_teardown() { z::kv::close _ls_test }

# _ls_list <key> <item> [<item> ...]
# Build a list in insertion order.
_ls_list() {
  local key="$1"
  shift
  local item
  for item in "$@"; do
    z::kv::rpush _ls_test "$key" "$item"
  done
}

# _ls_set <key> <member> [<member> ...]
_ls_set() {
  local key="$1"
  shift
  local member
  for member in "$@"; do
    z::kv::sadd _ls_test "$key" "$member"
  done
}


# -----------------------------------------------------------------------------
# List pops
# -----------------------------------------------------------------------------

test_zkv_lpop_returns_the_first_element() {
  _ls_list "L" one two three

  z::kv::lpop _ls_test "L"
  ztest::assert::eq "one" "$REPLY" "lpop returns the head, not the remainder"

  z::kv::lrange _ls_test "L" 0 -1
  ztest::assert::eq "two three" "${reply[*]}" "remainder intact and in order"
}

test_zkv_rpop_returns_the_last_element() {
  _ls_list "L" one two three

  z::kv::rpop _ls_test "L"
  ztest::assert::eq "three" "$REPLY" "rpop returns the tail"

  z::kv::lrange _ls_test "L" 0 -1
  ztest::assert::eq "one two" "${reply[*]}" "remainder intact and in order"
}

test_zkv_pops_drain_a_list_in_order() {
  _ls_list "L" one two three

  z::kv::lpop _ls_test "L"; local first="$REPLY"
  z::kv::lpop _ls_test "L"; local second="$REPLY"
  z::kv::rpop _ls_test "L"; local last="$REPLY"

  ztest::assert::eq "one two three" "$first $second $last"
}

# Popping the last element deletes the key rather than leaving an empty
# encoded string behind, so the count has to read back as 0.
test_zkv_pop_to_empty_removes_the_key() {
  _ls_list "L" only

  z::kv::lpop _ls_test "L"
  ztest::assert::eq "only" "$REPLY"

  z::kv::llen _ls_test "L"
  ztest::assert::eq "0" "$REPLY" "drained list reports length 0"

  ztest::assert::returns $Z_ERR_NOTFOUND z::kv::lpop _ls_test "L"
}

test_zkv_pop_on_a_missing_key_reports_not_found() {
  ztest::assert::returns $Z_ERR_NOTFOUND z::kv::lpop _ls_test "absent"
  ztest::assert::returns $Z_ERR_NOTFOUND z::kv::rpop _ls_test "absent"
}

test_zkv_pop_preserves_values_containing_separators() {
  _ls_list "L" "a b" "c
d" "e|f"

  z::kv::lpop _ls_test "L"
  ztest::assert::eq "a b" "$REPLY"

  z::kv::rpop _ls_test "L"
  ztest::assert::eq "e|f" "$REPLY"

  z::kv::lrange _ls_test "L" 0 -1
  ztest::assert::eq "c
d" "${reply[*]}"
}


# -----------------------------------------------------------------------------
# Set algebra
# -----------------------------------------------------------------------------

test_zkv_sdiff_subtracts_one_set() {
  _ls_set "A" a b
  _ls_set "B" b c

  z::kv::sdiff _ls_test "A" "B"
  ztest::assert::eq "a" "${reply[*]}"
}

test_zkv_sdiff_subtracts_several_sets() {
  _ls_set "A" a b c d
  _ls_set "B" b
  _ls_set "C" c

  z::kv::sdiff _ls_test "A" "B" "C"
  ztest::assert::eq "a d" "${reply[*]}"
}

test_zkv_sdiff_with_one_argument_returns_the_whole_set() {
  _ls_set "A" a b

  z::kv::sdiff _ls_test "A"
  ztest::assert::eq "a b" "${(o)reply[*]}"
}

test_zkv_sdiff_ignores_a_missing_subtrahend() {
  _ls_set "A" a b

  z::kv::sdiff _ls_test "A" "absent"
  ztest::assert::eq "a b" "${(o)reply[*]}"
}

test_zkv_sdiff_on_an_empty_first_set_is_empty() {
  _ls_set "B" b

  z::kv::sdiff _ls_test "absent" "B"
  ztest::assert::eq "0" "${#reply}"
}

# sunion carried the same accumulate-into-reply defect as sdiff: members from
# earlier keys were wiped as soon as the next key was decoded.
test_zkv_sunion_keeps_members_from_every_set() {
  _ls_set "A" a b
  _ls_set "B" b c
  _ls_set "C" d

  z::kv::sunion _ls_test "A" "B" "C"
  ztest::assert::eq "a b c d" "${(o)reply[*]}" "union spans all inputs"
  ztest::assert::eq "4" "${#reply}" "duplicates collapsed"
}

test_zkv_sunion_of_a_single_set_is_that_set() {
  _ls_set "A" a b

  z::kv::sunion _ls_test "A"
  ztest::assert::eq "a b" "${(o)reply[*]}"
}

test_zkv_sinter_still_intersects() {
  _ls_set "A" a b c
  _ls_set "B" b c d

  z::kv::sinter _ls_test "A" "B"
  ztest::assert::eq "b c" "${(o)reply[*]}"
}


# -----------------------------------------------------------------------------
# Counts on absent keys
# -----------------------------------------------------------------------------

# These resolve their storage map through REPLY, so the absent-key path used
# to return the map name (e.g. "_zkv_lists__ls_test") with status 0.
test_zkv_counts_are_zero_for_a_missing_key() {
  z::kv::llen _ls_test "absent"
  ztest::assert::eq "0" "$REPLY" "llen"

  z::kv::scard _ls_test "absent"
  ztest::assert::eq "0" "$REPLY" "scard"

  z::kv::zcard _ls_test "absent"
  ztest::assert::eq "0" "$REPLY" "zcard"
}

test_zkv_scard_is_zero_after_the_last_member_is_removed() {
  _ls_set "A" only
  z::kv::srem _ls_test "A" only

  z::kv::scard _ls_test "A"
  ztest::assert::eq "0" "$REPLY"
}


# -----------------------------------------------------------------------------
# Transactions
# -----------------------------------------------------------------------------
# Pops go through tx_resolve_write, so the buffered path needs the same proof.

test_zkv_lpop_inside_a_transaction_returns_the_element() {
  _ls_list "L" one two three

  z::kv::begin _ls_test
  z::kv::lpop _ls_test "L"
  ztest::assert::eq "one" "$REPLY" "in-tx lpop"

  z::kv::lrange _ls_test "L" 0 -1
  ztest::assert::eq "two three" "${reply[*]}" "in-tx read sees the buffer"

  z::kv::commit _ls_test
  z::kv::lrange _ls_test "L" 0 -1
  ztest::assert::eq "two three" "${reply[*]}" "committed"
}

test_zkv_rollback_restores_the_pre_pop_list() {
  _ls_list "L" one two three

  z::kv::begin _ls_test
  z::kv::lpop _ls_test "L"
  z::kv::rpop _ls_test "L"
  z::kv::rollback _ls_test

  z::kv::lrange _ls_test "L" 0 -1
  ztest::assert::eq "one two three" "${reply[*]}" "rollback restores the list"

  z::kv::llen _ls_test "L"
  ztest::assert::eq "3" "$REPLY"
}

test_zkv_pop_to_empty_inside_a_transaction_rolls_back() {
  _ls_list "L" only

  z::kv::begin _ls_test
  z::kv::lpop _ls_test "L"
  ztest::assert::eq "only" "$REPLY"
  z::kv::rollback _ls_test

  z::kv::llen _ls_test "L"
  ztest::assert::eq "1" "$REPLY" "the drained key comes back"
}

test_zkv_sdiff_inside_a_transaction_sees_buffered_writes() {
  _ls_set "A" a b
  _ls_set "B" b

  z::kv::begin _ls_test
  z::kv::sadd _ls_test "B" a
  z::kv::sdiff _ls_test "A" "B"
  ztest::assert::eq "0" "${#reply}" "buffered member removes the difference"
  z::kv::rollback _ls_test

  z::kv::sdiff _ls_test "A" "B"
  ztest::assert::eq "a" "${reply[*]}" "difference is back after rollback"
}

# Standalone execution; under the runner ztest::run is called by the runner.
(( ${ZTEST_RUNNER:-0} )) || ztest::run "${1:-test_*}"
