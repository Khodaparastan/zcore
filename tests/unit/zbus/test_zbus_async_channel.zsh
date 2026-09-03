#!/usr/bin/env zsh
# =============================================================================
# test_zbus_async_channel.zsh — Async dispatch and channels
# =============================================================================
# Description:  Covers the two delivery paths the synchronous suite does
#               not touch: emit_async/wait_all_async background dispatch
#               (including failure reporting through the wait status), and
#               the channel triad subscribe/unsubscribe/publish with its
#               duplicate and stale-handler edges. Also pins the
#               introspection queries has/count/handlers and the batched
#               off paths against wildcard registrations.
#
# Usage:        zsh tests/run_tests.zsh zbus
#               zsh tests/unit/zbus/test_zbus_async_channel.zsh  # standalone
#
# Covers:       z::bus::emit_async, z::bus::wait_all_async, z::bus::on,
#               z::bus::subscribe, z::bus::unsubscribe, z::bus::publish,
#               z::bus::has, z::bus::count, z::bus::handlers, z::bus::off
#
# Requires:     zbus — loaded by ztest::require below
# =============================================================================

source "${0:A:h}/../../bootstrap.zsh"
ztest::require zbus

test_setup() { z::bus::reset; z::bus::init }

# -----------------------------------------------------------------------------
# Async dispatch
# -----------------------------------------------------------------------------

test_zbus_emit_async_runs_the_handler_and_wait_collects_it() {
  local probe="$(mktemp -t zbus_async.XXXXXX)" || {
    ztest::fail "cannot create probe file"; return 1
  }
  command rm -f -- "$probe"

  _async_h() { : >| "$2"; }
  z::bus::on "evt" _async_h
  z::bus::emit_async "evt" "$probe"
  ztest::assert::eq "0" "$?"
  ztest::assert::matches "$REPLY" '<->' "reply carries the dispatcher PID"
  ztest::assert::returns 0 z::bus::wait_all_async
  ztest::assert::file_exists "$probe" "backgrounded handler actually ran"
  ztest::assert::returns 0 z::bus::wait_all_async "second wait is idempotent"
  command rm -f -- "$probe"
}

test_zbus_emit_async_reports_failed_handlers_via_wait() {
  _failing_h() { return 7; }
  z::bus::on "evt" _failing_h
  z::bus::emit_async "evt"
  ztest::assert::eq "0" "$?"
  # The backgrounded synchronous dispatch exits with the number of handlers
  # that failed, which wait_all_async surfaces as its return status.
  ztest::assert::returns 1 z::bus::wait_all_async
}

# -----------------------------------------------------------------------------
# Channels
# -----------------------------------------------------------------------------

test_zbus_subscribe_and_publish_deliver_the_message() {
  typeset -ga _received=()
  _chan_h() { _received+=("$1=$2"); }
  z::bus::subscribe "chan" _chan_h
  z::bus::publish "chan" "hello"
  ztest::assert::eq "chan=hello" "${_received[*]}"
}

test_zbus_subscribe_ignores_duplicates() {
  typeset -gi _count=0
  _dup_h() { (( _count += 1 )); }
  z::bus::subscribe "chan" _dup_h
  z::bus::subscribe "chan" _dup_h
  z::bus::publish "chan" "m"
  ztest::assert::eq "1" "$_count" "a duplicated subscriber must run once"
}

test_zbus_publish_skips_stale_handlers_and_empty_channels() {
  typeset -gi _healthy=0
  _stale_h() { :; }
  _healthy_h() { (( _healthy += 1 )); }
  z::bus::subscribe "chan" _stale_h
  z::bus::subscribe "chan" _healthy_h
  unset -f _stale_h
  z::bus::publish "chan" "m"
  ztest::assert::eq "1" "$_healthy" "the defined subscriber still runs"
  z::bus::publish "empty" "m"
  ztest::assert::eq "0" "$?" "publishing to an empty channel is a no-op"
}

test_zbus_unsubscribe_removes_one_subscriber_or_all() {
  typeset -gi _left=0
  _keep_h() { (( _left += 1 )); }
  _drop_h() { (( _left += 1 )); }
  z::bus::subscribe "chan" _keep_h
  z::bus::subscribe "chan" _drop_h
  z::bus::unsubscribe "chan" _drop_h
  z::bus::publish "chan" "m"
  ztest::assert::eq "1" "$_left" "only the removed subscriber is gone"

  z::bus::unsubscribe "chan"
  _left=0
  z::bus::publish "chan" "m"
  ztest::assert::eq "0" "$_left" "unsubscribe-all empties the channel"
}

test_zbus_unsubscribe_reports_a_missing_channel() {
  _h() { :; }
  ztest::assert::returns 0 z::bus::subscribe "chan" _h
  ztest::assert::returns $Z_ERR_NOTFOUND z::bus::unsubscribe "empty" _h
}

# -----------------------------------------------------------------------------
# Introspection and batched unsubscribe
# -----------------------------------------------------------------------------

test_zbus_has_and_count_include_wildcard_handlers() {
  _g1() { :; }
  _g2() { :; }
  z::bus::on "app.one" _g1
  z::bus::on "app.*" _g2
  ztest::assert::returns 0 z::bus::has "app.one"
  ztest::assert::returns 1 z::bus::has "other"
  z::bus::count "app.one"
  ztest::assert::eq "2" "$REPLY" "exact and wildcard handlers both counted"
}

test_zbus_handlers_lists_ids_in_priority_order() {
  _low() { :; }
  _high() { :; }
  z::bus::on "evt" _low --priority 10
  local low_id="$REPLY"
  z::bus::on "evt" _high --priority 90
  local high_id="$REPLY"
  z::bus::handlers "evt"
  ztest::assert::eq "$high_id $low_id" "${reply[*]}"
}

test_zbus_off_batches_across_pattern_forms() {
  _h() { :; }
  z::bus::on "app.one" _h
  z::bus::on "app.*" _h
  z::bus::off "app.*"
  ztest::assert::eq "2" "$REPLY" "off returns the number of removed handlers"
  z::bus::count "app.one"
  ztest::assert::eq "0" "$REPLY" "exact and wildcard handlers both removed"
  ztest::assert::returns $Z_ERR_NOTFOUND z::bus::off "app.*"
}

test_zbus_off_with_a_function_filter_removes_only_that_function() {
  _a() { :; }
  _b() { :; }
  z::bus::on "evt" _a
  z::bus::on "evt" _b
  z::bus::off "evt" _a
  ztest::assert::eq "1" "$REPLY"
  z::bus::count "evt"
  ztest::assert::eq "1" "$REPLY"
}

# Standalone execution; under the runner ztest::run is called by the runner.
(( ${ZTEST_RUNNER:-0} )) || ztest::run "${1:-test_*}"
