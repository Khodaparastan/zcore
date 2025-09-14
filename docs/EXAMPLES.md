# ZCore Usage Examples

This document provides practical examples of using the ZCore library in various scripting scenarios.

## Table of Contents

- [Basic Script Setup](#basic-script-setup)
- [Logging Examples](#logging-examples)
- [Safe Command Execution](#safe-command-execution)
- [Platform Detection](#platform-detection)
- [Path Management](#path-management)
- [State Management](#state-management)
- [Progress Tracking](#progress-tracking)
- [Error Handling](#error-handling)
- [Caching Examples](#caching-examples)
- [Complete Script Examples](#complete-script-examples)

## Basic Script Setup

### Minimal Script with ZCore

```zsh
#!/usr/bin/env zsh

# Source ZCore library
source /path/to/lib/core.zsh
source /path/to/lib/platform.zsh

# Basic usage
z::log::info "Script started"
z::detect::platform
z::log::info "Running on platform: $OSTYPE"
```

### Script with Error Handling

```zsh
#!/usr/bin/env zsh

# Source ZCore
source /path/to/lib/core.zsh

# Set up error handling
trap 'z::runtime::handle_interrupt' INT TERM

# Check for interrupts
z::runtime::check_interrupted || exit $?

z::log::info "Script running..."
```

## Logging Examples

### Basic Logging

```zsh
#!/usr/bin/env zsh
source /path/to/lib/core.zsh

# Different log levels
z::log::error "This is an error message"
z::log::warn "This is a warning message"
z::log::info "This is an info message"
z::log::debug "This is a debug message"

# Enable debug mode
z::log::enable_debug
z::log::debug "Debug mode enabled"

# Check current level
z::log::get_level
```

### Conditional Logging

```zsh
#!/usr/bin/env zsh
source /path/to/lib/core.zsh

# Log based on conditions
if [[ -f "/important/file" ]]; then
    z::log::info "Important file found"
else
    z::log::warn "Important file not found"
fi

# Log with variables
local count=42
z::log::info "Processing $count items"

# Log arrays
local -a files=("file1" "file2" "file3")
z::log::debug "Files to process: ${files[*]}"
```

### Logging in Functions

```zsh
#!/usr/bin/env zsh
source /path/to/lib/core.zsh

process_file() {
    local file="$1"

    if [[ -z "$file" ]]; then
        z::log::error "No file provided"
        return 1
    fi

    if [[ ! -f "$file" ]]; then
        z::log::warn "File does not exist: $file"
        return 1
    fi

    z::log::info "Processing file: $file"
    # ... processing logic ...
    z::log::info "File processed successfully: $file"
}

# Use the function
process_file "/path/to/file.txt"
```

## Safe Command Execution

### Basic Safe Execution

```zsh
#!/usr/bin/env zsh
source /path/to/lib/core.zsh

# Safe command execution with timeout
z::exec::run "ls -la" 30

# Safe evaluation
z::exec::eval "echo 'Hello World'" 10

# Check exit code
if z::exec::run "git status" 30; then
    z::log::info "Git status successful"
else
    z::log::warn "Git status failed"
fi
```

### Command Execution with Error Handling

```zsh
#!/usr/bin/env zsh
source /path/to/lib/core.zsh

run_command_safely() {
    local cmd="$1"
    local timeout="${2:-30}"

    z::log::info "Running command: $cmd"

    if z::exec::run "$cmd" "$timeout"; then
        z::log::info "Command succeeded: $cmd"
        return 0
    else
        local exit_code=$?
        z::log::error "Command failed (exit $exit_code): $cmd"
        return $exit_code
    fi
}

# Use the function
run_command_safely "ls -la"
run_command_safely "git status" 10
```

### Batch Command Execution

```zsh
#!/usr/bin/env zsh
source /path/to/lib/core.zsh

# Array of commands to execute
local -a commands=(
    "ls -la"
    "git status"
    "pwd"
    "whoami"
)

# Execute each command safely
for cmd in "${commands[@]}"; do
    z::log::info "Executing: $cmd"
    if z::exec::run "$cmd" 30; then
        z::log::info "✓ $cmd"
    else
        z::log::error "✗ $cmd"
    fi
done
```

## Platform Detection

### Basic Platform Detection

```zsh
#!/usr/bin/env zsh
source /path/to/lib/core.zsh
source /path/to/lib/platform.zsh

# Detect platform
z::detect::platform

# Check platform flags
if (( IS_MACOS )); then
    z::log::info "Running on macOS"
    # macOS-specific code
elif (( IS_LINUX )); then
    z::log::info "Running on Linux"
    # Linux-specific code
elif (( IS_BSD )); then
    z::log::info "Running on BSD"
    # BSD-specific code
else
    z::log::warn "Unknown platform"
fi
```

### Platform-Specific Operations

```zsh
#!/usr/bin/env zsh
source /path/to/lib/core.zsh
source /path/to/lib/platform.zsh

z::detect::platform

# Platform-specific package managers
if (( IS_MACOS )); then
    if z::cmd::exists "brew"; then
        z::log::info "Using Homebrew on macOS"
        z::exec::run "brew update" 60
    fi
elif (( IS_LINUX )); then
    if z::cmd::exists "apt"; then
        z::log::info "Using apt on Linux"
        z::exec::run "sudo apt update" 60
    elif z::cmd::exists "pacman"; then
        z::log::info "Using pacman on Linux"
        z::exec::run "sudo pacman -Sy" 60
    fi
fi
```

### WSL and Termux Detection

```zsh
#!/usr/bin/env zsh
source /path/to/lib/core.zsh
source /path/to/lib/platform.zsh

z::detect::platform

if (( IS_WSL )); then
    z::log::info "Running in WSL"
    # WSL-specific code
    export DISPLAY=:0
elif (( IS_TERMUX )); then
    z::log::info "Running in Termux"
    # Termux-specific code
    export PREFIX="/data/data/com.termux/files/usr"
fi
```

## Path Management

### Basic Path Operations

```zsh
#!/usr/bin/env zsh
source /path/to/lib/core.zsh

# Add directories to PATH
z::path::add "/usr/local/bin" prepend
z::path::add "$HOME/.local/bin" append

# Resolve paths
local resolved_path
if resolved_path=$(z::path::resolve "~/Documents"); then
    z::log::info "Resolved path: $resolved_path"
else
    z::log::error "Failed to resolve path"
fi
```

### Path Building Script

```zsh
#!/usr/bin/env zsh
source /path/to/lib/core.zsh
source /path/to/lib/platform.zsh

z::detect::platform

# Build PATH based on platform
if (( IS_MACOS )); then
    z::path::add "/opt/homebrew/bin" prepend
    z::path::add "/usr/local/bin" prepend
elif (( IS_LINUX )); then
    z::path::add "/usr/local/bin" prepend
    z::path::add "/snap/bin" append
fi

# Add user directories
z::path::add "$HOME/.local/bin" prepend
z::path::add "$HOME/bin" append

z::log::info "PATH updated: $PATH"
```

### Safe File Sourcing

```zsh
#!/usr/bin/env zsh
source /path/to/lib/core.zsh

# Source files safely
local -a config_files=(
    "~/.config/script1.zsh"
    "~/.config/script2.zsh"
    "~/.config/script3.zsh"
)

for file in "${config_files[@]}"; do
    if z::path::source "$file"; then
        z::log::info "Sourced: $file"
    else
        z::log::warn "Failed to source: $file"
    fi
done
```

## State Management

### Variable and Function Management

```zsh
#!/usr/bin/env zsh
source /path/to/lib/core.zsh

# Check if command exists (cached)
if z::cmd::exists "git"; then
    z::log::info "Git is available"
else
    z::log::warn "Git is not available"
fi

# Check if function exists (cached)
if z::func::exists "my_function"; then
    z::log::info "my_function is defined"
else
    z::log::warn "my_function is not defined"
fi

# Safe cleanup
z::state::unset "temp_variable"
z::func::unset "temp_function"
```

### Function Definition and Management

```zsh
#!/usr/bin/env zsh
source /path/to/lib/core.zsh

# Define a function
my_script_function() {
    local arg="$1"
    z::log::info "Processing: $arg"
    # ... function logic ...
}

# Check if function exists
if z::func::exists "my_script_function"; then
    z::log::info "Function is available"
    my_script_function "test"
else
    z::log::error "Function not available"
fi

# Clean up function
z::func::unset "my_script_function"
```

## Progress Tracking

### Basic Progress Display

```zsh
#!/usr/bin/env zsh
source /path/to/lib/core.zsh

# Simple progress tracking
local -i total=10
for ((i=1; i<=total; i++)); do
    z::ui::progress::show $i $total "processing items"
    # ... work ...
    sleep 0.1
done
```

### File Processing with Progress

```zsh
#!/usr/bin/env zsh
source /path/to/lib/core.zsh

process_files() {
    local -a files=("$@")
    local -i total=${#files[@]}
    local -i current=0

    for file in "${files[@]}"; do
        ((current++))
        z::ui::progress::show $current $total "processing files"

        if [[ -f "$file" ]]; then
            z::log::debug "Processing: $file"
            # ... process file ...
        else
            z::log::warn "File not found: $file"
        fi
    done
}

# Use the function
process_files file1.txt file2.txt file3.txt
```

### Progress with Error Handling

```zsh
#!/usr/bin/env zsh
source /path/to/lib/core.zsh

# Set up interrupt handling
trap 'z::runtime::handle_interrupt' INT TERM

process_with_progress() {
    local -i total="$1"

    for ((i=1; i<=total; i++)); do
        # Check for interrupts
        z::runtime::check_interrupted || return $?

        z::ui::progress::show $i $total "working"

        # ... work ...
        sleep 0.1
    done
}

process_with_progress 100
```

## Error Handling

### Basic Error Handling

```zsh
#!/usr/bin/env zsh
source /path/to/lib/core.zsh

# Fatal error handling
if [[ ! -f "/required/file" ]]; then
    z::runtime::die "Required file not found" 1
fi

# Recoverable error handling
if ! z::exec::run "optional_command" 30; then
    z::log::warn "Optional command failed, continuing..."
fi
```

### Comprehensive Error Handling

```zsh
#!/usr/bin/env zsh
source /path/to/lib/core.zsh

# Set up error handling
trap 'z::runtime::handle_interrupt' INT TERM

script_main() {
    # Check for interrupts
    z::runtime::check_interrupted || return $?

    # Validate prerequisites
    if ! z::cmd::exists "required_command"; then
        z::runtime::die "Required command not found" 1
    fi

    # Execute main logic
    if ! z::exec::run "main_command" 60; then
        z::log::error "Main command failed"
        return 1
    fi

    z::log::info "Script completed successfully"
}

# Run the script
script_main
```

### Error Recovery

```zsh
#!/usr/bin/env zsh
source /path/to/lib/core.zsh

robust_operation() {
    local max_retries=3
    local retry_count=0

    while ((retry_count < max_retries)); do
        if z::exec::run "unreliable_command" 30; then
            z::log::info "Operation succeeded on attempt $((retry_count + 1))"
            return 0
        else
            ((retry_count++))
            z::log::warn "Operation failed, attempt $retry_count/$max_retries"
            sleep 1
        fi
    done

    z::log::error "Operation failed after $max_retries attempts"
    return 1
}

robust_operation
```

## Caching Examples

### Command Existence Caching

```zsh
#!/usr/bin/env zsh
source /path/to/lib/core.zsh

# Check multiple commands (cached)
local -a commands=("git" "docker" "kubectl" "helm")

for cmd in "${commands[@]}"; do
    if z::cmd::exists "$cmd"; then
        z::log::info "✓ $cmd is available"
    else
        z::log::warn "✗ $cmd is not available"
    fi
done

# Subsequent checks use cache
z::cmd::exists "git"  # Uses cache
```

### Function Existence Caching

```zsh
#!/usr/bin/env zsh
source /path/to/lib/core.zsh

# Check function existence (cached)
check_functions() {
    local -a functions=("func1" "func2" "func3")

    for func in "${functions[@]}"; do
        if z::func::exists "$func"; then
            z::log::info "Function $func exists"
        else
            z::log::warn "Function $func does not exist"
        fi
    done
}

# Call multiple times - uses cache
check_functions
check_functions  # Second call uses cache
```

## Complete Script Examples

### System Information Script

```zsh
#!/usr/bin/env zsh

# Source ZCore
source /path/to/lib/core.zsh
source /path/to/lib/platform.zsh

# Set up error handling
trap 'z::runtime::handle_interrupt' INT TERM

# Main script
main() {
    z::log::info "System Information Script"

    # Detect platform
    z::detect::platform

    # Platform-specific information
    if (( IS_MACOS )); then
        z::log::info "Platform: macOS"
        z::exec::run "sw_vers" 10
    elif (( IS_LINUX )); then
        z::log::info "Platform: Linux"
        z::exec::run "uname -a" 10
    fi

    # Common information
    z::exec::run "whoami" 5
    z::exec::run "pwd" 5
    z::exec::run "date" 5

    z::log::info "Script completed"
}

# Run main function
main
```

### File Backup Script

```zsh
#!/usr/bin/env zsh

# Source ZCore
source /path/to/lib/core.zsh
source /path/to/lib/platform.zsh

# Configuration
BACKUP_DIR="$HOME/backups"
SOURCE_DIRS=("$HOME/Documents" "$HOME/Pictures")

# Set up error handling
trap 'z::runtime::handle_interrupt' INT TERM

backup_directory() {
    local source_dir="$1"
    local backup_name=$(basename "$source_dir")
    local backup_path="$BACKUP_DIR/$backup_name-$(date +%Y%m%d)"

    z::log::info "Backing up: $source_dir"

    if [[ ! -d "$source_dir" ]]; then
        z::log::warn "Source directory not found: $source_dir"
        return 1
    fi

    if z::exec::run "cp -r '$source_dir' '$backup_path'" 300; then
        z::log::info "Backup successful: $backup_path"
        return 0
    else
        z::log::error "Backup failed: $source_dir"
        return 1
    fi
}

main() {
    z::log::info "Starting backup process"

    # Create backup directory
    if ! z::exec::run "mkdir -p '$BACKUP_DIR'" 10; then
        z::runtime::die "Failed to create backup directory" 1
    fi

    # Backup each directory
    local -i total=${#SOURCE_DIRS[@]}
    local -i current=0

    for dir in "${SOURCE_DIRS[@]}"; do
        ((current++))
        z::ui::progress::show $current $total "backing up directories"

        backup_directory "$dir"
    done

    z::log::info "Backup process completed"
}

# Run main function
main
```

### Package Installation Script

```zsh
#!/usr/bin/env zsh

# Source ZCore
source /path/to/lib/core.zsh
source /path/to/lib/platform.zsh

# Set up error handling
trap 'z::runtime::handle_interrupt' INT TERM

install_packages() {
    local -a packages=("$@")
    local -i total=${#packages[@]}
    local -i current=0

    z::detect::platform

    for package in "${packages[@]}"; do
        ((current++))
        z::ui::progress::show $current $total "installing packages"

        z::log::info "Installing: $package"

        if (( IS_MACOS )); then
            z::exec::run "brew install '$package'" 300
        elif (( IS_LINUX )); then
            if z::cmd::exists "apt"; then
                z::exec::run "sudo apt install -y '$package'" 300
            elif z::cmd::exists "pacman"; then
                z::exec::run "sudo pacman -S --noconfirm '$package'" 300
            else
                z::log::warn "No package manager found for Linux"
            fi
        else
            z::log::warn "Unsupported platform for package installation"
        fi
    done
}

main() {
    local -a packages=("git" "curl" "wget" "vim")

    z::log::info "Package Installation Script"
    install_packages "${packages[@]}"
    z::log::info "Installation completed"
}

# Run main function
main
```

### Development Environment Setup

```zsh
#!/usr/bin/env zsh

# Source ZCore
source /path/to/lib/core.zsh
source /path/to/lib/platform.zsh

# Set up error handling
trap 'z::runtime::handle_interrupt' INT TERM

setup_development_environment() {
    z::log::info "Setting up development environment"

    z::detect::platform

    # Set up PATH
    z::path::add "$HOME/.local/bin" prepend
    z::path::add "/usr/local/bin" prepend

    # Platform-specific setup
    if (( IS_MACOS )); then
        z::log::info "Setting up macOS development environment"

        # Install Homebrew if not available
        if ! z::cmd::exists "brew"; then
            z::log::info "Installing Homebrew"
            z::exec::run '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' 600
        fi

        # Install development tools
        local -a brew_packages=("git" "node" "python" "go")
        for package in "${brew_packages[@]}"; do
            if ! z::cmd::exists "$package"; then
                z::log::info "Installing $package via Homebrew"
                z::exec::run "brew install '$package'" 300
            fi
        done

    elif (( IS_LINUX )); then
        z::log::info "Setting up Linux development environment"

        # Install development tools
        if z::cmd::exists "apt"; then
            local -a apt_packages=("git" "nodejs" "python3" "golang-go" "build-essential")
            for package in "${apt_packages[@]}"; do
                if ! z::cmd::exists "$package"; then
                    z::log::info "Installing $package via apt"
                    z::exec::run "sudo apt install -y '$package'" 300
                fi
            done
        fi
    fi

    # Set up Git
    if z::cmd::exists "git"; then
        z::log::info "Configuring Git"
        z::exec::run "git config --global init.defaultBranch main" 10
    fi

    z::log::info "Development environment setup completed"
}

main() {
    setup_development_environment
}

# Run main function
main
```

---

These examples demonstrate various ways to use the ZCore library in different scripting scenarios. The library provides a solid foundation for reliable shell scripting with proper error handling, logging, and cross-platform support.
