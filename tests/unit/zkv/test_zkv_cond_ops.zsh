#!/usr/bin/env zsh
# =============================================================================
# test_zkv_cond_ops.zsh — Numeric, conditional, and multi-key operations
# =============================================================================
# Description:  Covers the production-critical paths that mutate or gate a
#               key's value: counters (incr/decr/hincrby) with their error
#               and TTL-preservation edges, conditional writes (setnx,
#               setxx, cas, getset), TTL manipulation through expire, the
#               atomic multi-key pair (mset/mget), and indexed list access
#               (lindex/lset) with negative indices.
#
# Usage:        zsh tests/run_tests.zsh zkv
#               zsh tests/unit/zkv/test_zkv_cond_ops.zsh    # standalone
#
# Covers:       z::kv::incr, z::kv::decr, z::kv::hincrby, z::kv::setnx,
#               z::kv::setxx, z::kv::cas, z::kv::getset, z::kv::expire,
#               z::kv::mset, z::kv::mget, z::kv::lindex, z::kv::lset,
#               z::kv::ttl, z::kv::get, z::kv::set, z::kv::hset
#
# Requires:     zkv — loaded by ztest::require below
# =============================================================================

source "${0:A:h}/../../bootstrap.zsh"
ztest::require zkv

test_setup() { z::kv::open _cond }
test_teardown() { z::kv::close _cond }

# -----------------------------------------------------------------------------
# Counters
# -----------------------------------------------------------------------------

test_zkv_incr_autovivifies_at_zero() {
  z::kv::incr _cond n
  ztest::assert::eq "0" "$?"
  ztest::assert::eq "1" "$REPLY"
}

test_zkv_incr_takes_an_amount_and_decr_negates_it() {
  z::kv::incr _cond n 5
  ztest::assert::eq "5" "$REPLY" "incr with an explicit amount"
  z::kv::decr _cond n 2
  ztest::assert::eq "3" "$REPLY" "decr by an explicit amount"
  z::kv::decr _cond n
  ztest::assert::eq "2" "$REPLY" "decr defaults to one"
  z::kv::incr _cond n -1
  ztest::assert::eq "1" "$REPLY" "negative amounts count down"
}

test_zkv_incr_preserves_remaining_ttl() {
  z::kv::set _cond n 10 --ttl 500
  z::kv::incr _cond n 5
  ztest::assert::eq "15" "$REPLY"
  z::kv::ttl _cond n
  (( REPLY > 495 && REPLY <= 500 )) \
    || ztest::fail "expected 495 < REPLY <= 500 after incr, got $REPLY"
}

test_zkv_incr_rejects_a_non_integer_amount() {
  ztest::assert::returns $Z_ERR_INPUT z::kv::incr _cond n abc
}

test_zkv_incr_rejects_a_non_integer_stored_value() {
  z::kv::set _cond s "abc"
  ztest::assert::returns $Z_ERR_INPUT z::kv::incr _cond s
}

test_zkv_hincrby_autovivifies_the_field() {
  z::kv::hincrby _cond h f
  ztest::assert::eq "1" "$REPLY"
  z::kv::hincrby _cond h f 4
  ztest::assert::eq "5" "$REPLY"
  z::kv::hget _cond h f
  ztest::assert::eq "5" "$REPLY" "field was actually stored"
}

test_zkv_hincrby_rejects_a_non_integer_field_value() {
  z::kv::hset _cond h f "zz"
  ztest::assert::returns $Z_ERR_INPUT z::kv::hincrby _cond h f
}

# -----------------------------------------------------------------------------
# Conditional writes
# -----------------------------------------------------------------------------

test_zkv_setnx_sets_only_when_absent() {
  ztest::assert::returns 0 z::kv::setnx _cond k "v1"
  z::kv::get _cond k
  ztest::assert::eq "v1" "$REPLY"
  ztest::assert::returns $Z_ERR_PERM z::kv::setnx _cond k "v2"
  z::kv::get _cond k
  ztest::assert::eq "v1" "$REPLY" "existing value untouched by failed setnx"
}

test_zkv_setxx_sets_only_when_present() {
  ztest::assert::returns $Z_ERR_NOTFOUND z::kv::setxx _cond ghost "v"
  z::kv::set _cond k "v1"
  ztest::assert::returns 0 z::kv::setxx _cond k "v2"
  z::kv::get _cond k
  ztest::assert::eq "v2" "$REPLY"
}

test_zkv_cas_swaps_only_on_exact_match() {
  z::kv::set _cond k "old"
  ztest::assert::returns 0 z::kv::cas _cond k "old" "new"
  z::kv::get _cond k
  ztest::assert::eq "new" "$REPLY"
  ztest::assert::returns $Z_ERR_PERM z::kv::cas _cond k "nope" "x"
  z::kv::get _cond k
  ztest::assert::eq "new" "$REPLY" "mismatched CAS must not modify the value"
}

test_zkv_cas_on_a_missing_key_follows_expected() {
  ztest::assert::returns 0 z::kv::cas _cond fresh "" "created"
  z::kv::get _cond fresh
  ztest::assert::eq "created" "$REPLY"
  ztest::assert::returns $Z_ERR_PERM z::kv::cas _cond fresh2 "e" "c"
}

test_zkv_getset_returns_the_old_value_and_preserves_ttl() {
  z::kv::set _cond k "one" --ttl 400
  z::kv::getset _cond k "two"
  ztest::assert::eq "one" "$REPLY" "reply carries the previous value"
  z::kv::ttl _cond k
  (( REPLY > 395 && REPLY <= 400 )) \
    || ztest::fail "expected 395 < REPLY <= 400 after getset, got $REPLY"
  z::kv::get _cond k
  ztest::assert::eq "two" "$REPLY"
}

test_zkv_getset_on_a_missing_key_creates_it() {
  z::kv::getset _cond fresh "first"
  ztest::assert::eq "" "$REPLY" "no previous value to return"
  z::kv::get _cond fresh
  ztest::assert::eq "first" "$REPLY"
}

# -----------------------------------------------------------------------------
# TTL through expire
# -----------------------------------------------------------------------------

test_zkv_expire_sets_and_removes_a_ttl() {
  z::kv::set _cond k "v"
  z::kv::expire _cond k 120
  z::kv::ttl _cond k
  (( REPLY > 115 && REPLY <= 120 )) \
    || ztest::fail "expected 115 < REPLY <= 120, got $REPLY"
  z::kv::expire _cond k 0
  z::kv::ttl _cond k
  ztest::assert::eq "-1" "$REPLY" "ttl zero removes the expiry"
  z::kv::expire _cond k -5
  z::kv::ttl _cond k
  ztest::assert::eq "-1" "$REPLY" "negative ttl also removes the expiry"
}

test_zkv_expire_rejects_an_unknown_key_and_bad_ttl() {
  ztest::assert::returns $Z_ERR_NOTFOUND z::kv::expire _cond ghost 5
  ztest::assert::returns $Z_ERR_INPUT z::kv::expire _cond k abc
}

test_zkv_an_expired_key_disappears_on_read() {
  z::kv::set _cond k "v" --ttl 1
  sleep 2
  ztest::assert::returns $Z_ERR_NOTFOUND z::kv::get _cond k
  z::kv::ttl _cond k
  ztest::assert::eq "-2" "$REPLY" "reaped keys report -2"
}

# -----------------------------------------------------------------------------
# Multi-key operations
# -----------------------------------------------------------------------------

test_zkv_mset_requires_paired_arguments() {
  ztest::assert::returns 0 z::kv::mset _cond a "1" b "2"
  ztest::assert::returns $Z_ERR_INPUT z::kv::mset _cond orphan
  ztest::assert::returns 1 z::kv::exists _cond orphan
}

test_zkv_mget_keeps_slots_in_order_with_blanks_for_missing() {
  z::kv::mset _cond x1 "v1" x2 "v2"
  z::kv::mget _cond x1 ghost x2
  ztest::assert::eq "3" "${#reply}"
  ztest::assert::eq "v1" "${reply[1]}"
  ztest::assert::eq "" "${reply[2]}" "missing key yields an empty slot"
  ztest::assert::eq "v2" "${reply[3]}"
}

# -----------------------------------------------------------------------------
# Indexed list access
# -----------------------------------------------------------------------------

test_zkv_lindex_reads_from_either_end() {
  z::kv::rpush _cond l "a"
  z::kv::rpush _cond l "b"
  z::kv::rpush _cond l "c"
  z::kv::lindex _cond l 0
  ztest::assert::eq "a" "$REPLY"
  z::kv::lindex _cond l -1
  ztest::assert::eq "c" "$REPLY" "negative indices count from the end"
  z::kv::lindex _cond l -3
  ztest::assert::eq "a" "$REPLY"
  ztest::assert::returns $Z_ERR_NOTFOUND z::kv::lindex _cond l 3
}

test_zkv_lset_replaces_by_index_and_rejects_oob() {
  z::kv::rpush _cond l "a"
  z::kv::rpush _cond l "b"
  z::kv::rpush _cond l "c"
  ztest::assert::returns 0 z::kv::lset _cond l 1 "X"
  ztest::assert::returns 0 z::kv::lset _cond l -1 "Z"
  z::kv::lrange _cond l 0 -1
  ztest::assert::eq "a X Z" "${reply[*]}"
  ztest::assert::returns $Z_ERR_INPUT z::kv::lset _cond l 9 "v"
  ztest::assert::returns $Z_ERR_NOTFOUND z::kv::lset _cond missing 0 "v"
  ztest::assert::returns $Z_ERR_INPUT z::kv::lset _cond l 0 ""
}

# Standalone execution; under the runner ztest::run is called by the runner.
(( ${ZTEST_RUNNER:-0} )) || ztest::run "${1:-test_*}"
