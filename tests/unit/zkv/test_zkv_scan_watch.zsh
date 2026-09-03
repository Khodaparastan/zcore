#!/usr/bin/env zsh
# =============================================================================
# test_zkv_scan_watch.zsh — Key-space navigation and watchers
# =============================================================================
# Description:  Covers the key-space traversal surface — keys with glob
#               patterns, cursor-based scan paging, and randomkey — plus
#               the observer surface: watch/unwatch registration, handler
#               payloads on set and del, pattern scoping, multiple handlers
#               per pattern, and the z::is::func guard on registration.
#
# Usage:        zsh tests/run_tests.zsh zkv
#               zsh tests/unit/zkv/test_zkv_scan_watch.zsh   # standalone
#
# Covers:       z::kv::keys, z::kv::scan, z::kv::randomkey, z::kv::watch,
#               z::kv::unwatch, z::kv::set, z::kv::del
#
# Requires:     zkv — loaded by ztest::require below
# =============================================================================

source "${0:A:h}/../../bootstrap.zsh"
ztest::require zkv

test_setup() { z::kv::open _scan }
test_teardown() { z::kv::close _scan }

# -----------------------------------------------------------------------------
# Key-space navigation
# -----------------------------------------------------------------------------

test_zkv_keys_matches_a_glob_pattern() {
  z::kv::set _scan "alpha" "1"
  z::kv::set _scan "beta" "1"
  z::kv::set _scan "gamma" "1"
  z::kv::keys _scan
  ztest::assert::eq "3" "${#reply}" "default pattern is *"
  z::kv::keys _scan "a*"
  ztest::assert::eq "alpha" "${reply[*]}"
  z::kv::keys _scan "zzz*"
  ztest::assert::eq "0" "${#reply}" "unmatched pattern yields an empty reply"
}

# Regression: scan must iterate the store's meta map, not the literal name
# of that map. A missing (P) indirection used to yield a phantom
# "_zkv_meta_<handle>" key on every call.
test_zkv_scan_returns_real_keys_in_sorted_pages() {
  z::kv::set _scan "delta" "1"
  z::kv::set _scan "alpha" "1"
  z::kv::set _scan "beta" "1"
  z::kv::set _scan "gamma" "1"
  z::kv::scan _scan 0 "*" 2
  ztest::assert::eq "0" "$?"
  ztest::assert::eq "2" "$REPLY" "cursor advances by one page"
  ztest::assert::eq "alpha beta" "${reply[*]}" "first page in sorted order"
  z::kv::scan _scan "$REPLY" "*" 2
  ztest::assert::eq "0" "$REPLY" "final page reports cursor 0"
  ztest::assert::eq "delta gamma" "${reply[*]}"
}

test_zkv_scan_applies_pattern_and_validates_bounds() {
  z::kv::set _scan "apple" "1"
  z::kv::set _scan "apricot" "1"
  z::kv::set _scan "pear" "1"
  z::kv::scan _scan 0 "ap*" 10
  ztest::assert::eq "apple apricot" "${reply[*]}" "pattern filters the page"
  ztest::assert::returns $Z_ERR_INPUT z::kv::scan _scan -1 "*" 1
  ztest::assert::returns $Z_ERR_INPUT z::kv::scan _scan 0 "*" 0
}

test_zkv_randomkey_returns_a_live_key_and_rejects_an_empty_store() {
  z::kv::set _scan "only" "1"
  z::kv::randomkey _scan
  ztest::assert::eq "only" "$REPLY" "a single-key store pins the choice"
  z::kv::open _scan_empty
  ztest::assert::returns $Z_ERR_NOTFOUND z::kv::randomkey _scan_empty
  z::kv::close _scan_empty
}

# -----------------------------------------------------------------------------
# Watchers
# -----------------------------------------------------------------------------

test_zkv_watch_fires_with_key_value_and_operation() {
  typeset -ga _events=()
  _ev_h() { _events+=("$2|$3|$4"); }
  z::kv::watch _scan "user.*" _ev_h
  z::kv::set _scan "user.1" "alice"
  z::kv::del _scan "user.1"
  ztest::assert::eq "user.1|alice|set user.1|alice|del" "${_events[*]}"
}

test_zkv_watch_pattern_only_fires_for_matching_keys() {
  typeset -gi _fired=0
  _scoped_h() { (( _fired += 1 )); }
  z::kv::watch _scan "user.*" _scoped_h
  z::kv::set _scan "user.x" "1"
  z::kv::set _scan "admin.x" "1"
  ztest::assert::eq "1" "$_fired" "non-matching keys must not fire the handler"
}

test_zkv_watch_supports_multiple_handlers_per_pattern() {
  typeset -ga _calls=()
  _h_a() { _calls+=("a"); }
  _h_b() { _calls+=("b"); }
  z::kv::watch _scan "k" _h_a
  z::kv::watch _scan "k" _h_b
  z::kv::set _scan "k" "v"
  ztest::assert::eq "a b" "${_calls[*]}"
}

test_zkv_watch_rejects_an_undefined_handler() {
  ztest::assert::returns $Z_ERR_NOTFOUND z::kv::watch _scan "k" _no_such_fn
}

test_zkv_watch_star_matches_everything() {
  # The catalog pattern "*" is a pure-glob key; the store must accept it
  # without treating it as an associative-array subscript slice.
  typeset -gi _fired=0
  _star_h() { (( _fired += 1 )); }
  ztest::assert::returns 0 z::kv::watch _scan "*" _star_h
  z::kv::set _scan "any.key" "v"
  z::kv::set _scan "other" "v"
  z::kv::del _scan "other"
  ztest::assert::eq "3" "$_fired"
}

test_zkv_unwatch_removes_one_handler_or_all() {
  typeset -ga _left=()
  _keep_h() { _left+=("keep"); }
  _drop_h() { _left+=("drop"); }
  z::kv::watch _scan "k" _keep_h
  z::kv::watch _scan "k" _drop_h
  z::kv::unwatch _scan "k" _drop_h
  z::kv::set _scan "k" "v"
  ztest::assert::eq "keep" "${_left[*]}" "only the removed handler is gone"

  z::kv::unwatch _scan "k"
  _left=()
  z::kv::set _scan "k" "v2"
  ztest::assert::eq "0" "${#_left}" "no handlers remain after unwatch-all"
}

test_zkv_unwatch_reports_a_missing_pattern() {
  _h() { :; }
  z::kv::watch _scan "k" _h
  ztest::assert::returns $Z_ERR_NOTFOUND z::kv::unwatch _scan "ghost.*" _h
  ztest::assert::returns 0 z::kv::unwatch _scan "ghost.*"
}

# Standalone execution; under the runner ztest::run is called by the runner.
(( ${ZTEST_RUNNER:-0} )) || ztest::run "${1:-test_*}"
