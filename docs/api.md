# Zcore Framework API Reference

**Version:** 1.1.0
**Last Updated:** 2025-11-02

## Table of Contents

1. [Quick Start](#quick-start)
2. [Core Concepts](#core-concepts)
3. [API Reference](#api-reference)
   - [Configuration Management](#1-configuration-management)
   - [Logging System](#2-logging-system)
   - [Runtime & Error Handling](#3-runtime--error-handling)
   - [Platform Detection](#4-platform-detection)
   - [Command & Alias Management](#5-command--alias-management)
   - [Safe Execution](#6-safe-execution)
   - [Filesystem Operations](#7-filesystem-operations)
   - [Introspection & Caching](#8-introspection--caching)
   - [State Management](#9-state-management)
   - [User Interface](#10-user-interface)
4. [Common Patterns](#common-patterns)
5. [Performance Tips](#performance-tips)
6. [Troubleshooting](#troubleshooting)

---

## Quick Start

```zsh
# Source the framework
source /path/to/zcore.zsh

# Basic logging
z::log::info "Application started"
z::log::debug "Debug information"

# Platform detection
z::detect::platform
if (( IS_MACOS )); then
  z::log::info "Running on macOS"
fi

# Safe command execution
if z::exec::run "curl -s https://api.github.com/zen" 10; then
  z::log::info "Command succeeded"
fi

# Function existence check
if z::func::exists my_function; then
  z::func::call my_function arg1 arg2
fi

# Progress bar for loops
local total=1000
for i in {1..$total}; do
  z::ui::progress::show $i $total "files"
  # Process item $i
done
```

---

## Core Concepts

### Naming Convention

All public API functions follow the pattern: `z::module::action`

- **`z::`** - Framework namespace prefix
- **`module`** - Functional area (log, exec, path, etc.)
- **`action`** - Specific operation

Private/internal functions use underscore prefix: `z::module::_action`

### Global Variables

| Variable | Type | Purpose | Modifiable |
|:---------|:-----|:--------|:-----------|
| `_zcore_config` | Associative array | Framework configuration | Via `z::config::set` only |
| `_zcore_verbose_level` | Integer | Current log level (0-3) | Yes (via `z::log::enable_debug`) |
| `IS_MACOS`, `IS_LINUX`, etc. | Read-only integer | Platform flags (0 or 1) | No |
| `_func_cache`, `_cmd_cache` | Associative arrays | Performance caches | Via cache API only |

### Return Codes

Zcore follows standard Unix conventions:

- **`0`** - Success
- **`1`** - General error (validation failure, resource not found)
- **`124`** - Timeout (from `z::exec::run` with timeout)
- **`130`** - User interrupt (Ctrl+C)

---

## API Reference

## 1. Configuration Management

### Overview

The configuration system provides type-safe access to framework settings through the `_zcore_config` associative array.

### Configuration Keys

| Key | Type | Default | Range | Description |
|:----|:-----|:--------|:------|:------------|
| `log_error` | integer | 0 | N/A | Error log level |
| `log_warn` | integer | 1 | N/A | Warning log level |
| `log_info` | integer | 2 | N/A | Info log level (default) |
| `log_debug` | integer | 3 | N/A | Debug log level |
| `exit_general_error` | integer | 1 | N/A | Default exit code for errors |
| `exit_interrupted` | integer | 130 | N/A | Exit code for user interrupts |
| `progress_update_interval` | integer | 10 | 1-100 | Progress bar update frequency |
| `timeout_default` | integer | 30 | 1-3600 | Default command timeout (seconds) |
| `log_max_depth` | integer | 50 | 10-200 | Max logging recursion depth |
| `cache_max_size` | integer | 100 | 10-10000 | Max cache entries |
| `performance_mode` | boolean | false | true/false | Disable expensive checks |
| `show_progress` | boolean | true | true/false | Global progress bar toggle |
| `init_whitelist_regex` | string | "" | Valid regex | Custom shell init command pattern |

### Environment Variables

Configuration can be pre-set via environment variables:

```zsh
export ZCORE_CONFIG_PERFORMANCE_MODE=true  # Skip expensive validations
export ZCORE_CONFIG_SHOW_PROGRESS=false    # Disable all progress bars
export zcore_config_verbose=3              # Set debug level
```

---

### `z::config::set`

**Syntax:** `z::config::set <key> <value>`

Safely updates a configuration value with validation.

**Parameters:**

- `key` (string, required) - Configuration key from table above
- `value` (string, required) - New value matching the key's type

**Returns:**

- `0` - Configuration updated successfully
- `1` - Validation failed (unknown key, invalid type, out of range)

**Side Effects:**

- Updates `_zcore_config[$key]`
- Logs debug message on success

**Examples:**

```zsh
# Increase command timeout to 60 seconds
z::config::set "timeout_default" "60"

# Enable performance mode
z::config::set "performance_mode" "true"

# Adjust cache size for memory-constrained environments
z::config::set "cache_max_size" "50"

# Invalid: will fail with error message
z::config::set "cache_max_size" "9"        # Below minimum (10)
z::config::set "performance_mode" "yes"    # Must be true/false
z::config::set "unknown_key" "value"       # Key doesn't exist
```

**Best Practices:**

- Always check return code for validation failures
- Set configuration early in script initialization
- Use environment variables for system-wide defaults

---

## 2. Logging System

### Overview

Provides leveled logging with automatic timestamping, color-coding (when supported), and verbosity control.

**Log Levels:**

- **`0` (error)** - Critical errors requiring attention
- **`1` (warn)** - Non-critical warnings
- **`2` (info)** - Standard operational messages (default)
- **`3` (debug)** - Verbose debugging information

Messages are only displayed if their level ≤ `_zcore_verbose_level`. All output goes to `stderr`.

---

### `z::log::error`

**Syntax:** `z::log::error <message...>`

Logs critical error messages (level 0).

**Parameters:**

- `message...` (string, variadic) - Message components joined by spaces

**Returns:**

- `0` - Always (even if message filtered by verbosity)

**Output Format:**

```
2025-10-15 14:23:45 [error] Database connection failed
```

**Examples:**

```zsh
z::log::error "Configuration file not found"
z::log::error "Failed to connect to" "$hostname" "on port" "$port"
z::log::error "Validation failed: expected integer, got" "$value"
```

---

### `z::log::warn`

**Syntax:** `z::log::warn <message...>`

Logs warning messages (level 1).

**Use Cases:**

- Deprecated feature usage
- Fallback behavior triggered
- Non-critical resource issues

**Examples:**

```zsh
z::log::warn "Configuration file not found, using defaults"
z::log::warn "Command 'jq' not available, falling back to grep"
z::log::warn "Cache size exceeded, evicting oldest entries"
```

---

### `z::log::info`

**Syntax:** `z::log::info <message...>`

Logs informational messages (level 2, default).

**Use Cases:**

- Operation start/completion
- State transitions
- User-facing status updates

**Examples:**

```zsh
z::log::info "Starting backup process"
z::log::info "Processed" "$count" "files in" "$elapsed" "seconds"
z::log::info "Backup completed successfully"
```

---

### `z::log::debug`

**Syntax:** `z::log::debug <message...>`

Logs verbose debugging information (level 3).

**Use Cases:**

- Variable values for troubleshooting
- Function entry/exit points
- Cache hits/misses
- Path resolution steps

**Examples:**

```zsh
z::log::debug "Function entered with args:" "$@"
z::log::debug "Resolved path:" "$resolved"
z::log::debug "Cache hit for command:" "$cmd"
```

**Note:** Debug messages are hidden unless `z::log::enable_debug` is called or `zcore_config_verbose=3` is set.

---

### `z::log::enable_debug`

**Syntax:** `z::log::enable_debug`

Enables debug-level logging (sets `_zcore_verbose_level=3`).

**Returns:** `0` - Always

**Side Effects:**

- Sets `_zcore_verbose_level` to 3
- Logs "Debug mode enabled" at info level

**Examples:**

```zsh
# Enable for troubleshooting
z::log::enable_debug

# Conditional debug mode
[[ -n ${DEBUG:-} ]] && z::log::enable_debug
```

---

### `z::log::get_level`

**Syntax:** `z::log::get_level`

Displays current verbosity level with human-readable name.

**Returns:** `0` - Always

**Output Example:**

```
Current verbosity level: 2 (info)
```

---

### `z::log::toggle_progress`

**Syntax:** `z::log::toggle_progress`

Toggles global progress bar visibility.

**Returns:** `0` - Always

**Side Effects:**

- Flips `_zcore_config[show_progress]` between `true` and `false`
- Logs current state

**Examples:**

```zsh
# Disable progress bars for non-interactive contexts
[[ ! -t 1 ]] && z::log::toggle_progress

# Toggle for user preference
z::log::toggle_progress
```

---

### Logging Performance

**Timestamp Caching:** Timestamps are cached per-second to avoid expensive `date` calls:

- First log call in a second generates timestamp
- Subsequent calls within same second reuse cached value
- Reduces overhead by ~90% for high-frequency logging

**Recursion Prevention:** The logging engine tracks call depth to prevent infinite loops:

- Maximum depth: 50 (configurable via `log_max_depth`)
- Depth check adds negligible overhead (<1µs)

---

## 3. Runtime & Error Handling

### Overview

Manages script lifecycle, graceful shutdown, and fatal error handling.

---

### `z::runtime::die`

**Syntax:** `z::runtime::die <message> [exit_code]`

Terminates script with fatal error message.

**Parameters:**

- `message` (string, required) - Fatal error description
- `exit_code` (integer, optional) - Exit code (default: 1)

**Returns:** Never returns (exits or returns from sourced context)

**Side Effects:**

- Clears active progress bars
- Logs error message prefixed with "FATAL:"
- **In sourced context:** Returns with exit code
- **In executed context:** Exits process with code

**Examples:**

```zsh
# Basic usage
[[ -f config.yml ]] || z::runtime::die "config.yml not found"

# With custom exit code
z::cmd::exists jq || z::runtime::die "jq is required" 127

# In error handling
if ! result=$(dangerous_operation); then
  z::runtime::die "Operation failed: $result" 1
fi
```

**Context Detection:**

```zsh
# When sourced: returns 1 (won't kill parent shell)
source my_library.zsh
# my_library.zsh calls z::runtime::die
# Parent shell continues

# When executed: exits 1
./my_script.zsh
# my_script.zsh calls z::runtime::die
# Process terminates
```

---

### `z::runtime::check_interrupted`

**Syntax:** `z::runtime::check_interrupted`

Checks if user interrupted script (Ctrl+C).

**Returns:**

- `0` - Not interrupted, continue execution
- `130` - Interrupted, should exit

**Side Effects:**

- Logs "Operation cancelled by user" when interrupted
- Does not modify interrupt flag

**Examples:**

```zsh
# In processing loops
for file in *.log; do
  z::runtime::check_interrupted || return $?
  process_file "$file"
done

# Before expensive operations
z::runtime::check_interrupted || return $?
z::exec::run "tar czf backup.tar.gz data/" 300

# With custom handling
if ! z::runtime::check_interrupted; then
  cleanup_partial_work
  return 130
fi
```

**Best Practices:**

- Check at the start of each loop iteration
- Check before starting time-consuming operations
- Always propagate return code: `|| return $?`

---

### `z::runtime::handle_interrupt`

**Syntax:** N/A (Internal trap handler)

**Purpose:** Internal signal handler for SIGINT and SIGTERM.

**Behavior:**

- Sets global `_zcore_config_interrupted` flag
- Clears progress bars
- Logs graceful shutdown message
- Only handles first interrupt (prevents message spam)
- Ignores interrupts during ZLE (command-line editing)

**Installation:** Automatically registered via:

```zsh
trap 'z::runtime::handle_interrupt' INT TERM
```

**User Code:** Should use `z::runtime::check_interrupted`, not this function.

---

### Interrupt Handling Pattern

**Complete Example:**

```zsh
#!/usr/bin/env zsh
source zcore.zsh

process_files() {
  local -a files=( data/*.csv )
  local total=${#files}
  local i=1

  for file in "${files[@]}"; do
    # Check for interrupt
    z::runtime::check_interrupted || return $?

    # Show progress
    z::ui::progress::show $i $total "files"

    # Process file
    if ! process_single_file "$file"; then
      z::log::warn "Failed to process: $file"
    fi

    (( i += 1 ))
  done

  z::ui::progress::clear
  z::log::info "Processed $total files"
}

# Run with automatic interrupt handling
process_files
```

---

## 4. Platform Detection

### Overview

Detects operating system and environment, setting global read-only flags for conditional logic.

---

### `z::detect::platform`

**Syntax:** `z::detect::platform`

Detects platform and sets global boolean flags.

**Returns:** `0` - Always

**Side Effects:** Sets read-only global integers (one time only):

| Variable | Value | Platform |
|:---------|:------|:---------|
| `IS_MACOS` | 1/0 | macOS / Darwin |
| `IS_LINUX` | 1/0 | Linux (any distribution) |
| `IS_BSD` | 1/0 | FreeBSD, OpenBSD, NetBSD, DragonFly |
| `IS_CYGWIN` | 1/0 | Cygwin, MSYS, MinGW (Windows) |
| `IS_WSL` | 1/0 | Windows Subsystem for Linux |
| `IS_TERMUX` | 1/0 | Termux (Android terminal) |
| `IS_UNKNOWN` | 1/0 | Unrecognized platform |

**Idempotency:** Can be called multiple times safely (detection runs once).

**Examples:**

```zsh
# Basic platform check
z::detect::platform
if (( IS_MACOS )); then
  z::log::info "Running on macOS"
  alias ls='ls -G'
elif (( IS_LINUX )); then
  z::log::info "Running on Linux"
  alias ls='ls --color=auto'
fi

# WSL-specific logic
if (( IS_WSL )); then
  z::log::warn "Running in WSL, adjusting paths"
  export DISPLAY="$(ip route | awk '/default/ {print $3}'):0.0"
fi

# Mobile environment
if (( IS_TERMUX )); then
  z::log::info "Termux detected, using mobile-friendly settings"
  z::config::set "cache_max_size" "50"
fi

# Multi-platform compatibility
if (( IS_MACOS )); then
  local sed_cmd="gsed"
elif (( IS_BSD )); then
  local sed_cmd="sed"
else
  local sed_cmd="sed"
fi
```

**Detection Methods:**

1. **Primary:** Uses `$OSTYPE` variable
2. **Fallback:** Calls `uname -s` if `$OSTYPE` empty
3. **WSL:** Checks environment variables and `/proc/version`
4. **Termux:** Looks for `/data/data/com.termux/files/usr`

---

## 5. Command & Alias Management

### Overview

Safe utilities for managing shell aliases and PATH modifications.

---

### `z::alias::define`

**Syntax:** `z::alias::define <name> <value>`

Creates shell alias with validation.

**Parameters:**

- `name` (string, required) - Alias name (no spaces or `=`)
- `value` (string, required) - Command to expand to

**Returns:**

- `0` - Alias created successfully
- `1` - Validation failed or creation error

**Side Effects:**

- Creates global alias in current shell
- Logs debug message on success

**Examples:**

```zsh
# Simple aliases
z::alias::define ll 'ls -lah'
z::alias::define gs 'git status'
z::alias::define .. 'cd ..'

# Complex aliases
z::alias::define update-system 'sudo apt update && sudo apt upgrade -y'

# Conditional aliases
if (( IS_MACOS )); then
  z::alias::define ls 'ls -G'
else
  z::alias::define ls 'ls --color=auto'
fi

# Validation failures
z::alias::define "name with space" "value"  # Returns 1
z::alias::define "name=bad" "value"         # Returns 1
z::alias::define "" "value"                 # Returns 1
```

---

### `z::path::add`

**Syntax:** `z::path::add <directory> [position]`

Adds directory to PATH if not already present.

**Parameters:**

- `directory` (string, required) - Path to add (supports `~` expansion)
- `position` (string, optional) - `prepend` or `append` (default: `append`)

**Returns:**

- `0` - Added successfully or already in PATH
- `1` - Validation failed or directory doesn't exist

**Side Effects:**

- Modifies `$PATH` environment variable
- Calls `hash -r` to rebuild command hash table
- Clears command existence cache
- Logs debug message

**Examples:**

```zsh
# Append to PATH (default)
z::path::add /usr/local/bin
z::path::add ~/bin

# Prepend (takes priority)
z::path::add ~/.local/bin prepend

# Conditional additions
if (( IS_MACOS )); then
  z::path::add /opt/homebrew/bin prepend
fi

# Batch additions
local -a paths=(
  ~/.cargo/bin
  ~/.local/bin
  ~/go/bin
)
for p in "${paths[@]}"; do
  z::path::add "$p"
done

# Idempotency: safe to call multiple times
z::path::add /usr/local/bin  # Adds once
z::path::add /usr/local/bin  # No-op (already in PATH)
```

**Path Resolution:**

- Performs full path resolution (symlinks, relative paths)
- Skips non-existent directories silently (logs debug only)
- Prevents duplicate entries

**Performance Note:** Calls `hash -r` which rebuilds command cache (~1-2ms). Batch additions recommended for multiple paths.

---

## 6. Safe Execution

### Overview

Provides security-hardened command execution with timeout support, pattern scanning, and context-aware evaluation.

**Security Features:**

- Blocks dangerous metacharacters (`;`, `&`, `()`, backticks)
- Scans for destructive commands (`rm -rf /`, `dd`, `mkfs`, etc.)
- Detects fork bombs and pipe-to-shell attacks
- Whitelists known-safe patterns (shell init hooks)
- Enforces timeout limits

---

### `z::exec::run`

**Syntax:** `z::exec::run <command_string> [timeout]`

Executes command in isolated subshell with security checks.

**Parameters:**

- `command_string` (string, required) - Command to execute
- `timeout` (integer, optional) - Timeout in seconds (default: 30)

**Returns:**

- Exit code of command
- `124` - Timeout exceeded
- `1` - Security check failed or validation error

**Security Behavior:**

- **Blocks:** Commands with `;`, `&`, `()`, backticks (unless whitelisted)
- **Blocks:** Destructive patterns (see below)
- **Allows:** Simple commands and pipelines
- **Isolation:** Runs in `zsh -o pipefail -c "..."`

**Examples:**

```zsh
# Basic usage
if z::exec::run "curl -s https://api.example.com/data" 10; then
  z::log::info "API call succeeded"
fi

# Pipeline (allowed)
z::exec::run "cat data.txt | grep ERROR | wc -l"

# With timeout
z::exec::run "rsync -av /src/ /dest/" 300  # 5 minute timeout

# Rejected: dangerous metacharacters
z::exec::run "cmd1; cmd2"              # BLOCKED: semicolon
z::exec::run "cmd1 && cmd2"            # BLOCKED: logic operator
z::exec::run "cmd1 | sh"               # BLOCKED: pipe to shell

# Rejected: destructive commands
z::exec::run "rm -rf /"                # BLOCKED: dangerous rm
z::exec::run "dd if=/dev/zero of=/dev/sda"  # BLOCKED: disk overwrite
z::exec::run "chmod 777 -R /"          # BLOCKED: insecure permissions
```

**Timeout Behavior:**

- Requires `timeout` (GNU) or `gtimeout` (macOS)
- Returns `124` on timeout (standard GNU timeout exit code)
- Logs warning with timeout duration

**Performance Mode:**

- When `performance_mode=true`, skips security scanning
- Use only with trusted input in performance-critical sections

---

### `z::exec::eval`

**Syntax:** `z::exec::eval <command_string> [timeout] [force_current_shell]`

Context-aware evaluation with smart security scanning.

**Parameters:**

- `command_string` (string, required) - Command/code to evaluate
- `timeout` (integer, optional) - Timeout seconds (default: 30)
- `force_current_shell` (boolean, optional) - Use `eval` instead of subshell (default: `false`)

**Returns:**

- Exit code of evaluated command
- `1` - Security check failed or validation error

**Behavior:**

- **Default:** Calls `z::exec::run` (subshell, security checks)
- **`force_current_shell=true`:** Uses `eval` in current shell (for init scripts)
- **Auto-detection:** Recognizes shell init patterns and package managers

**Examples:**

```zsh
# Standard usage (subshell)
z::exec::eval "export PATH=/new/path:$PATH"  # Won't affect current shell

# Force current shell (for init scripts)
z::exec::eval "eval \$(starship init zsh)" 30 true

# Auto-detected patterns (skips some security checks)
z::exec::eval "npm install express"         # Recognized as package manager
z::exec::eval "direnv init zsh"             # Recognized as shell init

# Complex initialization
local init_code
init_code=$(some_tool dump-config)
z::exec::eval "$init_code" 10 true          # Apply to current shell
```

**When to Use `force_current_shell=true`:**

- ✅ Shell integration tools (starship, direnv, zoxide)
- ✅ Environment variable exports that must persist
- ✅ Function definitions needed in current shell
- ❌ Untrusted input
- ❌ Commands that modify filesystem

**Security Scanning:**

- Skipped for recognized patterns (shell init, package managers)
- Skipped in performance mode
- Always performed for unknown commands

---

### `z::exec::from_hook`

**Syntax:** `z::exec::from_hook <tool_name> [subcommand] [shell_arg]`

High-level helper for shell integration tools.

**Parameters:**

- `tool_name` (string, required) - Command name (e.g., `starship`)
- `subcommand` (string, optional) - Init subcommand (default: `init`)
- `shell_arg` (string, optional) - Shell name (default: `zsh`)

**Returns:**

- `0` - Success or tool not found (non-error)
- `1` - Tool found but initialization failed

**Behavior:**

1. Checks if `tool_name` exists (via `z::cmd::exists`)
2. Captures output: `$tool_name $subcommand $shell_arg`
3. Evaluates output with `force_current_shell=true`

**Examples:**

```zsh
# Common integrations
z::exec::from_hook starship         # starship init zsh
z::exec::from_hook direnv           # direnv hook zsh
z::exec::from_hook zoxide           # zoxide init zsh

# Custom subcommands
z::exec::from_hook mise activate zsh
z::exec::from_hook atuin init zsh

# Graceful degradation
z::exec::from_hook fzf              # No error if fzf not installed
```

**Best Practice Pattern:**

```zsh
# Initialize all optional tools
local -a shell_tools=(
  starship
  direnv
  zoxide
  atuin
)

for tool in "${shell_tools[@]}"; do
  z::exec::from_hook "$tool"
done
```

---

### Security Pattern Reference

**Blocked Patterns:**

| Pattern | Example | Reason |
|:--------|:--------|:-------|
| `rm -rf` on critical paths | `rm -rf /` | Data loss |
| `dd of=/dev/*` | `dd if=/dev/zero of=/dev/sda` | Disk corruption |
| `mkfs.*` on devices | `mkfs.ext4 /dev/sda` | Filesystem destruction |
| `chmod 777 -R /` | `chmod 777 -R /` | Security compromise |
| `killall -9` | `killall -9 process` | Force kill signals |
| Pipe to shell | `curl url \| sh` | Code injection risk |
| Fork bombs | `:(){ :\|:& };:` | System DoS |

**Whitelisted Patterns:**

- Shell init: `starship init zsh`, `direnv hook zsh`
- Custom regex via `_zcore_config[init_whitelist_regex]`

---

## 7. Filesystem Operations

### Overview

Path resolution and safe file sourcing with comprehensive validation.

---

### `z::path::resolve`

**Syntax:** `z::path::resolve <path>`

Resolves path to canonical absolute form.

**Parameters:**

- `path` (string, required) - Path to resolve

**Returns:**

- `0` - Success, prints resolved path to stdout
- `1` - Invalid input, empty path, or symlink cycle

**Features:**

- ✅ Tilde expansion (`~`, `~/...`, `~+`, `~-`)
- ✅ Resolves symlinks (with cycle detection)
- ✅ Normalizes `.` and `..`
- ✅ Converts relative to absolute paths

**Examples:**

```zsh
# Basic resolution
local resolved
resolved=$(z::path::resolve "~/dotfiles")
# → /home/user/dotfiles

# Relative paths
resolved=$(z::path::resolve "../config")
# → /home/user/config (if pwd=/home/user/project)

# Symlink resolution
ln -s /usr/local/bin /home/user/bin
resolved=$(z::path::resolve "~/bin")
# → /usr/local/bin (follows symlink)

# Special tilde forms
resolved=$(z::path::resolve "~+")       # $PWD
resolved=$(z::path::resolve "~-")       # $OLDPWD

# Error handling
if ! resolved=$(z::path::resolve "~/missing"); then
  z::log::error "Failed to resolve path"
fi
```

**Resolution Methods (priority order):**

1. **Zsh native:** `${path:A}` modifier (fastest)
2. **Fallback:** Manual symlink traversal with `readlink`
3. **Physical:** `cd -P && pwd -P` for directory canonicalization

**Symlink Cycle Detection:**

- Uses associative array for O(1) cycle detection
- Maximum depth: 100 iterations
- Returns error with original path if cycle detected

**Performance:**

- **Native mode:** ~50µs (zsh `:A` modifier)
- **Fallback mode:** ~500µs (readlink loops)
- **Performance mode:** Skips resolution entirely (tilde expansion only)

---

### `z::path::source`

**Syntax:** `z::path::source [--global] <file> [args...]`

Safely sources shell script with validation.

**Parameters:**

- `--global` (flag, optional) - Preserve global scope (no `emulate -L zsh`)
- `file` (string, required) - Path to source
- `args...` (any, optional) - Arguments passed to sourced script

**Returns:**

- `0` - Sourced successfully
- Exit code from sourced script
- `1` - File not found, not readable, or path resolution failed

**Side Effects:**

- Sources file in current shell
- Clears function cache after successful sourcing
- Uses local emulation unless `--global` specified

**Examples:**

```zsh
# Basic sourcing
z::path::source ~/.zshrc

# With arguments
z::path::source ~/lib/utils.zsh --verbose

# Global scope (for configuration files)
z::path::source --global /etc/zsh/zprofile

# Error handling
if ! z::path::source ~/config.zsh; then
  z::runtime::die "Failed to load configuration"
fi

# Conditional sourcing
[[ -f ~/.zshrc.local ]] && z::path::source ~/.zshrc.local

# Multiple files
local -a config_files=(
  ~/.zshrc.pre
  ~/.zshrc.main
  ~/.zshrc.post
)
for file in "${config_files[@]}"; do
  [[ -f $file ]] && z::path::source "$file"
done
```

**Path Resolution:**

- Always performs tilde expansion (cheap)
- Full path resolution unless `performance_mode=true`
- Validates file exists and is readable before sourcing

**Scope Behavior:**

- **Default:** Uses `emulate -L zsh` (local scope)
- **`--global`:** Skips emulation (preserves global scope)
- Use `--global` for files that set global options/variables

---

## 8. Introspection & Caching

### Overview

High-performance existence checks with LRU caching to avoid repeated hash table lookups.

**Cache Benefits:**

- ~10x faster than native `$+commands`/`$+functions` checks
- Automatic LRU eviction when size limit reached
- Transparent to caller (returns immediately from cache)

---

### `z::cmd::exists`

**Syntax:** `z::cmd::exists <command>`

Checks if external command exists in PATH.

**Parameters:**

- `command` (string, required) - Command name to check

**Returns:**

- `0` - Command exists
- `1` - Command not found

**Caching:**

- First call: Checks `$+commands[$cmd]`, caches result
- Subsequent calls: Returns cached result instantly
- Cache cleared on `z::path::add` or `z::cache::cmd::clear`

**Examples:**

```zsh
# Basic check
if z::cmd::exists git; then
  z::log::info "Git is available"
fi

# Required dependencies
local -a required_commands=(git curl jq)
for cmd in "${required_commands[@]}"; do
  z::cmd::exists "$cmd" || z::runtime::die "$cmd is required"
done

# Conditional behavior
if z::cmd::exists bat; then
  alias cat='bat'
elif z::cmd::exists batcat; then
  alias cat='batcat'
fi

# Feature detection
local has_parallel=false
z::cmd::exists parallel && has_parallel=true
```

**Performance:**

- First call: ~50µs (native check + cache insert)
- Cached calls: ~1µs (hash table lookup)
- Cache hit rate: Typically >95% in real workloads

---

### `z::func::exists`

**Syntax:** `z::func::exists <function>`

Checks if zsh function is defined.

**Parameters:**

- `function` (string, required) - Function name to check

**Returns:**

- `0` - Function exists
- `1` - Function not defined

**Caching:**

- First call: Checks `$+functions[$func]`, caches result
- Subsequent calls: Returns cached result
- Cache cleared on `z::path::source` or `z::func::unset`

**Examples:**

```zsh
# Safe function calls
if z::func::exists my_helper; then
  my_helper arg1 arg2
fi

# Optional hooks
z::func::exists pre_command_hook && pre_command_hook

# Plugin detection
if z::func::exists _zsh_autosuggest_start; then
  z::log::info "zsh-autosuggestions loaded"
fi

# Conditional definitions
if ! z::func::exists my_function; then
  my_function() {
    z::log::info "Default implementation"
  }
fi
```

---

### `z::func::call`

**Syntax:** `z::func::call <function> [args...]`

Safely calls function by name with existence check.

**Parameters:**

- `function` (string, required) - Function name
- `args...` (any, optional) - Arguments to pass

**Returns:**

- Function's exit code
- `1` - Function not found

**Behavior:**

- Checks existence via `z::func::exists` (cached)
- Silently ignores known dynamic functions (prompt helpers)
- Logs warning for missing non-dynamic functions
- Forwards all arguments to function

**Examples:**

```zsh
# Dynamic function dispatch
local handler="process_${type}"
if z::func::call "$handler" "$data"; then
  z::log::info "Handler succeeded"
fi

# Optional callbacks
z::func::call on_complete_hook "$result"

# Array of functions
local -a hooks=(pre_hook main_hook post_hook)
for hook in "${hooks[@]}"; do
  z::func::call "$hook" || break
done

# Error handling
if ! z::func::call validate_input "$input"; then
  z::log::error "Validation failed"
  return 1
fi
```

**Silent Patterns:**

- `_git_prompt_info` - Git prompt helpers
- `__zconvey_*` - ZConvey functions
- `_*prompt*` - Any prompt-related functions
- `_*git*` - Other git integration functions

---

### Cache Management

#### `z::cache::cmd::clear`

Clears command existence cache.

**Usage:**

```zsh
# After installing new commands
z::exec::run "npm install -g typescript"
z::cache::cmd::clear  # Ensure tsc is found

# After PATH modification (done automatically by z::path::add)
export PATH="/new/bin:$PATH"
hash -r
z::cache::cmd::clear
```

#### `z::cache::func::clear`

Clears function existence cache.

**Usage:**

```zsh
# After sourcing new definitions (done automatically by z::path::source)
source ~/functions.zsh
z::cache::func::clear  # Ensure new functions are detected
```

**Automatic Clearing:**

- Command cache: Cleared on `z::path::add`
- Function cache: Cleared on successful `z::path::source`

---

## 9. State Management

### Overview

Safe variable and function removal with cache consistency.

---

### `z::var::unset`

**Syntax:** `z::var::unset <variable>`

Unsets a shell variable.

**Parameters:**

- `variable` (string, required) - Variable name to unset

**Returns:**

- `0` - Successfully unset
- `1` - Variable not found or readonly

**Examples:**

```zsh
# Clean up temporary variables
local temp_var="value"
z::var::unset temp_var

# Conditional cleanup
[[ -n ${OLD_VAR:-} ]] && z::var::unset OLD_VAR

# Readonly protection
readonly CONST=42
z::var::unset CONST  # Returns 1, logs debug message
```

---

### `z::func::unset`

**Syntax:** `z::func::unset <function>`

Unsets a shell function.

**Parameters:**

- `function` (string, required) - Function name to unset

**Returns:**

- `0` - Successfully unset
- `1` - Function not found

**Side Effects:**

- Removes function from shell
- Updates function existence cache

**Examples:**

```zsh
# Remove temporary function
z::func::unset temp_helper

# Cleanup after use
my_function() { echo "hi" }
my_function
z::func::unset my_function

# Replace function
z::func::exists old_impl && z::func::unset old_impl
new_impl() { ... }
```

---

### `z::state::unset`

**Syntax:** `z::state::unset <target> [type]`

Unified unset with auto-detection.

**Parameters:**

- `target` (string, required) - Variable or function name
- `type` (string, optional) - `var`, `func`, or `auto` (default)

**Returns:**

- `0` - Successfully unset
- `1` - Target not found or unset failed

**Examples:**

```zsh
# Auto-detect (checks both)
z::state::unset MY_VAR        # Unsets variable or function

# Explicit type
z::state::unset MY_VAR var    # Only unsets variable
z::state::unset my_func func  # Only unsets function

# Cleanup pattern
local -a cleanup_items=(temp_dir temp_file temp_func)
for item in "${cleanup_items[@]}"; do
  z::state::unset "$item"
done
```

---

## 10. User Interface

### Overview

Terminal UI components for interactive feedback.

---

### `z::ui::progress::show`

**Syntax:** `z::ui::progress::show <current> <total> [label]`

Displays adaptive progress bar.

**Parameters:**

- `current` (integer, required) - Current item (1-indexed)
- `total` (integer, required) - Total items
- `label` (string, optional) - Item description (default: "items")

**Returns:**

- `0` - Progress updated successfully
- `1` - Invalid parameters

**Features:**

- ✅ Percentage display
- ✅ Visual bar with unicode blocks (█, ░)
- ✅ Formatted item counts (with thousands separators)
- ✅ Adaptive width (compact on narrow terminals)
- ✅ Automatic throttling (updates at configurable interval)
- ✅ Respects verbosity and `show_progress` setting

**Examples:**

```zsh
# Basic usage
local files=(data/*.txt)
local total=${#files}
for i in {1..$total}; do
  z::ui::progress::show $i $total "files"
  process_file "${files[i]}"
done

# Custom label
z::ui::progress::show $current $total "downloads"

# In function
process_batch() {
  local items=("$@")
  local total=${#items}
  local i=1

  for item in "${items[@]}"; do
    z::ui::progress::show $i $total "items"
    process_item "$item"
    (( i += 1 ))
  done

  z::ui::progress::clear
}

# With error handling
for i in {1..$total}; do
  z::runtime::check_interrupted || break
  z::ui::progress::show $i $total
  process_item "$i" || {
    z::ui::progress::clear
    z::log::error "Failed at item $i"
    return 1
  }
done
```

**Output Examples:**

Wide terminal (>70 cols):

```
[████████████░░░░░░░░]  60% | files: 600 / 1,000
```

Narrow terminal (≤70 cols):

```
[████░░]  40% (40/100)
```

**Throttling:**

- Total ≤10: Shows only first and last
- Total ≤50: Shows every 5th item
- Total >50: Shows every Nth item (configurable interval)

---

### `z::ui::progress::clear`

**Syntax:** `z::ui::progress::clear`

Clears progress bar from terminal.

**Examples:**

```zsh
# After loop completion
for i in {1..100}; do
  z::ui::progress::show $i 100
done
z::ui::progress::clear
z::log::info "Processing complete"

# On error
z::ui::progress::show $i $total || {
  z::ui::progress::clear
  z::runtime::die "Progress display failed"
}

# In cleanup
cleanup() {
  z::ui::progress::clear
  # ... other cleanup
}
trap cleanup EXIT
```

---

### `z::ui::term::width`

**Syntax:** `z::ui::term::width`

Returns terminal width with caching.

**Returns:** `0` - Always

**Output:** Terminal width to stdout

**Examples:**

```zsh
# Get width
local width=$(z::ui::term::width)

# Conditional formatting
if (( $(z::ui::term::width) > 120 )); then
  # Wide layout
else
  # Compact layout
fi

# Centered text
center_text() {
  local text="$1"
  local width=$(z::ui::term::width)
  local padding=$(( (width - ${#text}) / 2 ))
  printf "%${padding}s%s\n" "" "$text"
}
```

**Detection Methods (priority):**

1. `$COLUMNS` variable (instant)
2. `tput cols` command (~1ms)
3. Fallback: 80

**Caching:** Result cached until `$COLUMNS` changes.

---

### `z::util::comma`

**Syntax:** `z::util::comma <number>`

Formats number with thousands separators.

**Parameters:**

- `number` (integer, required) - Number to format

**Returns:** `0` - Always

**Output:** Formatted number to stdout

**Examples:**

```zsh
# Format numbers
z::util::comma 1234567
# → 1,234,567

z::util::comma -9876543
# → -9,876,543

# In messages
local count=1234567
z::log::info "Processed $(z::util::comma $count) records"

# Non-numeric input (passes through)
z::util::comma "abc"
# → abc
```

**Performance:** O(n) single-pass algorithm, ~5µs for typical values.

---

## Common Patterns

### Script Initialization

```zsh
#!/usr/bin/env zsh
source /path/to/zcore.zsh

# Enable debug mode if requested
[[ -n ${DEBUG:-} ]] && z::log::enable_debug

# Detect platform once
z::detect::platform

# Initialize shell integrations
z::exec::from_hook starship
z::exec::from_hook direnv

# Required commands
local -a required=(git curl jq)
for cmd in "${required[@]}"; do
  z::cmd::exists "$cmd" || z::runtime::die "$cmd is required"
done

z::log::info "Initialization complete"
```

### Safe File Processing

```zsh
process_files() {
  local -a files=("$@")
  local total=${#files}
  local processed=0 failed=0

  for i in {1..$total}; do
    # Check for interrupt
    z::runtime::check_interrupted || return $?

    # Show progress
    z::ui::progress::show $i $total "files"

    # Process with error handling
    if process_single_file "${files[i]}"; then
      (( processed += 1 ))
    else
      (( failed += 1 ))
      z::log::warn "Failed: ${files[i]}"
    fi
  done

  z::ui::progress::clear
  z::log::info "Processed: $processed, Failed: $failed"
  return $(( failed > 0 ? 1 : 0 ))
}
```

### Plugin System

```zsh
load_plugins() {
  local plugin_dir="${1:?Plugin directory required}"

  if [[ ! -d "$plugin_dir" ]]; then
    z::log::warn "Plugin directory not found: $plugin_dir"
    return 0
  fi

  local -a plugins=("$plugin_dir"/*.zsh(N))
  local total=${#plugins}

  [[ $total -eq 0 ]] && return 0

  z::log::info "Loading $total plugins..."

  local i=1
  for plugin in "${plugins[@]}"; do
    z::ui::progress::show $i $total "plugins"

    if z::path::source "$plugin"; then
      z::log::debug "Loaded: ${plugin:t}"
    else
      z::log::warn "Failed to load: ${plugin:t}"
    fi

    (( i += 1 ))
  done

  z::ui::progress::clear
}
```

### Conditional Execution

```zsh
run_if_available() {
  local cmd="${1:?Command required}"
  shift

  if z::cmd::exists "$cmd"; then
    z::exec::run "$cmd $*"
  else
    z::log::debug "$cmd not available, skipping"
    return 0
  fi
}

# Usage
run_if_available prettier --write "*.js"
run_if_available eslint --fix .
```

---

## Performance Tips

### 1. Enable Performance Mode for Tight Loops

```zsh
# Before expensive loop
z::config::set performance_mode true

for item in "${huge_array[@]}"; do
  # Security checks skipped
  z::exec::run "process $item"
done

# Restore
z::config::set performance_mode false
```

### 2. Batch PATH Additions

```zsh
# ❌ Slow: Multiple hash table rebuilds
z::path::add /path1
z::path::add /path2
z::path::add /path3

# ✅ Fast: Batch then single rebuild
export PATH="/path1:/path2:/path3:$PATH"
hash -r
z::cache::cmd::clear
```

### 3. Cache Command Checks

```zsh
# ❌ Slow: Repeated existence checks
for file in *.txt; do
  if (( $+commands[jq] )); then  # Checked every iteration
    # process
  fi
done

# ✅ Fast: Check once, cache result
local has_jq=false
z::cmd::exists jq && has_jq=true

for file in *.txt; do
  if [[ $has_jq == true ]]; then
    # process
  fi
done
```

### 4. Use Local Variables

```zsh
# ❌ Slow: Global scope pollution
process_items() {
  for item in "$@"; do
    result=$(process "$item")  # Global scope
  done
}

# ✅ Fast: Local scope (faster cleanup)
process_items() {
  local item result
  for item in "$@"; do
    result=$(process "$item")
  done
}
```

---

## Troubleshooting

### Debug Mode

```zsh
# Enable debug logging
z::log::enable_debug

# Or via environment
DEBUG=1 ./my-script.zsh

# Or via config
export zcore_config_verbose=3
```

### Common Issues

#### Commands Not Found After Installation

```zsh
# Clear command cache
z::cache::cmd::clear

# Or rebuild hash table
hash -r
z::cache::cmd::clear
```

#### Functions Not Found After Sourcing

```zsh
# Clear function cache
z::cache::func::clear
```

#### Progress Bar Artifacts

```zsh
# Clear progress before logging
z::ui::progress::clear
z::log::info "Done"

# Or disable progress globally
z::log::toggle_progress
```

#### Timeouts Too Short

```zsh
# Increase default timeout
z::config::set timeout_default 60

# Or per-command
z::exec::run "slow_command" 120
```

#### Security Checks Too Strict

```zsh
# Add custom whitelist regex
_zcore_config[init_whitelist_regex]='my_safe_tool init'

# Or use performance mode (use with caution)
z::config::set performance_mode true
```
