#!/usr/bin/env zsh
#
# zinit Plugin Manager Module
# Handles the installation and configuration of the zinit plugin manager and its plugins.
#

# ==============================================================================
# PRIVATE HELPERS
# ==============================================================================

###
# Checks for network connectivity by pinging a reliable public DNS server.
#
# @param 1: integer - Timeout in seconds (default: 3).
# @return 0 on success, 1 on failure.
###
__z::mod::zi::check_network()
{
  emulate -L zsh
  local -i timeout=${1:-3}
  local host="google.com"

  if ! z::probe::cmd "ping"; then
    z::log::warn "ping command not found, cannot check network status."
    return 1
  fi

  # Use flags compatible with both macOS/BSD and Linux ping
  if ping -c 1 -W "${timeout}000" "$host" > /dev/null 2>&1 \
    || \
    ping -c 1 -t "$timeout" "$host" > /dev/null 2>&1; then
    return 0
  fi
  return 1
}

###
# Installs the zinit plugin manager if it's not already present.
###
__z::mod::zi::install()
{
  emulate -L zsh
  typeset -g ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
  typeset -g ZINIT_SCRIPT="$ZINIT_HOME/zinit.zsh"

  if [[ -f "$ZINIT_SCRIPT" ]]; then
    if z::file::source "$ZINIT_SCRIPT"; then
      z::log::debug "zinit already installed and sourced from: $ZINIT_HOME"
      return 0
    else
      z::log::error "Found zinit script at $ZINIT_SCRIPT but failed to source it."
      return 1
    fi
  fi

  z::log::info "zinit plugin manager not found. Attempting installation..."

  if ! __z::mod::zi::check_network 3; then
    z::log::warn "No network connectivity. Skipping zinit installation."
    return 1
  fi

  if ! z::probe::cmd "git"; then
    z::log::error "git is required to install ZI, but it was not found."
    return 1
  fi
  # https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME" > /dev/null 2>&1; then

  z::log::info "Installing zinit to $ZINIT_HOME..."
  if ! command git clone --depth 1 --single-branch \
    https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"; then
    z::log::error "zinit installation (git clone) failed."
    [[ -d "$ZINIT_HOME" ]] \
      && command rm -rf -- "$ZINIT_HOME" 2> /dev/null
    return 1
  fi
  # if [[ ! -f $HOME/.local/share/zinit/zinit.git/zinit.zsh ]]; then
  #     print -P "%F{33} %F{220}Installing %F{33}ZDHARMA-CONTINUUM%F{220} Initiative Plugin Manager (%F{33}zdharma-continuum/zinit%F{220})…%f"
  #     command mkdir -p "$HOME/.local/share/zinit" && command chmod g-rwX "$HOME/.local/share/zinit"
  #     command git clone https://github.com/zdharma-continuum/zinit "$HOME/.local/share/zinit/zinit.git" && \
  #         print -P "%F{33} %F{34}Installation successful.%f%b" || \
  #         print -P "%F{160} The clone has failed.%f%b"
  # fi

  source "$HOME/.local/share/zinit/zinit.git/zinit.zsh"


  if [[ -f "$ZINIT_SCRIPT" ]]; then
    if z::file::source "$ZINIT_SCRIPT"; then
      z::log::info "zinit installed and sourced successfully."
      return 0
    else
      z::log::error "Failed to source newly installed zinit script."
      return 1
    fi
  else
    z::log::error "zinit cloned, but zi.zsh script not found at expected path: $ZINIT_SCRIPT"
    return 1
  fi
}

###
# Loads all user-defined plugins and configurations using ZI.
###
__z::mod::zi::load_plugins()
{
  emulate -L zsh


  ((!${+functions[zinit]})) \
    && return 1

  # --- Begin User Plugin Configuration ---
  zinit light-mode for \
      zdharma-continuum/zinit-annex-as-monitor \
      zdharma-continuum/zinit-annex-bin-gem-node \
      zdharma-continuum/zinit-annex-patch-dl \
      zdharma-continuum/zinit-annex-rust


  zstyle :plugin:history-search-multi-word reset-prompt-protect 1
  zstyle ":history-search-multi-word" page-size "8"
  typeset -gAx HSMW_HIGHLIGHT_STYLES
  HSMW_HIGHLIGHT_STYLES[path]="bg=magenta,fg=white,bold"
  zinit load zdharma-continuum/history-search-multi-word
  zinit light zsh-users/zsh-syntax-highlighting
  zinit light zsh-users/zsh-autosuggestions
  zinit light zsh-users/zsh-completions
  zinit sbin'bin/zsweep' for @psprint/zsh-sweep
  # zinit ice eval"dircolors -b LS_COLORS" \
  #   atload'zstyle ":completion:*" list-colors ${(s.:.)LS_COLORS}'
  zinit light trapd00r/LS_COLORS
  zinit pack for ls_colors
  zinit light denisidoro/navi

  # --- End User Plugin Configuration ---

  z::log::debug "zinit plugins loaded successfully"
  return 0
}

# ==============================================================================
# MAIN INITIALIZATION ORCHESTRATOR
# ==============================================================================

###
# Public entry point to install zinit and load all configured plugins.
###
__z::mod::zi::init()
{
  emulate -L zsh

  z::log::info "Initializing zinit plugin manager module..."

  if __z::mod::zi::install; then
    autoload -Uz _zinit
    (( ${+_comps} )) && _comps[zinit]=_zinit
    __z::mod::zi::load_plugins
  else
    z::log::error "zinit installation failed. Cannot load plugins."
    return 1
  fi

  z::log::info "zinit module initialized successfully."
  return 0
}

# ==============================================================================
# MODULE EXECUTION
# ==============================================================================

# Auto-initialize the module when it is sourced.
if z::probe::func "__z::mod::zi::init"; then
  __z::mod::zi::init
fi
