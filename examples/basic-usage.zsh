#!/usr/bin/env zsh
################################################################################
# Z - BASIC USAGE EXAMPLES
################################################################################

# Load z
source "${0:A:h}/../z.zsh"

################################################################################
# EXAMPLE 1: Logging
################################################################################
print "\n=== Example 1: Logging ==="

z::log::info "Application started"
z::log::warn "This is a warning message"
z::log::error "This is an error message"

# Enable debug logging
z::log::set_level debug
z::log::debug "Debug information: variable=$USER"

# Reset to info level
z::log::set_level info

################################################################################
# EXAMPLE 2: Platform Detection
################################################################################
print "\n=== Example 2: Platform Detection ==="

z::detect::platform

if (( IS_MACOS )); then
  z::log::info "Running on macOS"
elif (( IS_LINUX )); then
  z::log::info "Running on Linux"
  if (( IS_WSL )); then
    z::log::info "  - Inside WSL"
  fi
elif (( IS_BSD )); then
  z::log::info "Running on BSD"
fi

################################################################################
# EXAMPLE 3: Safe Command Execution
################################################################################
print "\n=== Example 3: Safe Command Execution ==="

# Execute safe commands
z::log::info "Listing /tmp directory:"
z::exec::run "ls -lh /tmp | head -5"

# This will be blocked by security checks
z::log::info "Attempting dangerous command (will be blocked):"
z::exec::run "rm -rf /"

################################################################################
# EXAMPLE 4: Progress Bars
################################################################################
print "\n=== Example 4: Progress Bars ==="

z::log::info "Processing files..."
typeset -i total=50
for i in {1..$total}; do
  z::ui::progress::show $i $total "files"
  sleep 0.05  # Simulate work
done

################################################################################
# EXAMPLE 5: Configuration
################################################################################
print "\n=== Example 5: Configuration ==="

z::log::info "Current cache size: $(z::config::get cache_max_size)"
z::config::set cache_max_size 150
z::log::info "Updated cache size: $(z::config::get cache_max_size)"

# Reset to default
z::config::set cache_max_size 100

################################################################################
# EXAMPLE 6: Path Operations
################################################################################
print "\n=== Example 6: Path Operations ==="

# Resolve paths
resolved=$(z::path::resolve "~/.zshrc")
z::log::info "Resolved path: $resolved"

# Add to PATH (if directory exists)
if [[ -d ~/bin ]]; then
  z::path::add ~/bin prepend
  z::log::info "Added ~/bin to PATH"
fi

################################################################################
# EXAMPLE 7: Caching
################################################################################
print "\n=== Example 7: Command Caching ==="

# Check command existence (cached)
if z::cmd::exists git; then
  z::log::info "Git is installed"
  z::exec::run "git --version"
else
  z::log::warn "Git is not installed"
fi

# Check function existence
if z::func::exists z::log::info; then
  z::log::info "z::log::info function exists"
fi

################################################################################
# EXAMPLE 8: Number Formatting
################################################################################
print "\n=== Example 8: Number Formatting ==="

formatted=$(z::util::comma 1234567)
z::log::info "Formatted number: $formatted"

formatted=$(z::util::comma 9876543210)
z::log::info "Large number: $formatted"

################################################################################
# COMPLETION
################################################################################
print "\n=== Examples Complete ==="
z::log::info "All basic examples completed successfully"
