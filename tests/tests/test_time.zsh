test_time_epoch_is_integer() {
  local -a match mbegin mend
  z::time::epoch
  ztest::assert::true [[ $REPLY =~ '^[0-9]+$' ]] || true
  (( REPLY > 1700000000 )) || ztest::fail "expected REPLY > 1700000000, got $REPLY"   # post-2023
}

test_time_epoch_ms_has_more_precision() {
  z::time::epoch;    local s=$REPLY
  z::time::epoch_ms; local ms=$REPLY
  local -a match mbegin mend
  ztest::assert::true [[ $ms =~ '^[0-9]+$' ]] || true
  # ms should be in the same ballpark as s*1000 (within 2s drift)
  local diff=$(( ms - s * 1000 ))
  (( diff < 0 )) && (( diff = -diff ))
  (( diff < 2000 )) || ztest::fail "expected diff < 2000, got $diff"
}

test_time_epoch_ms_monotonic() {
  z::time::epoch_ms; local a=$REPLY
  z::time::epoch_ms; local b=$REPLY
  (( b >= a )) || ztest::fail "epoch_ms went backwards: a=$a b=$b"
}

test_time_epoch_ns_more_digits_than_ms() {
  z::time::epoch_ms; local ms_len=${#REPLY}
  z::time::epoch_ns; local ns_len=${#REPLY}
  ztest::assert::eq 6 "$(( ns_len - ms_len ))" "ns should have 6 more digits than ms"
}
