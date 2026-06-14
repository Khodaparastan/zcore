#!/usr/bin/env zsh
#
# LS Enhancements Module
# Replaces `ls` with modern alternatives like `eza` or `lsd` and provides
# helper utilities.  Safe to source multiple times.
#

# ==============================================================================
# PRIVATE HELPERS
# ==============================================================================

###
# Configures colour env vars in a re-source-safe way.
###
__z::mod::ls::setup_colors() {
  emulate -L zsh

  if (( IS_MACOS )); then
    : ${LSCOLORS:=exfxcxdxbxegedAbAgacad}
    typeset -gx LSCOLORS CLICOLOR=1
  elif [[ -z ${LS_COLORS:-} ]] && z::probe::cmd "dircolors"; then
    local dircolors_output
    if dircolors_output="$(dircolors -b 2>/dev/null)"; then
      if [[ "$dircolors_output" == LS_COLORS=* ]]; then
        eval "$dircolors_output"
        z::log::debug "Configured LS_COLORS via dircolors"
      else
        z::log::debug "Unexpected dircolors output format, skipping"
      fi
    fi
  fi
}

###
# Creates aliases for `ls`, preferring `eza` -> `lsd` -> system ls.
###
__z::mod::ls::setup_ls_aliases() {
  emulate -L zsh

  if z::probe::cmd "eza"; then
    local -a base_opts=(--group-directories-first --color=always --classify --icons)
    local eza_base="eza ${(j: :)base_opts}"
    z::env::alias_set ls  "$eza_base"
    z::env::alias_set ll  "$eza_base --long --header --git --time-style=long-iso"
    z::env::alias_set la  "$eza_base --all"
    z::env::alias_set l   "$eza_base --all --long --header --git --time-style=long-iso"
    z::env::alias_set lt  "$eza_base --tree --level=3"
    z::env::alias_set llt "$eza_base --long --tree --level=2"
    z::log::info "Configured eza as ls replacement"
    return 0
  fi

  __z::mod::ls::setup_lsd_or_fallback
}

###
# Configures lsd, otherwise system ls.
###
__z::mod::ls::setup_lsd_or_fallback() {
  emulate -L zsh

  if z::probe::cmd "lsd"; then
    local lsd_base='lsd --group-directories-first --color=always --icon=auto'
    z::env::alias_set ls "$lsd_base"
    z::env::alias_set ll "$lsd_base --long"
    z::env::alias_set la "$lsd_base --all"
    z::env::alias_set l  "$lsd_base --long --all"
    z::env::alias_set lt "$lsd_base --tree --depth=3"
    z::log::info "Configured lsd as ls replacement"
    return 0
  fi

  __z::mod::ls::setup_system_ls
}

###
# Configures the system `ls` with sensible defaults.
###
__z::mod::ls::setup_system_ls() {
  emulate -L zsh

  local ls_base="command ls -F"
  if (( IS_MACOS )); then
    ls_base+=" -G"
  elif (( IS_LINUX )); then
    ls_base+=" --color=auto --group-directories-first"
  fi

  z::env::alias_set ls "$ls_base"
  z::env::alias_set ll "$ls_base -lh"
  z::env::alias_set la "$ls_base -A"
  z::env::alias_set l  "$ls_base -Alh"
  z::log::info "Configured system ls with enhanced options"
}

###
# Creates a tiny fallback `tree` function if the binary is missing.
###
__z::mod::ls::setup_tree_fallback() {
  emulate -L zsh

  if z::probe::cmd "tree"; then
    z::log::debug "System 'tree' command available"
    return 0
  fi
  typeset -f tree >/dev/null 2>&1 && return 0

  tree() {
    emulate -L zsh
    local dir="${1:-.}" depth="${2:-3}"

    if [[ ! -d "$dir" ]]; then
      print -ru2 -- "tree: $dir: No such directory"
      return 1
    fi
    if [[ "$depth" != <-> ]]; then
      print -ru2 -- "tree: invalid depth: $depth"
      return 1
    fi

    print "."
    command find "$dir" -maxdepth "$depth" -print 2>/dev/null \
      | command sed -e 's;[^/]*/;|____;g;s;____|; |;g' \
      | command tail -n +2

    local -i file_count dir_count
    file_count=$(command find "$dir" -maxdepth "$depth" -type f 2>/dev/null | command wc -l)
    dir_count=$(command find "$dir" -maxdepth "$depth" -type d 2>/dev/null | command wc -l)
    file_count=${file_count// /}
    dir_count=${dir_count// /}
    (( dir_count = dir_count - 1 ))  # exclude root

    print "\n$dir_count directories, $file_count files"
  }
  z::log::info "System 'tree' not found; created fallback function"
}

# ==============================================================================
# MAIN INITIALIZATION
# ==============================================================================

__z::mod::ls::init() {
  emulate -L zsh

  z::log::info "Initializing ls enhancements..."
  __z::mod::ls::setup_colors
  __z::mod::ls::setup_ls_aliases
  __z::mod::ls::setup_tree_fallback
  z::log::info "LS enhancements initialized successfully"
}

if z::probe::func "__z::mod::ls::init"; then
  __z::mod::ls::init
fi
