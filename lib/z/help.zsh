#!/usr/bin/env zsh
# =============================================================================
# z/help.zsh — API listing and quick reference
# =============================================================================
# Description:  Lists the public functions of a namespace and prints the
#               quick-reference banner.
#
# Part of:      z — assembled by bin/zbundle; see lib/z/parts
#
# Requires:     nothing beyond zsh itself
# =============================================================================


# z::help::list [<namespace-prefix>]
# Print the public functions under <namespace-prefix> (default `z::`), one per
# line, sorted. Always returns 0.
z::help::list() {
  emulate -L zsh
  local namespace="${1:-z::}"

  local func
  # `(Mok)` keeps only the matches of the `:#` pattern, sorted by name.
  for func in ${(Mok)functions:#${namespace}*}; do
    # Internal helpers are marked by an underscore-prefixed segment.
    [[ $func == *::_* ]] && continue
    print -r -- "$func"
  done
  return 0
}

# z::help::quick
# Print the quick-reference banner to stdout. Always returns 0.
z::help::quick() {
  emulate -L zsh

  cat <<'EOF'
ZCORE - Quick Reference
======================================
EOF
  return 0
}


