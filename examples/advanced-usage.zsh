#!/usr/bin/env zsh
################################################################################
# Z - ADVANCED USAGE EXAMPLES
################################################################################

# Load z
source "${0:A:h}/../z.zsh"

z::log::set_level debug

################################################################################
# EXAMPLE 1: Custom Configuration
################################################################################
print "\n=== Example 1: Custom Configuration ==="

# Export current configuration
config_file="/tmp/z-config-$$.txt"
z::config::export "$config_file"
z::log::info "Configuration exported to: $config_file"

# Modify configuration
z::config::set_int timeout_default 60
z::config::set_bool performance_mode false
z::log::info "Configuration updated"

# Validate configuration
if z::config::validate; then
  z::log::info "Configuration is valid"
fi

# Cleanup
rm -f "$config_file"

################################################################################
# EXAMPLE 2: Shell Integration
################################################################################
print "\n=== Example 2: Shell Integration ==="

# Initialize tools from hooks (if installed)
z::log::info "Attempting to initialize shell tools..."

# These will only run if the tools are installed
z::exec::from_hook starship init zsh
z::exec::from_hook zoxide init zsh
z::exec::from_hook direnv hook zsh

z::log::info "Shell integration complete"

################################################################################
# EXAMPLE 3: Batch Processing with Progress
################################################################################
print "\n=== Example 3: Batch Processing ==="

# Create temporary test files
temp_dir="/tmp/z-test-$$"
mkdir -p "$temp_dir"

z::log::info "Creating test files..."
for i in {1..20}; do
  echo "Test file $i" > "$temp_dir/file_$i.txt"
done

# Process files with progress bar
z::log::info "Processing files..."
typeset -a files=("$temp_dir"/*.txt)
typeset -i total=${#files}
typeset -i current=0

for file in "${files[@]}"; do
  (( current += 1 ))
  z::ui::progress::show $current $total "files"

  # Simulate processing
  z::exec::run "wc -l $file" >/dev/null

  # Check for interrupts
  z::runtime::check_interrupted || break
done

# Cleanup
rm -rf "$temp_dir"
z::log::info "Batch processing complete"

################################################################################
# EXAMPLE 4: Error Handling
################################################################################
print "\n=== Example 4: Error Handling ==="

# Function with error handling
process_file() {
  local file="$1"

  if [[ ! -f $file ]]; then
    z::log::error "File not found: $file"
    return 1
  fi

  if ! z::exec::run "cat $file" 10; then
    z::log::error "Failed to read file: $file"
    return 1
  fi

  z::log::info "Successfully processed: $file"
  return 0
}

# Test error handling
if process_file "/etc/hosts"; then
  z::log::info "File processing succeeded"
else
  z::log::warn "File processing failed"
fi

################################################################################
# EXAMPLE 5: Async Execution
################################################################################
print "\n=== Example 5: Async Execution ==="

# Callback function
async_callback() {
  local exit_code="$1"
  local result="$2"

  if (( exit_code == 0 )); then
    z::log::info "Async task completed successfully"
  else
    z::log::error "Async task failed with code: $exit_code"
  fi
}

# Start async task
z::log::info "Starting async task..."
job_id=$(z::exec::run_async "sleep 2 && echo 'Done'" "async_callback")
z::log::info "Job started with ID: $job_id"

# Wait for completion
z::log::info "Waiting for async tasks..."
z::exec::wait_all
z::log::info "All async tasks complete"

################################################################################
# EXAMPLE 6: State Management
################################################################################
print "\n=== Example 6: State Management ==="

# Create temporary variables and functions
TEST_VAR="test_value"
test_temp_func() {
  z::log::info "Temporary function called"
}

z::log::info "Created TEST_VAR and test_temp_func"

# Check existence
if (( ${+TEST_VAR} )); then
  z::log::info "TEST_VAR exists: $TEST_VAR"
fi

if z::func::exists test_temp_func; then
  z::log::info "test_temp_func exists"
  z::func::call test_temp_func
fi

# Clean up
z::var::unset TEST_VAR
z::func::unset test_temp_func

z::log::info "Cleaned up temporary state"

################################################################################
# EXAMPLE 7: Debug Utilities
################################################################################
print "\n=== Example 7: Debug Utilities ==="

# Profile a section of code
z::debug::profile_start

# Simulate work
for i in {1..1000}; do
  : # No-op
done

z::debug::profile_end "loop_test"

# Dump configuration
z::log::info "Configuration dump:"
z::debug::dump_config

# Stack trace
test_trace_func() {
  z::debug::trace
}

z::log::info "Stack trace example:"
test_trace_func

################################################################################
# EXAMPLE 8: Security Testing
################################################################################
print "\n=== Example 8: Security Testing ==="

z::log::info "Testing security features..."

# These should all be blocked
typeset -a dangerous_commands=(
  "rm -rf /"
  "dd if=/dev/zero of=/dev/sda"
  "chmod -R 777 /"
  ":(){ :|:& };:"
  "killall -9 init"
)

for cmd in "${dangerous_commands[@]}"; do
  z::log::info "Testing: $cmd"
  if z::exec::run "$cmd" 2>/dev/null; then
    z::log::error "SECURITY FAILURE: Command was not blocked!"
  else
    z::log::info "✓ Command blocked successfully"
  fi
done

################################################################################
# EXAMPLE 9: Terminal UI
################################################################################
print "\n=== Example 9: Terminal UI ==="

# Get terminal width
width=$(z::ui::term::width)
z::log::info "Terminal width: $width columns"

# Toggle progress bars
z::log::info "Toggling progress bars..."
z::ui::toggle_progress
z::ui::toggle_progress  # Toggle back

# Format large numbers
numbers=(100 1000 10000 100000 1000000 1234567890)
z::log::info "Number formatting:"
for num in "${numbers[@]}"; do
  formatted=$(z::util::comma $num)
  z::log::info "  $num → $formatted"
done

################################################################################
# COMPLETION
################################################################################
print "\n=== Advanced Examples Complete ==="
z::log::info "All advanced examples completed successfully"
