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
