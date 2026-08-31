#!/usr/bin/env zsh
# =============================================================================
# test_z_core.zsh — Integration-layer invariants
# =============================================================================
# Description:  Guards the parts of z that tie the other modules together:
#               the version constant agreeing with ./VERSION, platform
#               detection staying correct when the cache behind it is
#               evicted, argument guards on the cache API, cache and TTL
#               round trips, the fatal path (z::sys::die) validating its exit
#               code and behaving differently in interactive and
#               non-interactive shells, the debug assertion rejecting
#               non-integer conditions, and config save/load reporting write
#               failures and validating typed keys.
#
# Usage:        zsh tests/run_tests.zsh z
#               zsh tests/unit/z/test_z_core.zsh       # standalone
#
# Covers:       z::sys::platform, z::sys::is_macos, z::sys::die,
#               z::cache::set, z::cache::get, z::cache::del, z::cache::clear,
#               z::cache::memoize, z::probe::cache, z::debug::assert,
#               z::config::set, z::config::get, z::config::save,
#               z::config::load
#
# Requires:     ui, z — loaded by ztest::require below; requiring z pulls in
#                       zlog, zbase and zkv
# =============================================================================

source "${0:A:h}/../../bootstrap.zsh"
ztest::require ui z

# -----------------------------------------------------------------------------
# Version
# -----------------------------------------------------------------------------
# ZCORE_VERSION, the banner and ./VERSION are three copies of one number;
# this is the only automatic check that they agree.

test_z_version_matches_version_file() {
  local file_version
  IFS= read -r file_version < "${ZCORE_ROOT}/VERSION"
  ztest::assert::eq "$file_version" "$ZCORE_VERSION"
}

# -----------------------------------------------------------------------------
# Platform detection
# -----------------------------------------------------------------------------
# The IS_* flags are cached, so detection has to cope with the cache being
# partially or entirely gone: entries expire and callers may clear them.

# One IS_* flag can be evicted while its companions survive, so detection
# must not feed a cache miss straight into an arithmetic expression.
test_z_platform_survives_partial_cache_eviction() {
  z::sys::platform
  local before=$IS_MACOS

  z::cache::del 'sys:is_macos'
  z::cache::del 'sys:is_linux'

  local out
  out="$(z::sys::platform 2>&1)"
  [[ $out == *'bad math expression'* ]] \
    && ztest::fail "platform detection raised a math error: $out"
  ztest::assert::eq "$before" "$IS_MACOS" 'IS_MACOS changed after eviction'
}

test_z_platform_survives_full_cache_clear() {
  z::sys::platform
  local before=$IS_MACOS

  z::cache::clear '*' >/dev/null 2>&1

  local out
  out="$(z::sys::is_macos 2>&1)"
  ztest::assert::eq '' "$out" 'z::sys::is_macos emitted output after cache clear'
  ztest::assert::eq "$before" "$IS_MACOS" 'IS_MACOS changed after cache clear'
}

test_z_platform_sets_exactly_one_family_flag() {
  z::sys::platform
  typeset -i family_count
  (( family_count = IS_MACOS + IS_LINUX + IS_BSD + IS_CYGWIN ))
  (( family_count <= 1 )) \
    || ztest::fail "more than one platform family flag set (count=$family_count)"
  if (( family_count == 1 )); then
    ztest::assert::eq '0' "$IS_UNKNOWN"
  else
    ztest::assert::eq '1' "$IS_UNKNOWN"
  fi
}

# -----------------------------------------------------------------------------
# Argument guards
# -----------------------------------------------------------------------------
# `shift 2` / `shift 3` on a shorter argv is a fatal builtin error, so these
# entry points must count their arguments before shifting and report bad
# input themselves.

test_z_cache_set_without_arguments_reports_input_error() {
  ztest::assert::returns $Z_ERR_INPUT z::cache::set
}

test_z_cache_memoize_without_arguments_reports_input_error() {
  ztest::assert::returns $Z_ERR_INPUT z::cache::memoize
}

test_z_cache_memoize_rejects_non_integer_ttl() {
  _ztz_compute() { print 'value'; }
  ztest::assert::returns $Z_ERR_INPUT z::cache::memoize 'k' 'notanint' _ztz_compute
}

# The counter in the callback makes a second evaluation visible: a cache hit
# must not re-run the producer.
test_z_cache_memoize_caches_result() {
  typeset -gi _ztz_calls=0
  _ztz_counted() { (( _ztz_calls += 1 )); print "run${_ztz_calls}"; }

  ztest::assert::eq 'run1' "$(z::cache::memoize 'memo:test' 60 _ztz_counted)"
  ztest::assert::eq 'run1' "$(z::cache::memoize 'memo:test' 60 _ztz_counted)"
}

# -----------------------------------------------------------------------------
# Cache basics
# -----------------------------------------------------------------------------

test_z_cache_roundtrip_and_delete() {
  z::cache::set 'ns:key' 'val'
  ztest::assert::eq 'val' "$(z::cache::get 'ns:key')"
  ztest::assert::true  z::probe::cache 'ns:key'

  z::cache::del 'ns:key'
  ztest::assert::false z::probe::cache 'ns:key'
  ztest::assert::returns $Z_ERR_NOTFOUND z::cache::get 'ns:key'
}

test_z_cache_ttl_expires() {
  # Backdating the deadline avoids sleeping: an already-elapsed TTL must read
  # back as a miss.
  z::cache::set 'ns:ttlkey' 'val' --ttl 1
  _zcore_cache_ttl[ns:ttlkey]=$(( ${EPOCHSECONDS:-0} - 1 ))
  ztest::assert::returns $Z_ERR_NOTFOUND z::cache::get 'ns:ttlkey'
}

# -----------------------------------------------------------------------------
# Fatal path
# -----------------------------------------------------------------------------

# _ztz_die_status <message> [exit_code]
# Run z::sys::die in a subshell and return its status. In this
# non-interactive runner die exits by design, so the subshell status is the
# code under test either way.
_ztz_die_status() {
  ( z::sys::die "$@" >/dev/null 2>&1 )
  return $?
}

# The exit code arrives from argv and is used in an arithmetic context, so
# it must be validated: a non-numeric value would raise a math error inside
# the fatal path, and 0 would signal success from a fatal error.
test_z_die_rejects_non_numeric_exit_code() {
  ztest::assert::returns $Z_ERR_GENERAL _ztz_die_status 'boom' 'notanumber'
}

test_z_die_rejects_zero_exit_code() {
  ztest::assert::returns $Z_ERR_GENERAL _ztz_die_status 'boom' 0
}

test_z_die_rejects_out_of_range_exit_code() {
  ztest::assert::returns $Z_ERR_GENERAL _ztz_die_status 'boom' 999
}

test_z_die_honours_valid_exit_code() {
  ztest::assert::returns 7 _ztz_die_status 'boom' 7
}

test_z_die_defaults_to_general_error() {
  ztest::assert::returns $Z_ERR_GENERAL _ztz_die_status 'boom'
}

# `ui` is an optional prerequisite; the fatal path must not depend on it.
test_z_die_works_without_progress_module() {
  local out
  out="$(
    unfunction z::progress::clear 2>/dev/null
    z::sys::die 'boom' 3 2>&1
  )"
  ztest::assert::not_contains "$out" 'command not found'
}

# `die` must never terminate an interactive session: it returns the code
# instead of exiting, so a shell that has sourced z stays alive. The
# `interactive` option cannot be toggled after startup, so the check needs a
# real `-i` child rather than a local setopt.
test_z_die_returns_instead_of_exiting_when_interactive() {
  local out
  ztest::child_prelude ui z
  out="$(zsh -fi -c "
    $REPLY
    z::sys::die 'boom' 5
    print \"survived:\$?\"
  " 2>/dev/null | grep survived)"

  ztest::assert::eq 'survived:5' "$out"
}

# The complementary half: a non-interactive script must still terminate.
test_z_die_exits_when_not_interactive() {
  local out
  ztest::child_prelude ui z
  out="$(zsh -f -c "
    $REPLY
    z::sys::die 'boom' 5
    print 'SHOULD NOT REACH'
  " 2>/dev/null)"
  local rc=$?

  ztest::assert::not_contains "$out" 'SHOULD NOT REACH'
  ztest::assert::eq '5' "$rc" 'die did not propagate the exit code'
}

# -----------------------------------------------------------------------------
# Assertions
# -----------------------------------------------------------------------------

# The condition is evaluated arithmetically, so a non-integer must be
# rejected outright: silently treating it as 0 would pass an assertion that
# was never actually checked.
test_z_assert_rejects_non_integer_condition() {
  ztest::assert::returns $Z_ERR_INPUT z::debug::assert 'abc'
}

test_z_assert_passes_on_zero() {
  ztest::assert::returns 0 z::debug::assert 0
}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

# The status of the redirection that writes the file is part of the return
# value: an unwritable target is a failure, not a silent no-op.
test_z_config_save_reports_write_failure() {
  local rc=0
  z::config::save '/nonexistent-dir-zcore/nope.cfg' >/dev/null 2>&1 || rc=$?
  ztest::assert::ne '0' "$rc" 'z::config::save returned 0 for an unwritable path'
}

test_z_config_save_load_roundtrip() {
  local file="${TMPDIR:-/tmp}/ztz_config_$$.cfg"
  z::config::set 'progress_style' 'classic' >/dev/null 2>&1

  ztest::assert::returns 0 z::config::save "$file"
  [[ -s $file ]] || ztest::fail "z::config::save produced no output at $file"
  ztest::assert::returns 0 z::config::load "$file"

  z::config::get 'progress_style'
  ztest::assert::eq 'classic' "$REPLY"

  command rm -f -- "$file"
}

test_z_config_set_validates_typed_keys() {
  ztest::assert::returns $Z_ERR_INPUT z::config::set 'performance_mode' 'maybe'
  ztest::assert::returns $Z_ERR_INPUT z::config::set 'cache_max_size' 'big'
  ztest::assert::returns 0 z::config::set 'cache_max_size' '250'
}

# Standalone execution; under the runner ztest::run is called by the runner.
(( ${ZTEST_RUNNER:-0} )) || ztest::run "${1:-test_*}"
