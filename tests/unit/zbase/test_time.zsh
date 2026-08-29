_time_is_digits() { [[ ${1:-} =~ '^[0-9]+$' ]]; }

test_time_epoch_is_integer() {
  z::get::epoch
  ztest::assert::true _time_is_digits "$REPLY"
  (( REPLY > 1700000000 )) || ztest::fail "expected REPLY > 1700000000, got $REPLY"   # post-2023
}

test_time_epoch_ms_has_more_precision() {
  z::get::epoch;    local s=$REPLY
  z::get::epoch_ms; local ms=$REPLY
  ztest::assert::true _time_is_digits "$ms"
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
