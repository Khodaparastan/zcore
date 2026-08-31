#!/usr/bin/env zsh
# =============================================================================
# test_loader.zsh — Single-file loader entrypoint
# =============================================================================
# Description:  A clean shell that sources zcore.zsh once must gain the same
#               public API as sourcing the six modules by hand, a second
#               source must be a no-op, and sourcing the loader after the
#               modules are already present must not fail. Also checks that
#               make uninstall removes exactly what make install wrote.
#
# Usage:        zsh tests/run_tests.zsh integration
#               zsh tests/integration/test_loader.zsh   # standalone
#
# Covers:       zcore.zsh, make install, make uninstall
#
# Requires:     tests/bootstrap.zsh — for ZCORE_ROOT. No module is loaded
#               in-process: every check runs in a clean child shell or
#               writes into a throwaway PREFIX.
# =============================================================================

source "${0:A:h}/../bootstrap.zsh"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

# _loader_manual_snippet
# Set REPLY to a snippet that sources the six modules in dependency order.
_loader_manual_snippet() {
  local root="${(q)ZCORE_ROOT}"
  REPLY="source ${root}/zlog; source ${root}/zbase; source ${root}/ui; source ${root}/zkv; source ${root}/zbus; source ${root}/z"
}

# _loader_public_api <snippet>
# Print the sorted public function names defined after running <snippet>
# in a clean shell, one per line.
_loader_public_api() {
  zsh -f -c "
    $1
    print -l \${(ok)functions[(I)z::*]} \${(ok)functions[(I)zlog::*]}
  " 2>/dev/null
}


# -----------------------------------------------------------------------------
# Completeness
# -----------------------------------------------------------------------------

# One source of the loader must define the same public API as sourcing the
# six modules by hand, which is the contract consumers actually depend on.
test_loader_defines_the_same_functions_as_manual_source() {
  local from_loader from_manual
  _loader_manual_snippet
  from_manual="$(_loader_public_api "$REPLY")"
  from_loader="$(_loader_public_api "source ${(q)ZCORE_ROOT}/zcore.zsh")"

  [[ -n $from_loader ]] || ztest::fail 'sourcing zcore.zsh defined no public functions'
  ztest::assert::eq "$from_manual" "$from_loader"
}

# A representative from each layer must be present after one source, so a
# truncated load (missing zbus, missing z, …) cannot hide behind an empty
# equality of two equally incomplete sets.
test_loader_defines_every_layer() {
  local out
  out="$(zsh -f -c "
    source ${(q)ZCORE_ROOT}/zcore.zsh
    print -r -- \${+functions[zlog::info]}
    print -r -- \${+functions[z::is::int]}
    print -r -- \${+functions[z::ui::width]}
    print -r -- \${+functions[z::kv::open]}
    print -r -- \${+functions[z::bus::emit]}
    print -r -- \${+functions[z::cache::get]}
  " 2>/dev/null)"
  ztest::assert::eq $'1\n1\n1\n1\n1\n1' "$out"
}


# -----------------------------------------------------------------------------
# Idempotency
# -----------------------------------------------------------------------------

# The load guard has to hold for the loader too: sourcing it twice must not
# fail on a readonly constant in any of the six modules.
test_loader_is_idempotent() {
  local out
  out="$(zsh -f -c "
    source ${(q)ZCORE_ROOT}/zcore.zsh
    source ${(q)ZCORE_ROOT}/zcore.zsh
    print ok
  " 2>&1 | tail -1)"
  ztest::assert::eq 'ok' "$out"
}

# Sourcing the loader after the modules are already present is a no-op at
# the module level and must still succeed.
test_loader_is_noop_after_manual_source() {
  local out
  _loader_manual_snippet
  out="$(zsh -f -c "
    $REPLY
    source ${(q)ZCORE_ROOT}/zcore.zsh
    print ok
  " 2>&1 | tail -1)"
  ztest::assert::eq 'ok' "$out"
}


# -----------------------------------------------------------------------------
# Install / uninstall
# -----------------------------------------------------------------------------

# make uninstall must remove exactly the files make install wrote, leaving
# a throwaway PREFIX the way it found it.
test_loader_install_uninstall_roundtrip() {
  local prefix dest
  prefix="$(mktemp -d -t zcore_prefix.XXXXXX)" \
    || { ztest::fail "cannot create PREFIX"; return 1; }
  dest="${prefix}/share/zcore"

  make -C "$ZCORE_ROOT" PREFIX="$prefix" install >/dev/null \
    || { command rm -rf -- "$prefix"; ztest::fail "make install failed"; return 1; }

  ztest::assert::file_exists "${dest}/zcore.zsh"
  ztest::assert::file_exists "${dest}/zlog"
  ztest::assert::file_exists "${dest}/zbase"
  ztest::assert::file_exists "${dest}/ui"
  ztest::assert::file_exists "${dest}/zkv"
  ztest::assert::file_exists "${dest}/zbus"
  ztest::assert::file_exists "${dest}/z"

  make -C "$ZCORE_ROOT" PREFIX="$prefix" uninstall >/dev/null \
    || { command rm -rf -- "$prefix"; ztest::fail "make uninstall failed"; return 1; }

  ztest::assert::file_absent "${dest}/zcore.zsh"
  ztest::assert::file_absent "${dest}/zlog"
  ztest::assert::file_absent "${dest}/zbase"
  ztest::assert::file_absent "${dest}/ui"
  ztest::assert::file_absent "${dest}/zkv"
  ztest::assert::file_absent "${dest}/zbus"
  ztest::assert::file_absent "${dest}/z"
  ztest::assert::file_absent "$dest"

  command rm -rf -- "$prefix"
}

# Standalone execution; under the runner ztest::run is called by the runner.
(( ${ZTEST_RUNNER:-0} )) || ztest::run "${1:-test_*}"
