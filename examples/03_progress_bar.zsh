#!/usr/bin/env zsh

if [[ ! -f "${0:h}/../zcore.zsh" ]]; then
  print -r -- "ERROR: zcore.zsh not found. Please run this script from the 'examples' directory." >&2
  exit 1
fi
source "${0:h}/../zcore.zsh" || exit 1

z::log::info "--- Zcore Progress Bar Demo ---"
z::log::info "This loop will run for 250 iterations. Press Ctrl+C to interrupt."

local -i total_items=250
local -i i
local start=${EPOCHREALTIME:-$SECONDS}
local show_progress=0

if z::config::get show_progress 2>/dev/null && [[ $REPLY == true ]]; then
  show_progress=1
fi

for (( i = 1; i <= total_items; i++ )); do
  z::runtime::check_interrupted || break

  sleep 0.02

  if (( show_progress )); then
    if (( ${_zlog_config[level]:-2} >= _ZLOG_LEVEL_INFO )); then
      z::progress::show "$i" "$total_items" "widgets" --since "$start" --newline
    else
      z::progress::show "$i" "$total_items" "widgets" --since "$start"
    fi
  fi
done

if z::runtime::check_interrupted; then
  z::progress::clear
  z::log::warn "Operation was cancelled by the user at item ${i}."
  exit 130
fi

if (( show_progress )); then
  z::progress::finish "Processing complete" --since "$start" --total "$total_items" --loaded "$i"
else
  z::log::info "Processing complete."
fi

z::log::info "--- Demo Complete ---"

# ------------------------------------------------------------------------------
#
# This script demonstrates the interactive UI progress bar.
#
# 1.  It sets up a loop to run for a fixed number of iterations.
# 2.  Inside the loop, it calls `z::progress::show`, passing the
#     current count, the total, and a descriptive label. Zcore's
#     internal throttling mechanism ensures the bar doesn't update on
#     every single iteration, which maintains performance.
# 3.  Crucially, it calls `z::runtime::check_interrupted` at the start of
#     each loop iteration. This allows the script to detect if the user
#     has pressed Ctrl+C and break the loop gracefully.
# 4.  After the loop, it checks the interrupt status again to provide
#     a final, appropriate message to the user.
#
# ------------------------------------------------------------------------------
