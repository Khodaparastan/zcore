#!/usr/bin/env zsh
# Zsh Options Module



z::log::info "Configuring shell options..."

# Validate HISTFILE
if [[ -z "${HISTFILE:-}" ]]; then
  z::log::error "HISTFILE is not set. History will not be saved."
  return 1
fi

# Set history size with explicit integer typing
typeset -gi HISTSIZE=500000
typeset -gi SAVEHIST=500000
z::log::debug "HISTFILE: $HISTFILE | HISTSIZE: $HISTSIZE | SAVEHIST: $SAVEHIST"

# Create history directory if needed
local hist_dir="${HISTFILE:h}"
if [[ ! -d "$hist_dir" ]]; then
  z::log::debug "Creating history directory: $hist_dir"
  if ! mkdir -p "$hist_dir" 2>/dev/null; then
    z::log::error "Failed to create history directory: $hist_dir"
    return 1
  fi
  chmod 700 "$hist_dir" 2>/dev/null
fi

# Create history file if needed
if [[ ! -e "$HISTFILE" ]]; then
  z::log::debug "Creating history file: $HISTFILE"
  if ! touch "$HISTFILE" 2>/dev/null; then
    z::log::error "Failed to create history file: $HISTFILE"
    return 1
  fi
  chmod 600 "$HISTFILE" 2>/dev/null
fi

# Verify writable
if [[ ! -w "$HISTFILE" ]]; then
  z::log::error "History file is not writable: $HISTFILE"
  return 1
fi

z::log::info "History file ready: $HISTFILE"

z::log::info "Setting shell options at module top level..."

# History Management
setopt EXTENDED_HISTORY          # Write the history file in the ':start:elapsed;command' format
setopt APPEND_HISTORY            # Append history to the history file (no overwriting)
setopt INC_APPEND_HISTORY        # Write to the history file immediately, not when the shell exits
setopt SHARE_HISTORY             # Share history between all sessions
setopt HIST_IGNORE_SPACE         # Don't record an entry starting with a space
setopt HIST_EXPIRE_DUPS_FIRST    # Expire duplicate entries first when trimming history
setopt HIST_IGNORE_DUPS          # Don't record an entry that was just recorded again
setopt HIST_FIND_NO_DUPS         # Don't display duplicates when searching history
setopt HIST_REDUCE_BLANKS        # Remove superfluous blanks before recording entry
setopt HIST_SAVE_NO_DUPS         # Don't write duplicate entries in the history file
setopt HIST_VERIFY               # Don't execute immediately upon history expansion

# Navigation & Directory Management
setopt AUTO_CD                   # Change directory without 'cd' command
setopt AUTO_PUSHD                # Push the old directory onto the stack on cd
setopt PUSHD_IGNORE_DUPS         # Don't push multiple copies of the same directory

# Completion & Menu
setopt AUTO_MENU                 # Show completion menu on successive tab press
setopt COMPLETE_IN_WORD          # Complete from both ends of a word
setopt PATH_DIRS                 # Perform path search even on command names with slashes

# Input/Output & Behavior
setopt INTERACTIVE_COMMENTS      # Allow comments in interactive shell
setopt NOTIFY                    # Report status of background jobs immediately
setopt LONG_LIST_JOBS            # List jobs in the long format by default
setopt GLOB_DOTS                 # Include dotfiles in globbing
# setopt NO_CLOBBER                # Don't overwrite existing files with > redirect
setopt NO_BEEP                   # Don't beep on errors
setopt NO_FLOW_CONTROL           # Disable start/stop characters (Ctrl+S/Ctrl+Q)

z::log::debug "Verifying options immediately after setting..."

if [[ -o INC_APPEND_HISTORY ]] && [[ -o EXTENDED_HISTORY ]]; then
  z::log::info "✓ History options verified: ON"
else
  z::log::error "✗ Options verification FAILED"
  if [[ -o INC_APPEND_HISTORY ]]; then
    z::log::error "  INC_APPEND_HISTORY: ON"
  else
    z::log::error "  INC_APPEND_HISTORY: OFF"
  fi
  if [[ -o EXTENDED_HISTORY ]]; then
    z::log::error "  EXTENDED_HISTORY: ON"
  else
    z::log::error "  EXTENDED_HISTORY: OFF"
  fi
  z::log::error ""
  z::log::error "This indicates the sourcing context is using local scope."
  z::log::error "Check that z::file::source is using --global flag correctly."
  return 1
fi

z::log::info "Shell options configured successfully"

return 0
