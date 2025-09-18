#!/usr/bin/env zsh
#
# Zsh Options Module
# Configures shell behavior via `setopt` and sets up history.
#

# ==============================================================================
# MAIN INITIALIZATION
# ==============================================================================
z::mod::options::init()
{
  emulate -L zsh
  z::runtime::check_interrupted \
    || return $?
  z::log::info "Configuring shell options..."

  # --- History Setup ---
  typeset -gi HISTSIZE=50000
  typeset -gi SAVEHIST=$HISTSIZE

  # HISTFILE is already set by the environment module's XDG setup.
  # We just ensure the file and its parent directory have secure permissions.
  if [[ -n "$HISTFILE" ]]; then
    local hist_dir="${HISTFILE:h}"
    if [[ -d "$hist_dir" && -O "$hist_dir" ]]; then
      chmod 700 "$hist_dir" 2> /dev/null
    fi
    if [[ ! -e "$HISTFILE" ]]; then
      : >| "$HISTFILE" 2> /dev/null
    fi
    if [[ -e "$HISTFILE" && -O "$HISTFILE" ]]; then
      chmod 600 "$HISTFILE" 2> /dev/null
    fi
  fi

  # --- History Behavior ---
  setopt EXTENDED_HISTORY
  setopt APPEND_HISTORY
  setopt INC_APPEND_HISTORY_TIME
  unsetopt SHARE_HISTORY # Avoids messy history from multiple concurrent sessions
  setopt HIST_IGNORE_SPACE
  setopt HIST_EXPIRE_DUPS_FIRST
  setopt HIST_IGNORE_DUPS
  setopt HIST_FIND_NO_DUPS
  setopt HIST_REDUCE_BLANKS
  setopt HIST_SAVE_NO_DUPS

  # --- Navigation & Interaction ---
  setopt AUTO_CD
  setopt AUTO_PUSHD
  setopt PUSHD_IGNORE_DUPS
  setopt AUTO_MENU
  setopt INTERACTIVE_COMMENTS
  setopt NOTIFY
  setopt LONG_LIST_JOBS

  # --- Safety & UX ---
  setopt NO_CLOBBER # Prevent overwriting files with `>`
  setopt NO_BEEP
  setopt NO_FLOW_CONTROL

  z::log::info "Shell options configured successfully."
}

if z::func::exists "z::mod::options::init"; then
  z::mod::options::init
fi
