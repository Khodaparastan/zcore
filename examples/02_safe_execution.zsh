#!/usr/bin/env zsh

if [[ ! -f "${0:h}/../zcore.zsh" ]]; then
  print -r -- "ERROR: zcore.zsh not found. Please run this script from the 'examples' directory." >&2
  exit 1
fi
source "${0:h}/../zcore.zsh" || exit 1

z::log::info "--- Zcore Safe Execution Demo ---"

z::log::info "1. Running a successful command..."
if z::exec::run "echo 'Hello from a safe subshell!'"; then
  z::log::info "Command finished successfully as expected."
else
  z::log::error "Command failed unexpectedly."
fi

z::log::info "2. Running a failing command..."
if z::exec::run "ls /nonexistent-directory-12345"; then
  z::log::error "Command succeeded unexpectedly."
else
  z::log::warn "Command failed as expected. Exit code: $?"
fi

z::log::info "3. Running a command that will time out..."
if z::exec::run "sleep 5" 2; then
  z::log::error "Command did not time out as expected."
else
  local exit_code=$?
  if (( exit_code == 124 )); then
    z::log::info "Command timed out after 2 seconds, as expected."
  else
    z::log::warn "Command failed with an unexpected code: ${exit_code}"
  fi
fi

z::log::info "4. Attempting to run a potentially dangerous command..."
if z::exec::run "echo 'danger' | zsh"; then
  z::log::error "Security scanner failed to block the command."
else
  z::log::info "Command was successfully blocked by the security scanner."
fi

z::log::info "--- Demo Complete ---"

# ------------------------------------------------------------------------------
#
# This script demonstrates the `z::exec::run` function for safe command
# execution.
#
# 1.  **Success Case**: It runs a simple `echo` command, which should succeed.
# 2.  **Failure Case**: It runs `ls` on a non-existent directory to show
#     how failures and non-zero exit codes are correctly propagated.
# 3.  **Timeout Case**: It runs a `sleep 5` command but with a timeout of
#     only 2 seconds. It checks for the specific exit code `124`, which
#     indicates a timeout occurred.
# 4.  **Security Case**: It attempts to execute a "pipe-to-shell" pattern.
#     Zcore's internal security scanner detects this and prevents the
#     command from running.
#
# ------------------------------------------------------------------------------
