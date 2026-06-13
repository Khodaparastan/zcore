#!/usr/bin/env zsh

if [[ ! -f "${0:h}/../zcore.zsh" ]]; then
  print -r -- "ERROR: zcore.zsh not found. Please run this script from the 'examples' directory." >&2
  exit 1
fi
source "${0:h}/../zcore.zsh" || exit 1

z::log::info "--- Zcore Shell Hook Initialization Demo ---"
z::log::info "Attempting to initialize Starship, Zoxide, and Direnv..."
z::log::info "This will only work if the tools are installed and in your PATH."

z::exec::from_hook "starship"
z::exec::from_hook "zoxide"
z::exec::from_hook "direnv" "hook"

z::log::info "Initialization calls are complete."
z::log::info "Checking if zoxide was successfully initialized..."

if z::func::exists "_z"; then
  z::log::info "Success: The zoxide function '_z' now exists in this shell."
else
  z::log::warn "The zoxide function '_z' does not exist. Is zoxide installed?"
fi

z::log::info "--- Demo Complete ---"

# ------------------------------------------------------------------------------
#
# This script demonstrates the high-level `z::exec::from_hook` helper, which
# is the safest and most reliable way to initialize modern shell tools.
#
# 1.  It calls `z::exec::from_hook` for three common tools: starship, zoxide,
#     and direnv.
# 2.  Zcore handles the details:
#     - It first checks if the command (e.g., "starship") exists. If not, it
#       silently does nothing.
#     - It captures the output of the tool's init command (e.g., `starship init zsh`).
#     - It evaluates this output in the *current* shell, which is necessary
#       for these tools to define their functions and aliases.
# 3.  To provide proof that it worked, the script then uses `z::func::exists`
#     to check for the `_z` function, which is created by `zoxide init zsh`.
#
# ------------------------------------------------------------------------------
