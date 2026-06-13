#!/usr/bin/env zsh
#
# zinit Plugin Manager Module
# Handles the installation and configuration of the zinit plugin manager
# and its plugins.
#

# ==============================================================================
# PRIVATE HELPERS
# ==============================================================================

###
# Checks for network connectivity by attempting to reach a public host.
#
# @param 1: integer - Timeout in seconds (default: 3).
# @return 0 on success, 1 on failure.
###
__z::mod::zi::check_network() {
  emulate -L zsh
  local -i timeout=${1:-3}
  local host="google.com"

  if ! z::probe::cmd "ping"; then
    z::log::warn "ping not found — cannot verify network connectivity."
    return 1
  fi

  # macOS/BSD use `-t <seconds>`; GNU/Linux use `-W <seconds>` (reply wait).
  local -a args=(-c 1 -q)
  case "${_Z_UNAME_S:-$(uname -s 2>/dev/null)}" in
    Darwin|*BSD) args+=(-t "$timeout") ;;
    *)           args+=(-W "$timeout") ;;
  esac

  ping "${args[@]}" "$host" &>/dev/null
}

###
# Installs the zinit plugin manager if not present, then sources it.
#
# @return 0 on success, 1 on failure.
###
__z::mod::zi::install() {
  emulate -L zsh

  typeset -g ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
  typeset -g ZINIT_SCRIPT="${ZINIT_HOME}/zinit.zsh"

  # ── Already installed ────────────────────────────────────────────────────
  if [[ -f "$ZINIT_SCRIPT" ]]; then
    if z::file::source --global "$ZINIT_SCRIPT"; then
      z::log::debug "zinit already installed; sourced from: $ZINIT_HOME"
      return 0
    fi
    z::log::error "Found zinit at $ZINIT_SCRIPT but failed to source it."
    return 1
  fi

  # ── Fresh install ────────────────────────────────────────────────────────
  z::log::info "zinit not found — attempting installation..."

  if ! __z::mod::zi::check_network 3; then
    z::log::warn "No network connectivity — skipping zinit installation."
    return 1
  fi

  if ! z::probe::cmd "git"; then
    z::log::error "git is required to install zinit but was not found."
    return 1
  fi

  z::log::info "Cloning zinit into $ZINIT_HOME..."
  if ! command git clone --depth 1 --single-branch \
       https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"; then
    z::log::error "git clone failed — zinit installation aborted."
    [[ -d "$ZINIT_HOME" ]] && command rm -rf -- "$ZINIT_HOME"
    return 1
  fi

  if [[ ! -f "$ZINIT_SCRIPT" ]]; then
    z::log::error "Clone succeeded but zinit.zsh not found at: $ZINIT_SCRIPT"
    return 1
  fi

  if z::file::source --global "$ZINIT_SCRIPT"; then
    z::log::info "zinit installed and sourced successfully."
    return 0
  fi
  z::log::error "Failed to source newly installed zinit script."
  return 1
}

###
# Loads user-defined plugins via zinit.
#
# @return 0 on success, 1 if zinit is not available.
###
__z::mod::zi::load_plugins() {
  emulate -L zsh

  if (( ! ${+functions[zinit]} )); then
    z::log::error "zinit function not available — cannot load plugins."
    return 1
  fi

  # ── Annexes (must come first) ────────────────────────────────────────────
  zinit light-mode for \
    zdharma-continuum/zinit-annex-as-monitor \
    zdharma-continuum/zinit-annex-bin-gem-node \
    zdharma-continuum/zinit-annex-patch-dl \
    zdharma-continuum/zinit-annex-rust

  # ── history-search-multi-word ────────────────────────────────────────────
  zstyle ':plugin:history-search-multi-word' reset-prompt-protect 1
  zstyle ':history-search-multi-word'        page-size            8
  typeset -gAx HSMW_HIGHLIGHT_STYLES
  HSMW_HIGHLIGHT_STYLES[path]="bg=magenta,fg=white,bold"
  zinit load zdharma-continuum/history-search-multi-word

  # ── Core UX plugins ──────────────────────────────────────────────────────
  zinit light zsh-users/zsh-syntax-highlighting
  zinit light zsh-users/zsh-autosuggestions
  zinit light zsh-users/zsh-completions

  # ── Utilities ────────────────────────────────────────────────────────────
  zinit sbin'bin/zsweep' for @psprint/zsh-sweep
  zinit pack  for ls_colors
  zinit light denisidoro/navi

  z::log::debug "zinit plugins loaded."
  return 0
}

# ==============================================================================
# PUBLIC ENTRY POINT
# ==============================================================================

###
# Installs zinit (if necessary) and loads all configured plugins.
###
__z::mod::zi::init() {
  emulate -L zsh

  # Only run inside interactive shells.
  [[ -o interactive ]] || return 0

  z::log::info "Initializing zinit module..."

  if ! __z::mod::zi::install; then
    z::log::error "zinit installation failed — plugins will not be loaded."
    return 1
  fi

  autoload -Uz _zinit
  (( ${+_comps} )) && _comps[zinit]=_zinit

  if ! __z::mod::zi::load_plugins; then
    z::log::error "Plugin loading failed."
    return 1
  fi

  z::log::info "zinit module initialized."
  return 0
}

# ==============================================================================
# MODULE EXECUTION
# ==============================================================================

__z::mod::zi::init
