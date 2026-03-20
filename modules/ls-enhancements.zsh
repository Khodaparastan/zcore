#!/usr/bin/env zsh
#
# LS Enhancements Module
# Replaces `ls` with modern alternatives like `eza` or `lsd` and provides helper utilities.
#

# ==============================================================================
# PRIVATE HELPERS
# ==============================================================================

###
# Configures LS_COLORS for non-macOS systems.
###
__z::mod::ls::setup_colors()
{
  emulate -L zsh
  

  if (( IS_MACOS )); then
    typeset -grx LSCOLORS='exfxcxdxbxegedAbAgacad'
    typeset -grx CLICOLOR=1
  elif [[ -z ${LS_COLORS:-} ]] && z::probe::cmd "dircolors"; then
    # Safely evaluate dircolors output with validation
    local dircolors_output
    if dircolors_output="$(dircolors -b 2>/dev/null)"; then
      # Validate output starts with expected pattern
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
# Creates aliases for `ls` and its variants, preferring `eza` or `lsd`.
###
__z::mod::ls::setup_ls_aliases()
{
  emulate -L zsh
  

  if z::probe::cmd "eza"; then
    local -a base_opts=(
      '--group-directories-first'
      '--color=always'
      '--classify'
    )

    # Check for icon support (cached to avoid repeated help calls)
    if [[ -z ${_z_eza_icons_checked:-} ]]; then
      typeset -g _z_eza_icons_checked=1
      if eza --help 2>&1 | command grep -q -- '--icons'; then
        typeset -g _z_eza_has_icons=1
        z::log::debug "eza supports --icons flag"
      else
        typeset -g _z_eza_has_icons=0
        z::log::debug "eza does not support --icons flag"
      fi
    fi

    if (( ${_z_eza_has_icons:-0} )); then
      base_opts+=('--icons')
    fi

    # Build command string properly
    local eza_base="eza ${(j: :)base_opts}"

    # Verify eza actually works before creating aliases
    if eza --version >/dev/null 2>&1; then
      z::env::alias_set ls "$eza_base"
      z::env::alias_set ll "$eza_base --long --header --git --time-style=long-iso"
      z::env::alias_set la "$eza_base --all"
      z::env::alias_set l "$eza_base --all --long --header --git --time-style=long-iso"
      z::env::alias_set lt "$eza_base --tree --level=3"
      z::env::alias_set llt "$eza_base --long --tree --level=2"
      z::log::info "Configured eza as ls replacement"
    else
      z::log::warn "eza found but not functional, falling back to next option"
      __z::mod::ls::setup_lsd_or_fallback
      return $?
    fi

  elif z::probe::cmd "lsd"; then
    __z::mod::ls::setup_lsd_or_fallback
  else
    __z::mod::ls::setup_system_ls
  fi
}

###
# Sets up lsd as ls replacement
###
__z::mod::ls::setup_lsd_or_fallback()
{
  emulate -L zsh

  if z::probe::cmd "lsd" && lsd --version >/dev/null 2>&1; then
    local lsd_base='lsd --group-directories-first --color=always'

    # Check for icon support
    if lsd --help 2>&1 | command grep -q -- '--icon'; then
      lsd_base+=' --icon=auto'
    fi

    z::env::alias_set ls "$lsd_base"
    z::env::alias_set ll "$lsd_base --long"
    z::env::alias_set la "$lsd_base --all"
    z::env::alias_set l "$lsd_base --long --all"
    z::env::alias_set lt "$lsd_base --tree --depth=3"
    z::log::info "Configured lsd as ls replacement"
  else
    __z::mod::ls::setup_system_ls
  fi
}

###
# Sets up system ls with enhanced options
###
__z::mod::ls::setup_system_ls()
{
  emulate -L zsh

  local ls_base="command ls -F"

  if (( IS_MACOS )); then
    ls_base+=" -G"
  else
    # GNU ls options
    if command ls --color=auto --version >/dev/null 2>&1; then
      ls_base+=" --color=auto --group-directories-first"
    fi
  fi

  z::env::alias_set ls "$ls_base"
  z::env::alias_set ll "$ls_base -lh"
  z::env::alias_set la "$ls_base -A"
  z::env::alias_set l "$ls_base -Alh"
  z::log::info "Configured system ls with enhanced options"
}

###
# Creates a fallback `tree` command if the system version isn't installed.
###
__z::mod::ls::setup_tree_fallback()
{
  emulate -L zsh
  

  # Only create fallback if tree doesn't exist and user hasn't defined it
  if ! z::probe::cmd "tree" && ! typeset -f tree >/dev/null 2>&1; then
    tree()
    {
      emulate -L zsh
      setopt local_options

      local dir="${1:-.}"
      local depth="${2:-3}"

      # Validate inputs
      if [[ ! -d "$dir" ]]; then
        print "tree: $dir: No such directory" >&2
        return 1
      fi

      if ! [[ "$depth" =~ '^[0-9]+$' ]]; then
        print "tree: invalid depth: $depth" >&2
        return 1
      fi

      print "."
      # Simple fallback using find with proper quoting
      command find "$dir" -maxdepth "$depth" -print 2>/dev/null \
        | command sed -e 's;[^/]*/;|____;g;s;____|; |;g' \
        | command tail -n +2

      # Count results
      local -i file_count dir_count
      file_count=$(command find "$dir" -maxdepth "$depth" -type f 2>/dev/null | wc -l)
      dir_count=$(command find "$dir" -maxdepth "$depth" -type d 2>/dev/null | wc -l)
      dir_count=$(( dir_count - 1 ))  # Don't count root

      print "\n$dir_count directories, $file_count files"
    }
    z::log::info "System 'tree' not found; created fallback function"
  elif z::probe::cmd "tree"; then
    z::log::debug "System 'tree' command available"
  fi
}

# ==============================================================================
# MAIN INITIALIZATION
# ==============================================================================

__z::mod::ls::init()
{
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
