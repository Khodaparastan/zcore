test_zkv_persist_save_load_roundtrip() {
  local tmp=$(mktemp -t zkv.XXXX)
  z::kv::open _ps_a
  z::kv::set _ps_a "k1" "v1"
  z::kv::set_int _ps_a "n" "42"
  z::kv::lpush _ps_a "list" "a"
  z::kv::lpush _ps_a "list" "b"
  z::kv::sadd _ps_a "set" "m1"
  z::kv::hset _ps_a "hash" "f" "hv"
  z::kv::save _ps_a "$tmp"
  z::kv::close _ps_a

  z::kv::open _ps_b
  z::kv::load _ps_b "$tmp"
  z::kv::get _ps_b "k1"
  ztest::assert::eq "v1" "$REPLY"
  z::kv::get_int _ps_b "n"
  ztest::assert::eq "42" "$REPLY"
  z::kv::llen _ps_b "list"
  ztest::assert::eq "2" "$REPLY"
  z::kv::sismember _ps_b "set" "m1"
  ztest::assert::eq "0" "$?"
  z::kv::hget _ps_b "hash" "f"
  ztest::assert::eq "hv" "$REPLY"
  z::kv::close _ps_b
  rm -f "$tmp"
}

test_zkv_persist_load_rejects_future_version() {
  local tmp=$(mktemp -t zkv.XXXX)
  cat > "$tmp" <<EOF
# zkv store dump
# version: 999

S|k|string|0|v
EOF
  z::kv::open _ps_v
  ztest::assert::returns $ZBASE_ERROR_GENERAL z::kv::load _ps_v "$tmp"
  z::kv::close _ps_v
  rm -f "$tmp"
}

test_zkv_persist_save_load_dangerous_chars() {
  # Regression: this is exactly the scenario the v3 backslash bug corrupted
  local tmp=$(mktemp -t zkv.XXXX)
  local val='line1
line2|pipe\backslash'
  z::kv::open _ps_d
  z::kv::set _ps_d "k" "$val"
  z::kv::save _ps_d "$tmp"
  z::kv::clear _ps_d
  z::kv::load _ps_d "$tmp"
  z::kv::get _ps_d "k"
  ztest::assert::eq "$val" "$REPLY" "dangerous-char persistence"
  z::kv::close _ps_d
  rm -f "$tmp"
}
