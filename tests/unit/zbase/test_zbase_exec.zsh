#!/usr/bin/env zsh
# =============================================================================
# test_zbase_exec.zsh — Function invocation and background execution
# =============================================================================
# Description:  Covers the unexplored execution surface of zbase: the
#               z::do::call dispatch wrapper (status and argument
#               propagation, error codes for missing names), and the async
#               job lifecycle z::do::run_async/z::do::wait. Because the
#               callback runs inside the forked child, its observations are
#               captured through temp files whose paths the child inherits.
#
# Usage:        zsh tests/run_tests.zsh zbase
#               zsh tests/unit/zbase/test_zbase_exec.zsh      # standalone
#
# Covers:       z::do::call, z::do::run_async, z::do::wait
#
# Requires:     zbase — loaded by ztest::require below
# =============================================================================

source "${0:A:h}/../../bootstrap.zsh"
ztest::require zbase

test_zbase_call_preserves_status_and_reply() {
  _probe_fn() { REPLY="seen:$1"; return 3; }
  z::do::call _probe_fn "arg1"
  ztest::assert::eq "3" "$?" "callee status passes through unchanged"
  ztest::assert::eq "seen:arg1" "$REPLY" "argument reached the callee"
}

test_zbase_call_rejects_missing_and_empty_names() {
  ztest::assert::returns $Z_ERR_NOTFOUND z::do::call _no_such_fn
  ztest::assert::returns $Z_ERR_INPUT z::do::call ""
}

test_zbase_run_async_waits_and_callback_sees_output() {
  local rc_out="$(mktemp -t zbase_cb.XXXXXX)" || {
    ztest::fail "cannot create callback probe"; return 1
  }
  local out_out="$(mktemp -t zbase_out.XXXXXX)"

  _async_cb() { print -r -- "$1" > "$rc_out"; print -r -- "$2" > "$out_out"; }

  z::do::run_async "print -r -- payload" _async_cb
  ztest::assert::eq "0" "$?"
  ztest::assert::matches "$REPLY" '<->' "reply carries the job PID"
  ztest::assert::returns 0 z::do::wait
  ztest::assert::file_exists "$rc_out" "callback observed the job exit"
  ztest::assert::eq "0" "$(cat "$rc_out")" "benign command succeeded"
  ztest::assert::eq "payload" "$(cat "$out_out")" "captured stdout survives"
  command rm -f -- "$rc_out" "$out_out"
}

test_zbase_run_async_callback_sees_a_real_failure() {
  local rc_out="$(mktemp -t zbase_rc.XXXXXX)" || {
    ztest::fail "cannot create callback probe"; return 1
  }

  _fail_cb() { print -r -- "$1" > "$rc_out"; }

  z::do::run_async "false" _fail_cb
  ztest::assert::returns 0 z::do::wait
  ztest::assert::eq "1" "$(cat "$rc_out")" "callback observed exit status 1"
  command rm -f -- "$rc_out"
}

test_zbase_run_async_requires_a_command() {
  ztest::assert::returns $Z_ERR_INPUT z::do::run_async ""
}

test_zbase_wait_with_nothing_pending_is_a_noop() {
  ztest::assert::returns 0 z::do::wait
}

# Standalone execution; under the runner ztest::run is called by the runner.
(( ${ZTEST_RUNNER:-0} )) || ztest::run "${1:-test_*}"
