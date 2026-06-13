test_setup() { z::bus::reset; z::bus::init }

test_zbus_priority_ordering() {
  typeset -ga _calls=()
  _h_low()  { _calls+=("low"); }
  _h_high() { _calls+=("high"); }
  _h_norm() { _calls+=("norm"); }
  z::bus::on "evt" _h_low  --priority 10
  z::bus::on "evt" _h_high --priority 90
  z::bus::on "evt" _h_norm --priority 50
  z::bus::emit "evt"
  ztest::assert::eq "high norm low" "${_calls[*]}"
}

test_zbus_once_handler_removed_after_first() {
  typeset -gi _once_count=0
  _once_h() { (( _once_count += 1 )); }
  z::bus::on "evt" _once_h --once
  z::bus::emit "evt"
  z::bus::emit "evt"
  z::bus::emit "evt"
  ztest::assert::eq "1" "$_once_count"
}

test_zbus_wildcard_matches() {
  typeset -gi _wc_count=0
  _wc_h() { (( _wc_count += 1 )); }
  z::bus::on "user.*" _wc_h
  z::bus::emit "user.login"
  z::bus::emit "user.logout"
  z::bus::emit "order.placed"
  ztest::assert::eq "2" "$_wc_count"
}

test_zbus_emit_safe_survives_handler_crash() {
  _crashing_h() { return 1; }
  _good_h() { typeset -gi _good_ran=1; }
  z::bus::on "evt" _crashing_h --priority 80
  z::bus::on "evt" _good_h     --priority 20
  z::bus::emit_safe "evt" || true
  ztest::assert::eq "1" "$_good_ran" "later handler ran despite earlier crash"
}

test_zbus_off_returns_count() {
  _h1() { :; }; _h2() { :; }
  z::bus::on "evt" _h1
  z::bus::on "evt" _h2
  z::bus::off "evt"
  ztest::assert::eq "2" "$REPLY"
}

test_zbus_off_id_specific() {
  _h() { :; }
  z::bus::on "evt" _h
  local hid="$REPLY"
  z::bus::on "evt" _h
  ztest::assert::returns 0 z::bus::off_id "$hid"
  z::bus::count "evt"
  ztest::assert::eq "1" "$REPLY"
}
