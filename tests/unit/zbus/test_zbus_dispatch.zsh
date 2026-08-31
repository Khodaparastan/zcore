#!/usr/bin/env zsh
# =============================================================================
# test_zbus_dispatch.zsh — Handler registration and dispatch order
# =============================================================================
# Description:  Covers how handlers are selected and run for an emit:
#               descending priority order, --once handlers unsubscribing
#               themselves after their first delivery, wildcard patterns
#               matching only the intended events, emit_safe continuing past
#               a handler that fails (observed via a temp-file probe because
#               the fork hides variable mutations), and the two unsubscribe
#               paths — off, which reports how many handlers it removed, and
#               off_id, which removes the single handler whose id was
#               returned by on.
#
# Usage:        zsh tests/run_tests.zsh zbus
#               zsh tests/unit/zbus/test_zbus_dispatch.zsh    # standalone
#
# Covers:       z::bus::init, z::bus::reset, z::bus::on, z::bus::off,
#               z::bus::off_id, z::bus::count, z::bus::emit,
#               z::bus::emit_safe
#
# Requires:     zbus — loaded by ztest::require below
# =============================================================================

source "${0:A:h}/../../bootstrap.zsh"
ztest::require zbus

test_setup() { z::bus::reset; z::bus::init }

# Registered out of order on purpose: dispatch order must follow priority,
# not registration.
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

# emit_safe forks each handler, so a probe that survives the fork is a
# temp file rather than a variable. The path is passed as an emit arg so
# the child does not depend on the caller's locals.
_zbus_emit_safe_isolation() {
  local crash_prio="$1" good_prio="$2"
  local probe failed
  probe="$(mktemp -t zcore_zbus_probe.XXXXXX)" \
    || { ztest::fail "cannot create probe file"; return 1; }
  command rm -f -- "$probe"

  _crashing_h() { return 1; }
  _good_h() { : >| "$2"; }

  z::bus::on "evt" _crashing_h --priority "$crash_prio"
  z::bus::on "evt" _good_h     --priority "$good_prio"
  z::bus::emit_safe "evt" "$probe" || true
  failed="$REPLY"

  ztest::assert::eq "1" "$failed" "emit_safe reports exactly one failed handler"
  ztest::assert::file_exists "$probe" "surviving handler ran despite crash"
  command rm -f -- "$probe"
}

# High-priority handler fails; the lower-priority one must still run.
test_zbus_emit_safe_survives_handler_crash() {
  _zbus_emit_safe_isolation 80 20
}

# Isolation is independent of order: a later crash must not rewind a
# handler that already ran.
test_zbus_emit_safe_survives_later_handler_crash() {
  _zbus_emit_safe_isolation 20 80
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

# Standalone execution; under the runner ztest::run is called by the runner.
(( ${ZTEST_RUNNER:-0} )) || ztest::run "${1:-test_*}"
