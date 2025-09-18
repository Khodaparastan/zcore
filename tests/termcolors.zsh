#!/usr/bin/env zsh

echo "--- Zsh Color Capability Test ---"
echo "Current TERM is: $TERM"
echo

# --- TEST 1: Before compinit ---
echo "Running color check BEFORE compinit is initialized..."
if [[ -t 2 ]] && command -v tput >/dev/null && tput setaf 1 >/dev/null 2>&1; then
    echo "  Result: SUCCESS. Colors would be enabled."
else
    # Grab the exit code from the failed tput command
    local tput_exit_code=$?
    echo "  Result: FAILURE. Colors would be disabled."
    echo "  (tput exit code was: $tput_exit_code)"
fi
echo

# --- Initialize the completion system ---
echo "Running 'autoload -Uz compinit && compinit'..."
autoload -Uz compinit && compinit
echo "Compinit has finished."
echo

# --- TEST 2: After compinit ---
echo "Running color check AFTER compinit is initialized..."
if [[ -t 2 ]] && command -v tput >/dev/null && tput setaf 1 >/dev/null 2>&1; then
    echo "  Result: SUCCESS. Colors would be enabled."
else
    local tput_exit_code=$?
    echo "  Result: FAILURE. Colors would be disabled."
    echo "  (tput exit code was: $tput_exit_code)"
fi
echo
echo "--- End of Test ---"
