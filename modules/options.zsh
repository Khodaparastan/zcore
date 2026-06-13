#!/usr/bin/env zsh
# Zsh Options Module

z::log::info "Configuring shell options..."

# ---------------------------------------------------------------------------
# History file validation & setup
# ---------------------------------------------------------------------------

if [[ -z "${HISTFILE:-}" ]]; then
  z::log::error "HISTFILE is not set. History will not be saved."
  return 1
fi

typeset -gi HISTSIZE=500000
typeset -gi SAVEHIST=500000
z::log::debug "HISTFILE: $HISTFILE | HISTSIZE: $HISTSIZE | SAVEHIST: $SAVEHIST"

typeset hist_dir="${HISTFILE:h}"

if [[ ! -d "$hist_dir" ]]; then
  z::log::debug "Creating history directory: $hist_dir"
  if ! command mkdir -p -- "$hist_dir" 2>/dev/null; then
    z::log::error "Failed to create history directory: $hist_dir"
    return 1
  fi
  command chmod 700 -- "$hist_dir" 2>/dev/null \
    || z::log::warn "Failed to set permissions on history directory: $hist_dir"
fi

if [[ ! -e "$HISTFILE" ]]; then
  z::log::debug "Creating history file: $HISTFILE"
  if ! : >> "$HISTFILE" 2>/dev/null; then
    z::log::error "Failed to create history file: $HISTFILE"
    return 1
  fi
  command chmod 600 -- "$HISTFILE" 2>/dev/null \
    || z::log::warn "Failed to set permissions on history file: $HISTFILE"
fi

if [[ ! -w "$HISTFILE" ]]; then
  z::log::error "History file is not writable: $HISTFILE"
  return 1
fi

z::log::info "History file ready: $HISTFILE"

# ---------------------------------------------------------------------------
# History options
#
# SHARE_HISTORY drives the interactive read/write cycle.  APPEND_HISTORY is
# kept on so that non-interactive zsh subshells don't truncate the file.
# ---------------------------------------------------------------------------
setopt EXTENDED_HISTORY          # Write ':start:elapsed;command' format
setopt SHARE_HISTORY             # Share history across sessions
setopt APPEND_HISTORY            # Append rather than overwrite on exit
setopt HIST_IGNORE_SPACE         # Don't record entries starting with a space
setopt HIST_EXPIRE_DUPS_FIRST    # Expire duplicates first when trimming
setopt HIST_IGNORE_DUPS          # Don't record consecutive duplicates
setopt HIST_FIND_NO_DUPS         # Don't display duplicates when searching
setopt HIST_REDUCE_BLANKS        # Strip superfluous blanks before recording
setopt HIST_SAVE_NO_DUPS         # Don't write duplicates to the history file
setopt HIST_VERIFY               # Show expanded history entry before executing

# ---------------------------------------------------------------------------
# Navigation & directory management
# ---------------------------------------------------------------------------
setopt AUTO_CD
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS

# ---------------------------------------------------------------------------
# Completion & menu
# ---------------------------------------------------------------------------
setopt AUTO_MENU
setopt COMPLETE_IN_WORD
setopt PATH_DIRS

# ---------------------------------------------------------------------------
# Input / output & general behaviour
# ---------------------------------------------------------------------------
setopt INTERACTIVE_COMMENTS
setopt NOTIFY
setopt LONG_LIST_JOBS
setopt GLOB_DOTS
setopt NO_BEEP
setopt NO_FLOW_CONTROL

# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------
z::log::debug "Verifying critical options..."

typeset -a _required_opts=(EXTENDED_HISTORY SHARE_HISTORY APPEND_HISTORY)
typeset -a _failed_opts=()
typeset _opt
for _opt in "${_required_opts[@]}"; do
  [[ -o "$_opt" ]] || _failed_opts+=("$_opt")
done

if (( ${#_failed_opts} == 0 )); then
  z::log::info "✓ History options verified."
  unset _opt _required_opts _failed_opts
else
  for _opt in "${_failed_opts[@]}"; do
    z::log::error "  $_opt: OFF (expected ON)"
  done
  unset _opt _required_opts _failed_opts
  z::log::error "Option verification failed — check that z::file::source uses global scope."
  return 1
fi

z::log::info "Shell options configured successfully."
return 0
