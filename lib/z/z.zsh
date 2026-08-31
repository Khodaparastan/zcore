#!/usr/bin/env zsh
# =============================================================================
# z/z.zsh — Development loader for the split z module
# =============================================================================
# Description:  Sources the part files listed in lib/z/parts, in order, so the
#               module can be exercised straight from its parts without
#               running bin/zbundle first. The assembled root `z` is what
#               ships; this loader exists so an edit to a part is testable
#               immediately, and so the two paths can be compared.
#
#               Sourcing this file must leave the shell in exactly the state
#               that sourcing the bundled root module would.
#
# Usage:        source lib/z/z.zsh     # in place of `source z`
#
# Requires:     the same chain as the bundled module — zlog, zbase and zkv
#               before it; ui and zbus optional
# =============================================================================

# The head part guards on _zcore_loaded, but a `return` inside a sourced part
# only leaves that part — the loop below would carry on and re-run the rest,
# and re-assigning the readonly ZCORE_VERSION would abort the load. So the
# guard has to live here as well.
if [[ ${_zcore_loaded:-} == 1 ]]; then return 0 2>/dev/null || exit 0; fi

# Everything below runs at file scope, never inside a function: a part
# assembled into the bundle executes at file scope, so `typeset` without -g
# must create a global here too. %x is this file even when sourced.
typeset -g _z_load_dir="${${(%):-%x}:A:h}"
typeset -g _z_load_manifest="${_z_load_dir}/parts"
typeset -g _z_load_line _z_load_part

if [[ ! -r $_z_load_manifest ]]; then
  print -u2 "z/z.zsh: missing part manifest: ${_z_load_manifest}"
  return 1 2>/dev/null || exit 1
fi

while IFS= read -r _z_load_line; do
  # Manifest comments start in column 1; the first field is the file name and
  # the remainder is the section title used only by the bundler.
  [[ $_z_load_line == '#'* ]] && continue
  [[ -z ${_z_load_line//[[:space:]]/} ]] && continue
  _z_load_part="${_z_load_line%%[[:space:]]*}"

  if [[ ! -r ${_z_load_dir}/${_z_load_part} ]]; then
    print -u2 "z/z.zsh: missing part: ${_z_load_dir}/${_z_load_part}"
    return 1 2>/dev/null || exit 1
  fi
  source "${_z_load_dir}/${_z_load_part}"
done < "$_z_load_manifest"

unset _z_load_dir _z_load_manifest _z_load_line _z_load_part
