#!/usr/bin/env zsh

if [[ ! -f "${0:h}/../zcore.zsh" ]]; then
  print -r -- "ERROR: zcore.zsh not found. Please run this script from the 'examples' directory." >&2
  exit 1
fi
source "${0:h}/../zcore.zsh" || exit 1

z::log::info "--- Zcore Logging and Configuration Demo ---"

z::log::get_level

z::log::info "This is an informational message."
z::log::warn "This is a warning message."
z::log::error "This is an error message."

z::log::debug "This debug message will NOT be visible by default."

z::log::info "Enabling debug mode..."
z::log::enable_debug

z::log::get_level
z::log::debug "This debug message IS visible now."

z::log::info "Changing a configuration value..."
z::config::set "timeout_default" "90"
z::log::debug "Configuration 'timeout_default' is now set to 90."

z::log::info "--- Demo Complete ---"

# ------------------------------------------------------------------------------
#
# This script demonstrates the core logging and configuration features of Zcore.
#
# 1.  It begins by showing the default logging level, which is 'info' (2).
# 2.  It prints messages at various levels. Note that the initial 'debug'
#     message is not displayed because the verbosity level is too low.
# 3.  It then calls `z::log::enable_debug` to raise the verbosity level.
# 4.  A second 'debug' message is logged, which is now visible.
# 5.  Finally, it uses `z::config::set` to modify a framework setting at
#     runtime and logs the change.
#
# ------------------------------------------------------------------------------
