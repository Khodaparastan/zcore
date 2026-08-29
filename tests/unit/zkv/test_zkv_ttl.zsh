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
