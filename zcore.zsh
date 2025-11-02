#!/usr/bin/env zsh

################################################################################
# ZCORE FRAMEWORK
################################################################################
#
# A zsh utility library providing:
#   - Robust logging with configurable verbosity levels
#   - Safe command execution with security scanning
#   - Cross-platform compatibility detection
#   - Function and command caching for performance
#   - State management and filesystem operations
#   - User interface components (progress bars)
#   - Interrupt handling and graceful shutdown
#
# Usage:
#   source /path/to/zcore.zsh
#   z::log::info "Application started"
#   z::detect::platform
#   z::exec::run "echo 'Hello World'"
#
# Configuration:
#   export ZCORE_CONFIG_PERFORMANCE_MODE=true  # Disable expensive checks
#   export ZCORE_CONFIG_SHOW_PROGRESS=false    # Disable progress bars
#   export zcore_config_verbose=3              # Set debug level
#
# Version: 1.0.0
# License: MIT
################################################################################

################################################################################
# MODULE INITIALIZATION
################################################################################
# Double-sourcing Guard
# This pattern returns 0 if sourced (allowing the sourcing script to continue)
# or exits 0 if executed directly (preventing re-execution)
if [[ ${_zcore_loaded:-} == 1 ]]; then return 0 2>/dev/null || exit 0; fi
typeset -g _zcore_loaded=1

# Ensure EPOCHSECONDS is available when possible (no-op if unavailable)
# Used for efficient timestamp generation in logging
zmodload -F zsh/datetime b:EPOCHSECONDS 2>/dev/null || true

################################################################################
# CONFIGURATION MANAGEMENT
################################################################################

###
# Global configuration store
# Centralized configuration for all zcore functionality
###
typeset -gA _zcore_config

# Logging levels (numeric)
_zcore_config[log_error]=0    # Critical errors only
_zcore_config[log_warn]=1     # Warnings and errors
_zcore_config[log_info]=2     # Informational messages (default)
_zcore_config[log_debug]=3    # Verbose debugging output

# Exit codes
_zcore_config[exit_general_error]=1    # Generic failure
_zcore_config[exit_interrupted]=130    # SIGINT (Ctrl+C)

# Performance tuning
_zcore_config[progress_update_interval]=10  # Updates per progress bar cycle
_zcore_config[timeout_default]=30           # Default command timeout (seconds)
_zcore_config[log_max_depth]=50             # Max recursion depth for logging
_zcore_config[cache_max_size]=100           # Max cached function/command entries
_zcore_config[cache_purge_threshold]=10     # Min excess before purging cache
_zcore_config[symlink_max_iterations]=40    # Max symlink resolution iterations

# Feature flags (can be overridden via environment)
_zcore_config[performance_mode]=${ZCORE_CONFIG_PERFORMANCE_MODE:-false}
_zcore_config[show_progress]=${ZCORE_CONFIG_SHOW_PROGRESS:-true}

# Optional: allow to extend/override init whitelist via regex (empty by default)
_zcore_config[init_whitelist_regex]=''

# Optional: force trap installation even in non-interactive mode
_zcore_config[install_traps]=${ZCORE_CONFIG_INSTALL_TRAPS:-false}

################################################################################
# GLOBAL VERBOSITY LEVEL
################################################################################

###
# Current logging verbosity level
# 0 = error only, 1 = warn, 2 = info (default), 3 = debug
###
typeset -gi _zcore_verbose_level=${_zcore_config[log_info]}

# Override verbosity from environment if valid
if [[ ${zcore_config_verbose:-} == <-> ]]; then
  typeset -i requested_level
  (( requested_level = 10#${zcore_config_verbose} ))

  if (( requested_level > _zcore_config[log_info] )) &&
    [[ ${_zcore_config[performance_mode]} != true ]]; then
    (( _zcore_verbose_level = requested_level ))
  elif (( requested_level <= _zcore_config[log_info] )); then
    (( _zcore_verbose_level = requested_level ))
  fi
fi

###
# Enable debug logging mode
# Sets verbosity to maximum level for troubleshooting
#
# Usage:
#   z::log::enable_debug
#
# @return 0 always
###
z::log::enable_debug()
{
  emulate -L zsh
  (( _zcore_verbose_level = _zcore_config[log_debug] ))
  z::log::info "Debug mode enabled"
  return 0
}

###
# Get current verbosity level
# Displays the current logging level with human-readable name
#
# Usage:
#   z::log::get_level
#
# @return 0 always
###
z::log::get_level()
{
  emulate -L zsh
  local level_name
  case $_zcore_verbose_level in
    (${_zcore_config[log_error]}) level_name="error" ;;
    (${_zcore_config[log_warn]}) level_name="warn" ;;
    (${_zcore_config[log_info]}) level_name="info" ;;
    (${_zcore_config[log_debug]}) level_name="debug" ;;
    (*) level_name="unknown" ;;
  esac
  print -r -- "Current verbosity level: $_zcore_verbose_level ($level_name)"
  return 0
}

###
# Toggle progress bar display
# Switches progress bar visibility on/off
#
# Usage:
#   z::log::toggle_progress
#
# @return 0 always
###
z::log::toggle_progress()
{
  emulate -L zsh
  if [[ ${_zcore_config[show_progress]:-} == true ]]; then
    _zcore_config[show_progress]=false
    z::log::info "Progress bars disabled"
  else
    _zcore_config[show_progress]=true
    z::log::info "Progress bars enabled"
  fi
  return 0
}

###
# Clear lingering progress output
# Removes any progress bar artifacts from terminal
#
# Usage:
#   z::ui::progress::clear
#
# @return 0 always
###
z::ui::progress::clear()
{
  emulate -L zsh
  if [[ -t 2 ]]; then
    printf '\r\e[K' >&2
  fi
  return 0
}

# Override performance mode from environment if set
if [[ -n ${ZCORE_CONFIG_PERFORMANCE_MODE:-} ]]; then
  _zcore_config[performance_mode]=${ZCORE_CONFIG_PERFORMANCE_MODE}
fi

# Override progress bar display from environment if set
if [[ -n ${ZCORE_CONFIG_SHOW_PROGRESS:-} ]]; then
  _zcore_config[show_progress]=${ZCORE_CONFIG_SHOW_PROGRESS}
fi

################################################################################
# GLOBAL STATE VARIABLES
################################################################################

# Interrupt handling
typeset -gi _zcore_config_interrupted=0    # Flag: user interrupted operation

# Logging recursion guard
typeset -gi _log_depth=0                   # Current logging call depth

# Terminal width caching for performance
typeset -gi _cached_term_width=0           # Last known terminal width
typeset -g _zcore_prev_columns=''          # Previous COLUMNS value for cache invalidation

################################################################################
# CACHING SUBSYSTEM
################################################################################

###
# Function existence cache
# Stores function lookup results to avoid repeated $+functions checks
###
typeset -gA _func_cache              # Cache: function_name -> exists (0/1)
typeset -ga _func_cache_order        # LRU order for cache eviction
typeset -gi _func_cache_size=0       # Current cache size

###
# Command existence cache
# Stores command lookup results to avoid repeated $+commands checks
###
typeset -gA _cmd_cache               # Cache: command_name -> exists (0/1)
typeset -ga _cmd_cache_order         # LRU order for cache eviction
typeset -gi _cmd_cache_size=0        # Current cache size

################################################################################
# TIMEOUT COMMAND DETECTION
################################################################################

###
# Detected timeout command (GNU timeout or macOS gtimeout)
# Used for enforcing command execution timeouts
###
typeset -g _zcore_timeout_cmd=""
if (( $+commands[timeout] )); then
  _zcore_timeout_cmd="timeout"
elif (( $+commands[gtimeout] )); then
  _zcore_timeout_cmd="gtimeout"
fi

################################################################################
# COLOR CONFIGURATION
################################################################################

###
# Terminal color codes
# Automatically detected based on terminal capabilities
# Empty strings if colors unavailable
###
typeset -gA _zcore_colors
if [[ -t 2 && -z ${NO_COLOR:-} && ${TERM:-} != dumb ]] &&
   (( $+commands[tput] )) &&
   tput setaf 1 >/dev/null 2>&1; then
  _zcore_colors=(
    [red]="$(tput setaf 1)"
    [green]="$(tput setaf 2)"
    [blue]="$(tput setaf 4)"
    [yellow]="$(tput setaf 3)"
    [reset]="$(tput sgr0)"
  )
else
  _zcore_colors=([red]="" [green]="" [blue]="" [yellow]="" [reset]="")
fi

################################################################################
# TIMESTAMP CACHING
################################################################################

###
# Cached timestamp for performance
# Updated only when EPOCHSECONDS changes to avoid repeated date calls
###
typeset -g _cached_timestamp=""      # Last formatted timestamp
typeset -gi _timestamp_epoch=0       # Epoch second of last timestamp update

################################################################################
# SECTION 1: LOGGING SUBSYSTEM
################################################################################

###
# Update cached timestamp
# Internal function to refresh timestamp only when needed
# Tries multiple methods: printf %()T, date command, fallback
#
# @private
# @return 0 always
###
z::log::_update_ts()
{
  emulate -L zsh
  typeset -i current_epoch
  (( current_epoch = ${EPOCHSECONDS:-$(date +%s 2>/dev/null || print 0)} ))

  # Only update if epoch second changed
  if (( current_epoch != _timestamp_epoch )); then
    (( _timestamp_epoch = current_epoch ))
    # Try zsh's built-in printf %()T formatting (fastest, zsh 5.0+)
    if ! _cached_timestamp=$(printf '%(%Y-%m-%d %H:%M:%S)T' "$current_epoch" 2>/dev/null); then
      # Fallback to date command
      if ! _cached_timestamp=$(date -r "$current_epoch" '+%Y-%m-%d %H:%M:%S' 2>/dev/null) && \
         ! _cached_timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null); then
        _cached_timestamp="unknown-time"
      fi
    fi
  fi
  return 0
}

###
# Core logging engine
# Internal implementation for all log levels
# Handles recursion prevention, level filtering, formatting
#
# @param 1: integer - Log level (0=error, 1=warn, 2=info, 3=debug)
# @param ...: string - Message components (joined with spaces)
# @private
# @return 0 on success, 1 on recursion overflow or invalid level
###
z::log::_engine()
{
  emulate -L zsh
  setopt localoptions no_unset warn_create_global

  # Infinite recursion prevention
  if (( _log_depth > _zcore_config[log_max_depth] )); then
    print -r -- "FATAL: Recursion in z::log::_engine" >&2
    return 1
  fi
  (( _log_depth += 1 ))

  # Log level validation with base-10 enforcement
  typeset -i level
  if [[ -z ${1-} || $1 != <-> ]]; then
    print -r -- "[error] Invalid log level: '${1-}'" >&2
    (( _log_depth -= 1 ))
    return 1
  fi
  (( level = 10#${1} ))
  shift

  # Early return for filtered messages
  if (( level > _zcore_verbose_level )); then
    (( _log_depth -= 1 ))
    return 0
  fi

  z::log::_update_ts

  # Map level to prefix and color
  local prefix=""
  case $level in
    (${_zcore_config[log_error]}) prefix="${_zcore_colors[red]}[error]${_zcore_colors[reset]}" ;;
    (${_zcore_config[log_warn]})  prefix="${_zcore_colors[yellow]}[warn]${_zcore_colors[reset]}" ;;
    (${_zcore_config[log_info]})  prefix="${_zcore_colors[blue]}[info]${_zcore_colors[reset]}" ;;
    (${_zcore_config[log_debug]}) prefix="${_zcore_colors[green]}[debug]${_zcore_colors[reset]}" ;;
    (*)                            prefix="[unknown]" ;;
  esac

  # Join all message parts with spaces
  local msg="${(j: :)@}"
  print -r -- "${_cached_timestamp} ${prefix} ${msg}" >&2

  (( _log_depth -= 1 ))
  return 0
}

###
# Log error message
# Critical errors that indicate failure
#
# Usage:
#   z::log::error "Failed to connect to database"
#   z::log::error "Invalid input:" "$value"
#
# @param ...: string - Message components
# @return 0 on success
###
z::log::error()
{
  emulate -L zsh
  z::log::_engine ${_zcore_config[log_error]} "$@"
}

###
# Log warning message
# Non-critical issues that don't stop execution
#
# Usage:
#   z::log::warn "Deprecated function called"
#   z::log::warn "Config file not found, using defaults"
#
# @param ...: string - Message components
# @return 0 on success
###
z::log::warn()
{
  emulate -L zsh
  z::log::_engine ${_zcore_config[log_warn]} "$@"
}

###
# Log informational message
# Standard operational messages
#
# Usage:
#   z::log::info "Starting backup process"
#   z::log::info "Processed" $count "files"
#
# @param ...: string - Message components
# @return 0 on success
###
z::log::info()
{
  emulate -L zsh
  z::log::_engine ${_zcore_config[log_info]} "$@"
}

###
# Log debug message
# Verbose debugging information
#
# Usage:
#   z::log::debug "Variable value:" "$var"
#   z::log::debug "Function entered with args:" "$@"
#
# @param ...: string - Message components
# @return 0 on success
###
z::log::debug()
{
  emulate -L zsh
  z::log::_engine ${_zcore_config[log_debug]} "$@"
}

################################################################################
# SECTION 2: INTERRUPT HANDLING
################################################################################

###
# Handle interrupt signal (SIGINT/SIGTERM)
# Sets global interrupt flag for graceful shutdown
# Ignores interrupts during ZLE (line editing) to avoid conflicts
#
# Usage:
#   trap 'z::runtime::handle_interrupt' INT TERM
#
# @return 0 always
###
z::runtime::handle_interrupt()
{
  emulate -L zsh

  # Only handle actual interrupts, not normal editing
  if [[ -n ${ZLE_STATE:-} ]]; then
    return 0 # Don't handle interrupts during ZLE (line editing)
  fi

  # Set flag only once to avoid repeated messages
  if (( _zcore_config_interrupted == 0 )); then
    (( _zcore_config_interrupted = 1 ))
    z::ui::progress::clear
    z::log::warn "Interrupt received. Gracefully shutting down..."
  fi
  return 0
}

###
# Check if operation was interrupted
# Call this in long-running operations to enable graceful cancellation
#
# Usage:
#   for file in *.txt; do
#     z::runtime::check_interrupted || return $?
#     process_file "$file"
#   done
#
# @return 0 if not interrupted, 130 if interrupted
###
z::runtime::check_interrupted()
{
  emulate -L zsh
  if (( _zcore_config_interrupted )); then
    z::log::info "Operation cancelled by user."
    return ${_zcore_config[exit_interrupted]}
  fi
  return 0
}

###
# Set configuration value
# Updates zcore configuration with validation
#
# Usage:
#   z::config::set log_info 2
#   z::config::set performance_mode true
#   z::config::set cache_max_size 200
#
# @param 1: string - Configuration key
# @param 2: string - Configuration value
# @return 0 on success, 1 on validation failure
###
z::config::set()
{
  emulate -L zsh
  local key="${1-}" value="${2-}"

  # Validate key exists
  if [[ -z $key ]]; then
    z::log::error "z::config::set: Configuration key cannot be empty."
    return 1
  fi

  if (( ! ${+_zcore_config[$key]} )); then
    z::log::warn "z::config::set: Unknown configuration key: '$key'."
    return 1
  fi

  # Type-specific validation
  case $key in
    log_* | exit_* | *interval | *timeout | *depth | *size | *threshold | *iterations)
      # Numeric values only with base-10 enforcement
      if [[ $value != <-> ]]; then
        z::log::error "z::config::set: Value for '$key' must be an integer, but got '$value'."
        return 1
      fi
        typeset -i val
        (( val = 10#${value} ))

      # Validate bounds for specific keys
      case $key in
        cache_max_size)
        if (( val < 10 || val > 10000 )); then
          z::log::error "z::config::set: cache_max_size must be between 10 and 10000"
          return 1
        fi
          ;;
        timeout_default | *timeout)
          if (( val < 1 || val > 86400 )); then
            z::log::error "z::config::set: timeout must be between 1 and 86400 seconds"
            return 1
          fi
          ;;
        log_max_depth)
          if (( val < 10 || val > 1000 )); then
            z::log::error "z::config::set: log_max_depth must be between 10 and 1000"
            return 1
          fi
          ;;
        symlink_max_iterations)
          if (( val < 10 || val > 1000 )); then
            z::log::error "z::config::set: symlink_max_iterations must be between 10 and 1000"
            return 1
          fi
          ;;
      esac
      ;;
    *mode | show_progress | install_traps)
      # Boolean values only
      if [[ $value != true && $value != false ]]; then
        z::log::error "z::config::set: Value for '$key' must be 'true' or 'false', but got '$value'."
        return 1
      fi
      ;;
  esac

  _zcore_config[$key]=$value
  z::log::debug "Configuration updated: $key = $value"
  return 0
}

################################################################################
# SECTION 3: FATAL ERROR HANDLING
################################################################################

###
# Fatal error handler
# Logs fatal error and exits or returns depending on context
# Automatically detects if sourced (returns) or executed (exits)
#
# Usage:
#   z::runtime::die "Database connection failed"
#   z::runtime::die "Invalid state" 2
#
# @param 1: string - Error message
# @param 2: integer - Exit code (optional, defaults to 1)
# @return Never returns if executed, returns exit code if sourced
###
z::runtime::die()
{
  emulate -L zsh
  local message="${1-}"
  typeset -i exit_code
  (( exit_code = 10#${2:-${_zcore_config[exit_general_error]}} ))

  z::ui::progress::clear
  z::log::error "FATAL: $message"

  # Return in sourced context, exit otherwise
  if [[ -n $ZSH_EVAL_CONTEXT && $ZSH_EVAL_CONTEXT == *:file:* ]]; then
    return $exit_code
  else
    exit $exit_code
  fi
}

################################################################################
# SECTION 4: PLATFORM DETECTION
################################################################################

###
# Detect operating system and platform features
# Sets global read-only flags for platform-specific logic:
#   IS_MACOS, IS_LINUX, IS_BSD, IS_CYGWIN, IS_UNKNOWN
#   IS_WSL (Windows Subsystem for Linux)
#   IS_TERMUX (Android terminal emulator)
#
# Only runs once (idempotent via _PLATFORM_DETECTED flag)
#
# Usage:
#   z::detect::platform
#   if (( IS_MACOS )); then
#     # macOS-specific code
#   fi
#
# @return 0 on success
###
z::detect::platform()
{
  emulate -L zsh
  setopt no_unset typeset_silent

  z::runtime::check_interrupted \
    || return $?

  # Idempotent: only detect once
  if [[ -n ${_PLATFORM_DETECTED:-} ]]; then
    return 0
  fi

  # Defensive fallback if OSTYPE is empty
  local ostype_value="${OSTYPE:-}"
  if [[ -z $ostype_value ]]; then
    case "$(uname -s 2> /dev/null)" in
      Darwin)                              ostype_value="darwin" ;;
      Linux)                               ostype_value="linux" ;;
      FreeBSD | OpenBSD | NetBSD | DragonFly) ostype_value="bsd" ;;
      CYGWIN* | MSYS* | MINGW*)            ostype_value="cygwin" ;;
      *)                                   ostype_value="unknown" ;;
    esac
  fi

  # Set platform variables based on $ostype_value
  case $ostype_value in
    darwin*)
      typeset -gri IS_MACOS=1 IS_LINUX=0 IS_BSD=0 IS_CYGWIN=0
      ;;
    linux* | linux-gnu*)
      typeset -gri IS_MACOS=0 IS_LINUX=1 IS_BSD=0 IS_CYGWIN=0
      ;;
    *bsd* | dragonfly* | netbsd* | openbsd* | freebsd*)
      typeset -gri IS_MACOS=0 IS_LINUX=0 IS_BSD=1 IS_CYGWIN=0
      ;;
    cygwin* | msys* | mingw*)
      typeset -gri IS_MACOS=0 IS_LINUX=0 IS_BSD=0 IS_CYGWIN=1
      ;;
    *)
      typeset -gri IS_MACOS=0 IS_LINUX=0 IS_BSD=0 IS_CYGWIN=0
      ;;
  esac

  # Check for Windows Subsystem for Linux (WSL) - Linux only
  typeset -i is_wsl=0
  if (( IS_LINUX )); then
    # Multiple detection methods for WSL compatibility
    if [[ -n ${WSL_DISTRO_NAME:-} || -n ${WSLENV:-} || -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
      (( is_wsl = 1 ))
    elif [[ -r /proc/version ]]; then
      local proc_version=""
      if IFS= read -r proc_version < /proc/version 2> /dev/null; then
        if [[ $proc_version == *[Mm]icrosoft* || $proc_version == *[Ww][Ss][Ll]* ]]; then
          (( is_wsl = 1 ))
        fi
      fi
    fi
  fi
  typeset -gri IS_WSL=$is_wsl

  # Check for Termux on Android - Linux only
  typeset -i is_termux=0
  if (( IS_LINUX )) && \
    [[ -d /data/data/com.termux/files/usr ]]; then
    (( is_termux = 1 ))
  fi
  typeset -gri IS_TERMUX=$is_termux

  # Unknown flag
  if (( IS_MACOS || IS_LINUX || IS_BSD || IS_CYGWIN )); then
    typeset -gri IS_UNKNOWN=0
  else
    typeset -gri IS_UNKNOWN=1
  fi

  # Mark complete
  typeset -gr _PLATFORM_DETECTED=1

  if (( IS_UNKNOWN )); then
    z::log::warn "Unknown platform: ${ostype_value}"
  fi

  z::log::debug "Platform: macOS=$IS_MACOS Linux=$IS_LINUX BSD=$IS_BSD WSL=$IS_WSL Cygwin=$IS_CYGWIN Termux=$IS_TERMUX"

  return 0
}


################################################################################
# SECTION 5: COMMAND & ALIAS HANDLING
################################################################################

###
# Define shell alias with validation
# Creates an alias with safety checks
#
# Usage:
#   z::alias::define ll 'ls -lah'
#   z::alias::define gs 'git status'
#
# @param 1: string - Alias name (no spaces or equals)
# @param 2: string - Alias value (command)
# @return 0 on success, 1 on validation failure
###
z::alias::define()
{
  emulate -L zsh
  setopt no_unset warn_create_global

  local alias_name="${1-}" alias_value="${2-}"

  # Validate inputs
  if [[ -z $alias_name || -z $alias_value || $alias_name == *[[:space:]=]* ]]; then
    z::log::error "Invalid alias definition: name='$alias_name' value='$alias_value'"
    return 1
  fi

  # Attempt to create alias
  if ! builtin alias "${alias_name}=${alias_value}" 2> /dev/null; then
    z::log::error "Failed to create alias: $alias_name='$alias_value'"
    return 1
  fi
  z::log::debug "Created alias: $alias_name='$alias_value'"
  return 0
}

###
# Add directory to PATH
# Resolves path, validates existence, prevents duplicates
# Automatically rehashes command cache after modification
#
# Usage:
#   z::path::add /usr/local/bin
#   z::path::add ~/bin prepend
#   z::path::add /opt/custom/bin append
#
# @param 1: string - Directory path (supports tilde expansion)
# @param 2: string - Position: 'prepend' or 'append' (default: append)
# @return 0 on success, 1 on validation failure
###
z::path::add()
{
  emulate -L zsh
  local dir="$1"
  local position="${2:-append}"

  # Validate input
  if [[ -z $dir ]]; then
    z::log::error "Empty directory provided to z::path::add"
    return 1
  fi

  # Resolve path with tilde and symlink expansion
  local original_dir="$dir"
  if ! dir=$(z::path::resolve "$dir"); then
    z::log::debug "Failed to resolve directory path for PATH: $original_dir"
    return 1
  fi

  # Skip non-existent directories silently
  if [[ ! -d $dir ]]; then
    z::log::debug "Directory does not exist, not adding to PATH: $dir"
    return 0
  fi

  # Prevent duplicate entries
  if [[ ":${PATH}:" == *":${dir}:"* ]]; then
    z::log::debug "Directory already in PATH: $dir"
    return 0
  fi

  # Add to PATH based on position
  case $position in
    prepend) export PATH="$dir:$PATH" ;;
    append)  export PATH="$PATH:$dir" ;;
    *)
      z::log::error "Invalid position for z::path::add: $position (use prepend or append)"
      return 1
      ;;
  esac

  # Rehash and clear command cache to avoid stale $commands hits
  builtin hash -r 2> /dev/null || true
  z::cache::cmd::clear

  z::log::debug "Added to PATH ($position): $dir"
  return 0
}

################################################################################
# SECTION 6: DYNAMIC & SAFE EXECUTION
################################################################################

###
# Check if command is a whitelisted shell init command
# Allows specific tools to bypass strict security checks
# Supports: starship, mise, direnv, zoxide, atuin, mcfly, fzf, oh-my-posh
#
# @param 1: string - Command string to check
# @private
# @return 0 if whitelisted init command, 1 otherwise
###
z::exec::_is_init_cmd()
{
  emulate -L zsh
  local input="$1"

  # Optional user-provided whitelist regex
  if [[ -n ${_zcore_config[init_whitelist_regex]:-} ]]; then
    if [[ $input =~ ${_zcore_config[init_whitelist_regex]} ]]; then
      return 0
    fi
  fi

  # Built-in whitelist for common shell integration tools
  # Pattern matches: starship init, mise activate, direnv hook, etc.
  if [[ $input =~ '(starship|mise|direnv|zoxide|atuin|mcfly|fzf|oh-my-posh)[[:space:]]+init([[:space:]]|$)' ]]; then
    return 0
  fi
  return 1
}

###
# Check command segment for dangerous patterns
# Scans for destructive operations: rm -rf /, dd of=/dev/*, chmod 777 -R /, etc.
#
# @param 1: string - Command name
# @param ...: string - Command arguments
# @private
# @return 0 if safe, 1 if dangerous pattern detected
###
z::exec::_check_segment()
{
  emulate -L zsh
  local cmd="$1"
  shift
  local -a args=("$@")

  # Guard: rm -rf on critical paths
  if [[ $cmd == rm ]]; then
    typeset -i have_r=0 have_f=0
    local a
    for a in "${args[@]}"; do
      if [[ $a == --* ]]; then
        continue
      elif [[ $a == -* ]]; then
        [[ $a == *r* ]] && (( have_r = 1 ))
        [[ $a == *f* ]] && (( have_f = 1 ))
        continue
      fi
    done
    # Check if rm -rf targeting dangerous paths
    if (( have_r && have_f )); then
      for a in "${args[@]}"; do
        case $a in
          / | /* | ~ | ~/* | '$HOME' | '$HOME'/*)
            z::log::error "Dangerous rm target: $a"
            return 1
            ;;
        esac
      done
    fi
  fi

  # Guard: dd writing to raw block devices
  if [[ $cmd == dd ]]; then
    local kv dev base
    for kv in "${args[@]}"; do
      if [[ $kv == of=/dev/* ]]; then
        dev="${kv#of=}"
        base="${dev#/dev/}"
        case $base in
          sd* | hd* | nvme* | disk* | rdisk*)
            z::log::error "Dangerous dd of= raw device: $dev"
            return 1
            ;;
        esac
      fi
    done
  fi

  # Guard: mkfs on block devices
  if [[ $cmd == mkfs.* ]]; then
    local a
    for a in "${args[@]}"; do
      if [[ $a == /dev/* ]]; then
        z::log::error "Dangerous mkfs target: $a"
        return 1
      fi
    done
  fi

  # Guard: chmod -R 777 / or similar
  if [[ $cmd == chmod ]]; then
    typeset -i nmode=-1 recursive=0 targets_root=0 is_wide_open=0
    local mode_arg="" a

    for a in "${args[@]}"; do
      # Check for recursive flag
      if [[ $a == -* ]]; then
        [[ $a == *R* ]] && (( recursive = 1 ))
        continue
      fi

      # First non-option is the mode
      if [[ -z $mode_arg ]]; then
        mode_arg="$a"
        # Numeric mode 777
        if [[ $mode_arg == <-> ]]; then
          (( nmode = 10#${mode_arg} ))
          (( nmode == 777 )) && (( is_wide_open = 1 ))
        # Symbolic modes that grant world-write
        elif [[ $mode_arg == *a+w* || $mode_arg == *a+rwx* || $mode_arg == *o+w* ]]; then
          (( is_wide_open = 1 ))
        fi
        continue
      fi

      # Check if any target is root
      [[ $a == / ]] && (( targets_root = 1 ))
    done

    # Dangerous if: recursive + root target + wide-open permissions
    if (( recursive && targets_root && is_wide_open )); then
      z::log::error "Dangerous chmod: recursive wide-open permissions on /"
      return 1
    fi
  fi

  # Guard: killall/pkill -9
  if [[ $cmd == killall || $cmd == pkill ]]; then
    local a
    for a in "${args[@]}"; do
      case $a in
        -9 | -KILL | -SIGKILL)
          z::log::error "Dangerous kill signal -9 detected"
          return 1
          ;;
      esac
    done
  fi

  # Guard: userdel -r (deletes home directory)
  if [[ $cmd == userdel ]]; then
    local a
    for a in "${args[@]}"; do
      [[ $a == -r ]] && {
        z::log::error "Dangerous userdel -r"
        return 1
      }
    done
  fi

  # Guard: groupdel (system modification)
  if [[ $cmd == groupdel ]]; then
    z::log::error "Dangerous groupdel detected"
    return 1
  fi

  return 0
}

###
# Check for dangerous shell metacharacters
# Detects: semicolons, ampersands, parentheses, backticks
#
# @param 1: string - Input string to check
# @private
# @return 0 if dangerous chars found, 1 otherwise
###
z::exec::_has_dangerous_metachars()
{
  emulate -L zsh
  local input="$1"
  [[ -z $input ]] && return 1
  [[ $input =~ '[;&()]' ]] || [[ $input == *'`'* ]]
}

###
# Scan command string for dangerous patterns
# Security analysis using zsh lexer
# Checks for: pipe to shell, fork bombs, dangerous commands
#
# @param 1: string - Command string to analyze
# @private
# @return 0 if safe, 1 if dangerous pattern detected
###
z::exec::_scan_patterns()
{
  emulate -L zsh
  setopt localoptions typeset_silent
  local input="${1-}"
  [[ -z $input ]] && return 0

  # Skip security checks for whitelisted init commands
  if z::exec::_is_init_cmd "$input"; then
    return 0
  fi

  # Tokenize using zsh's built-in lexer
  local -a words
  words=(${(z)input})
  (( ${#words} == 0 )) && return 0

  # Guard: pipe to a shell (command injection risk)
  typeset -i i j
  local next_cmd base
  for (( i = 1; i <= ${#words}; i++ )); do
    if [[ ${words[i]} == '|' ]]; then
      (( j = i + 1 ))
      # Find the first real command in the next segment
      while (( j <= ${#words} )); do
        case ${words[j]} in
          '|' | '||' | '&&' | ';' | '&')
            break
            ;;
          # Skip precommands and variable assignments
          nocorrect | noglob | builtin | command | exec | time | nice | nohup | sudo | doas | env)
            (( j += 1 ))
            continue
            ;;
          [[:alpha:]_][[:alnum:]_]*=*)
            (( j += 1 ))
            continue
            ;;
        esac
        next_cmd="${words[j]}"
        break
      done
      if [[ -n ${next_cmd:-} ]]; then
        base="${next_cmd:t}"
        case $base in
          sh | bash | zsh | ksh | dash)
            z::log::error "Dangerous pattern: pipe to shell"
            return 1
            ;;
        esac
      fi
    fi
  done

  # Guard: common fork bomb pattern :(){ :|:& };:
  # Simplified check: look for suspicious function definition with recursion
  if [[ $input =~ ':\(\)' && $input =~ ':\|:' ]]; then
    z::log::error "Dangerous pattern: potential fork bomb"
    return 1
  fi

  # Build and check segments split across |, ||, &&, ;, &
  local -a seg=()
  local w
  for w in "${words[@]}"; do
    case $w in
      '|' | '||' | '&&' | ';' | '&')
        # Process completed segment
        if (( ${#seg} )); then
          local cmd="${seg[1]}"
          local -a args=("${(@)seg[2,-1]}")
          z::exec::_check_segment "$cmd" "${args[@]}" || return 1
          seg=()
        fi
        ;;
      # Skip precommands only at segment start
      nocorrect | noglob | builtin | command | exec | time | nice | nohup | sudo | doas | env)
        if (( ${#seg} == 0 )); then
          continue
        else
          seg+=("$w")
        fi
        ;;
      # Skip leading assignments in a segment
      [[:alpha:]_][[:alnum:]_]*=*)
        if (( ${#seg} == 0 )); then
          continue
        else
          seg+=("$w")
        fi
        ;;
      *)
        seg+=("$w")
        ;;
    esac
  done

  # Check final segment if exists
  if (( ${#seg} )); then
    local cmd="${seg[1]}"
    local -a args=("${(@)seg[2,-1]}")
    z::exec::_check_segment "$cmd" "${args[@]}" || return 1
  fi

  return 0
}

###
# Safe command execution without eval
# Runs command in subshell with pipefail, optional timeout
# Performs security checks unless whitelisted
#
# Usage:
#   z::exec::run "ls -la /tmp"
#   z::exec::run "long_command" 60  # 60 second timeout
#
# @param 1: string - Command string to execute
# @param 2: integer - Timeout in seconds (optional, default: 30)
# @return Command exit code, 124 on timeout
###
z::exec::run()
{
  emulate -L zsh
  local input="$1"
  typeset -i timeout
  (( timeout = 10#${2:-${_zcore_config[timeout_default]}} ))

  # Validate input
  if [[ -z $input ]]; then
    z::log::error "Empty input for z::exec::run"
    return 1
  fi

  # Short-term guard: block dangerous metacharacters unless whitelisted
  if ! z::exec::_is_init_cmd "$input"; then
    if z::exec::_has_dangerous_metachars "$input"; then
      z::log::error "Rejected dangerous metacharacters in input"
      return 1
    fi
  fi

  # Security scan
  z::exec::_scan_patterns "$input" || return 1

  z::runtime::check_interrupted || return $?

  typeset -i exit_code=0

  # Execute with timeout if available
  if [[ -n ${_zcore_timeout_cmd:-} ]]; then
    ${_zcore_timeout_cmd} "$timeout" zsh -o pipefail -c "$input" || exit_code=$?
    if (( exit_code == 124 )); then
      z::log::warn "Command timed out after ${timeout}s"
    fi
  else
    z::log::warn "Timeout command not found, executing directly"
    zsh -o pipefail -c "$input" || exit_code=$?
  fi

  if (( exit_code != 0 && exit_code != 124 )); then
    z::log::warn "Command failed with exit code $exit_code"
  fi
  return $exit_code
}

###
# Evaluate command with security checks and optional timeout
# Smart evaluation with context detection for shell init vs regular commands
# Can force evaluation in current shell (for init scripts)
#
# Usage:
#   z::exec::eval "export PATH=/usr/local/bin:$PATH"
#   z::exec::eval "starship init zsh" 30 true  # Force current shell
#   z::exec::eval "npm install express" 300    # 5 min timeout
#
# @param 1: string - Command string to evaluate
# @param 2: integer - Timeout in seconds (optional, default: 30)
# @param 3: string - Force current shell: "true" or "false" (optional, default: false)
# @return Command exit code
###
z::exec::eval()
{
  emulate -L zsh
  local input="$1"
  typeset -i timeout
  (( timeout = 10#${2:-${_zcore_config[timeout_default]}} ))
  local force_current_shell="${3:-false}"

  # Validate input
  if [[ -z $input ]]; then
    z::log::error "Empty input for z::exec::eval"
    return 1
  fi

  # Force eval in current shell if requested
  if [[ $force_current_shell == true ]]; then
    z::log::warn "Forced eval in current shell requested — input must be trusted"
    z::runtime::check_interrupted || return $?
    typeset -i exit_code=0
    builtin eval -- "$input" || exit_code=$?
    if (( exit_code != 0 )); then
      z::log::warn "Forced eval failed with exit code $exit_code"
    fi
    return $exit_code
  fi

  # Detect shell init commands
  local is_shell_init=false
  z::exec::_is_init_cmd "$input" && is_shell_init=true

  # Detect package manager install commands
  local is_package_install=false
  if [[ $input =~ '(^|[[:space:]])(npm|yarn|pip|pip3|cargo|brew|apt|yum|dnf|pacman)[[:space:]]+(add|install)($|[[:space:]])' ]]; then
    is_package_install=true
  fi

  # Security scan (skipped for known safe patterns in performance mode)
  if [[ ${_zcore_config[performance_mode]} != true ]] && \
    [[ $is_shell_init != true ]] && \
    [[ $is_package_install != true ]]; then
    z::exec::_scan_patterns "$input" || return 1
  fi

  z::runtime::check_interrupted || return $?

  if [[ $is_shell_init == true ]]; then
    z::log::debug "Detected shell init command (running in subshell): ${input}"
  fi

  z::exec::run "$input" "$timeout"
}

###
# Initialize tool by evaluating its shell hook
# Safely sources output from command's init/hook subcommand
# Commonly used for: starship, direnv, zoxide, etc.
#
# Usage:
#   z::exec::from_hook direnv
#   z::exec::from_hook starship init zsh
#   z::exec::from_hook mise activate zsh
#
# @param 1: string - Tool name (command)
# @param 2: string - Subcommand (default: "init")
# @param 3: string - Shell argument (default: "zsh")
# @return 0 on success, 1 on failure, 0 if tool not found
###
z::exec::from_hook()
{
  emulate -L zsh
  local tool_name="$1"
  local subcommand="${2:-init}"
  local shell_arg="${3:-zsh}"

  z::runtime::check_interrupted || return $?

  # Skip silently if tool not installed
  if ! z::cmd::exists "$tool_name"; then
    z::log::debug "$tool_name not found, skipping"
    return 0 # Return 0 because not finding the tool isn't a failure
  fi

  # Capture hook output
  local init_code
  if init_code=$("$tool_name" "$subcommand" "$shell_arg" 2> /dev/null) && [[ -n $init_code ]]; then
    # Use the 'true' flag to force eval in the current shell context
    if z::exec::eval "$init_code" 30 true; then
      z::log::debug "$tool_name initialized successfully via hook"
      return 0
    else
      z::log::warn "Failed to initialize $tool_name from its hook"
      return 1
    fi
  else
    z::log::warn "Failed to get hook/init code from $tool_name"
    return 1
  fi
}

################################################################################
# SECTION 7: FILESYSTEM & SOURCING
################################################################################

###
# Resolve path to absolute canonical form
# Handles: tilde expansion (~, ~/..., ~+, ~-), symlinks, relative paths
# Prefers zsh's :A modifier, falls back to readlink/manual resolution
#
# Usage:
#   resolved=$(z::path::resolve "~/dotfiles")
#   resolved=$(z::path::resolve "../config")
#   resolved=$(z::path::resolve "/usr/local/bin")
#
# @param 1: string - Path to resolve
# @stdout Resolved absolute path
# @return 0 on success, 1 on validation failure or symlink cycle
###
z::path::resolve()
{
  emulate -L zsh
  local path="$1"

  # Validate input
  if [[ -z $path || $path =~ ^[[:space:]]*$ ]]; then
    z::log::error "Empty or whitespace path provided to z::path::resolve"
    return 1
  fi

  # Tilde expansion (handle ~, ~/..., ~+, ~-, without glob side-effects)
  if [[ $path == '~' || $path == '~/'* ]]; then
    path="${HOME}${path#\~}"
  elif [[ $path == '~+' || $path == '~+/'* ]]; then
    path="${PWD}${path#\~+}"
  elif [[ $path == '~-' || $path == '~-/'* ]]; then
    path="${OLDPWD:-$PWD}${path#\~-}"
  fi

  # Ensure absolute path prior to normalization
  if [[ $path != /* ]]; then
    path="${PWD%/}/$path"
  fi

  # Prefer zsh's realpath-like modifier (:A) for portability and speed
  local normalized
  normalized="${path:A}"
  if [[ -n $normalized ]]; then
    printf '%s' "$normalized"
    return 0
  fi

  # Fallback: POSIX-friendly manual resolution without readlink -f
  local current_path="$path"
  # Use associative array for O(1) cycle detection
  typeset -A visited_paths
  typeset -i iteration_count=0
  typeset -i max_iterations
  (( max_iterations = _zcore_config[symlink_max_iterations] ))

  # Resolve symlinks manually if readlink available
  if command -v readlink > /dev/null 2>&1; then
    while [[ -L $current_path ]]; do
      # Iteration limit to prevent infinite loops
      (( iteration_count += 1 ))
      if (( iteration_count > max_iterations )); then
        z::log::warn "Symlink resolution exceeded max iterations at $current_path"
        printf '%s' "$path"
        return 1
      fi

      # Cycle detection - O(1) lookup
      if (( ${+visited_paths[$current_path]} )); then
        z::log::warn "Symlink cycle detected at $current_path"
        printf '%s' "$path"
        return 1
      fi
      visited_paths[$current_path]=1
      local target
      target=$(readlink "$current_path" 2> /dev/null) || break
      [[ -z $target ]] && break
      # Handle relative vs absolute symlink targets
      if [[ $target == /* ]]; then
        current_path="$target"
      else
        current_path="${current_path:h}/$target"
      fi
    done
  fi

  # Physical directory resolution
  if [[ -d ${current_path:h} ]]; then
    local physical_dir
    if physical_dir=$(
      cd -P "${current_path:h}" 2> /dev/null && pwd -P
    ); then
      current_path="${physical_dir}/${current_path:t}"
    fi
  fi

  printf '%s' "$current_path"
  return 0
}

###
# Source file with validation and optional global scope
# Safely sources shell scripts with path resolution and interrupt checks
# Clears function cache after successful sourcing
#
# Usage:
#   z::path::source ~/.zshrc
#   z::path::source --global /etc/zsh/zprofile  # Global scope
#   z::path::source ~/lib/utils.zsh arg1 arg2   # Pass arguments
#
# @param 1: string - "--global" flag (optional, preserves global scope)
# @param 2: string - File path to source
# @param ...: string - Arguments to pass to sourced file
# @return 0 on success, 1 on validation failure or source error
###
z::path::source()
{
  # Parse flags BEFORE setting emulate (so we can skip it conditionally)
  local use_global_scope=false
  if [[ ${1-} == --global ]]; then
    use_global_scope=true
    shift
  fi

  # Only use local emulation if not loading global config
  if [[ $use_global_scope != true ]]; then
    emulate -L zsh
  fi

  local file="${1-}"
  shift

  # Validate input
  if [[ -z $file ]]; then
    z::log::error "Empty file path for source"
    return 1
  fi

  local resolved_file="$file"

  # Always do cheap tilde expansion (even in performance mode)
  case $resolved_file in
    '~' | '~/'*)   resolved_file="${HOME}${resolved_file#~}" ;;
    '~+' | '~+/'*) resolved_file="${PWD}${resolved_file#~+}" ;;
    '~-' | '~-/'*) resolved_file="${OLDPWD:-$PWD}${resolved_file#~-}" ;;
  esac

  # Skip expensive path normalization in performance mode
  if [[ ${_zcore_config[performance_mode]} != true ]]; then
    if ! resolved_file=$(z::path::resolve "$resolved_file"); then
      z::log::error "Failed to resolve path: $file"
      return 1
    fi
  fi

  # Validate file exists and is readable
  if [[ ! -f $resolved_file || ! -r $resolved_file ]]; then
    z::log::warn "File not found or not readable: $resolved_file"
    return 1
  fi

  z::runtime::check_interrupted || return $?

  # Source file with optional arguments
  typeset -i exit_code=0
  source "$resolved_file" "$@" || exit_code=$?

  if (( exit_code != 0 )); then
    z::log::warn "Failed to source $resolved_file (code: $exit_code)"
  else
    # Clear function cache after successful sourcing
    z::cache::func::clear
  fi

  return $exit_code
}

################################################################################
# SECTION 8: FUNCTION INTROSPECTION & CACHING
################################################################################

###
# Shared cache update logic for LRU tracking
# Reduces code duplication between function and command caches
#
# @param 1: string - Cache type: "func" or "cmd"
# @param 2: string - Cache key
# @param 3: integer - Result value (0 or 1)
# @private
# @return 0 always
###
z::cache::_update_entry()
{
  emulate -L zsh
  local cache_type="$1" cache_key="$2"
  typeset -i result
  (( result = 10#${3} ))

  case $cache_type in
    func)
      # Only de-duplicate if key already exists
      if (( ${+_func_cache[$cache_key]} )); then
        _func_cache_order=("${(@)_func_cache_order:#$cache_key}")
      else
        (( _func_cache_size += 1 ))
      fi
      _func_cache[$cache_key]=$result
      _func_cache_order+=("$cache_key")
      ;;
    cmd)
      # Only de-duplicate if key already exists
      if (( ${+_cmd_cache[$cache_key]} )); then
        _cmd_cache_order=("${(@)_cmd_cache_order:#$cache_key}")
      else
        (( _cmd_cache_size += 1 ))
      fi
      _cmd_cache[$cache_key]=$result
      _cmd_cache_order+=("$cache_key")
      ;;
  esac
  return 0
}

###
# Purge oldest cache entries when size exceeds limit
# Shared implementation for function and command caches
# Uses LRU (Least Recently Used) eviction strategy
# Uses batch removal instead of repeated array slicing
#
# @param 1: string - Cache type: "func" or "cmd"
# @private
# @return 0 on success, 1 on invalid cache type
###
z::cache::_purge_impl()
{
  emulate -L zsh
  local cache_type="$1"
  typeset -i current_size threshold excess to_remove purge_threshold

  # Determine cache parameters based on type
  case $cache_type in
    func)
      (( current_size = _func_cache_size ))
      (( threshold = _zcore_config[cache_max_size] ))
      ;;
    cmd)
      (( current_size = _cmd_cache_size ))
      (( threshold = _zcore_config[cache_max_size] ))
      ;;
    *)
      z::log::error "Invalid cache type: $cache_type"
      return 1
      ;;
  esac

  # Early return if under threshold
  if (( current_size <= threshold )); then
    return 0
  fi

  # Calculate excess
  (( excess = current_size - threshold ))
  (( purge_threshold = _zcore_config[cache_purge_threshold] ))

  # Only purge if excess is significant (avoid thrashing)
  if (( excess < purge_threshold )); then
    return 0
  fi

  # Calculate entries to remove (half the excess + 1)
  # Explicit parentheses for clarity
  (( to_remove = (excess / 2) + 1 ))

  # OPTIMIZATION: Batch removal using array slicing (single operation)
  case $cache_type in
    func)
      # Bounds check: ensure we don't slice beyond array size
      if (( to_remove >= ${#_func_cache_order} )); then
        # Remove all entries
        _func_cache=()
        _func_cache_order=()
        (( _func_cache_size = 0 ))
        z::log::debug "Cleared entire function cache (exceeded bounds)"
      else
      # Get keys to remove
      local -a keys_to_remove=("${(@)_func_cache_order[1,to_remove]}")

      # Remove from order array in one operation
      _func_cache_order=("${(@)_func_cache_order[to_remove+1,-1]}")

      # Remove from cache hash
      local key
      for key in "${keys_to_remove[@]}"; do
        if (( ${+_func_cache[$key]} )); then
          unset "_func_cache[$key]"
        fi
      done

      # Update size from actual hash size
      (( _func_cache_size = ${#_func_cache} ))
      z::log::debug "Cleaned function cache: removed ${#keys_to_remove} entries, new size: $_func_cache_size"
      fi
      ;;
    cmd)
      # Bounds check: ensure we don't slice beyond array size
      if (( to_remove >= ${#_cmd_cache_order} )); then
        # Remove all entries
        _cmd_cache=()
        _cmd_cache_order=()
        (( _cmd_cache_size = 0 ))
        z::log::debug "Cleared entire command cache (exceeded bounds)"
      else
      # Get keys to remove
      local -a keys_to_remove=("${(@)_cmd_cache_order[1,to_remove]}")

      # Remove from order array in one operation
      _cmd_cache_order=("${(@)_cmd_cache_order[to_remove+1,-1]}")

      # Remove from cache hash
      local key
      for key in "${keys_to_remove[@]}"; do
        if (( ${+_cmd_cache[$key]} )); then
          unset "_cmd_cache[$key]"
        fi
      done

      # Update size from actual hash size
      (( _cmd_cache_size = ${#_cmd_cache} ))
      z::log::debug "Cleaned command cache: removed ${#keys_to_remove} entries, new size: $_cmd_cache_size"
      fi
      ;;
  esac
  return 0
}

###
# Purge function cache when size exceeds limit
# @private
# @return 0 on success
###
z::cache::func::_purge()
{
  emulate -L zsh
  z::cache::_purge_impl func
}

###
# Purge command cache when size exceeds limit
# @private
# @return 0 on success
###
z::cache::cmd::_purge()
{
  emulate -L zsh
  z::cache::_purge_impl cmd
}

###
# Clear all command cache entries
# Useful after PATH modifications or package installations
#
# Usage:
#   z::cache::cmd::clear
#
# @return 0 always
###
z::cache::cmd::clear()
{
  emulate -L zsh
  _cmd_cache=()
  _cmd_cache_order=()
  (( _cmd_cache_size = 0 ))
  z::log::debug "Cleared command cache"
  return 0
}

###
# Clear all function cache entries
# Useful after sourcing new files or function definitions
#
# Usage:
#   z::cache::func::clear
#
# @return 0 always
###
z::cache::func::clear()
{
  emulate -L zsh
  _func_cache=()
  _func_cache_order=()
  (( _func_cache_size = 0 ))
  z::log::debug "Cleared function cache"
  return 0
}

###
# Check if command exists with result caching
# Significantly faster than repeated $+commands checks
# Automatically manages cache size and LRU eviction
#
# Usage:
#   if z::cmd::exists git; then
#     git status
#   fi
#
# @param 1: string - Command name to check
# @return 0 if command exists, 1 otherwise
###
z::cmd::exists()
{
  emulate -L zsh
  local cmd="$1"
  [[ -z $cmd ]] && return 1

  # Sanitize command name for use as cache key
  local cache_key="cmd_${cmd//[^a-zA-Z0-9_]/_}"

  # Return cached result if available
  if (( ${+_cmd_cache[$cache_key]} )); then
    return ${_cmd_cache[$cache_key]}
  fi

  # Perform actual check
  typeset -i result=1
  (( $+commands[$cmd] )) && (( result = 0 ))

  # Update cache with LRU tracking (using shared helper)
  z::cache::_update_entry cmd "$cache_key" $result

  # Purge cache if size exceeded
  (( _cmd_cache_size > _zcore_config[cache_max_size] )) && z::cache::cmd::_purge

  return $result
}

###
# Check if function exists with result caching
# Significantly faster than repeated $+functions checks
# Automatically manages cache size and LRU eviction
#
# Usage:
#   if z::func::exists my_function; then
#     my_function arg1 arg2
#   fi
#
# @param 1: string - Function name to check
# @return 0 if function exists, 1 otherwise
###
z::func::exists()
{
  emulate -L zsh
  local func="$1"
  if [[ -z $func ]]; then
    return 1
  fi

  # Sanitize function name for use as cache key
  local cache_key="func_exists_${func//[^a-zA-Z0-9_]/_}"

  # Return cached result if available
  if (( ${+_func_cache[$cache_key]} )); then
    return ${_func_cache[$cache_key]}
  fi

  # Perform actual check
  typeset -i result=1
  (( $+functions[$func] )) && (( result = 0 ))

  # Update cache with LRU tracking (using shared helper)
  z::cache::_update_entry func "$cache_key" $result

  # Always purge; internal threshold check handles cost
  z::cache::func::_purge

  return $result
}

###
# Call function with existence check and error handling
# Silently skips known dynamic functions (git prompts, etc.)
# Logs warnings for missing non-dynamic functions
#
# Usage:
#   z::func::call my_function arg1 arg2
#   z::func::call process_data "$file"
#
# @param 1: string - Function name to call
# @param ...: any - Arguments to pass to function
# @return Function exit code, 1 if function not found
###
z::func::call()
{
  emulate -L zsh
  local func="$1"

  # Validate input
  if [[ -z $func ]]; then
    z::log::error "Empty function name for z::func::call"
    return 1
  fi
  shift

  # Check function existence with caching
  if ! z::func::exists "$func"; then
    # Silently skip known dynamic functions that may not always exist
    case $func in
      _git_prompt_info | __zconvey_on_period_passed* | _*prompt* | _*git*)
        return 1 # Silently skip known dynamic functions
        ;;
      *)
        z::log::warn "Function '$func' not found"
        return 1
        ;;
    esac
  fi

  z::runtime::check_interrupted || return $?

  # Call function and capture exit code
  typeset -i exit_code=0
  "$func" "$@" || exit_code=$?

  if (( exit_code != 0 )); then
    z::log::warn "Function '$func' failed with code $exit_code"
  fi
  return $exit_code
}

################################################################################
# SECTION 9: STATE MANAGEMENT
################################################################################

###
# Core unset implementation for variables and functions
# Shared implementation with type-specific behavior
# Handles readonly variables gracefully
# Updates function cache on successful function unset
#
# @param 1: string - Target name (variable or function)
# @param 2: string - Type: "var", "func", or "auto" (checks both)
# @private
# @return 0 on success, 1 if not found or unset failed
###
z::state::_unset_impl()
{
  emulate -L zsh
  setopt typeset_silent no_unset

  local target="${1-}"
  local unset_type="${2:-auto}"

  # Validate inputs
  if [[ -z $target ]]; then
    z::log::error "Empty target for unset"
    return 1
  fi

  case $unset_type in
    var | func | auto) ;;
    *)
      z::log::error "Invalid unset type: $unset_type"
      return 1
      ;;
  esac

  typeset -i found=0 success=0

  # Handle variable unsetting
  if [[ $unset_type == var || $unset_type == auto ]]; then
    if (( ${+parameters[$target]} )); then
      (( found = 1 ))
      # Check if readonly (cannot be unset)
      if [[ ${(tP)target} == *readonly* ]]; then
        z::log::debug "Cannot unset readonly var: $target"
      else
        if unset -v -- "$target" 2> /dev/null; then
          (( success = 1 ))
        fi
      fi
    fi
  fi

  # Handle function unsetting
  if [[ $unset_type == func || $unset_type == auto ]]; then
    if (( ${+functions[$target]} )); then
      (( found = 1 ))
      if unset -f -- "$target" 2> /dev/null; then
        (( success = 1 ))
        # Update function-existence cache
        local cache_key="func_exists_${target//[^A-Za-z0-9_]/_}"
        if (( ${+_func_cache[$cache_key]} )); then
          unset "_func_cache[$cache_key]"
          _func_cache_order=("${(@)_func_cache_order:#$cache_key}")
          (( _func_cache_size = ${#_func_cache} ))
        fi
      fi
    fi
  fi

  # Return appropriate status
  if (( !found )); then
    z::log::debug "Target not found for unset: $target"
    return 1
  fi

  if (( success )); then
    z::log::debug "Unset: $target"
    return 0
  fi

  z::log::warn "Failed to unset $target"
  return 1
}

###
# Unset a variable
# Type-safe variable removal with readonly protection
#
# Usage:
#   z::var::unset MY_VAR
#   z::var::unset TEMP_CONFIG
#
# @param 1: string - Variable name
# @return 0 on success, 1 if not found or readonly
###
z::var::unset()
{
  emulate -L zsh
  setopt typeset_silent no_unset
  local target="${1-}"
  if [[ -z $target ]]; then
    z::log::error "Empty target for var unset"
    return 1
  fi
  z::state::_unset_impl "$target" var
}

###
# Unset a function
# Removes function and updates function cache
#
# Usage:
#   z::func::unset my_function
#   z::func::unset temporary_helper
#
# @param 1: string - Function name
# @return 0 on success, 1 if not found
###
z::func::unset()
{
  emulate -L zsh
  setopt typeset_silent no_unset
  local target="${1-}"
  if [[ -z $target ]]; then
    z::log::error "Empty target for func unset"
    return 1
  fi
  z::state::_unset_impl "$target" func
}

###
# Unset variable or function (backward-compatible API)
# Automatically detects whether target is variable or function
#
# Usage:
#   z::state::unset MY_VAR
#   z::state::unset my_function
#   z::state::unset MY_VAR var      # Explicit type
#   z::state::unset my_function func
#
# @param 1: string - Target name (variable or function)
# @param 2: string - Type: "auto" (default), "var", or "func"
# @return 0 on success, 1 if not found or unset failed
###
z::state::unset()
{
  emulate -L zsh
  setopt typeset_silent no_unset
  local target="${1-}"
  local unset_type="${2:-auto}"
  z::state::_unset_impl "$target" "$unset_type"
}

################################################################################
# SECTION 10: USER INTERFACE (UI)
################################################################################

###
# Get terminal width with caching
# Tries multiple methods: $COLUMNS, tput, fallback to 80
# Caches result until COLUMNS changes for performance
# Validates bounds (10-1000) to avoid display issues
#
# Usage:
#   width=$(z::ui::term::width)
#   if (( width > 120 )); then
#     # Wide terminal layout
#   fi
#
# @stdout Terminal width in columns
# @return 0 always
###
z::ui::term::width()
{
  emulate -L zsh
  typeset -i cols_val width

  # Check if COLUMNS is set and valid
  local columns_current="${COLUMNS:-}"

  # Use cached width if COLUMNS hasn't changed and cache is valid
  if (( _cached_term_width > 0 )); then
    # Cache invalidation: check if COLUMNS changed (including becoming empty)
    if [[ $columns_current == $_zcore_prev_columns ]]; then
      print -r -- "$_cached_term_width"
      return 0
    fi
  fi

  # Try $COLUMNS first (fastest) - use zsh pattern matching for consistency
  if [[ -n $columns_current && $columns_current == <-> ]]; then
    (( cols_val = 10#${columns_current} ))
    if (( cols_val >= 10 && cols_val <= 1000 )); then
      (( width = cols_val ))
    else
      (( width = 80 ))
    fi
  # Fallback to tput
  elif (( $+commands[tput] )); then
    local tput_width
    if tput_width=$(tput cols 2> /dev/null) && \
      [[ $tput_width == <-> ]]; then
      (( cols_val = 10#${tput_width} ))
      if (( cols_val >= 10 && cols_val <= 1000 )); then
        (( width = cols_val ))
      else
        (( width = 80 ))
      fi
    else
      (( width = 80 ))
    fi
  # Final fallback
  else
    (( width = 80 ))
  fi

  # Update cache (store actual COLUMNS value for comparison)
  (( _cached_term_width = width ))
  _zcore_prev_columns="$columns_current"
  print -r -- "$width"
  return 0
}

###
# Determine if progress should be shown for current/total
# Throttles updates to reduce flicker and improve performance
# Shows: first item, last item, every Nth item, items near end
#
# @param 1: integer - Current item number
# @param 2: integer - Total items
# @private
# @return 0 if should show, 1 if should skip
###
z::ui::progress::_should_show()
{
  emulate -L zsh
  typeset -i current total interval
  (( current = 10#${1} ))
  (( total = 10#${2} ))
  (( interval = 10#${_zcore_config[progress_update_interval]:-20} ))

  # Always show first and last
  if (( current == 1 || current == total )); then
    return 0
  fi

  # For very small totals (≤5), show all items
  if (( total <= 5 )); then
    return 0
  fi

  # For small totals (≤10), show every 2nd item
  if (( total <= 10 )); then
    (( current % 2 == 0 )) && return 0
    return 1
  fi

  # For medium totals (≤50), show every 5th
  if (( total <= 50 )); then
    (( current % 5 == 0 )) && return 0
    return 1
  fi

  # For large totals, show at intervals or near end
  if (( current % interval == 0 )) || (( total - current < interval )); then
    return 0
  fi

  return 1
}

###
# Format number with thousands separator (comma)
# Handles positive and negative integers
# Single-pass algorithm
#
# Usage:
#   formatted=$(z::util::comma 1234567)    # "1,234,567"
#   formatted=$(z::util::comma -9876543)   # "-9,876,543"
#
# @param 1: string/integer - Number to format
# @stdout Formatted number with commas
# @return 0 always
###
z::util::comma()
{
  emulate -L zsh
  setopt localoptions typeset_silent
  local n="${1:-0}"

  # Normalize sign and digits
  local sign=''
  if [[ $n == -* ]]; then
    sign='-'
    n="${n#-}"
  fi

  # Non-digit input: return as-is
  if [[ $n != <-> ]]; then
    print -r -- "${sign}${n}"
    return 0
  fi

  typeset -i len
  (( len = ${#n} ))

  # Only add commas if length > 3
  if (( len <= 3 )); then
    print -r -- "${sign}${n}"
    return 0
  fi

  # Single-pass formatting
  local result="" chunk
  typeset -i pos remainder

  # Calculate leading digits (not divisible by 3)
  (( remainder = len % 3 ))

  # Extract leading chunk if exists
  if (( remainder > 0 )); then
    result="${n[1,remainder]}"
    (( pos = remainder + 1 ))
  else
    (( pos = 1 ))
  fi

  # Process remaining digits in groups of 3
  while (( pos <= len )); do
    chunk="${n[pos,pos+2]}"
    if [[ -n $result ]]; then
      result="${result},${chunk}"
    else
      result="$chunk"
    fi
    (( pos += 3 ))
  done

  print -r -- "${sign}${result}"
  return 0
}

###
# Display progress bar for long-running operations
# Features: percentage, visual bar, item counts, adaptive width
# Automatically throttles updates to reduce terminal flicker
# Respects verbosity settings and terminal capabilities
#
# Usage:
#   for i in {1..$total}; do
#     z::ui::progress::show $i $total "files"
#     process_item $i
#   done
#
# @param 1: integer - Current item number (1-indexed)
# @param 2: integer - Total items
# @param 3: string - Label (optional, default: "items")
# @return 0 on success, 1 on validation failure
###
z::ui::progress::show()
{
  emulate -L zsh
  setopt typeset_silent

  # Validate inputs are integers
  if [[ ${1-} != <-> || ${2-} != <-> ]]; then
    z::log::debug "Invalid progress params: must be integers."
    return 1
  fi
  typeset -i current total
  (( current = 10#${1} ))
  (( total = 10#${2} ))

  local label="${3:-items}"

  # Validate range
  if (( total <= 0 || current < 0 || current > total )); then
    z::log::debug "Invalid progress range: $current/$total."
    return 1
  fi

  # Skip if verbosity too low, not interactive, or disabled
  if (( _zcore_verbose_level < _zcore_config[log_info] )) || \
    [[ ! -t 2 ]] || \
    [[ ${_zcore_config[show_progress]:-true} == false ]]; then
    return 0
  fi

  # Throttle updates for performance
  z::ui::progress::_should_show "$current" "$total" || return 0

  typeset -i term_width percent_int filled bar_width empty_len
  (( term_width = $(z::ui::term::width) ))

  # Calculate percentage safely (multiply first to avoid precision loss)
    (( percent_int = (current * 100) / total ))

  # Adaptive bar width based on terminal size
  if (( term_width > 40 )); then
    (( bar_width = 20 ))
  else
    (( bar_width = 10 ))
  fi

  # Calculate filled portion with bounds checking
  (( filled = (current * bar_width) / total ))
  (( filled < 0 )) && (( filled = 0 ))
  (( filled > bar_width )) && (( filled = bar_width ))
  (( empty_len = bar_width - filled ))

  # Build progress bar with block characters
  local bar_fill bar_empty
  if (( filled > 0 )); then
    bar_fill="${(l:filled::█:)}"
  else
    bar_fill=""
  fi
  if (( empty_len > 0 )); then
    bar_empty="${(l:empty_len::░:)}"
  else
    bar_empty=""
  fi
  local progress_bar="${bar_fill}${bar_empty}"

  # Format numbers with thousand separators
  local current_fmt total_fmt
  current_fmt=$(z::util::comma "$current")
  total_fmt=$(z::util::comma "$total")

  # Build and print output in single operation
  if (( term_width > 70 )); then
    # Wide terminal: full format with label
    printf '\r[%s] %3d%% | %s: %s / %s ' "$progress_bar" "$percent_int" "$label" "$current_fmt" "$total_fmt" >&2
  else
    # Narrow terminal: compact format
    printf '\r[%s] %3d%% (%s/%s)' "$progress_bar" "$percent_int" "$current_fmt" "$total_fmt" >&2
  fi

  # Print newline on completion
  (( current == total )) && printf '\n' >&2
  return 0
}

################################################################################
# SECTION 11: INITIALIZATION
################################################################################

# Install interrupt handlers in interactive session
if [[ -o interactive ]] || [[ ${_zcore_config[install_traps]:-} == true ]]; then
  trap 'z::runtime::handle_interrupt' INT TERM
fi

# Log successful initialization
z::log::debug "Zsh utility library initialized (performance_mode=${_zcore_config[performance_mode]})"
