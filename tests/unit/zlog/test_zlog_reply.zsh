#!/usr/bin/env zsh
# =============================================================================
# test_zlog_reply.zsh — zlog must not disturb the shared return channel
# =============================================================================
# Description:  REPLY and reply are the framework's universal return channel,
#               so a function that sets a return value and then logs before
#               returning would hand back a log line instead. This suite
#               pins the invariant: every emit-path zlog call leaves both
#               channels byte-identical, at every log level.
#
#               The level sweep is the point. The defect this guards was
#               invisible at level error — a filtered message returns early
#               and never touches REPLY — and only appeared once a message
#               actually emitted. ztest::require pins the level to error, so
#               each test sets the level it wants explicitly rather than
#               inheriting the one configuration where the bug is dormant.
#
#               The accessor cases are the other half: with_context and
#               friends return through REPLY by contract, so they prove the
#               fix was not over-applied.
#
#               zlog is a git submodule, so this suite is also the tripwire
#               that fails here if a future submodule bump reintroduces the
#               clobber.
#
# Usage:        zsh tests/run_tests.zsh zlog
#               zsh tests/unit/zlog/test_zlog_reply.zsh    # standalone
#
# Covers:       zlog::error, zlog::warn, zlog::info, zlog::debug, zlog::log,
#               zlog::errorf, zlog::warnf, zlog::infof, zlog::debugf,
#               zlog::always, zlog::once, zlog::rate_limit,
#               zlog::with_context, zlog::remove_context,
#               zlog::get_timestamp, z::kv::snapshot_create,
#               z::kv::snapshot_restore
#
# Requires:     zlog, zkv — loaded by ztest::require below
# =============================================================================

source "${0:A:h}/../../bootstrap.zsh"
ztest::require zlog zkv

typeset -g ZTEST_SENTINEL="zcore-return-channel-sentinel"
typeset -ga ZTEST_LEVELS=( debug info warn error )

# _neutral <label> <command> [args ...]
# Seed both return channels, run the command with all output discarded, and
# assert neither channel moved. Output is discarded rather than captured
# because a passing emit still writes a full log line to stderr.
_neutral() {
  local label="$1"
  shift

  REPLY="$ZTEST_SENTINEL"
  reply=( alpha beta gamma )

  "$@" >/dev/null 2>/dev/null

  ztest::assert::eq "$ZTEST_SENTINEL" "$REPLY"        "$label — REPLY"
  ztest::assert::eq "alpha beta gamma" "${reply[*]}"  "$label — reply"
}

# The four level-named entry points, swept across every level, so both the
# filtered path and the emitting path are exercised for each one.
test_zlog_level_functions_preserve_reply() {
  local level fn
  for level in "${ZTEST_LEVELS[@]}"; do
    zlog::set_level "$level"
    for fn in error warn info debug; do
      _neutral "${level}/zlog::${fn}" zlog::${fn} "message" key value
    done
  done
}

# zlog::log resolves its level through __zlog::level_number, which itself
# returns via REPLY — the shadowed copy must satisfy that without leaking.
test_zlog_log_preserves_reply() {
  local level target
  for level in "${ZTEST_LEVELS[@]}"; do
    zlog::set_level "$level"
    for target in error warn info debug; do
      _neutral "${level}/zlog::log ${target}" zlog::log "$target" "message" key value
    done
  done
}

test_zlog_printf_variants_preserve_reply() {
  local level fn
  for level in "${ZTEST_LEVELS[@]}"; do
    zlog::set_level "$level"
    for fn in errorf warnf infof debugf; do
      _neutral "${level}/zlog::${fn}" zlog::${fn} "value is %s (%d)" "x" 7
    done
  done
}

# always forces the level to error internally, so it emits at every setting.
test_zlog_always_preserves_reply() {
  local level
  for level in "${ZTEST_LEVELS[@]}"; do
    zlog::set_level "$level"
    _neutral "${level}/zlog::always" zlog::always "critical" key value
  done
}

# Both the first (emitting) call and the suppressed second call must be
# neutral — the two take different paths through once.
test_zlog_once_preserves_reply_on_both_paths() {
  local level
  for level in "${ZTEST_LEVELS[@]}"; do
    zlog::set_level "$level"
    _neutral "${level}/zlog::once first"  zlog::once "k-${level}" info "message"
    _neutral "${level}/zlog::once repeat" zlog::once "k-${level}" info "message"
  done
}

# Same idea for rate_limit: under the limit it logs, over it drops.
test_zlog_rate_limit_preserves_reply_on_both_paths() {
  local level
  typeset -i i
  for level in "${ZTEST_LEVELS[@]}"; do
    zlog::set_level "$level"
    for i in 1 2 3; do
      _neutral "${level}/zlog::rate_limit ${i}" \
        zlog::rate_limit "rk-${level}" 2 60 info "message"
    done
  done
}

# The other half of the contract: accessors are supposed to write REPLY, and
# scoping must not have been applied to them.
test_zlog_accessors_still_return_via_reply() {
  zlog::set_level debug

  REPLY="$ZTEST_SENTINEL"
  zlog::with_context "trusted_eval" "label" >/dev/null 2>/dev/null
  local ctx="$REPLY"
  ztest::assert::ne "$ZTEST_SENTINEL" "$ctx" "with_context must return an id"
  ztest::assert::ne "" "$ctx" "with_context id must be non-empty"
  zlog::remove_context "$ctx" >/dev/null 2>/dev/null

  REPLY="$ZTEST_SENTINEL"
  zlog::get_timestamp "human" >/dev/null 2>/dev/null
  ztest::assert::ne "$ZTEST_SENTINEL" "$REPLY" "get_timestamp must return a stamp"
}

# The live symptom that exposed the defect: snapshot_create documents that it
# returns the snapshot id in REPLY, and it logs at info before returning. At
# the default level the id used to come back as a log line, so the follow-on
# restore failed. Behaviour must not depend on verbosity.
test_zkv_snapshot_roundtrip_at_every_log_level() {
  local level handle snap
  for level in "${ZTEST_LEVELS[@]}"; do
    zlog::set_level "$level"

    handle="snapshot_${level}"
    z::kv::open "$handle" >/dev/null 2>/dev/null
    z::kv::set "$handle" answer original >/dev/null 2>/dev/null

    z::kv::snapshot_create "$handle" >/dev/null 2>/dev/null
    snap="$REPLY"
    ztest::assert::eq "snap_1" "$snap" "${level} — snapshot id in REPLY"

    z::kv::set "$handle" answer changed >/dev/null 2>/dev/null
    ztest::assert::returns 0 z::kv::snapshot_restore "$handle" "$snap"

    z::kv::get "$handle" answer >/dev/null 2>/dev/null
    ztest::assert::eq "original" "$REPLY" "${level} — value restored"
  done
}

# Standalone execution; under the runner ztest::run is called by the runner.
(( ${ZTEST_RUNNER:-0} )) || ztest::run "${1:-test_*}"
