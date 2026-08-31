#!/usr/bin/env zsh
# =============================================================================
# test_zkv_zset.zsh — Sorted-set score ordering and score validation
# =============================================================================
# Description:  Sorted sets keep members as packed entries prefixed by a
#               19-digit zero-padded sort key, so a lexicographic sort of the
#               entries has to reproduce numeric score order. That invariant
#               collapsed when the sort key was computed with int(), a
#               zsh/mathfunc function no module ever loads: the arithmetic
#               raised "unknown function", every score packed to the same
#               key, and zrange returned insertion order.
#
#               These cases pin the ordering across the sign boundary, over
#               fractional scores and over ties, and assert that no
#               arithmetic diagnostic reaches stderr — a silent regression in
#               the packer would otherwise still look like a plain ordering
#               bug.
#
#               z::kv::lock_wait is here for the same reason: it is the other
#               int() call site, and its poll interval was never computed.
#
# Usage:        zsh tests/run_tests.zsh zkv
#               zsh tests/unit/zkv/test_zkv_zset.zsh    # standalone
#
# Covers:       z::kv::zadd, z::kv::zscore, z::kv::zcard, z::kv::zrange,
#               z::kv::zrange_withscores, z::kv::zrangebyscore, z::kv::zrank,
#               z::kv::zrem, z::kv::lock, z::kv::lock_wait, z::kv::unlock
#
# Requires:     zkv — loaded by ztest::require below
# =============================================================================

source "${0:A:h}/../../bootstrap.zsh"
ztest::require zkv

test_setup() { z::kv::open _zs_test }
test_teardown() { z::kv::close _zs_test }

# _zs_add_all <key> <score> <member> [<score> <member> ...]
# Load a sorted set in one call, returning the combined stderr so a caller can
# assert the arithmetic stayed quiet.
_zs_add_all() {
  local key="$1"
  shift
  {
    while (( $# >= 2 )); do
      z::kv::zadd _zs_test "$key" "$1" "$2" >/dev/null
      shift 2
    done
  } 2>&1
}

test_zkv_zrange_orders_by_score_not_insertion() {
  _zs_add_all "board" 10 x 5 y 20 w >/dev/null

  z::kv::zrange _zs_test "board" 0 -1
  ztest::assert::eq "y x w" "${reply[*]}" "ascending by score"

  z::kv::zrange _zs_test "board" 0 -1 --rev
  ztest::assert::eq "w x y" "${reply[*]}" "descending by score"
}

# The packer used to raise "unknown function: int" on every write. The message
# went to stderr and the operation still returned 0, so only stderr shows it.
test_zkv_zadd_emits_no_arithmetic_error() {
  local captured
  captured="$(_zs_add_all "quiet" 1 a -2.5 b 0 c)"
  ztest::assert::not_contains "$captured" "unknown function"
  ztest::assert::eq "" "$captured" "zadd must be silent on success"
}

# Negative, zero and positive scores share one unsigned key space, so the
# shift into that space is what makes the sign boundary sort correctly.
test_zkv_zrange_spans_the_sign_boundary() {
  _zs_add_all "signed" -5 n5 0 z0 3.5 f35 -0.000001 tiny 2.25 f225 >/dev/null

  z::kv::zrange _zs_test "signed" 0 -1
  ztest::assert::eq "n5 tiny z0 f225 f35" "${reply[*]}"
}

test_zkv_zrange_orders_fractional_scores() {
  _zs_add_all "frac" 1.5 b 1.25 a 1.75 c >/dev/null

  z::kv::zrange _zs_test "frac" 0 -1
  ztest::assert::eq "a b c" "${reply[*]}"
}

# Equal scores must not crash or drop members; they share a sort key, so the
# order among them is settled by the packed entry as a whole.
test_zkv_zrange_handles_equal_score_ties() {
  _zs_add_all "ties" 1 a 1 b 0 c >/dev/null

  z::kv::zcard _zs_test "ties"
  ztest::assert::eq "3" "$REPLY" "no member lost to a tie"

  z::kv::zrange _zs_test "ties" 0 -1
  ztest::assert::eq "c" "${reply[1]}" "the lower score still sorts first"
  ztest::assert::eq "3" "${#reply}"
}

test_zkv_zscore_returns_canonical_six_decimals() {
  _zs_add_all "scores" 10 x 2.5 y >/dev/null

  z::kv::zscore _zs_test "scores" x
  ztest::assert::eq "10.000000" "$REPLY"

  z::kv::zscore _zs_test "scores" y
  ztest::assert::eq "2.500000" "$REPLY"
}

test_zkv_zrange_withscores_interleaves_in_order() {
  _zs_add_all "ws" 100 alice 250 bob >/dev/null

  z::kv::zrange_withscores _zs_test "ws" 0 -1 --rev
  ztest::assert::eq "bob 250.000000 alice 100.000000" "${reply[*]}"
}

test_zkv_zrangebyscore_selects_an_inclusive_window() {
  _zs_add_all "win" 10 x 5 y 20 w -3 v >/dev/null

  z::kv::zrangebyscore _zs_test "win" 5 20
  ztest::assert::eq "y x w" "${reply[*]}" "bounds are inclusive"

  z::kv::zrangebyscore _zs_test "win" -5 0
  ztest::assert::eq "v" "${reply[*]}" "negative window"

  z::kv::zrangebyscore _zs_test "win" 100 200
  ztest::assert::eq "" "${reply[*]}" "empty window"
}

test_zkv_zrank_follows_score_order() {
  _zs_add_all "rank" 10 x 5 y 20 w >/dev/null

  z::kv::zrank _zs_test "rank" y
  ztest::assert::eq "0" "$REPLY" "lowest score ranks first"

  z::kv::zrank _zs_test "rank" w
  ztest::assert::eq "2" "$REPLY"
}

test_zkv_zrem_keeps_the_remainder_ordered() {
  _zs_add_all "rm" 10 x 5 y 20 w >/dev/null

  z::kv::zrem _zs_test "rm" x
  z::kv::zrange _zs_test "rm" 0 -1
  ztest::assert::eq "y w" "${reply[*]}"
}

# A score printf cannot represent must be refused, not stored as 0 — the
# documented contract for zadd is Z_ERR_INPUT on an unrepresentable score.
test_zkv_zadd_rejects_a_non_numeric_score() {
  ztest::assert::returns $Z_ERR_INPUT z::kv::zadd _zs_test "bad" "abc" m
  ztest::assert::returns $Z_ERR_INPUT z::kv::zadd _zs_test "bad" "" m
  ztest::assert::returns $Z_ERR_INPUT z::kv::zadd _zs_test "bad" "1.2.3" m
  ztest::assert::returns $Z_ERR_INPUT z::kv::zadd _zs_test "bad" "5 " m
}

# The documented range is ±999999999999.999999. That bound is not exactly
# representable in a double, so it canonicalises to 1e12 and is accepted;
# anything an order of magnitude beyond it is refused.
test_zkv_zadd_rejects_an_out_of_range_score() {
  ztest::assert::returns $Z_ERR_INPUT z::kv::zadd _zs_test "range" 10000000000000 hi
  ztest::assert::returns $Z_ERR_INPUT z::kv::zadd _zs_test "range" -10000000000000 lo
  ztest::assert::returns $Z_ERR_INPUT z::kv::zadd _zs_test "range" 1e20 huge
  ztest::assert::returns 0 z::kv::zadd _zs_test "range" 999999999999.999999 max
}

test_zkv_zrangebyscore_rejects_a_non_numeric_bound() {
  _zs_add_all "bounds" 1 a >/dev/null
  ztest::assert::returns $Z_ERR_INPUT z::kv::zrangebyscore _zs_test "bounds" abc 10
  ztest::assert::returns $Z_ERR_INPUT z::kv::zrangebyscore _zs_test "bounds" 0 abc
}

# lock_wait is the second int() call site: the poll interval was never
# computed, so the retry loop could not sleep.
test_zkv_lock_wait_acquires_a_free_lock() {
  local captured
  captured="$(z::kv::lock_wait _zs_test "free" 10 3 0.1 2>&1 >/dev/null)"
  ztest::assert::not_contains "$captured" "unknown function"

  z::kv::unlock _zs_test "free"
  ztest::assert::returns 0 z::kv::lock_wait _zs_test "free" 10 3 0.1
}

test_zkv_lock_wait_times_out_on_a_held_lock() {
  z::kv::lock _zs_test "held" 30 owner_a

  local captured
  captured="$(z::kv::lock_wait _zs_test "held" 10 3 0.1 owner_b 2>&1 >/dev/null)"
  ztest::assert::not_contains "$captured" "unknown function"

  ztest::assert::returns $Z_ERR_PERM \
    z::kv::lock_wait _zs_test "held" 10 2 0.1 owner_b
}

# The interval reaches zselect as centiseconds; a sub-second value must
# survive that conversion rather than collapsing to zero and spinning.
test_zkv_lock_wait_honours_its_retry_interval() {
  z::kv::lock _zs_test "slow" 30 owner_a

  local -F started elapsed
  started=$EPOCHREALTIME
  z::kv::lock_wait _zs_test "slow" 10 3 0.1 owner_b >/dev/null 2>&1
  elapsed=$(( EPOCHREALTIME - started ))

  # Two waits of 0.1 s between three attempts; the upper bound catches a
  # fallback to whole-second sleeps.
  ztest::assert::true _zs_between "$elapsed" 0.1 2.0
}

# Arithmetic comparison as a callable, since assert::true takes argv.
_zs_between() {
  local -F value="$1" low="$2" high="$3"
  (( value >= low && value <= high ))
}

test_zkv_lock_wait_rejects_a_malformed_interval() {
  ztest::assert::returns $Z_ERR_INPUT \
    z::kv::lock_wait _zs_test "bad_interval" 10 3 "abc"
}

# Standalone execution; under the runner ztest::run is called by the runner.
(( ${ZTEST_RUNNER:-0} )) || ztest::run "${1:-test_*}"
