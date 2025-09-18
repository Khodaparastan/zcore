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
z::mod::ls::_setup_colors()
{
  emulate -L zsh
  z::runtime::check_interrupted \
    || return $?

  if ((IS_MACOS)); then
    typeset -grx LSCOLORS='exfxcxdxbxegedAbAgacad'
    typeset -grx CLICOLOR=1
  elif [[ -z ${LS_COLORS:-} ]] \
    && z::cmd::exists "dircolors"; then
    # Safely evaluate dircolors output
    local dircolors_output
    if dircolors_output="$(dircolors -b 2> /dev/null)"; then
      eval "$dircolors_output"
    fi
  fi
}

###
# Creates aliases for `ls` and its variants, preferring `eza` or `lsd`.
###
z::mod::ls::_setup_ls_aliases()
{
  emulate -L zsh
  z::runtime::check_interrupted \
    || return $?

  if z::cmd::exists "eza"; then
    local -a base_opts=('--group-directories-first' '--color=always' '--classify')
    # Check for icon support without running the help command every time
    # if ! z::state::exists "_zcore_eza_no_icons"; then
    if eza --help 2>&1 \
      | command grep -q -- '--icons'; then
      base_opts+=('--icons')
    else
      typeset -g _zcore_eza_no_icons=1
    fi
    # fi
    local eza_cmd="eza ${base_opts[*]}"
    z::alias::define ls "$eza_cmd"
    z::alias::define ll "$eza_cmd --long --header --git --time-style=long-iso"
    z::alias::define l "$eza_cmd --all --long --header --git --time-style=long-iso"
    z::alias::define lt "$eza_cmd --tree --level=3"
    z::log::info "Configured eza as ls replacement."
  elif z::cmd::exists "lsd"; then
    z::alias::define ls 'lsd --group-directories-first --color=always --icon=auto'
    z::alias::define ll 'lsd --long'
    z::alias::define l 'lsd -al'
    z::alias::define lt 'lsd --tree --depth=3'
    z::log::info "Configured lsd as ls replacement."
  else
    local ls_base="ls -F"
    ((!IS_MACOS)) \
      && ls_base+=" --color=auto --group-directories-first"
    ((IS_MACOS)) \
      && ls_base+=" -G"
    z::alias::define ls "$ls_base"
    z::alias::define ll "$ls_base -lh"
    z::alias::define l "$ls_base -Alh"
    z::log::info "Configured system ls with enhanced options."
  fi
}

###
# Creates a fallback `tree` command if the system version isn't installed.
###
z::mod::ls::_setup_tree_fallback()
{
  emulate -L zsh
  z::runtime::check_interrupted \
    || return $?

  if ! z::cmd::exists "tree"; then
    tree()
    {
      # Simple, safe fallback using find
      command find "${1:-.}" -maxdepth "${2:-3}" -print \
        | command sed -e 's;[^/]*/;|____;g;s;____|; |;g'
    }
    z::log::info "System 'tree' not found. Created a fallback function."
  fi
}

# ==============================================================================
# MAIN INITIALIZATION
# ==============================================================================
z::mod::ls::init()
{
  emulate -L zsh
  z::runtime::check_interrupted \
    || return $?
  z::log::info "Initializing ls enhancements..."

  z::mod::ls::_setup_colors
  z::mod::ls::_setup_ls_aliases
  z::mod::ls::_setup_tree_fallback

  z::log::info "LS enhancements initialized successfully."
}

if z::func::exists "z::mod::ls::init"; then
  z::mod::ls::init
fi
