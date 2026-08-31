#!/usr/bin/env zsh
# =============================================================================
# test_zbase_contract.zsh — zbase behavioural contract
# =============================================================================
# Description:  Pins the promises zbase makes to its callers: the z::is::
#               predicates work under `emulate -L zsh`, the z::is:: and
#               z::get:: families use their documented return channels
#               without clobbering the others, z::do::run refuses chained or
#               substituted commands and its init-command fast path stays
#               narrow, z::do::scan sees past operators and tabs when looking
#               for dangerous commands, argument-count guards report bad
#               input instead of aborting on shift, and the metacharacter
#               regexes are all defined.
#
# Usage:        zsh tests/run_tests.zsh zbase
#               zsh tests/unit/zbase/test_zbase_contract.zsh    # standalone
#
# Covers:       z::is::int, z::is::blank, z::is::path, z::get::opt,
#               z::get::funcs, z::do::run, z::do::scan, z::do::source,
#               _z::do::run::is_init_cmd, _z::do::run::has_metachars
#
# Requires:     zbase — loaded by ztest::require below
# =============================================================================

source "${0:A:h}/../../bootstrap.zsh"
ztest::require zbase

# -----------------------------------------------------------------------------
# Predicates under emulate -L zsh
# -----------------------------------------------------------------------------
# Callers run under `emulate -L zsh`, which clears extendedglob. Any
# predicate relying on it must set the option locally, otherwise a `#`
# closure is matched literally and every multi-digit number is rejected.
# These wrappers reproduce the caller's environment.

# _zbc_is_int_under_emulate <value>
# Call z::is::int with the caller's option set, not the test file's.
_zbc_is_int_under_emulate() {
  emulate -L zsh
  z::is::int "$1"
}

# _zbc_is_blank_under_emulate <value>
# Call z::is::blank with the caller's option set, not the test file's.
_zbc_is_blank_under_emulate() {
  emulate -L zsh
  z::is::blank "$1"
}

test_zbase_is_int_accepts_multi_digit_under_emulate() {
  local n
  for n in 5 42 100 -7 1234567; do
    ztest::assert::true _zbc_is_int_under_emulate "$n"
  done
}

test_zbase_is_int_rejects_non_integers_under_emulate() {
  local n
  for n in abc 1a '' 007 -0 1.5; do
    ztest::assert::false _zbc_is_int_under_emulate "$n"
  done
}

test_zbase_is_blank_under_emulate() {
  ztest::assert::true  _zbc_is_blank_under_emulate ''
  ztest::assert::true  _zbc_is_blank_under_emulate '   '
  ztest::assert::false _zbc_is_blank_under_emulate 'x'
}

# -----------------------------------------------------------------------------
# Return-channel contract
# -----------------------------------------------------------------------------
# A predicate answers through its exit status only and must leave REPLY,
# REPLY2 and reply alone; a getter writes exactly the channel it documents.

# z::is::path calls z::get::abspath internally, which resets all three
# channels, so the sentinels prove they are restored.
test_zbase_is_path_preserves_return_channels() {
  REPLY='sentinel'; REPLY2='sentinel2'; reply=(one two)

  z::is::path /usr/bin

  ztest::assert::eq 'sentinel'  "$REPLY"  'REPLY clobbered by z::is::path'
  ztest::assert::eq 'sentinel2' "$REPLY2" 'REPLY2 clobbered by z::is::path'
  ztest::assert::eq 'one two'   "${reply[*]}" 'reply clobbered by z::is::path'
}

# z::get::opt promises the default in REPLY on its early-return paths, and
# every zlog:: helper clobbers REPLY, so the default has to survive any
# logging on the way out.
test_zbase_get_opt_returns_default_when_both_names_empty() {
  typeset -A _zbc_opts=( -x 1 )
  z::get::opt _zbc_opts '' '' 'THEDEFAULT'
  ztest::assert::eq 'THEDEFAULT' "$REPLY"
}

test_zbase_get_opt_returns_default_for_non_assoc() {
  local _zbc_scalar='not-an-assoc'
  z::get::opt _zbc_scalar 'y' '' 'THEDEFAULT'
  ztest::assert::eq 'THEDEFAULT' "$REPLY"
}

test_zbase_get_opt_returns_matched_value() {
  typeset -A _zbc_opts=( -x 'xval' --long 'lval' )
  z::get::opt _zbc_opts 'x' '' 'THEDEFAULT'
  ztest::assert::eq 'xval' "$REPLY"
  z::get::opt _zbc_opts '' 'long' 'THEDEFAULT'
  ztest::assert::eq 'lval' "$REPLY"
}

# reply= must hold one element per match, in sorted order: quoting the
# expansion would join every match into a single string and drop the
# ordering.
test_zbase_get_funcs_returns_one_element_per_match() {
  z::get::funcs 'z::is::*'

  (( ${#reply} > 5 )) \
    || ztest::fail "expected several matches, got ${#reply}: ${reply[*]}"

  # One element per match: a whitespace hit means several were joined.
  local f
  for f in "${reply[@]}"; do
    ztest::assert::matches "$f" 'z::is::*'
    ztest::assert::not_contains "$f" ' '
  done
}

test_zbase_get_funcs_is_sorted() {
  z::get::funcs 'z::is::*'
  local -a expected=( "${(o)reply[@]}" )
  ztest::assert::array_eq expected reply
}

test_zbase_get_funcs_leaves_reply_scalar_clean() {
  REPLY='dirty'
  # Empty pattern triggers zlog::once, which clobbers REPLY.
  z::get::funcs ''
  ztest::assert::eq '' "$REPLY"
}

# -----------------------------------------------------------------------------
# z::do::run and z::do::scan hardening
# -----------------------------------------------------------------------------
# The init-command fast path skips BOTH metachar rejection and the pattern
# scan, so it must only accept a single unchained literal invocation.

test_zbase_init_fast_path_accepts_plain_tool_init() {
  ztest::assert::true  _z::do::run::is_init_cmd 'starship init zsh'
  ztest::assert::true  _z::do::run::is_init_cmd '/usr/local/bin/starship init zsh'
  ztest::assert::true  _z::do::run::is_init_cmd 'starship init zsh --print-full-init'
  ztest::assert::true  _z::do::run::is_init_cmd 'mise init zsh'
}

test_zbase_init_fast_path_rejects_chaining_and_substitution() {
  ztest::assert::false _z::do::run::is_init_cmd 'starship init zsh; id'
  ztest::assert::false _z::do::run::is_init_cmd 'starship init zsh && id'
  ztest::assert::false _z::do::run::is_init_cmd 'starship init zsh | id'
  ztest::assert::false _z::do::run::is_init_cmd 'starship init zsh $(id)'
  ztest::assert::false _z::do::run::is_init_cmd 'starship init zsh `id`'
  ztest::assert::false _z::do::run::is_init_cmd 'starship init zsh > /tmp/x'
}

test_zbase_init_fast_path_rejects_unknown_tools() {
  ztest::assert::false _z::do::run::is_init_cmd 'evil init zsh'
  ztest::assert::false _z::do::run::is_init_cmd 'starship activate zsh'
}

# End-to-end: rejecting the string is not enough, the injected command must
# never execute.
test_zbase_run_does_not_execute_injected_tail() {
  local marker="${TMPDIR:-/tmp}/zbc_pwned_$$"
  command rm -f -- "$marker"

  z::do::run "starship init zsh; touch ${marker}" >/dev/null 2>&1

  ztest::assert::file_absent "$marker"
  command rm -f -- "$marker"
}

test_zbase_run_does_not_execute_command_substitution() {
  local marker="${TMPDIR:-/tmp}/zbc_pwned_sub_$$"
  command rm -f -- "$marker"

  z::do::run "starship init zsh \$(touch ${marker})" >/dev/null 2>&1

  ztest::assert::file_absent "$marker"
  command rm -f -- "$marker"
}

# `|` belongs in the metacharacter class in its own right: blocking `&`
# stops `&&` but leaves a plain pipeline through the gate.
test_zbase_run_does_not_execute_pipeline() {
  local marker="${TMPDIR:-/tmp}/zbc_pwned_pipe_$$"
  command rm -f -- "$marker"

  z::do::run "starship init zsh | touch ${marker}" >/dev/null 2>&1

  ztest::assert::file_absent "$marker"
  command rm -f -- "$marker"
}

test_zbase_run_rejects_every_chaining_operator() {
  local op
  for op in ';' '&&' '||' '|' '&'; do
    ztest::assert::returns $Z_ERR_PERM z::do::run "echo a ${op} echo b"
  done
}

test_zbase_has_metachars_covers_all_compound_operators() {
  local s
  for s in 'a; b' 'a && b' 'a || b' 'a | b' 'a & b' 'a(b)' 'a > b' 'a < b' 'a `b`'; do
    ztest::assert::true _z::do::run::has_metachars "$s"
  done
  ztest::assert::false _z::do::run::has_metachars 'ls -la /tmp'
}

# Tokenization: the scanner must split on operators and on tabs, or the
# dangerous command sitting after one never reaches the segment checker.
test_zbase_scan_detects_dangerous_rm_after_operator() {
  ztest::assert::false z::do::scan 'echo hi; rm -rf --no-preserve-root /'
  ztest::assert::false z::do::scan 'echo hi && rm -rf --no-preserve-root /'
  ztest::assert::false z::do::scan 'echo hi | rm -rf --no-preserve-root /'
}

test_zbase_scan_detects_tab_separated_dangerous_rm() {
  ztest::assert::false z::do::scan $'rm\t-rf\t--no-preserve-root\t/'
}

test_zbase_scan_detects_shell_invocation_after_operator() {
  ztest::assert::false z::do::scan 'echo hi; bash -c whatever'
}

test_zbase_scan_allows_benign_commands() {
  ztest::assert::true z::do::scan 'ls -la'
  ztest::assert::true z::do::scan 'echo hello; echo world'
  ztest::assert::true z::do::scan 'rm -rf ./build'
}

# -----------------------------------------------------------------------------
# Argument-count guards
# -----------------------------------------------------------------------------

# A bare `shift` on an empty argv is a fatal builtin error, so the argument
# count has to be checked before the shift, not after.
test_zbase_do_source_without_arguments_reports_input_error() {
  local out
  out="$(z::do::source 2>&1)"
  [[ $out == *'shift count'* ]] \
    && ztest::fail "z::do::source aborted on empty argv: $out"
  ztest::assert::returns $Z_ERR_INPUT z::do::source
}

# -----------------------------------------------------------------------------
# Metacharacter regexes
# -----------------------------------------------------------------------------

# An unset regex makes [[ =~ ]] match everything, which would silently
# neuter the fork-bomb detector rather than fail loudly.
test_zbase_metachar_regexes_are_all_defined() {
  ztest::assert::ne '' "$_Z_EXEC_META_RE"
  ztest::assert::ne '' "$_Z_EXEC_FORKBOMB_RE_1"
  ztest::assert::ne '' "$_Z_EXEC_FORKBOMB_RE_2"
}

# Standalone execution; under the runner ztest::run is called by the runner.
(( ${ZTEST_RUNNER:-0} )) || ztest::run "${1:-test_*}"
