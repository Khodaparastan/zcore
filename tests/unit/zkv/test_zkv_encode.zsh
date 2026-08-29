test_setup_all() {
  z::kv::open _enc_test
}

test_teardown_all() {
  z::kv::close _enc_test 2>/dev/null
}

# ─── The regression that caused this whole thing ─────────────────────────
test_zkv_encode_backslash_roundtrip() {
  local original='path\to\file'
  _z::kv::encode_value "$original"
  local encoded="$REPLY"
  _z::kv::decode_value "$encoded"
  ztest::assert::eq "$original" "$REPLY" "backslash roundtrip (v3 bug)"
}

test_zkv_encode_all_dangerous_chars() {
  # Use literal chars via $'…' escapes
  local original="line1"$'\n'"line2|pipe"$'\\'"backslash"${Z_SEP}"sep"${Z_RECSEP}"rec"${Z_ESC}"esc"
  _z::kv::encode_value "$original"
  local encoded="$REPLY"
  _z::kv::decode_value "$encoded"
  ztest::assert::eq "$original" "$REPLY" "all dangerous chars roundtrip"
}

test_zkv_encode_empty() {
  _z::kv::encode_value ""
  ztest::assert::eq "" "$REPLY"
  _z::kv::decode_value ""
  ztest::assert::eq "" "$REPLY"
}

test_zkv_encode_only_escape_byte() {
  local original="${Z_ESC}${Z_ESC}${Z_ESC}"
  _z::kv::encode_value "$original"
  _z::kv::decode_value "$REPLY"
  ztest::assert::eq "$original" "$REPLY" "ESC-heavy roundtrip"
}

test_zkv_encode_persist_load_backslash() {
  local tmp=$(mktemp -t zkv.XXXX)
  z::kv::set _enc_test "wpath" 'C:\Users\test\file.txt'
  z::kv::save _enc_test "$tmp"
  z::kv::clear _enc_test
  z::kv::load _enc_test "$tmp"
  z::kv::get _enc_test "wpath"
  ztest::assert::eq 'C:\Users\test\file.txt' "$REPLY" "Windows-path persistence"
  rm -f "$tmp"
}

test_zkv_encode_fuzz_random_strings() {
  local i original
  for (( i = 0; i < 50; i++ )); do
    # Construct values mixing dangerous bytes randomly
    original=""
    local j
    for (( j = 0; j < $(( RANDOM % 30 + 1 )); j++ )); do
      case $(( RANDOM % 8 )) in
        0) original+=$'\n' ;;
        1) original+=$'\\' ;;
        2) original+="|" ;;
        3) original+="${Z_SEP}" ;;
        4) original+="${Z_RECSEP}" ;;
        5) original+="${Z_ESC}" ;;
        6) original+="a" ;;
        7) original+=" " ;;
      esac
    done
    _z::kv::encode_value "$original"
    _z::kv::decode_value "$REPLY"
    if [[ "$original" != "$REPLY" ]]; then
      ztest::fail "fuzz iter $i: roundtrip mismatch for length ${#original}"
      return 1
    fi
  done
  return 0
}
