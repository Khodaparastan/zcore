#!/usr/bin/env zsh
# =============================================================================
# run_tests.zsh — Select, execute, and summarise the zcore test suites
# =============================================================================
# Description:  Resolves the requested selectors into suite files, sources
#               each one in its own subshell, and prints a combined summary.
#               The runner loads no framework module: every suite declares
#               what it needs through ztest::require, so it behaves the same
#               whether the runner or a developer starts it.
#
#               The subshell is what keeps suites independent — the ztest
#               hooks (test_setup and friends) are global names, so without
#               it the last file sourced would redefine the hooks of every
#               file after it. Counters cross that boundary through
#               ZTEST_STATS_FILE.
#
# Usage:        zsh tests/run_tests.zsh                 # everything
#               zsh tests/run_tests.zsh unit
#               zsh tests/run_tests.zsh integration
#               zsh tests/run_tests.zsh zkv zbus        # by module
#               zsh tests/run_tests.zsh tests/unit/zkv/test_zkv_tx.zsh
#               zsh tests/run_tests.zsh zkv -t 'test_zkv_ttl_*'
#
#               A selector is `all`, `unit`, `integration`, a module name, or
#               a path to a suite file or directory. -t narrows the test
#               names within each selected file.
#
# Requires:     tests/bootstrap.zsh — supplies ztest and ZCORE_ROOT
#               the suites themselves — they load the modules they exercise
# =============================================================================
emulate -L zsh
setopt extendedglob typesetsilent

source "${0:A:h}/bootstrap.zsh" \
  || { print -u2 -r -- "run_tests: failed to source tests/bootstrap.zsh"; exit 1; }

typeset -g TESTS_DIR="${ZCORE_ROOT}/tests"


# =============================================================================
# SELECTION
# =============================================================================

# runner::usage
# Print the accepted selectors to stdout. Always returns 0.
runner::usage() {
  print -r -- "usage: zsh tests/run_tests.zsh [selector ...] [-t <test-pattern>]"
  print -r -- "  selectors: all | unit | integration | <module> | <path>"
  print -r -- "  -t         glob matched against test function names"
  return 0
}

# runner::expand <selector>
# Append the suite files a single selector names to the global `files` array.
# Directories are searched one level deep for test_*.zsh, which matches both
# tests/unit/<module>/ and tests/integration/. Returns 1 when the selector
# resolves to nothing, so a typo fails the run instead of passing vacuously.
runner::expand() {
  local selector="$1"
  local -a found

  case "$selector" in
    all)
      found=( "${TESTS_DIR}"/unit/*/test_*.zsh(N)
              "${TESTS_DIR}"/integration/test_*.zsh(N) )
      ;;
    unit)
      found=( "${TESTS_DIR}"/unit/*/test_*.zsh(N) )
      ;;
    integration)
      found=( "${TESTS_DIR}"/integration/test_*.zsh(N) )
      ;;
    *)
      # A module name is tried first: the repo root holds files named `z`,
      # `zkv` and so on, so a path test would match the module itself.
      if [[ -d ${TESTS_DIR}/unit/${selector} ]]; then
        found=( "${TESTS_DIR}/unit/${selector}"/test_*.zsh(N) )
      elif [[ -f $selector ]]; then
        found=( "${selector:A}" )
      elif [[ -d $selector ]]; then
        found=( "${selector:A}"/test_*.zsh(N) "${selector:A}"/*/test_*.zsh(N) )
      fi
      ;;
  esac

  if (( ${#found} == 0 )); then
    print -u2 -r -- "run_tests: no suites match selector '$selector'"
    return 1
  fi

  files+=( "${found[@]}" )
  return 0
}

typeset -ga files=()
typeset -ga selectors=()
typeset -g name_filter='test_*'
typeset -i argerr=0

while (( $# )); do
  case "$1" in
    -h|--help) runner::usage; exit 0 ;;
    -t|--test)
      if (( $# < 2 )); then
        print -u2 -r -- "run_tests: -t requires a pattern"
        exit 2
      fi
      name_filter="$2"
      shift 2
      ;;
    -*)
      print -u2 -r -- "run_tests: unknown option: $1"
      runner::usage
      exit 2
      ;;
    *) selectors+=( "$1" ); shift ;;
  esac
done

(( ${#selectors} )) || selectors=( all )

typeset selector
for selector in "${selectors[@]}"; do
  runner::expand "$selector" || argerr=1
done
(( argerr )) && exit 2

# Selectors may overlap (`unit zkv`); each file must still run once. The sort
# keeps the report order stable and independent of the selector order.
files=( "${(@u)files}" )
files=( "${(@o)files}" )


# =============================================================================
# EXECUTION
# =============================================================================
# One subshell per file, with its counters written to a scratch file that the
# parent reads back. A file that dies before reporting counts as a failure
# with no tests, which is exactly how a syntax error should surface.

typeset -g stats_file
stats_file="$(mktemp -t zcore_ztest.XXXXXX)" \
  || { print -u2 -r -- "run_tests: cannot create a scratch file"; exit 1; }

export ZTEST_RUNNER=1
export ZTEST_STATS_FILE="$stats_file"

typeset -i files_run=0 files_failed=0 files_empty=0
typeset -i total_pass=0 total_fail=0 total_skip=0 total_assertions=0
typeset -a failed_files=()
typeset test_file line
typeset -i rc=0

for test_file in "${files[@]}"; do
  (( files_run += 1 ))
  print
  print "═══ ${test_file:h:t}/${test_file:t} ═══"

  : >| "$stats_file"
  (
    source "$test_file"
    ztest::run "$name_filter"
  )
  rc=$?

  # One line, four fields, written by ztest::run just before it returned.
  line=""
  [[ -r $stats_file ]] && IFS= read -r line < "$stats_file"
  if [[ -n $line ]]; then
    typeset -a counts=( ${=line} )
    (( total_pass       += ${counts[1]:-0} ))
    (( total_fail       += ${counts[2]:-0} ))
    (( total_skip       += ${counts[3]:-0} ))
    (( total_assertions += ${counts[4]:-0} ))
  fi

  # rc 2 means the name filter selected nothing in this file. Under an
  # explicit -t that is the normal case and must not fail the run; with the
  # default filter it means a suite file defines no tests at all.
  if (( rc == 2 )) && [[ $name_filter != 'test_*' ]]; then
    (( files_empty += 1 ))
  elif (( rc != 0 )); then
    (( files_failed += 1 ))
    failed_files+=( "${test_file#${ZCORE_ROOT}/}" )
  fi
done

rm -f -- "$stats_file"


# =============================================================================
# SUMMARY
# =============================================================================

typeset files_line="${files_run} run, ${files_failed} failed"
(( files_empty )) && files_line+=", ${files_empty} with no matching test"

print
print -r -- "═════════════════════════════════════════════════════════════"
print -r -- "files:      ${files_line}"
print -r -- "tests:      ${total_pass} passed, ${total_fail} failed, ${total_skip} skipped"
print -r -- "assertions: ${total_assertions}"

# A filter that matches nothing anywhere is a typo, not a passing run.
if (( files_failed == 0 && total_pass + total_fail + total_skip == 0 )); then
  print -r -- "✗ no test matched '${name_filter}'"
  exit 1
fi

if (( files_failed == 0 )); then
  print -r -- "✓ all suites passed"
  exit 0
fi

print -r -- "✗ failing suites:"
for test_file in "${failed_files[@]}"; do
  print -r -- "    ${test_file}"
done
exit 1
