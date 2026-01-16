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
# Prevents this module from being initialized multiple times in the same session.
# Returns 0 when already loaded (whether sourced or executed).
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

# Logging level constants (readonly for safety)
typeset -gri ZCORE_LOG_LEVEL_ERROR=0    # Critical errors only
typeset -gri ZCORE_LOG_LEVEL_WARN=1     # Warnings and errors
typeset -gri ZCORE_LOG_LEVEL_INFO=2     # Informational messages (default)
typeset -gri ZCORE_LOG_LEVEL_DEBUG=3    # Verbose debugging output

# Logging levels (numeric) - reference constants
_zcore_config[log_error]=$ZCORE_LOG_LEVEL_ERROR
_zcore_config[log_warn]=$ZCORE_LOG_LEVEL_WARN
_zcore_config[log_info]=$ZCORE_LOG_LEVEL_INFO
_zcore_config[log_debug]=$ZCORE_LOG_LEVEL_DEBUG

# Exit codes
_zcore_config[exit_general_error]=1    # Generic failure
_zcore_config[exit_interrupted]=130    # SIGINT (Ctrl+C)
# Standard return codes
typeset -gri ZCORE_SUCCESS=0
typeset -gri ZCORE_ERROR_NOT_FOUND=1
typeset -gri ZCORE_ERROR_INVALID_INPUT=2
typeset -gri ZCORE_ERROR_PERMISSION=3
typeset -gri ZCORE_ERROR_TIMEOUT=124
typeset -gri ZCORE_ERROR_INTERRUPTED=130

_zcore_config[alias.force_overwrite]=0
_zcore_config[alias.interactive_mode]=0
_zcore_config[alias.warn_shadow]=0
_zcore_config[alias.auto_persist]=0
# Performance tuning
_zcore_config[progress_update_interval]=10  # Updates per progress bar cycle
_zcore_config[timeout_default]=30           # Default command timeout (seconds)
_zcore_config[log_max_depth]=50             # Max recursion depth for logging
_zcore_config[cache_max_size]=100           # Max cached function/command entries
_zcore_config[cache_purge_threshold]=10     # Min excess before purging cache
_zcore_config[symlink_max_iterations]=40    # Max symlink resolution iterations

_zcore_config[event_max_history]=100
_zcore_config[event_handler_timeout]=5
_zcore_config[event_max_handlers_per_event]=50
_zcore_config[event_enable_history]=true
_zcore_config[event_enable_stats]=true
_zcore_config[event_enable_wildcards]=true


# Feature flags (can be overridden via environment)
_zcore_config[performance_mode]=${ZCORE_CONFIG_PERFORMANCE_MODE:-false}
_zcore_config[show_progress]=${ZCORE_CONFIG_SHOW_PROGRESS:-true}

# Optional: allow to extend/override init whitelist via regex (empty by default)
_zcore_config[init_whitelist_regex]=''

# Optional: force trap installation even in non-interactive mode
_zcore_config[install_traps]=${ZCORE_CONFIG_INSTALL_TRAPS:-false}

# Configuration locking flag (prevents modification of critical values)
typeset -gi _zcore_config_locked=0


################################################################################
# GLOBAL VERBOSITY LEVEL
################################################################################

###
# Current logging verbosity level
# 0 = error only, 1 = warn, 2 = info (default), 3 = debug
###
typeset -gi _zcore_verbose_level=${_zcore_config[log_info]}

###
# Get human-readable name for log level
# Internal helper for consistent level naming across functions
#
# @param 1: integer - Log level (0-3)
# @stdout Log level name (error|warn|info|debug|unknown)
# @private
# @return 0 on success, 1 if invalid level
###
__z::log::level_name() {
  emulate -L zsh
  setopt no_unset
  typeset -i level
  (( level = 10#${1:-9999} ))

  case $level in
    (${_zcore_config[log_error]}) print -r -- "error" ;;
    (${_zcore_config[log_warn]})  print -r -- "warn" ;;
    (${_zcore_config[log_info]})  print -r -- "info" ;;
    (${_zcore_config[log_debug]}) print -r -- "debug" ;;
    (*)
      print -r -- "unknown"
      return 1
      ;;
  esac
  return 0
}
###
# Parse log level input (numeric or name) into a validated integer
#
# @param 1: string - Level (0-3 or error|warn|info|debug)
# @stdout Integer level on success
# @return 0 on success, 1 on invalid input
###
__z::log::parse_level() {
  emulate -L zsh
  setopt no_unset
  local input="${1-}"
  typeset -i level

  if [[ -z $input ]]; then
    return 1
  fi

  # Validate numeric input before arithmetic
  if [[ $input == <-> ]]; then
    (( level = 10#${input} ))
  else
    case ${input:l} in
      error) (( level = _zcore_config[log_error] )) ;;
      warn)  (( level = _zcore_config[log_warn]  )) ;;
      info)  (( level = _zcore_config[log_info]  )) ;;
      debug) (( level = _zcore_config[log_debug] )) ;;
      *) return 1 ;;
    esac
  fi

  if (( level < _zcore_config[log_error] || level > _zcore_config[log_debug] )); then
    return 1
  fi

  print -r -- "$level"
  return 0
}

###
# Bootstrap-safe logging function for early initialization
# Uses direct stderr output without depending on logging subsystem
#
# @param 1: string - Level prefix (WARN|ERROR|INFO|DEBUG)
# @param ...: string - Message components
# @private
# @return 0 always
###
__z::log::bootstrap() {
  emulate -L zsh
  setopt no_unset
  local level_prefix="${1:-INFO}"
  shift

  # Always log to stderr; an env flag can disable if desired
  if [[ ${ZCORE_BOOTSTRAP_QUIET:-false} == true ]]; then
    return 0
  fi

  print -r -- "[bootstrap:${level_prefix}] $*" >&2
  return 0
}

###
# Enable debug logging mode
# Sets verbosity to maximum level for troubleshooting
# Note: Respects performance mode restrictions
#
# Usage:
#   z::log::enable_debug
#
# @return 0 on success, 1 if restricted by performance mode
###
z::log::enable_debug() {
  emulate -L zsh
  setopt no_unset
  if (( _zcore_config_locked )); then
    z::log::warn "z::log::enable_debug: configuration is locked; ignoring request"
    return 1
  fi
  # Check if performance mode prevents debug level
  if [[ ${_zcore_config[performance_mode]} == true ]]; then
    z::log::warn "Debug mode not available in performance mode (capped at info level)"
    (( _zcore_verbose_level = _zcore_config[log_info] ))
    return 1
  fi

  (( _zcore_verbose_level = _zcore_config[log_debug] ))
  z::log::info "Debug mode enabled"
  return 0
}

###
# Stack trace for debugging
# Prints the current function call stack
#
# Usage:
#   z::debug::trace
#
# @return 0 always
###
z::debug::trace() {
  emulate -L zsh
  setopt no_unset
  local -i i
  print "Stack trace:" >&2
  for (( i = 1; i < ${#funcstack[@]}; i++ )); do
    print "  $i: ${funcstack[i]} (${funcfiletrace[i]:-unknown})" >&2
  done
  return 0
}

###
# Variable dump for debugging
# Prints all configuration values
#
# Usage:
#   z::debug::dump_config
#
# @return 0 always
###
z::debug::dump_config() {
  emulate -L zsh
  setopt no_unset
  local key value
  print "Configuration:" >&2
  for key value in "${(@kv)_zcore_config}"; do
    print "  $key = $value" >&2
  done
  return 0
}

###
# Performance profiling start
# Records start time for performance measurement
#
# Usage:
#   z::debug::profile_start
#
# @return 0 always
###
z::debug::profile_start() {
  emulate -L zsh
  setopt no_unset
  typeset -g _zcore_profile_start=${EPOCHREALTIME:-0}
  return 0
}

###
# Performance profiling end
# Calculates and logs elapsed time since profile_start
#
# Usage:
#   z::debug::profile_end "operation_name"
#
# @param 1: string - Label for the operation (optional, defaults to "operation")
# @return 0 on success, 1 if profiling wasn't started
###
z::debug::profile_end() {
  emulate -L zsh
  setopt no_unset
  local label="${1:-operation}"

  # Guard against uninitialized profiling
  if [[ -z ${_zcore_profile_start:-} ]]; then
    z::log::warn "z::debug::profile_end: profiling not started"
    return 1
  fi

  local duration
  (( duration = EPOCHREALTIME - _zcore_profile_start ))
  z::log::debug "Profile [$label]: ${duration}s"
  return 0
}

###
# Set verbosity level programmatically
# Validates input and respects performance mode restrictions
#
# Usage:
#   z::log::set_level 3           # Set to debug
#   z::log::set_level debug       # Set by name
#   z::log::set_level $ZCORE_LOG_LEVEL_ERROR  # Set by constant
#
# @param 1: integer|string - Log level (0-3 or error|warn|info|debug)
# @return 0 on success, 1 if invalid level
###
z::log::set_level() {
  emulate -L zsh
  setopt no_unset
  local input="${1-}"

  if [[ -z $input ]]; then
    z::log::error "z::log::set_level: No level provided"
    return 1
  fi

  local parsed
  if ! parsed=$(__z::log::parse_level "$input" 2>/dev/null); then
    z::log::error "z::log::set_level: Invalid level: '$input' (use: 0-3 or error|warn|info|debug)"
    return 1
  fi
  typeset -i new_level
  (( new_level = 10#${parsed} ))

  # performance_mode restriction
  if [[ ${_zcore_config[performance_mode]} == true ]] && \
     (( new_level > _zcore_config[log_info] )); then
    z::log::warn "Debug level not available in performance mode, capping at info"
    (( new_level = _zcore_config[log_info] ))
  fi

  local old_level=$_zcore_verbose_level
  (( _zcore_verbose_level = new_level ))

  local old_name new_name
  old_name=$(__z::log::level_name "$old_level")
  new_name=$(__z::log::level_name "$new_level")

  z::log::info "Verbosity changed: $old_level ($old_name) → $new_level ($new_name)"
  return 0
}


###
# Get current verbosity level
# Displays the current logging level with human-readable name
#
# Usage:
#   z::log::get_level
#   current_level=$(z::log::get_level --numeric)  # Output only number
#
# @param 1: string - "--numeric" flag to output only number (optional)
# @stdout Current verbosity level with name, or just number if --numeric
# @return 0 always
###
z::log::get_level() {
  emulate -L zsh
  setopt no_unset

  # Check for --numeric flag
  if [[ ${1:-} == --numeric ]]; then
    print -r -- "$_zcore_verbose_level"
    return 0
  fi

  local level_name
  level_name=$(__z::log::level_name "$_zcore_verbose_level")
  print -r -- "Current verbosity level: $_zcore_verbose_level ($level_name)"
  return 0
}
###
# Initialize verbosity level from environment variable
# Validates input, respects performance mode restrictions, and logs errors
# Uses bootstrap logging to avoid circular dependencies during initialization
#
# This function is called during module load, before the full logging
# subsystem is guaranteed to be ready. It uses bootstrap logging for
# early feedback.
#
# @private
# @return 0 on success, 1 if invalid level provided
###
__z::config::init_verbosity() {
  emulate -L zsh
  setopt no_unset

  if [[ -z ${zcore_config_verbose:-} ]]; then
    return 0
  fi

  local parsed
  if ! parsed=$(__z::log::parse_level "$zcore_config_verbose" 2>/dev/null); then
    __z::log::bootstrap WARN \
      "Invalid zcore_config_verbose='$zcore_config_verbose' (must be integer 0-3 or error|warn|info|debug). Using default."
    return 1
  fi
  typeset -i requested_level
  (( requested_level = 10#${parsed} ))

  # Determine max allowed based on performance_mode
  typeset -i max_allowed_level
  if [[ ${_zcore_config[performance_mode]} == true ]]; then
    (( max_allowed_level = _zcore_config[log_info] ))
  else
    (( max_allowed_level = _zcore_config[log_debug] ))
  fi

  if (( requested_level <= max_allowed_level )); then
    (( _zcore_verbose_level = requested_level ))
    local level_name
    level_name=$(__z::log::level_name "$requested_level")
    __z::log::bootstrap INFO \
      "Verbosity level set to $requested_level ($level_name) via zcore_config_verbose"
  else
    (( _zcore_verbose_level = max_allowed_level ))
    local cap_name
    cap_name=$(__z::log::level_name "$max_allowed_level")
    __z::log::bootstrap WARN \
      "Verbosity level $requested_level not allowed in performance mode, capped at $max_allowed_level ($cap_name)"
  fi

  return 0
}


# Initialize verbosity level during module load
__z::config::init_verbosity

###
# Validate entire configuration after initialization
# Checks all configuration values for consistency
#
# @return 0 if valid, 1 if issues found
###
z::config::validate() {
  emulate -L zsh
  setopt no_unset
  typeset -i errors=0

  # Validate numeric ranges
  typeset -i val

  # Cache max size
  (( val = _zcore_config[cache_max_size] ))
  if (( val < 10 || val > 10000 )); then
    z::log::error "Invalid cache_max_size: $val (must be 10-10000)"
    (( errors += 1 ))
  fi

  # Timeout default
  (( val = _zcore_config[timeout_default] ))
  if (( val < 1 || val > 86400 )); then
    z::log::error "Invalid timeout_default: $val (must be 1-86400)"
    (( errors += 1 ))
  fi

  # Log max depth
  (( val = _zcore_config[log_max_depth] ))
  if (( val < 10 || val > 1000 )); then
    z::log::error "Invalid log_max_depth: $val (must be 10-1000)"
    (( errors += 1 ))
  fi

  # Symlink max iterations
  (( val = _zcore_config[symlink_max_iterations] ))
  if (( val < 10 || val > 1000 )); then
    z::log::error "Invalid symlink_max_iterations: $val (must be 10-1000)"
    (( errors += 1 ))
  fi

  # Cache purge threshold
  (( val = _zcore_config[cache_purge_threshold] ))
  if (( val < 1 || val > 1000 )); then
    z::log::error "Invalid cache_purge_threshold: $val (must be 1-1000)"
    (( errors += 1 ))
  fi

  # Progress update interval
  (( val = _zcore_config[progress_update_interval] ))
  if (( val < 1 || val > 100 )); then
    z::log::error "Invalid progress_update_interval: $val (must be 1-100)"
    (( errors += 1 ))
  fi

  # Validate boolean flags
  local flag
  for flag in performance_mode show_progress install_traps; do
    if [[ ${_zcore_config[$flag]:-} != true && ${_zcore_config[$flag]:-} != false ]]; then
      z::log::error "Invalid boolean config $flag: ${_zcore_config[$flag]:-} (must be true/false)"
      (( errors += 1 ))
    fi
  done

  if (( errors > 0 )); then
    z::log::error "Configuration validation failed with $errors error(s)"
    return 1
  fi

  z::log::debug "Configuration validation passed"
  return 0
}

###
# Get configuration value with validation
# Retrieves a configuration value by key
#
# Usage:
#   value=$(z::config::get cache_max_size)
#
# @param 1: string - Configuration key
# @stdout Configuration value
# @return 0 on success, 1 if key doesn't exist
###
z::config::get() {
  emulate -L zsh
  setopt no_unset
  local key="${1-}"

  if [[ -z $key ]]; then
    z::log::error "z::config::get: No key provided"
    return 1
  fi

  if (( ! ${+_zcore_config[$key]} )); then
    z::log::error "Unknown config key: $key"
    return 1
  fi
  print -r -- "${_zcore_config[$key]}"
  return 0
}

###
# Type-safe boolean setter
# Sets a boolean configuration value with validation
#
# Usage:
#   z::config::set_bool performance_mode true
#
# @param 1: string - Configuration key
# @param 2: string - Boolean value (true|false)
# @return 0 on success, 1 on validation failure
###
z::config::set_bool() {
  emulate -L zsh
  setopt no_unset
  local key="${1-}" value="${2-}"

  if [[ -z $key ]]; then
    z::log::error "z::config::set_bool: No key provided"
    return 1
  fi

  # Validate key exists
  if (( ! ${+_zcore_config[$key]} )); then
    z::log::error "z::config::set_bool: Unknown config key: $key"
    return 1
  fi

  if [[ $value != true && $value != false ]]; then
    z::log::error "Boolean value required: $value"
    return 1
  fi
  z::config::set "$key" "$value"
}

###
# Type-safe integer setter
# Sets an integer configuration value with validation
#
# Usage:
#   z::config::set_int cache_max_size 200
#
# @param 1: string - Configuration key
# @param 2: string - Integer value
# @return 0 on success, 1 on validation failure
###
z::config::set_int() {
  emulate -L zsh
  setopt no_unset
  local key="${1-}" value="${2-}"

  if [[ -z $key ]]; then
    z::log::error "z::config::set_int: No key provided"
    return 1
  fi

  # Validate key exists
  if (( ! ${+_zcore_config[$key]} )); then
    z::log::error "z::config::set_int: Unknown config key: $key"
    return 1
  fi

  if [[ $value != <-> ]]; then
    z::log::error "Integer value required: $value"
    return 1
  fi
  z::config::set "$key" "$value"
}

###
# Export current configuration to a file
# Useful for debugging and configuration management
#
# Usage:
#   z::config::export /tmp/zcore-config.txt
#
# @param 1: string - Output file path
# @return 0 on success, 1 on failure
###
z::config::export() {
  emulate -L zsh
  setopt no_unset
  local output_file="${1-}"

  if [[ -z $output_file ]]; then
    z::log::error "z::config::export: No output file specified"
    return 1
  fi

  {
    print "# Zcore Configuration Export"
    print "# Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    print "# Verbosity Level: $_zcore_verbose_level"
    print ""

    local key value
    for key value in "${(@kv)_zcore_config}"; do
      print "$key=$value"
    done
  } > "$output_file"

  z::log::info "Configuration exported to: $output_file"
  return 0
}
###
# Lock critical configuration values
# Prevents modification of core configuration after initialization
# Should be called after zcore is fully initialized
#
# Usage:
#   z::config::lock_critical
#
# @return 0 always
###
z::config::lock_critical() {
  emulate -L zsh
  setopt no_unset
  (( _zcore_config_locked = 1 ))
  z::log::debug "Critical configuration locked"
  return 0
}
###
# Toggle progress bar display
# Switches progress bar visibility on/off
#
# Usage:
#   z::ui::toggle_progress
#
# @return 0 always
###
z::ui::toggle_progress()
{
  emulate -L zsh
  setopt no_unset
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
  setopt no_unset
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
__z::log::update_ts()
{
  emulate -L zsh
  setopt no_unset
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
__z::log::engine()
{
  emulate -L zsh
  setopt localoptions no_unset warn_create_global typeset_silent
  # Test mode: suppress all logging
  if [[ -n ${ZCORE_TEST_MODE-} ]]; then
    return 0
  fi
  # Infinite recursion prevention
  typeset -i max_depth
  (( max_depth = _zcore_config[log_max_depth] ))
  (( max_depth <= 0 )) && (( max_depth = 50 ))  # sane fallback

  if (( _log_depth > max_depth )); then
    print -r -- "FATAL: Recursion in __z::log::engine" >&2
    return 1
  fi

  # Use always block to ensure depth cleanup
  {
  (( _log_depth += 1 ))


  # Log level validation with base-10 enforcement
  typeset -i level
  if [[ -z ${1-} || $1 != <-> ]]; then
    print -r -- "[error] Invalid log level: '${1-}'" >&2
    return 1
  fi
  (( level = 10#${1} ))
  shift

  # Early return for filtered messages
  if (( level > _zcore_verbose_level )); then
    return 0
  fi

  __z::log::update_ts

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
  } always {
  (( _log_depth -= 1 ))
  }

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
  setopt no_unset
  __z::log::engine ${_zcore_config[log_error]} "$@"
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
  setopt no_unset
  __z::log::engine ${_zcore_config[log_warn]} "$@"
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
  setopt no_unset
  __z::log::engine ${_zcore_config[log_info]} "$@"
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
  setopt no_unset
  __z::log::engine ${_zcore_config[log_debug]} "$@"
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
  setopt no_unset

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
  setopt no_unset
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
  setopt no_unset
  local key="${1-}" value="${2-}"

  # Honor configuration lock for critical values
  if (( _zcore_config_locked )); then
    # Adjust this case list if some keys must remain mutable
    case $key in
      log_* | exit_* | *interval | *timeout | *depth | *size | *threshold | *iterations | \
      performance_mode | show_progress | install_traps)
        z::log::warn "z::config::set: Configuration is locked; cannot modify '$key'"
        return 1
        ;;
    esac
  fi

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
        cache_purge_threshold)
          if (( val < 1 || val > 1000 )); then
            z::log::error "z::config::set: cache_purge_threshold must be between 1 and 1000"
            return 1
          fi
          ;;
        progress_update_interval)
          if (( val < 1 || val > 100 )); then
            z::log::error "z::config::set: progress_update_interval must be between 1 and 100"
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
  setopt no_unset
  local message="${1-}"
  typeset -i exit_code
  (( exit_code = 10#${2:-${_zcore_config[exit_general_error]}} ))

  z::ui::progress::clear
  z::log::error "FATAL (exit $exit_code): $message"


  # Return in sourced context, exit otherwise
  if [[ -n $ZSH_EVAL_CONTEXT && $ZSH_EVAL_CONTEXT == *:file:* ]]; then
    return $exit_code
  else
    exit $exit_code
  fi
}
###
# Get option value from parsed zparseopts with fallback
#
# @param 1: string - Name of associative array containing parsed opts
# @param 2: string - Short option name WITHOUT dash (e.g., 't') - can be empty
# @param 3: string - Long option name WITHOUT dashes (e.g., 'type') - can be empty
# @param 4: string - Default value if not found (optional)
# @output: string - Resolved option value
# @return 0 always
#
# @note: Expects opts array keys to include dashes (e.g., '-t', '--type')
#        as produced by zparseopts or manual assignment
#
# @example
#   local -A opts
#   zparseopts -D -E -A opts -- t: -type:
#   local type_value=$(z::opt::get opts 't' 'type' 'default')
###
z::opt::get()
{
  emulate -L zsh
  setopt warn_create_global no_unset extended_glob

  local opts_var="$1" short_opt="$2" long_opt="$3" default_value="${4:-}"
  local resolved_value="$default_value"

  # Validate opts_var exists
  if [[ -z $opts_var ]]; then
    z::log::error "z::opt::get: opts_var parameter required"
    print -r -- "$default_value"
    return 0
  fi

  # Check if the variable exists and is an associative array
  if (( ! ${(P)+opts_var} )) || [[ ${(Pt)opts_var} != *association* ]]; then
    print -r -- "$default_value"
    return 0
  fi

  # Use direct parameter expansion with (P) flag instead of copying entire array
  # Check short option first (higher precedence)
  if [[ -n $short_opt ]]; then
    local key="-${short_opt}"
    # Use nested parameter expansion: ${(P)var} expands to the value of the variable named by $var
    # Then we check if that associative array has the key
    if (( ${(P)+${opts_var}[$key]} )); then
      resolved_value="${(P)${opts_var}[$key]}"
    fi
  fi

  # Then check long option (only if short didn't match)
  if [[ $resolved_value == $default_value && -n $long_opt ]]; then
    local key="--${long_opt}"
    if (( ${(P)+${opts_var}[$key]} )); then
      resolved_value="${(P)${opts_var}[$key]}"
    fi
  fi

  print -r -- "$resolved_value"
  return 0
}

###
# Check if option flag is present in parsed zparseopts
#
# @param 1: string - Name of associative array containing parsed opts
# @param 2: string - Short option name WITHOUT dash (e.g., 'f') - can be empty
# @param 3: string - Long option name WITHOUT dashes (e.g., 'force') - can be empty
# @return 0 if present, 1 if not
#
# @note: Expects opts array keys to include dashes (e.g., '-f', '--force')
#        as produced by zparseopts or manual assignment
#
# @example
#   local -A opts
#   zparseopts -D -E -A opts -- f -force
#   if z::opt::has opts 'f' 'force'; then
#     echo "Force flag is set"
#   fi
###
z::opt::has()
{
  emulate -L zsh
  setopt warn_create_global no_unset extended_glob

  local opts_var="$1" short_opt="$2" long_opt="$3"

  # Validate opts_var exists
  if [[ -z $opts_var ]]; then
    z::log::error "z::opt::has: opts_var parameter required"
    return 1
  fi

  # Check if the variable exists and is an associative array
  if (( ! ${(P)+opts_var} )) || [[ ${(Pt)opts_var} != *association* ]]; then
    return 1
  fi

  # Create local reference to the associative array
  local -A opts_ref
  opts_ref=("${(@Pkv)opts_var}")

  # Check if either short or long option exists
  if [[ -n $short_opt ]] && (( ${+opts_ref[-${short_opt}]} )); then
    return 0
  fi

  if [[ -n $long_opt ]] && (( ${+opts_ref[--${long_opt}]} )); then
    return 0
  fi

  return 1
}

###
# Parse --force/-f flag with optional config fallback
#
# @param 1: string - Name of associative array containing parsed opts
# @param 2: string - Config key for fallback (optional, e.g., 'alias.force_overwrite')
# @param 3: int - Default value if config not set (default: 0)
# @output: int - Resolved force value (0 or 1)
# @return 0 always
#
# @example
#   local -A opts
#   zparseopts -D -E -A opts -- f -force
#   typeset -i force
#   (( force = $(z::opt::parse::force opts 'alias.force_overwrite' 0) ))
###
z::opt::parse::force()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local opts_var="$1" config_key="${2:-}"
  typeset -i default_value force_value
  (( default_value = ${3:-0} ))
  (( force_value = default_value ))

  # Check if flag is present
  if z::opt::has "$opts_var" 'f' 'force'; then
    (( force_value = 1 ))
  # Check config fallback if provided and flag not set
  elif [[ -n $config_key ]]; then
    local config_result
    config_result=$(z::config::get "$config_key" "$default_value")
    (( force_value = config_result ))
  fi

  print -r -- "$force_value"
  return 0
}

###
# Parse --dry-run flag with optional config fallback
#
# @param 1: string - Name of associative array containing parsed opts
# @param 2: string - Config key for fallback (optional)
# @param 3: int - Default value if config not set (default: 0)
# @output: int - Resolved dry-run value (0 or 1)
# @return 0 always
#
# @example
#   local -A opts
#   zparseopts -D -E -A opts -- n -dry-run
#   typeset -i dryrun
#   (( dryrun = $(z::opt::parse::dryrun opts) ))
###
z::opt::parse::dryrun()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local opts_var="$1" config_key="${2:-}"
  typeset -i default_value dryrun_value
  (( default_value = ${3:-0} ))
  (( dryrun_value = default_value ))

  # Check if flag is present
  if z::opt::has "$opts_var" 'n' 'dry-run'; then
    (( dryrun_value = 1 ))
  # Check config fallback if provided
  elif [[ -n $config_key ]]; then
    local config_result
    config_result=$(z::config::get "$config_key" "$default_value")
    (( dryrun_value = config_result ))
  fi

  print -r -- "$dryrun_value"
  return 0
}

###
# Parse --verbose/-v flag with optional config fallback
#
# @param 1: string - Name of associative array containing parsed opts
# @param 2: string - Config key for fallback (optional)
# @param 3: int - Default value if config not set (default: 0)
# @output: int - Resolved verbose value (0 or 1)
# @return 0 always
#
# @example
#   local -A opts
#   zparseopts -D -E -A opts -- v -verbose
#   typeset -i verbose
#   (( verbose = $(z::opt::parse::verbose opts) ))
###
z::opt::parse::verbose()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local opts_var="$1" config_key="${2:-}"
  typeset -i default_value verbose_value
  (( default_value = ${3:-0} ))
  (( verbose_value = default_value ))

  # Check if flag is present
  if z::opt::has "$opts_var" 'v' 'verbose'; then
    (( verbose_value = 1 ))
  # Check config fallback if provided
  elif [[ -n $config_key ]]; then
    local config_result
    config_result=$(z::config::get "$config_key" "$default_value")
    (( verbose_value = config_result ))
  fi

  print -r -- "$verbose_value"
  return 0
}

###
# Parse --quiet/-q flag with optional config fallback
#
# @param 1: string - Name of associative array containing parsed opts
# @param 2: string - Config key for fallback (optional)
# @param 3: int - Default value if config not set (default: 0)
# @output: int - Resolved quiet value (0 or 1)
# @return 0 always
#
# @example
#   local -A opts
#   zparseopts -D -E -A opts -- q -quiet
#   typeset -i quiet
#   (( quiet = $(z::opt::parse::quiet opts) ))
###
z::opt::parse::quiet()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local opts_var="$1" config_key="${2:-}"
  typeset -i default_value quiet_value
  (( default_value = ${3:-0} ))
  (( quiet_value = default_value ))

  # Check if flag is present
  if z::opt::has "$opts_var" 'q' 'quiet'; then
    (( quiet_value = 1 ))
  # Check config fallback if provided
  elif [[ -n $config_key ]]; then
    local config_result
    config_result=$(z::config::get "$config_key" "$default_value")
    (( quiet_value = config_result ))
  fi

  print -r -- "$quiet_value"
  return 0
}

###
# Parse generic boolean flag (present=1, absent=0)
#
# @param 1: string - Name of associative array containing parsed opts
# @param 2: string - Short option name WITHOUT dash
# @param 3: string - Long option name WITHOUT dashes
# @output: int - 1 if present, 0 if absent
# @return 0 always
#
# @example
#   local -A opts
#   zparseopts -D -E -A opts -- r -recursive
#   typeset -i recursive
#   (( recursive = $(z::opt::parse::bool opts 'r' 'recursive') ))
###
z::opt::parse::bool()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  if z::opt::has "$@"; then
    print -r -- "1"
  else
    print -r -- "0"
  fi

  return 0
}
###
# Generic validation functions
# Public API for user/developer-facing validation in scripts
###

###
# Validate identifier name (alphanumeric, underscore, hyphen)
# Used for: alias names, function names, variable names, config keys, etc.
#
# @param 1: string - Name to validate
# @param 2: string - Context description (for error messages, default: "Identifier")
# @return 0 if valid, 1 if invalid
#
# @example
#   if z::validate::identifier "$alias_name" "Alias name"; then
#     # name is valid
#   fi
###
z::validate::identifier()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local name="$1" context="${2:-Identifier}"

  if [[ -z $name ]]; then
    z::log::error "${context} cannot be empty"
    return 1
  fi

  # Use zsh glob pattern: ## means "one or more"
  # Pattern must match the entire string (implicit anchoring with ==)
  if [[ $name != [[:alnum:]_-]## ]]; then
    z::log::error "Invalid ${context} '${name}': must contain only alphanumeric characters, underscore, or hyphen"
    return 1
  fi

  return 0
}

###
# Validate non-empty string
#
# @param 1: string - Value to validate
# @param 2: string - Field name (for error messages, default: "Value")
# @return 0 if valid, 1 if invalid
#
# @example
#   z::validate::nonempty "$value" "Configuration value" || return 1
###
z::validate::nonempty()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local value="$1" field_name="${2:-Value}"

  if [[ -z $value ]]; then
    z::log::error "${field_name} cannot be empty"
    return 1
  fi

  return 0
}

###
# Validate integer value
#
# @param 1: string - Value to validate
# @param 2: string - Field name (for error messages, default: "Value")
# @return 0 if valid integer, 1 if invalid
#
# @example
#   z::validate::integer "$port" "Port number" || return 1
###
z::validate::integer()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local value="$1" field_name="${2:-Value}"

  # Use zsh glob pattern with alternation for clarity
  # Match either: -[digits] OR [digits]
  # ## means "one or more", ensuring at least one digit
  if [[ $value != (-[0-9]##|[0-9]##) ]]; then
    z::log::error "${field_name} must be an integer: '${value}'"
    return 1
  fi

  return 0
}

###
# Validate integer within range
#
# @param 1: string - Value to validate
# @param 2: int - Minimum value (inclusive)
# @param 3: int - Maximum value (inclusive)
# @param 4: string - Field name (for error messages, default: "Value")
# @return 0 if valid, 1 if invalid
#
# @note: Parameters 2 and 3 must be valid integers
#
# @example
#   z::validate::integer::range "$priority" 0 100 "Priority" || return 1
###
z::validate::integer::range()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local value="$1" field_name="${4:-Value}"
  typeset -i min_val max_val int_value

  # Validate min/max are provided
  if [[ -z ${2-} || -z ${3-} ]]; then
    z::log::error "z::validate::integer::range: min and max parameters required"
    return 1
  fi

  (( min_val = ${2} ))
  (( max_val = ${3} ))

  # First validate it's an integer
  z::validate::integer "$value" "$field_name" || return 1

  (( int_value = value ))

  if (( int_value < min_val || int_value > max_val )); then
    z::log::error "${field_name} must be between ${min_val} and ${max_val}: got ${int_value}"
    return 1
  fi

  return 0
}

###
# Validate file/directory path exists
#
# @param 1: string - Path to validate
# @param 2: string - Type: 'file', 'dir', or 'any' (default: 'any')
# @param 3: string - Field name (for error messages, default: "Path")
# @return 0 if valid, 1 if invalid
#
# @example
#   z::validate::path "$config_file" 'file' "Config file" || return 1
###
z::validate::path()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local path="$1" path_type="${2:-any}" field_name="${3:-Path}"

  if [[ -z $path ]]; then
    z::log::error "${field_name} cannot be empty"
    return 1
  fi

  case $path_type in
    file)
      if [[ ! -f $path ]]; then
        z::log::error "${field_name} does not exist or is not a file: ${path}"
        return 1
      fi
      ;;
    dir)
      if [[ ! -d $path ]]; then
        z::log::error "${field_name} does not exist or is not a directory: ${path}"
        return 1
      fi
      ;;
    any)
      if [[ ! -e $path ]]; then
        z::log::error "${field_name} does not exist: ${path}"
        return 1
      fi
      ;;
    *)
      z::log::error "z::validate::path: invalid path_type '${path_type}' (must be file, dir, or any)"
      return 1
      ;;
  esac

  return 0
}

###
# Validate path is readable
#
# @param 1: string - Path to validate
# @param 2: string - Field name (for error messages, default: "Path")
# @return 0 if readable, 1 if not
#
# @example
#   z::validate::path::readable "$input_file" "Input file" || return 1
###
z::validate::path::readable()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local path="$1" field_name="${2:-Path}"

  if [[ -z $path ]]; then
    z::log::error "${field_name} cannot be empty"
    return 1
  fi

  if [[ ! -r $path ]]; then
    z::log::error "${field_name} is not readable: ${path}"
    return 1
  fi

  return 0
}

###
# Validate path is writable
#
# @param 1: string - Path to validate
# @param 2: string - Field name (for error messages, default: "Path")
# @return 0 if writable, 1 if not
#
# @example
#   z::validate::path::writable "$output_file" "Output file" || return 1
###
z::validate::path::writable()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local path="$1" field_name="${2:-Path}"

  if [[ -z $path ]]; then
    z::log::error "${field_name} cannot be empty"
    return 1
  fi

  # If path exists, check if writable
  if [[ -e $path ]]; then
    if [[ ! -w $path ]]; then
      z::log::error "${field_name} is not writable: ${path}"
      return 1
    fi
  else
    # If path doesn't exist, check if parent directory is writable
    local parent_dir="${path:h}"
    if [[ ! -w $parent_dir ]]; then
      z::log::error "Cannot write to ${field_name}: parent directory not writable: ${parent_dir}"
      return 1
    fi
  fi

  return 0
}

###
# Validate value is in allowed set (enum validation)
#
# @param 1: string - Pipe-separated allowed values (e.g., "red|green|blue")
# @param 2: string - Value to validate
# @param 3: string - Field name (for error messages, default: "Value")
# @return 0 if valid, 1 if invalid
#
# @example
#   z::validate::enum "regular|global|suffix" "$type" "Alias type" || return 1
###
z::validate::enum()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local allowed_values="$1" value="$2" field_name="${3:-Value}"
  local -a allowed_array

  if [[ -z $allowed_values ]]; then
    z::log::error "z::validate::enum: allowed_values parameter required"
    return 1
  fi

  if [[ -z $value ]]; then
    z::log::error "${field_name} cannot be empty"
    return 1
  fi

  # Split allowed values by pipe
  allowed_array=("${(@s:|:)allowed_values}")

  # Check if value is in allowed set
  # (Ie) flag: I=index, e=exact match; returns 0 if not found
  if (( ${allowed_array[(Ie)$value]} == 0 )); then
    z::log::error "Invalid ${field_name} '${value}': must be one of: ${allowed_values}"
    return 1
  fi

  return 0
}

###
# Validate boolean value (0, 1, true, false, yes, no, on, off)
#
# @param 1: string - Value to validate
# @param 2: string - Field name (for error messages, default: "Value")
# @return 0 if valid boolean, 1 if invalid
#
# @example
#   z::validate::boolean "$enabled" "Enabled flag" || return 1
###
z::validate::boolean()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local value="$1" field_name="${2:-Value}"

  # Lowercase the value for case-insensitive comparison
  case "${value:l}" in
    0|1|true|false|yes|no|on|off)
      return 0
      ;;
    *)
      z::log::error "Invalid ${field_name} '${value}': must be boolean (0, 1, true, false, yes, no, on, off)"
      return 1
      ;;
  esac
}
###
# Existence checking utilities with caching
# Unified namespace for all "does X exist?" queries
# Replaces scattered existence checks across modules
###

###
# Check if command exists (cached)
#
# @param 1: string - Command name to check
# @return 0 if command exists, 1 otherwise
#
# @example
#   if z::probe::cmd git; then
#     git status
#   fi
###
z::probe::cmd()
{
  emulate -L zsh
  setopt extended_glob warn_create_global

  local cmd="$1"

  if [[ -z $cmd ]]; then
    z::log::error "z::probe::cmd: command name required"
    return 1
  fi

  # Sanitize command name for use as cache key
  local cache_key="cmd_${cmd//[^a-zA-Z0-9_]/_}"

  # Return cached result if available
  if (( ${+_cmd_cache[$cache_key]} )); then
    return ${_cmd_cache[$cache_key]}
  fi

  # Perform actual check
  typeset -i result
  (( result = 1 ))
  (( $+commands[$cmd] )) && (( result = 0 ))

  # Update cache with LRU tracking
  __z::cache::update_entry cmd "$cache_key" $result

  # Purge cache if size exceeded
  (( _cmd_cache_size > ${_zcore_config[cache_max_size]:-1000} )) && z::cache::cmd::_purge

  return $result
}

###
# Check if function exists (cached)
#
# @param 1: string - Function name to check
# @return 0 if function exists, 1 otherwise
#
# @example
#   if z::probe::func my_function; then
#     my_function arg1 arg2
#   fi
###
z::probe::func()
{
  emulate -L zsh
  setopt extended_glob warn_create_global

  local func="$1"

  if [[ -z $func ]]; then
    z::log::error "z::probe::func: function name required"
    return 1
  fi

  # Sanitize function name for use as cache key
  local cache_key="func_${func//[^a-zA-Z0-9_]/_}"

  # Return cached result if available
  if (( ${+_func_cache[$cache_key]} )); then
    return ${_func_cache[$cache_key]}
  fi

  # Perform actual check
  typeset -i result
  (( result = 1 ))
  (( $+functions[$func] )) && (( result = 0 ))

  # Update cache with LRU tracking
  __z::cache::update_entry func "$cache_key" $result

  # Always purge; internal threshold check handles cost
  z::cache::func::_purge

  return $result
}

###
# Check if builtin exists
#
# @param 1: string - Builtin name to check
# @return 0 if builtin exists, 1 otherwise
#
# @example
#   if z::probe::builtin pushd; then
#     pushd /tmp
#   fi
###
z::probe::builtin()
{
  emulate -L zsh
  setopt extended_glob warn_create_global

  local builtin_name="$1"

  if [[ -z $builtin_name ]]; then
    z::log::error "z::probe::builtin: builtin name required"
    return 1
  fi

  (( $+builtins[$builtin_name] )) && return 0
  return 1
}

###
# Check if alias exists (with optional type filtering)
#
# @param 1: string - Alias name to check
# @flag --type, -t: Alias type (regular|global|suffix)
# @return 0 if alias exists, 1 otherwise
#
# @example
#   if z::probe::alias ll; then
#     echo "ll alias exists"
#   fi
#
#   if z::probe::alias G --type global; then
#     echo "Global alias G exists"
#   fi
###
z::probe::alias()
{
  emulate -L zsh
  setopt extended_glob warn_create_global

  local -A opts
  local name alias_type

  zparseopts -D -E -A opts -- t: -type:

  if (( $# != 1 )); then
    z::log::error "Usage: z::probe::alias NAME [--type TYPE]"
    return 1
  fi

  name="$1"
  alias_type=$(z::opt::get opts 't' 'type' 'regular')

  # Validate type
  case $alias_type in
    regular|global|suffix)
      ;;
    *)
      z::log::error "Invalid alias type '${alias_type}': must be regular, global, or suffix"
      return 1
      ;;
  esac

  # Check if alias exists in aliases array
  if (( ! ${+aliases[$name]} )); then
    return 1
  fi

  # If checking for specific type, verify it matches
  case $alias_type in
    regular)
      # Check it's not a global or suffix alias
      # Use pure zsh: check galiases and saliases if available
      if (( ${+galiases[$name]} )) || (( ${+saliases[$name]} )); then
        return 1
      fi
      return 0
      ;;
    global)
      # Check galiases if available, else fallback to alias -L
      if (( ${+galiases} )); then
        (( ${+galiases[$name]} )) && return 0
        return 1
      else
        local flags
        flags=$(alias -L "$name" 2>/dev/null)
        [[ $flags == *' -g '* ]] && return 0
        return 1
      fi
      ;;
    suffix)
      # Check saliases if available, else fallback to alias -L
      if (( ${+saliases} )); then
        (( ${+saliases[$name]} )) && return 0
        return 1
      else
        local flags
        flags=$(alias -L "$name" 2>/dev/null)
        [[ $flags == *' -s '* ]] && return 0
        return 1
      fi
      ;;
  esac

  return 1
}

###
# Check if named directory exists
#
# @param 1: string - Named directory name to check
# @return 0 if named directory exists, 1 otherwise
#
# @example
#   if z::probe::dir projects; then
#     cd ~projects
#   fi
###
z::probe::dir()
{
  emulate -L zsh
  setopt extended_glob warn_create_global

  local name="$1"

  if [[ -z $name ]]; then
    z::log::error "z::probe::dir: directory name required"
    return 1
  fi

  (( ${+nameddirs[$name]} )) && return 0
  return 1
}

###
# Check if variable exists
#
# @param 1: string - Variable name to check
# @return 0 if variable exists, 1 otherwise
#
# @example
#   if z::probe::var PATH; then
#     echo "PATH is set"
#   fi
###
z::probe::var()
{
  emulate -L zsh
  setopt extended_glob warn_create_global

  local var_name="$1"

  if [[ -z $var_name ]]; then
    z::log::error "z::probe::var: variable name required"
    return 1
  fi

  # Check if variable is set (works for scalars, arrays, associative arrays)
  (( ${(P)+var_name} )) && return 0
  return 1
}

###
# Check if path exists
#
# @param 1: string - Path to check
# @param 2: string - Type: 'file', 'dir', or 'any' (default: 'any')
# @return 0 if path exists and matches type, 1 otherwise
#
# @example
#   if z::probe::path /etc/hosts file; then
#     cat /etc/hosts
#   fi
#
#   if z::probe::path ~/.config dir; then
#     ls ~/.config
#   fi
###
z::probe::path()
{
  emulate -L zsh
  setopt extended_glob warn_create_global

  local path="$1" path_type="${2:-any}"

  if [[ -z $path ]]; then
    z::log::error "z::probe::path: path required"
    return 1
  fi

  case $path_type in
    file)
      [[ -f $path ]] && return 0
      return 1
      ;;
    dir)
      [[ -d $path ]] && return 0
      return 1
      ;;
    any)
      [[ -e $path ]] && return 0
      return 1
      ;;
    *)
      z::log::error "z::probe::path: invalid type '${path_type}' (must be file, dir, or any)"
      return 1
      ;;
  esac
}

###
# Check if path is readable
#
# @param 1: string - Path to check
# @return 0 if path is readable, 1 otherwise
#
# @example
#   if z::probe::path::readable ~/.zshrc; then
#     source ~/.zshrc
#   fi
###
z::probe::path::readable()
{
  emulate -L zsh
  setopt extended_glob warn_create_global

  local path="$1"

  if [[ -z $path ]]; then
    z::log::error "z::probe::path::readable: path required"
    return 1
  fi

  [[ -r $path ]] && return 0
  return 1
}

###
# Check if path is writable
#
# @param 1: string - Path to check
# @return 0 if path is writable, 1 otherwise
#
# @example
#   if z::probe::path::writable /tmp/output.txt; then
#     echo "data" > /tmp/output.txt
#   fi
###
z::probe::path::writable()
{
  emulate -L zsh
  setopt extended_glob warn_create_global

  local path="$1"

  if [[ -z $path ]]; then
    z::log::error "z::probe::path::writable: path required"
    return 1
  fi

  # If path exists, check if writable
  if [[ -e $path ]]; then
    [[ -w $path ]] && return 0
    return 1
  fi

  # If path doesn't exist, walk up to find first existing directory
  local parent_dir="${path:h}"
  while [[ $parent_dir != "/" && $parent_dir != "." ]]; do
    if [[ -d $parent_dir ]]; then
      [[ -w $parent_dir ]] && return 0
      return 1
    fi
    parent_dir="${parent_dir:h}"
  done

  # Fallback: check root or current directory
  [[ -w $parent_dir ]] && return 0
  return 1
}

###
# Check if path is executable
#
# @param 1: string - Path to check
# @return 0 if path is executable, 1 otherwise
#
# @example
#   if z::probe::path::executable /usr/bin/git; then
#     /usr/bin/git --version
#   fi
###
z::probe::path::executable()
{
  emulate -L zsh
  setopt extended_glob warn_create_global

  local path="$1"

  if [[ -z $path ]]; then
    z::log::error "z::probe::path::executable: path required"
    return 1
  fi

  [[ -x $path ]] && return 0
  return 1
}

###
# Check if module/feature is available
# Convenience wrapper for checking multiple conditions
#
# @param 1: string - Module name
# @return 0 if module is available, 1 otherwise
#
# @example
#   if z::probe::module git; then
#     # git command exists
#   fi
###
z::probe::module()
{
  emulate -L zsh
  setopt extended_glob warn_create_global

  local module_name="$1"

  if [[ -z $module_name ]]; then
    z::log::error "z::probe::module: module name required"
    return 1
  fi

  # Check if it's a command
  if z::probe::cmd "$module_name"; then
    return 0
  fi

  # Check if it's a function
  if z::probe::func "$module_name"; then
    return 0
  fi

  # Check if it's a builtin
  if z::probe::builtin "$module_name"; then
    return 0
  fi

  return 1
}

###
# Clear all probe caches
#
# @return 0 always
#
# @example
#   # After modifying PATH or loading new functions
#   z::probe::cache::clear
###
z::probe::cache::clear()
{
  emulate -L zsh
  setopt extended_glob warn_create_global

  z::cache::cmd::clear
  z::cache::func::clear

  z::log::debug "Cleared all probe caches"
  return 0
}

###
# Get probe cache statistics
#
# @return 0 always
#
# @example
#   z::probe::cache::stats
###
z::probe::cache::stats()
{
  emulate -L zsh
  setopt extended_glob warn_create_global

  typeset -i cmd_cache_size func_cache_size total_size
  (( cmd_cache_size = ${#_cmd_cache} ))
  (( func_cache_size = ${#_func_cache} ))
  (( total_size = cmd_cache_size + func_cache_size ))

  # Fallback if z::util::comma is unavailable
  if (( $+functions[z::util::comma] )); then
    print -r -- "Probe Cache Statistics:"
    print -r -- "  Command cache: $(z::util::comma $cmd_cache_size) entries"
    print -r -- "  Function cache: $(z::util::comma $func_cache_size) entries"
    print -r -- "  Total: $(z::util::comma $total_size) entries"
  else
    print -r -- "Probe Cache Statistics:"
    print -r -- "  Command cache: $cmd_cache_size entries"
    print -r -- "  Function cache: $func_cache_size entries"
    print -r -- "  Total: $total_size entries"
  fi

  return 0
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
  local platform_name="unknown"
  case $ostype_value in
    darwin*)
      typeset -gri IS_MACOS=1 IS_LINUX=0 IS_BSD=0 IS_CYGWIN=0
      platform_name="macos"
      ;;
    linux* | linux-gnu*)
      typeset -gri IS_MACOS=0 IS_LINUX=1 IS_BSD=0 IS_CYGWIN=0
      platform_name="linux"
      ;;
    *bsd* | dragonfly* | netbsd* | openbsd* | freebsd*)
      typeset -gri IS_MACOS=0 IS_LINUX=0 IS_BSD=1 IS_CYGWIN=0
      platform_name="bsd"
      ;;
    cygwin* | msys* | mingw*)
      typeset -gri IS_MACOS=0 IS_LINUX=0 IS_BSD=0 IS_CYGWIN=1
      platform_name="cygwin"
      ;;
    *)
      typeset -gri IS_MACOS=0 IS_LINUX=0 IS_BSD=0 IS_CYGWIN=0
      platform_name="unknown"
      ;;
  esac

  _zcore_config[platform_name]="$platform_name"


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
    z::log::warn "Unknown platform (ostype='${ostype_value}')"
  fi

  z::log::debug "Platform: name=${_zcore_config[platform_name]} macOS=$IS_MACOS Linux=$IS_LINUX BSD=$IS_BSD WSL=$IS_WSL Cygwin=$IS_CYGWIN Termux=$IS_TERMUX"

  return 0
}


################################################################################
# SECTION 5: COMMAND & ALIAS HANDLING
################################################################################

###
# Alias management system with comprehensive type support
# Supports regular aliases, global aliases, and suffix aliases
#
# Public API:
#   z::alias::set NAME VALUE [--global|--suffix|--force]
#   z::alias::get NAME [--type TYPE]
#   z::alias::unset NAME [--type TYPE]
#   z::alias::list [PATTERN] [--type TYPE]
#   z::alias::clear [--type TYPE]
#   z::alias::info NAME
#   z::alias::export [FILE]
#   z::alias::import FILE [--force]
#   z::alias::stats
###

###
# Set an alias (regular, global, or suffix)
#
# @param 1: string - Alias name
# @param 2: string - Alias value/command
# @flag --global, -g: Create global alias
# @flag --suffix, -s: Create suffix alias
# @flag --force, -f: Overwrite existing
# @return 0 on success, 1 on failure
#
# @example
#   z::alias::set ll 'ls -lah'
#   z::alias::set G 'grep' --global
#   z::alias::set pdf 'zathura' --suffix
#   z::alias::set ll 'ls -la' --force
###
z::alias::set()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local -A opts
  local name value alias_type='regular'
  typeset -i force

  zparseopts -D -E -A opts -- \
    g -global \
    s -suffix \
    f -force

  # Determine alias type
  if z::opt::has opts 'g' 'global'; then
    alias_type='global'
  elif z::opt::has opts 's' 'suffix'; then
    alias_type='suffix'
  fi

  # Parse force flag with config fallback
  (( force = $(z::opt::parse::force opts 'alias.force_overwrite' 0) ))

  # Validate arguments
  if (( $# != 2 )); then
    z::log::error "Usage: z::alias::set NAME VALUE [--global|--suffix] [--force]"
    return 1
  fi

  name="$1"
  value="$2"

  # Validate inputs
  z::validate::identifier "$name" "Alias name" || return 1
  z::validate::nonempty "$value" "Alias value" || return 1

  # Create alias
  __z::alias::create "$name" "$value" "$alias_type" "$force"
  return $?
}

###
# Get alias value
#
# @param 1: string - Alias name
# @flag --type, -t: Alias type (regular|global|suffix)
# @return 0 on success, 1 if not found
#
# @example
#   z::alias::get ll
#   z::alias::get G --type global
###
z::alias::get()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local -A opts
  local name alias_type

  zparseopts -D -E -A opts -- t: -type:

  if (( $# != 1 )); then
    z::log::error "Usage: z::alias::get NAME [--type TYPE]"
    return 1
  fi

  name="$1"
  alias_type=$(z::opt::get opts 't' 'type' 'regular')

  __z::alias::get_value "$name" "$alias_type"
  return $?
}

###
# Remove an alias
#
# @param 1: string - Alias name
# @flag --type, -t: Alias type (regular|global|suffix)
# @return 0 on success, 1 on failure
#
# @example
#   z::alias::unset ll
#   z::alias::unset G --type global
###
z::alias::unset()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local -A opts
  local name alias_type

  zparseopts -D -E -A opts -- t: -type:

  if (( $# != 1 )); then
    z::log::error "Usage: z::alias::unset NAME [--type TYPE]"
    return 1
  fi

  name="$1"
  alias_type=$(z::opt::get opts 't' 'type' 'regular')

  __z::alias::remove "$name" "$alias_type"
  return $?
}

###
# List aliases matching pattern
#
# @param 1: string - Pattern (optional, default: *)
# @flag --type, -t: Alias type filter (regular|global|suffix|all)
# @return 0 on success
#
# @example
#   z::alias::list
#   z::alias::list 'g*'
#   z::alias::list --type global
###
z::alias::list()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local -A opts
  local pattern alias_type

  zparseopts -D -E -A opts -- t: -type:

  pattern="${1:-*}"
  alias_type=$(z::opt::get opts 't' 'type' 'all')

  __z::alias::list_matching "$pattern" "$alias_type"
  return $?
}

###
# Clear all aliases of specified type
#
# @flag --type, -t: Alias type (regular|global|suffix|all)
# @return 0 on success
#
# @example
#   z::alias::clear --type global
#   z::alias::clear --type all
###
z::alias::clear()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local -A opts
  local alias_type

  zparseopts -D -E -A opts -- t: -type:

  alias_type=$(z::opt::get opts 't' 'type' 'regular')

  __z::alias::clear_all "$alias_type"
  return $?
}

###
# Show detailed information about an alias
#
# @param 1: string - Alias name
# @return 0 on success, 1 if not found
#
# @example
#   z::alias::info ll
###
z::alias::info()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local name

  if (( $# != 1 )); then
    z::log::error "Usage: z::alias::info NAME"
    return 1
  fi

  name="$1"

  __z::alias::show_info "$name"
  return $?
}

###
# Export aliases to file or stdout
#
# @param 1: string - Output file (optional, default: stdout)
# @return 0 on success
#
# @example
#   z::alias::export
#   z::alias::export ~/.aliases.txt
###
z::alias::export()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local output_file="${1:-}"

  __z::alias::export_all "$output_file"
  return $?
}

###
# Import aliases from file
#
# @param 1: string - Input file
# @flag --force, -f: Overwrite existing aliases
# @return 0 on success, 1 on failure
#
# @example
#   z::alias::import ~/.aliases.txt
#   z::alias::import ~/.aliases.txt --force
###
z::alias::import()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local -A opts
  local input_file
  typeset -i force

  zparseopts -D -E -A opts -- f -force

  if (( $# != 1 )); then
    z::log::error "Usage: z::alias::import FILE [--force]"
    return 1
  fi

  input_file="$1"

  # Validate file
  z::validate::path "$input_file" 'file' "Input file" || return 1
  z::validate::path::readable "$input_file" "Input file" || return 1

  (( force = $(z::opt::parse::force opts 'alias.force_overwrite' 0) ))

  __z::alias::import_from_file "$input_file" "$force"
  return $?
}

###
# Show alias statistics
#
# @return 0 on success
#
# @example
#   z::alias::stats
###
z::alias::stats()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  __z::alias::show_stats
  return $?
}

# ============================================================================
# Internal Implementation Functions
# ============================================================================

###
# Internal: Validate alias type
#
# @param 1: string - Type to validate
# @return 0 if valid, 1 if invalid
###
__z::alias::validate_type()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local alias_type="$1"

  case $alias_type in
    regular|global|suffix|all)
      return 0
      ;;
    *)
      z::log::error "Invalid alias type '${alias_type}': must be regular, global, suffix, or all"
      return 1
      ;;
  esac
}

###
# Internal: Check if alias exists
#
# @param 1: string - Alias name
# @param 2: string - Alias type
# @return 0 if exists, 1 if not
###
__z::alias::check_exists()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local name="$1" alias_type="${2:-regular}"

  case $alias_type in
    regular)
      # Check regular aliases (non-global, non-suffix)
      if (( ${+aliases[$name]} )); then
        # Verify it's not a global or suffix alias
        local flags
        flags=$(alias -L "$name" 2>/dev/null)
        if [[ $flags != *' -g '* && $flags != *' -s '* ]]; then
          return 0
        fi
      fi
      return 1
      ;;
    global)
      # Check global aliases
      if (( ${+aliases[$name]} )); then
        local flags
        flags=$(alias -L "$name" 2>/dev/null)
        [[ $flags == *' -g '* ]] && return 0
      fi
      return 1
      ;;
    suffix)
      # Check suffix aliases
      if (( ${+aliases[$name]} )); then
        local flags
        flags=$(alias -L "$name" 2>/dev/null)
        [[ $flags == *' -s '* ]] && return 0
      fi
      return 1
      ;;
    *)
      z::log::error "Invalid alias type: ${alias_type}"
      return 1
      ;;
  esac
}

###
# Internal: Get alias value
#
# @param 1: string - Alias name
# @param 2: string - Alias type
# @return 0 on success, 1 if not found
###
__z::alias::get_value()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local name="$1" alias_type="${2:-regular}"

  # Validate type
  __z::alias::validate_type "$alias_type" || return 1

  if ! __z::alias::check_exists "$name" "$alias_type"; then
    z::log::error "Alias '${name}' not found (type: ${alias_type})"
    return 1
  fi

  # Output the alias value
  print -r -- "${aliases[$name]}"
  return 0
}

###
# Internal: Check for command/function shadowing
#
# @param 1: string - Alias name
# @return 0 if no shadow, 1 if shadowing detected
###
__z::alias::check_shadow()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local name="$1"
  typeset -i warn_shadow shadowed

  (( warn_shadow = $(z::config::get 'alias.warn_shadow' 0) ))
  (( warn_shadow == 0 )) && return 0

  (( shadowed = 0 ))

  if z::probe::cmd "$name"; then
    z::log::warn "Alias '${name}' will shadow existing command"
    (( shadowed = 1 ))
  fi

  if z::probe::func "$name"; then
    z::log::warn "Alias '${name}' will shadow existing function"
    (( shadowed = 1 ))
  fi

  return $shadowed
}

###
# Internal: Create alias with validation
#
# @param 1: string - Alias name
# @param 2: string - Alias value
# @param 3: string - Alias type (regular|global|suffix)
# @param 4: int - Force overwrite (0|1)
# @return 0 on success, 1 on failure
###
__z::alias::create()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local name="$1" value="$2" alias_type="${3:-regular}"
  typeset -i force existed
  (( force = ${4:-0} ))
  (( existed = 0 ))

  local alias_flags='' event_type='alias:created'

  # Validate type
  __z::alias::validate_type "$alias_type" || return 1

  # Set alias flags
  case $alias_type in
    global)
      alias_flags='-g'
      ;;
    suffix)
      alias_flags='-s'
      ;;
  esac

  # Check for shadowing
  __z::alias::check_shadow "$name"

  # Check if alias exists
  if __z::alias::check_exists "$name" "$alias_type"; then
    (( existed = 1 ))
    event_type='alias:overwritten'

    if (( force == 0 )); then
      typeset -i interactive
      (( interactive = $(z::config::get 'alias.interactive_mode' 0) ))

      if (( interactive )); then
        local response
        print -n "Alias '${name}' exists. Overwrite? [y/N] "
        read -r response
        if [[ ! $response =~ ^[Yy]$ ]]; then
          z::log::info "Cancelled"
          return 1
        fi
      else
        z::log::warn "Alias '${name}' already exists (use --force to overwrite)"
        return 1
      fi
    fi
  fi

  # Create the alias
  if [[ -n $alias_flags ]]; then
    if ! builtin alias $alias_flags -- "${name}=${value}" 2>/dev/null; then
      z::log::error "Failed to create ${alias_type} alias: ${name}='${value}'"
      return 1
    fi
  else
    if ! builtin alias -- "${name}=${value}" 2>/dev/null; then
      z::log::error "Failed to create alias: ${name}='${value}'"
      return 1
    fi
  fi

  # Persist if enabled
  typeset -i auto_persist
  (( auto_persist = $(z::config::get 'alias.auto_persist' 0) ))
  if (( auto_persist )); then
    __z::alias::persist::store "$name" "$value" "$alias_type"
  fi

  # Emit event
  z::event::emit "$event_type" "name=${name}" "value=${value}" "type=${alias_type}"

  z::log::debug "Created ${alias_type} alias: ${name}='${value}'"
  return 0
}

###
# Internal: Remove alias
#
# @param 1: string - Alias name
# @param 2: string - Alias type
# @return 0 on success, 1 on failure
###
__z::alias::remove()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local name="$1" alias_type="${2:-regular}"
  local old_value

  # Validate type
  __z::alias::validate_type "$alias_type" || return 1

  if ! __z::alias::check_exists "$name" "$alias_type"; then
    z::log::error "Alias '${name}' does not exist (type: ${alias_type})"
    return 1
  fi

  old_value="${aliases[$name]}"

  # Remove the alias
  if ! builtin unalias -- "$name" 2>/dev/null; then
    z::log::error "Failed to remove alias: ${name}"
    return 1
  fi

  # Remove from persistent storage
  typeset -i auto_persist
  (( auto_persist = $(z::config::get 'alias.auto_persist' 0) ))
  if (( auto_persist )); then
    __z::alias::persist::delete "$name" "$alias_type"
  fi

  # Emit event
  z::event::emit "alias:removed" "name=${name}" "value=${old_value}" "type=${alias_type}"

  z::log::debug "Removed ${alias_type} alias: ${name}"
  return 0
}

###
# Internal: List aliases matching pattern
#
# @param 1: string - Pattern
# @param 2: string - Alias type filter
# @return 0 on success
###
__z::alias::list_matching()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local pattern="${1:-*}" alias_type="${2:-all}"
  local -a matching_aliases
  local name value count flags

  # Validate type
  __z::alias::validate_type "$alias_type" || return 1

  # Validate pattern
  if [[ -z $pattern ]]; then
    pattern='*'
  fi

  # Get matching aliases
  for name in ${(k)aliases}; do
    # Check pattern match
    if [[ $name != ${~pattern} ]]; then
      continue
    fi

    # Check type filter
    if [[ $alias_type != 'all' ]]; then
      if ! __z::alias::check_exists "$name" "$alias_type"; then
        continue
      fi
    fi

    matching_aliases+=("$name")
  done

  (( count = ${#matching_aliases} ))

  if (( count == 0 )); then
    z::log::info "No aliases matching pattern: ${pattern} (type: ${alias_type})"
    return 0
  fi

  z::log::info "Found $(z::util::comma $count) alias(es) matching '${pattern}' (type: ${alias_type}):\n"

  # Sort and display
  for name in ${(o)matching_aliases}; do
    value="${aliases[$name]}"
    flags=$(alias -L "$name" 2>/dev/null)

    # Determine type indicator
    local type_indicator=''
    if [[ $flags == *' -g '* ]]; then
      type_indicator=' [global]'
    elif [[ $flags == *' -s '* ]]; then
      type_indicator=' [suffix]'
    fi

    print -r -- "${name}='${value}'${type_indicator}"
  done

  return 0
}

###
# Internal: Clear all aliases of specified type
#
# @param 1: string - Alias type
# @return 0 on success
###
__z::alias::clear_all()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local alias_type="${1:-regular}"
  local -a to_remove
  local name
  typeset -i count

  # Validate type
  __z::alias::validate_type "$alias_type" || return 1

  # Collect aliases to remove
  for name in ${(k)aliases}; do
    if [[ $alias_type == 'all' ]] || __z::alias::check_exists "$name" "$alias_type"; then
      to_remove+=("$name")
    fi
  done

  (( count = ${#to_remove} ))

  if (( count == 0 )); then
    z::log::info "No ${alias_type} aliases to clear"
    return 0
  fi

  # Remove each alias
  for name in $to_remove; do
    builtin unalias -- "$name" 2>/dev/null
  done

  z::log::info "Cleared $(z::util::comma $count) ${alias_type} alias(es)"
  z::event::emit "alias:cleared" "type=${alias_type}" "count=${count}"

  return 0
}

###
# Internal: Show detailed alias information
#
# @param 1: string - Alias name
# @return 0 on success, 1 if not found
###
__z::alias::show_info()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local name="$1"
  local value flags alias_type='regular'
  local key

  # Check all types
  if __z::alias::check_exists "$name" 'global'; then
    alias_type='global'
  elif __z::alias::check_exists "$name" 'suffix'; then
    alias_type='suffix'
  elif __z::alias::check_exists "$name" 'regular'; then
    alias_type='regular'
  else
    z::log::error "Alias '${name}' not found"
    return 1
  fi

  value="${aliases[$name]}"
  flags=$(alias -L "$name" 2>/dev/null)

  print -r -- "Alias: ${name}"
  print -r -- "Type: ${alias_type}"
  print -r -- "Value: ${value}"
  print -r -- "Definition: ${flags}"

  # Check if persisted
  key=$(__z::alias::persist::make_key "$name" "$alias_type")
  if z::kv::exists "$key"; then
    print -r -- "Persisted: yes"
  else
    print -r -- "Persisted: no"
  fi

  return 0
}

###
# Internal: Export all aliases
#
# @param 1: string - Output file (optional)
# @return 0 on success
###
__z::alias::export_all()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local output_file="${1:-}"
  local name value flags
  local -a output_lines

  # Collect all aliases
  for name in ${(ko)aliases}; do
    value="${aliases[$name]}"
    flags=$(alias -L "$name" 2>/dev/null)

    # Determine type
    local type_prefix=''
    if [[ $flags == *' -g '* ]]; then
      type_prefix='global:'
    elif [[ $flags == *' -s '* ]]; then
      type_prefix='suffix:'
    fi

    output_lines+=("${type_prefix}${name}=${value}")
  done

  # Output
  if [[ -n $output_file ]]; then
    # Validate output path is writable
    z::validate::path::writable "$output_file" "Output file" || return 1

    printf '%s\n' "${output_lines[@]}" > "$output_file"
    z::log::info "Exported $(z::util::comma ${#output_lines}) alias(es) to: ${output_file}"
  else
    printf '%s\n' "${output_lines[@]}"
  fi

  return 0
}

###
# Internal: Import aliases from file
#
# @param 1: string - Input file
# @param 2: int - Force overwrite
# @return 0 on success, 1 on failure
###
__z::alias::import_from_file()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local input_file="$1"
  typeset -i force line_num success failed
  (( force = ${2:-0} ))
  (( line_num = 0 ))
  (( success = 0 ))
  (( failed = 0 ))

  local line name value alias_type

  z::log::info "Importing aliases from: ${input_file}"

  while IFS= read -r line; do
    (( line_num += 1 ))

    # Skip empty lines and comments
    [[ -z $line || $line == \#* ]] && continue

    # Parse format: [type:]name=value
    alias_type='regular'

    if [[ $line == global:* ]]; then
      alias_type='global'
      line="${line#global:}"
    elif [[ $line == suffix:* ]]; then
      alias_type='suffix'
      line="${line#suffix:}"
    fi

    # Parse name=value
    if [[ $line =~ ^([[:alnum:]_-]+)=(.+)$ ]]; then
      name="${match[1]}"
      value="${match[2]}"

      # Remove surrounding quotes if present
      value="${value#[\'\"]}"
      value="${value%[\'\"]}"

      if __z::alias::create "$name" "$value" "$alias_type" "$force"; then
        (( success += 1 ))
        z::log::debug "✓ ${name}='${value}'"
      else
        (( failed += 1 ))
        z::log::warn "✗ Failed: ${name}='${value}'"
      fi
    else
      z::log::warn "Invalid format at line ${line_num}: ${line}"
      (( failed += 1 ))
    fi
  done < "$input_file"

  # Emit event
  z::event::emit "alias:batch_imported" "file=${input_file}" "success=${success}" "failed=${failed}"

  z::log::info "Imported: $(z::util::comma $success) successful, $(z::util::comma $failed) failed"

  (( failed > 0 )) && return 1
  return 0
}

###
# Internal: Show alias statistics
#
# @return 0 on success
###
__z::alias::show_stats()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  typeset -i total regular_count global_count suffix_count
  local name flags

  (( total = ${#aliases} ))
  (( regular_count = 0 ))
  (( global_count = 0 ))
  (( suffix_count = 0 ))

  for name in ${(k)aliases}; do
    flags=$(alias -L "$name" 2>/dev/null)

    if [[ $flags == *' -g '* ]]; then
      (( global_count += 1 ))
    elif [[ $flags == *' -s '* ]]; then
      (( suffix_count += 1 ))
    else
      (( regular_count += 1 ))
    fi
  done

  print -r -- "Alias Statistics:"
  print -r -- "  Total: $(z::util::comma $total)"
  print -r -- "  Regular: $(z::util::comma $regular_count)"
  print -r -- "  Global: $(z::util::comma $global_count)"
  print -r -- "  Suffix: $(z::util::comma $suffix_count)"

  return 0
}
###
# Named directory management (hash -d)
# Provides convenient shortcuts for frequently accessed directories
#
# Public API:
#   z::alias::dir::set NAME PATH [--force]
#   z::alias::dir::get NAME
#   z::alias::dir::unset NAME
#   z::alias::dir::list [PATTERN]
###

###
# Set a named directory (hash -d)
#
# @param 1: string - Directory name
# @param 2: string - Directory path
# @flag --force, -f: Overwrite existing
# @return 0 on success, 1 on failure
#
# @example
#   z::alias::dir::set projects ~/workspace/projects
#   z::alias::dir::set config ~/.config --force
#   cd ~projects
###
z::alias::dir::set()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local -A opts
  local name path
  typeset -i force

  zparseopts -D -E -A opts -- f -force

  if (( $# != 2 )); then
    z::log::error "Usage: z::alias::dir::set NAME PATH [--force]"
    return 1
  fi

  name="$1"
  path="$2"

  # Validate inputs
  z::validate::identifier "$name" "Directory name" || return 1
  z::validate::nonempty "$path" "Directory path" || return 1

  (( force = $(z::opt::parse::force opts 'alias.force_overwrite' 0) ))

  __z::alias::dir::create "$name" "$path" "$force"
  return $?
}

###
# Get named directory path
#
# @param 1: string - Directory name
# @return 0 on success, 1 if not found
#
# @example
#   z::alias::dir::get projects
#   path=$(z::alias::dir::get projects)
###
z::alias::dir::get()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local name

  if (( $# != 1 )); then
    z::log::error "Usage: z::alias::dir::get NAME"
    return 1
  fi

  name="$1"

  __z::alias::dir::get_path "$name"
  return $?
}

###
# Remove named directory
#
# @param 1: string - Directory name
# @return 0 on success, 1 on failure
#
# @example
#   z::alias::dir::unset projects
###
z::alias::dir::unset()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local name

  if (( $# != 1 )); then
    z::log::error "Usage: z::alias::dir::unset NAME"
    return 1
  fi

  name="$1"

  __z::alias::dir::remove "$name"
  return $?
}

###
# List named directories matching pattern
#
# @param 1: string - Pattern (optional, default: *)
# @return 0 on success
#
# @example
#   z::alias::dir::list
#   z::alias::dir::list 'proj*'
###
z::alias::dir::list()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local pattern="${1:-*}"

  __z::alias::dir::list_matching "$pattern"
  return $?
}

# ============================================================================
# Internal Implementation Functions
# ============================================================================

###
# Internal: Create named directory
#
# @param 1: string - Directory name
# @param 2: string - Directory path
# @param 3: int - Force overwrite
# @return 0 on success, 1 on failure
###
__z::alias::dir::create()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local name="$1" path="$2"
  typeset -i force existed
  (( force = ${3:-0} ))
  (( existed = 0 ))

  # Expand path to absolute
  path="${path:a}"

  # Warn if directory doesn't exist (but don't fail)
  if ! z::probe::path "$path" 'dir'; then
    z::log::warn "Directory does not exist: ${path}"
  fi

  # Check if named directory exists
  if z::probe::dir "$name"; then
    (( existed = 1 ))

    if (( force == 0 )); then
      typeset -i interactive
      (( interactive = $(z::config::get 'alias.interactive_mode' 0) ))

      if (( interactive )); then
        local response
        print -n "Named directory '${name}' exists. Overwrite? [y/N] "
        read -r response
        if [[ ! $response =~ ^[Yy]$ ]]; then
          z::log::info "Cancelled"
          return 1
        fi
      else
        z::log::warn "Named directory '${name}' already exists (use --force to overwrite)"
        return 1
      fi
    fi
  fi

  # Create named directory
  if ! hash -d -- "${name}=${path}" 2>/dev/null; then
    z::log::error "Failed to create named directory: ${name}=${path}"
    return 1
  fi

  # Persist if enabled
  typeset -i auto_persist
  (( auto_persist = $(z::config::get 'alias.auto_persist' 0) ))
  if (( auto_persist )); then
    local key
    key=$(__z::alias::persist::make_dir_key "$name")
    z::kv::set "$key" "$path"
  fi

  # Emit event
  local event_type='alias:dir:created'
  (( existed )) && event_type='alias:dir:overwritten'
  z::event::emit "$event_type" "name=${name}" "path=${path}"

  z::log::debug "Created named directory: ${name}=${path}"
  return 0
}

###
# Internal: Get named directory path
#
# @param 1: string - Directory name
# @return 0 on success, 1 if not found
###
__z::alias::dir::get_path()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local name="$1"

  if ! z::probe::dir "$name"; then
    z::log::error "Named directory '${name}' not found"
    return 1
  fi

  print -r -- "${nameddirs[$name]}"
  return 0
}

###
# Internal: Remove named directory
#
# @param 1: string - Directory name
# @return 0 on success, 1 on failure
###
__z::alias::dir::remove()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local name="$1"
  local old_path

  if ! z::probe::dir "$name"; then
    z::log::error "Named directory '${name}' does not exist"
    return 1
  fi

  old_path="${nameddirs[$name]}"

  # Remove named directory
  if ! unhash -d -- "$name" 2>/dev/null; then
    z::log::error "Failed to remove named directory: ${name}"
    return 1
  fi

  # Remove from persistent storage
  typeset -i auto_persist
  (( auto_persist = $(z::config::get 'alias.auto_persist' 0) ))
  if (( auto_persist )); then
    local key
    key=$(__z::alias::persist::make_dir_key "$name")
    z::kv::del "$key"
  fi

  # Emit event
  z::event::emit "alias:dir:removed" "name=${name}" "path=${old_path}"

  z::log::debug "Removed named directory: ${name}"
  return 0
}

###
# Internal: List named directories matching pattern
#
# @param 1: string - Pattern
# @return 0 on success
###
__z::alias::dir::list_matching()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local pattern="${1:-*}"
  local -a matching_dirs
  local name path
  typeset -i count

  # Validate pattern
  if [[ -z $pattern ]]; then
    pattern='*'
  fi

  # Get matching named directories
  for name in ${(k)nameddirs}; do
    if [[ $name == ${~pattern} ]]; then
      matching_dirs+=("$name")
    fi
  done

  (( count = ${#matching_dirs} ))

  if (( count == 0 )); then
    z::log::info "No named directories matching pattern: ${pattern}"
    return 0
  fi

  # Handle singular/plural
  local item_word='directory'
  (( count > 1 )) && item_word='directories'

  z::log::info "Found $(z::util::comma $count) named ${item_word} matching '${pattern}':\n"

  # Sort and display
  for name in ${(o)matching_dirs}; do
    path="${nameddirs[$name]}"
    print -r -- "${name}=${path}"
  done

  return 0
}
###
# Alias persistence operations
# Manages saving/loading aliases to/from persistent storage
#
# Public API:
#   z::alias::persist::save [FILE]
#   z::alias::persist::load [FILE] [--force]
#   z::alias::persist::enable [--auto]
#   z::alias::persist::disable
#   z::alias::persist::clear
###

###
# Save aliases to persistent storage
#
# @param 1: string - Storage file (optional, uses default KV storage)
# @return 0 on success, 1 on failure
#
# @example
#   z::alias::persist::save
#   z::alias::persist::save ~/.aliases.db
###
z::alias::persist::save()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local storage_file="${1:-}"

  # Validate file path if provided
  if [[ -n $storage_file ]]; then
    z::validate::path::writable "$storage_file" "Storage file" || return 1
  fi

  __z::alias::persist::save_all "$storage_file"
  return $?
}

###
# Load aliases from persistent storage
#
# @param 1: string - Storage file (optional, uses default KV storage)
# @flag --force, -f: Overwrite existing aliases
# @return 0 on success, 1 on failure
#
# @example
#   z::alias::persist::load
#   z::alias::persist::load ~/.aliases.db --force
###
z::alias::persist::load()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local -A opts
  local storage_file
  typeset -i force

  zparseopts -D -E -A opts -- f -force

  storage_file="${1:-}"

  # Validate file if provided
  if [[ -n $storage_file ]]; then
    z::validate::path "$storage_file" 'file' "Storage file" || return 1
    z::validate::path::readable "$storage_file" "Storage file" || return 1
  fi

  (( force = $(z::opt::parse::force opts 'alias.force_overwrite' 0) ))

  __z::alias::persist::load_all "$storage_file" "$force"
  return $?
}

###
# Enable automatic persistence
#
# @flag --auto: Enable auto-save on every change
# @return 0 on success
#
# @example
#   z::alias::persist::enable
#   z::alias::persist::enable --auto
###
z::alias::persist::enable()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local -A opts
  typeset -i auto_save

  zparseopts -D -E -A opts -- -auto

  (( auto_save = $(z::opt::parse::bool opts '' 'auto') ))

  z::config::set_bool 'alias.persist_enabled' 1
  (( auto_save )) && z::config::set_bool 'alias.auto_persist' 1

  z::log::debug "Alias persistence enabled"
  return 0
}

###
# Disable automatic persistence
#
# @return 0 on success
#
# @example
#   z::alias::persist::disable
###
z::alias::persist::disable()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  z::config::set_bool 'alias.persist_enabled' 0
  z::config::set_bool 'alias.auto_persist' 0

  z::log::debug "Alias persistence disabled"
  return 0
}

###
# Clear all persisted aliases from storage
#
# @return 0 on success
#
# @example
#   z::alias::persist::clear
###
z::alias::persist::clear()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  __z::alias::persist::clear_storage
  return $?
}

# ============================================================================
# Internal Implementation Functions
# ============================================================================

###
# Internal: Construct storage key for alias
#
# @param 1: string - Alias name
# @param 2: string - Alias type (regular|global|suffix)
# @output: string - Storage key
# @return 0 always
###
__z::alias::persist::make_key()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local name="$1" alias_type="${2:-regular}"
  print -r -- "alias:${alias_type}:${name}"
  return 0
}

###
# Internal: Construct storage key for named directory
#
# @param 1: string - Directory name
# @output: string - Storage key
# @return 0 always
###
__z::alias::persist::make_dir_key()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local name="$1"
  print -r -- "alias:dir:${name}"
  return 0
}

###
# Internal: Store alias in persistent storage
#
# @param 1: string - Alias name
# @param 2: string - Alias value
# @param 3: string - Alias type
# @return 0 on success
###
__z::alias::persist::store()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local name="$1" value="$2" alias_type="${3:-regular}"
  local key

  key=$(__z::alias::persist::make_key "$name" "$alias_type")
  z::kv::set "$key" "$value"
  return $?
}

###
# Internal: Delete alias from persistent storage
#
# @param 1: string - Alias name
# @param 2: string - Alias type
# @return 0 on success
###
__z::alias::persist::delete()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local name="$1" alias_type="${2:-regular}"
  local key

  key=$(__z::alias::persist::make_key "$name" "$alias_type")
  z::kv::del "$key"
  return $?
}

###
# Internal: Save all aliases to storage
#
# @param 1: string - Storage file (optional)
# @return 0 on success
###
__z::alias::persist::save_all()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local storage_file="${1:-}"
  local name value flags alias_type
  typeset -i count
  (( count = 0 ))

  # If file specified, export to file
  if [[ -n $storage_file ]]; then
    __z::alias::export_all "$storage_file"
    return $?
  fi

  # Otherwise save to KV storage
  for name in ${(k)aliases}; do
    value="${aliases[$name]}"
    flags=$(alias -L "$name" 2>/dev/null)

    # Determine type
    alias_type='regular'
    if [[ $flags == *' -g '* ]]; then
      alias_type='global'
    elif [[ $flags == *' -s '* ]]; then
      alias_type='suffix'
    fi

    __z::alias::persist::store "$name" "$value" "$alias_type"
    (( count += 1 ))
  done

  # Save named directories
  for name in ${(k)nameddirs}; do
    local key
    key=$(__z::alias::persist::make_dir_key "$name")
    z::kv::set "$key" "${nameddirs[$name]}"
    (( count += 1 ))
  done

  z::log::info "Saved $(z::util::comma $count) alias(es) to persistent storage"
  return 0
}

###
# Internal: Load all aliases from storage
#
# @param 1: string - Storage file (optional)
# @param 2: int - Force overwrite
# @return 0 on success
###
__z::alias::persist::load_all()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local storage_file="$1"
  typeset -i force success failed
  (( force = ${2:-0} ))
  (( success = 0 ))
  (( failed = 0 ))

  local -a stored_keys
  local key name value alias_type

  # If file specified, import from file
  if [[ -n $storage_file ]]; then
    __z::alias::import_from_file "$storage_file" "$force"
    return $?
  fi

  # Load each alias type
  local -a alias_types
  alias_types=(regular global suffix)

  for alias_type in $alias_types; do
    stored_keys=( $(z::kv::keys "alias:${alias_type}:*") )

    for key in $stored_keys; do
      name="${key#alias:${alias_type}:}"
      value=$(z::kv::get "$key")

      if [[ -z $value ]]; then
        z::log::warn "Empty value for key: ${key}"
        (( failed += 1 ))
        continue
      fi

      if __z::alias::create "$name" "$value" "$alias_type" "$force"; then
        (( success += 1 ))
      else
        (( failed += 1 ))
      fi
    done
  done

  # Load named directories
  stored_keys=( $(z::kv::keys 'alias:dir:*') )
  for key in $stored_keys; do
    name="${key#alias:dir:}"
    value=$(z::kv::get "$key")

    if [[ -z $value ]]; then
      z::log::warn "Empty value for key: ${key}"
      (( failed += 1 ))
      continue
    fi

    if __z::alias::dir::create "$name" "$value" "$force"; then
      (( success += 1 ))
    else
      (( failed += 1 ))
    fi
  done

  z::log::info "Loaded: $(z::util::comma $success) successful, $(z::util::comma $failed) failed"

  (( failed > 0 )) && return 1
  return 0
}

###
# Internal: Clear persistent storage
#
# @return 0 on success
###
__z::alias::persist::clear_storage()
{
  emulate -L zsh
  setopt no_unset warn_create_global extended_glob

  local -a stored_keys
  local key
  typeset -i count

  # Get all alias-related keys
  stored_keys=( $(z::kv::keys 'alias:*') )
  (( count = ${#stored_keys} ))

  if (( count == 0 )); then
    z::log::info "No persisted aliases in storage"
    return 0
  fi

  # Delete all keys
  for key in $stored_keys; do
    z::kv::del "$key"
  done

  z::log::info "Cleared $(z::util::comma $count) persisted alias(es) from storage"
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
__z::exec::is_init_cmd()
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
__z::exec::check_segment()
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
__z::exec::has_dangerous_metachars()
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
__z::exec::scan_patterns()
{
  emulate -L zsh
  setopt localoptions typeset_silent
  local input="${1-}"
  [[ -z $input ]] && return 0

  # Skip security checks for whitelisted init commands
  if __z::exec::is_init_cmd "$input"; then
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
          __z::exec::check_segment "$cmd" "${args[@]}" || return 1
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
    __z::exec::check_segment "$cmd" "${args[@]}" || return 1
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
  if ! __z::exec::is_init_cmd "$input"; then
    if __z::exec::has_dangerous_metachars "$input"; then
      z::log::error "Rejected dangerous metacharacters in input"
      return 1
    fi
  fi

  # Security scan
  __z::exec::scan_patterns "$input" || return 1

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
# Background execution
z::exec::run_async() {
  local cmd="$1" callback="${2:-}"

  # Run in background with job control
  {
    local result
    result=$(z::exec::run "$cmd" 2>&1)
    local exit_code=$?

    if [[ -n $callback ]] && z::probe::func "$callback"; then
      "$callback" "$exit_code" "$result"
    fi
  } &

  local job_id=$!
  print -r -- "$job_id"
}

# Wait for background jobs
z::exec::wait_all() {
  wait
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
    z::log::warn "Forced eval in current shell requested"
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
  __z::exec::is_init_cmd "$input" && is_shell_init=true

  # Detect package manager install commands
  local is_package_install=false
  if [[ $input =~ '(^|[[:space:]])(npm|yarn|pip|pip3|cargo|brew|apt|yum|dnf|pacman)[[:space:]]+(add|install)($|[[:space:]])' ]]; then
    is_package_install=true
  fi

  # Security scan (skipped for known safe patterns in performance mode)
  if [[ ${_zcore_config[performance_mode]} != true ]] && \
    [[ $is_shell_init != true ]] && \
    [[ $is_package_install != true ]]; then
    __z::exec::scan_patterns "$input" || return 1
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
  if ! z::probe::cmd "$tool_name"; then
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
__z::cache::update_entry()
{
  emulate -L zsh
  local cache_type="$1" cache_key="$2"
  typeset -i result
  # Simplified: no need for 10# prefix if input is already 0 or 1
  (( result = $3 ))

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
__z::cache::purge_impl()
{
  emulate -L zsh
  local cache_type="$1"
  typeset -i current_size threshold excess to_remove purge_threshold

  # Determine cache parameters based on type
  case $cache_type in
    func)
      (( current_size = _func_cache_size ))
      (( threshold = ${_zcore_config[cache_max_size]:-1000} ))
      ;;
    cmd)
      (( current_size = _cmd_cache_size ))
      (( threshold = ${_zcore_config[cache_max_size]:-1000} ))
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
  (( purge_threshold = ${_zcore_config[cache_purge_threshold]:-10} ))

  # Only purge if excess is significant (avoid thrashing)
  if (( excess < purge_threshold )); then
    return 0
  fi

  # Calculate entries to remove: at least half the excess, minimum 1
  (( to_remove = excess / 2 ))
  (( to_remove = to_remove > 0 ? to_remove : 1 ))

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

        # Update size from actual hash size for consistency
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

        # Update size from actual hash size for consistency
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
  __z::cache::purge_impl func
}

###
# Purge command cache when size exceeds limit
# @private
# @return 0 on success
###
z::cache::cmd::_purge()
{
  emulate -L zsh
  __z::cache::purge_impl cmd
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
  if ! z::probe::func "$func"; then
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
__z::state::unset_impl()
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
  __z::state::unset_impl "$target" var
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
  __z::state::unset_impl "$target" func
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
  __z::state::unset_impl "$target" "$unset_type"
}

################################################################################
# SECTION 10: PLUGIN SYSTEM (ZSH-COMPATIBLE)
################################################################################

###
# Plugin registry and state tracking
###
typeset -gA _zcore_plugins              # Plugin metadata: name -> data
typeset -gA _zcore_plugin_states        # Plugin states: name -> state
typeset -ga _zcore_plugin_load_order    # Load order (topologically sorted)
typeset -gA _zcore_plugin_deps          # Dependency graph: name -> deps
typeset -gA _zcore_plugin_paths         # Plugin search paths
typeset -gi _zcore_plugin_count=0       # Total plugins active
typeset -gA _zcore_plugin_rollback      # Rollback state storage

# Plugin states (read-only constants)
typeset -gr PLUGIN_STATE_DISCOVERED="discovered"
typeset -gr PLUGIN_STATE_VALIDATED="validated"
typeset -gr PLUGIN_STATE_LOADED="loaded"
typeset -gr PLUGIN_STATE_INITIALIZED="initialized"
typeset -gr PLUGIN_STATE_ENABLED="enabled"
typeset -gr PLUGIN_STATE_DISABLED="disabled"
typeset -gr PLUGIN_STATE_FAILED="failed"

# Plugin configuration with validation
_zcore_config[plugin_init_timeout]=30        # Plugin init timeout (seconds)
_zcore_config[plugin_max_depth]=5            # Max dependency depth
_zcore_config[plugin_manifest_max_size]=102400  # Max manifest size (100KB)

# Default plugin search paths
_zcore_plugin_paths[system]="/usr/local/share/zcore/plugins"
_zcore_plugin_paths[user]="${HOME}/.local/share/zcore/plugins"
_zcore_plugin_paths[custom]="${ZCORE_PLUGIN_PATH:-}"

################################################################################
# PLUGIN PATH MANAGEMENT
################################################################################

###
# Add plugin search path with validation
#
# Usage:
#   z::plugin::add_path /custom/plugins
#
# @param 1: string - Directory path
# @return 0 on success, 1 on failure
###
z::plugin::add_path()
{
  emulate -L zsh
  setopt localoptions no_unset warn_create_global

  local path="${1-}"

  if [[ -z $path ]]; then
    z::log::error "z::plugin::add_path: Empty plugin path"
    return 1
  fi

  z::runtime::check_interrupted || return $?

  local resolved_path
  if ! resolved_path=$(z::path::resolve "$path"); then
    z::log::error "z::plugin::add_path: Failed to resolve path: $path"
    return 1
  fi

  if [[ ! -d $resolved_path ]]; then
    z::log::warn "z::plugin::add_path: Directory does not exist: $resolved_path"
    return 1
  fi

  if [[ ! -r $resolved_path ]]; then
    z::log::error "z::plugin::add_path: Directory not readable: $resolved_path"
    return 1
  fi

  # Prevent duplicates
  local existing_path
  for existing_path in "${_zcore_plugin_paths[@]}"; do
    if [[ $existing_path == "$resolved_path" ]]; then
      z::log::debug "z::plugin::add_path: Path already added: $resolved_path"
      return 0
    fi
  done

  typeset -i key_suffix
  (( key_suffix = ${#_zcore_plugin_paths} ))
  local key="custom_${key_suffix}"

  while (( ${+_zcore_plugin_paths[$key]} )); do
    (( key_suffix = 10#${key_suffix} + 1 ))
    key="custom_${key_suffix}"
  done

  _zcore_plugin_paths[$key]="$resolved_path"

  z::log::info "Added plugin search path: $resolved_path"
  return 0
}

################################################################################
# MANIFEST PARSING (ZSH-SAFE IMPLEMENTATION)
################################################################################

###
# Parse plugin manifest file safely without eval
# Uses zsh parameter expansion for safe array manipulation
#
# @param 1: string - Manifest file path
# @param 2: string - Output associative array name (must exist globally)
# @private
# @return 0 on success, 1 on parse error
###
###
# Parse plugin manifest file safely without eval
# Uses controlled eval for array element access (safe since var names are controlled)
#
# @param 1: string - Manifest file path
# @param 2: string - Output associative array name (must exist globally)
# @private
# @return 0 on success, 1 on parse error
###
__z::plugin::parse_manifest()
{
  emulate -L zsh
  setopt localoptions extended_glob no_unset warn_create_global

  local manifest_file="${1-}"
  local output_var_name="${2-}"

  # Declare regex match arrays locally to avoid global creation
  local -a match mbegin mend

  if [[ -z $manifest_file ]]; then
    z::log::error "_parse_manifest: Empty manifest file path"
    return 1
  fi

  if [[ -z $output_var_name ]]; then
    z::log::error "_parse_manifest: Empty output array name"
    return 1
  fi

  if [[ ! -f $manifest_file || ! -r $manifest_file ]]; then
    z::log::error "_parse_manifest: Manifest not readable: $manifest_file"
    return 1
  fi

  # Security: Check file size limit
  typeset -i file_size
  (( file_size = $(command wc -c < "$manifest_file" 2>/dev/null || print 0) ))
  if (( file_size > _zcore_config[plugin_manifest_max_size] )); then
    z::log::error "_parse_manifest: Manifest exceeds size limit: $file_size bytes"
    return 1
  fi

  local line key value section current_key array_key existing_val
  typeset -i line_num=0

  while IFS= read -r line || [[ -n $line ]]; do
    (( line_num = 10#${line_num} + 1 ))

    z::runtime::check_interrupted || return $?

    # Skip empty lines and comments
    [[ $line =~ '^[[:space:]]*(#.*)?$' ]] && continue

    # Section headers: name:
    if [[ $line =~ '^([a-zA-Z_][a-zA-Z0-9_]*):$' ]]; then
      section="${match[1]}"
      current_key="$section"
      # Initialize section with empty string using controlled eval
      # Safe: output_var_name is controlled by us, not from manifest
      eval "${output_var_name}[${current_key}]=''"
      continue
    fi

    # Key-value pairs: key: value
    if [[ $line =~ '^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*(.*)$' ]]; then
      key="${match[1]}"
      value="${match[2]}"

      # Remove surrounding quotes
      if [[ $value == \"*\" ]]; then
        value="${value#\"}"
        value="${value%\"}"
      elif [[ $value == \'*\' ]]; then
        value="${value#\'}"
        value="${value%\'}"
      fi

      # Build full key
      if [[ -n ${section:-} ]]; then
        array_key="${section}.${key}"
      else
        array_key="$key"
      fi

      # Direct assignment using controlled eval
      # Escape value for safe eval (single quotes protect everything)
      # Safe: array_key is built from our parsing, not arbitrary input
      eval "${output_var_name}[${array_key}]='${value//\'/\'\\\'\'}'"
      continue
    fi

    # Array items: - value
    if [[ $line =~ '^[[:space:]]+-[[:space:]]*(.*)$' ]]; then
      value="${match[1]}"

      # Remove quotes
      if [[ $value == \"*\" ]]; then
        value="${value#\"}"
        value="${value%\"}"
      elif [[ $value == \'*\' ]]; then
        value="${value#\'}"
        value="${value%\'}"
      fi

      if [[ -n ${current_key:-} ]]; then
        # Get existing value safely using controlled eval with default
        # Safe: current_key is from section header we parsed
        eval "existing_val=\"\${${output_var_name}[${current_key}]:-}\""

        # Append to array (pipe-separated)
        if [[ -n ${existing_val} ]]; then
          # Escape single quotes in both existing_val and value
          existing_val="${existing_val//\'/\'\\\'\'}"
          value="${value//\'/\'\\\'\'}"
          eval "${output_var_name}[${current_key}]='${existing_val}|${value}'"
        else
          # Escape single quotes in value
          value="${value//\'/\'\\\'\'}"
          eval "${output_var_name}[${current_key}]='${value}'"
        fi
      fi
      continue
    fi

    z::log::warn "_parse_manifest: Unrecognized syntax at line $line_num: ${line[1,50]}"
  done < "$manifest_file"

  z::log::debug "_parse_manifest: Parsed $line_num lines from $manifest_file"
  return 0
}
###
# Validate plugin manifest fields and formats
#
# @param 1: string - Plugin name
# @param 2: string - Manifest associative array name
# @private
# @return 0 if valid, 1 if invalid
###
__z::plugin::validate_manifest()
{
  emulate -L zsh
  setopt localoptions no_unset warn_create_global

  local plugin_name="${1-}"
  local manifest_var_name="${2-}"

  # Declare regex match arrays locally
  local -a match mbegin mend

  if [[ -z $plugin_name ]]; then
    z::log::error "_validate_manifest: Empty plugin name"
    return 1
  fi

  if [[ -z $manifest_var_name ]]; then
    z::log::error "_validate_manifest: Empty manifest array name"
    return 1
  fi

  # Required fields
  local -a required_fields=(name version entry_point)
  local field value

  for field in "${required_fields[@]}"; do
    # Construct the parameter name and use indirect expansion
    local param_name="${manifest_var_name}[${field}]"
    value="${(P)param_name}"

    if [[ -z ${value:-} ]]; then
      z::log::error "Plugin $plugin_name: Missing required field '$field'"
      return 1
    fi
  done

  # Validate version format (semver: X.Y.Z)
  local param_name="${manifest_var_name}[version]"
  value="${(P)param_name}"

  if [[ ! $value =~ '^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.+-]+)?$' ]]; then
    z::log::error "Plugin $plugin_name: Invalid version format: $value (expected semver)"
    return 1
  fi

  # Validate name matches
  param_name="${manifest_var_name}[name]"
  value="${(P)param_name}"

  if [[ $value != "$plugin_name" ]]; then
    z::log::warn "Plugin $plugin_name: Manifest name mismatch: $value"
  fi

  # Validate entry_point format
  param_name="${manifest_var_name}[entry_point]"
  value="${(P)param_name}"

  if [[ ! $value =~ '^[a-zA-Z_][a-zA-Z0-9_:]*$' ]]; then
    z::log::error "Plugin $plugin_name: Invalid entry_point format: $value"
    return 1
  fi

  # Validate optional fields if present
  param_name="${manifest_var_name}[requires_zcore]"
  if [[ -n ${(P)param_name:-} ]]; then
    value="${(P)param_name}"
    if [[ ! $value =~ '^[0-9]+\.[0-9]+\.[0-9]+' ]]; then
      z::log::warn "Plugin $plugin_name: Invalid requires_zcore version: $value"
    fi
  fi

  # Validate homepage URL if present
  param_name="${manifest_var_name}[homepage]"
  if [[ -n ${(P)param_name:-} ]]; then
    value="${(P)param_name}"
    if [[ ! $value =~ '^https?://' ]]; then
      z::log::warn "Plugin $plugin_name: Invalid homepage URL: $value"
    fi
  fi

  z::log::debug "Plugin $plugin_name: Manifest validated successfully"
  return 0
}

################################################################################
# PLUGIN DISCOVERY
################################################################################

###
# Discover plugins in all search paths
#
# Usage:
#   z::plugin::discover
#
# @return 0 on success
###
z::plugin::discover()
{
  emulate -L zsh
  setopt localoptions null_glob no_unset warn_create_global

  z::log::info "Discovering plugins..."

  z::runtime::check_interrupted || return $?

  local search_path plugin_dir manifest_file plugin_name
  typeset -i discovered=0

  for search_path in "${_zcore_plugin_paths[@]}"; do
    [[ -z $search_path || ! -d $search_path ]] && continue

    z::runtime::check_interrupted || return $?

    z::log::debug "Scanning plugin path: $search_path"

    for plugin_dir in "$search_path"/*(/N); do
      z::runtime::check_interrupted || return $?

      plugin_name="${plugin_dir:t}"
      manifest_file="$plugin_dir/plugin.zsh-plugin"

      if [[ ! -f $manifest_file ]]; then
        z::log::debug "Skipping $plugin_name: No manifest found"
        continue
      fi

      if [[ -n ${_zcore_plugin_states[$plugin_name]:-} ]]; then
        z::log::debug "Plugin $plugin_name already discovered"
        continue
      fi

      # Create temporary associative array for manifest data
      typeset -A manifest_data

      if ! __z::plugin::parse_manifest "$manifest_file" manifest_data; then
        z::log::warn "Failed to parse manifest: $manifest_file"
        _zcore_plugin_states[$plugin_name]="$PLUGIN_STATE_FAILED"
        continue
      fi

      if ! __z::plugin::validate_manifest "$plugin_name" manifest_data; then
        _zcore_plugin_states[$plugin_name]="$PLUGIN_STATE_FAILED"
        continue
      fi

      local resolved_dir
      if ! resolved_dir=$(z::path::resolve "$plugin_dir"); then
        z::log::error "Failed to resolve plugin directory: $plugin_dir"
        _zcore_plugin_states[$plugin_name]="$PLUGIN_STATE_FAILED"
        continue
      fi

      _zcore_plugins[$plugin_name]="$plugin_name"
      _zcore_plugins["${plugin_name}.path"]="$resolved_dir"
      _zcore_plugin_states[$plugin_name]="$PLUGIN_STATE_DISCOVERED"

      # Store manifest data
      local key value
      for key value in "${(@kv)manifest_data}"; do
        _zcore_plugins["${plugin_name}.${key}"]="$value"
      done

      (( discovered = 10#${discovered} + 1 ))

      local version_param="manifest_data[version]"
      local version_value="${(P)version_param}"
      z::log::info "Discovered plugin: $plugin_name v${version_value}"
    done
  done

  z::log::info "Plugin discovery complete: $discovered plugins found"
  return 0
}

################################################################################
# DEPENDENCY RESOLUTION
################################################################################

###
# Parse dependency string into name and version constraint
#
# @param 1: string - Dependency string
# @param 2: string - Output variable name for dependency name
# @param 3: string - Output variable name for version constraint
# @private
# @return 0 on success
###
__z::plugin::parse_dependency()
{
  emulate -L zsh
  setopt localoptions no_unset

  local dep_string="${1-}"
  local name_var="${2-}"
  local constraint_var="${3-}"

  local name="$dep_string"
  local constraint=""

  # Check for version constraints
  if [[ $name == *">="* ]]; then
    constraint="${name#*>=}"
    name="${name%%>=*}"
  elif [[ $name == *"<="* ]]; then
    constraint="${name#*<=}"
    name="${name%%<=*}"
  elif [[ $name == *"^"* ]]; then
    constraint="${name#*^}"
    name="${name%%^*}"
  elif [[ $name == *"~"* ]]; then
    constraint="${name#*~}"
    name="${name%%~*}"
  elif [[ $name == *":"* ]]; then
    constraint="${name#*:}"
    name="${name%%:*}"
  fi

  # Trim whitespace
  name="${name## }"
  name="${name%% }"
  constraint="${constraint## }"
  constraint="${constraint%% }"

  # Use typeset -g to set the output variables
  typeset -g "${name_var}=${name}"
  typeset -g "${constraint_var}=${constraint}"

  return 0
}

###
# Resolve plugin dependencies using topological sort
# Handles both plugin dependencies and command dependencies
#
# Usage:
#   z::plugin::resolve_dependencies
#
# @return 0 on success, 1 if unresolvable dependencies
###
z::plugin::resolve_dependencies()
{
  emulate -L zsh
  setopt localoptions no_unset warn_create_global

  z::log::info "Resolving plugin dependencies..."

  z::runtime::check_interrupted || return $?

  typeset -A in_degree
  typeset -A adj_list
  typeset -A depths
  local plugin_name deps_str dep_string dep_name dep_constraint

  # Initialize graph for all discovered/validated plugins
  for plugin_name in "${(@k)_zcore_plugin_states}"; do
    local state="${_zcore_plugin_states[$plugin_name]}"
    [[ $state == "$PLUGIN_STATE_FAILED" ]] && continue

    in_degree[$plugin_name]=0
    adj_list[$plugin_name]=""
    depths[$plugin_name]=0
  done

  z::runtime::check_interrupted || return $?

  # Build edges from dependencies
  for plugin_name in "${(@k)in_degree}"; do
    z::runtime::check_interrupted || return $?

    deps_str="${_zcore_plugins["${plugin_name}.dependencies"]:-}"
    [[ -z $deps_str ]] && continue

    # Parse pipe-separated dependencies
    local -a deps_array
    deps_array=("${(@s:|:)deps_str}")

    for dep_string in "${deps_array[@]}"; do
      [[ -z $dep_string ]] && continue

      # Parse dependency name and version constraint
      __z::plugin::parse_dependency "$dep_string" dep_name dep_constraint

      # Determine if this is a plugin dependency or command dependency
      if [[ -n ${in_degree[$dep_name]:-} ]]; then
        # This is a plugin dependency
        z::log::debug "Plugin $plugin_name: Plugin dependency found: $dep_name"

        # Add edge: dep_name -> plugin_name
        (( in_degree[$plugin_name] = 10#${in_degree[$plugin_name]} + 1 ))

        if [[ -n ${adj_list[$dep_name]:-} ]]; then
          adj_list[$dep_name]="${adj_list[$dep_name]} $plugin_name"
        else
          adj_list[$dep_name]="$plugin_name"
        fi

      else
        # This is a command dependency - check if command exists
        if z::probe::cmd "$dep_name"; then
          z::log::debug "Plugin $plugin_name: Command dependency satisfied: $dep_name"

          # Optional: Check version constraint if specified
          if [[ -n $dep_constraint ]]; then
            z::log::debug "Plugin $plugin_name: Version constraint for $dep_name: $dep_constraint (not validated)"
          fi
        else
          # Command not found - check if it's optional
          local opt_deps="${_zcore_plugins["${plugin_name}.optional_dependencies"]:-}"
          if [[ $opt_deps == *"$dep_name"* ]]; then
            z::log::warn "Plugin $plugin_name: Optional command dependency $dep_name not found"
            continue
          else
            z::log::error "Plugin $plugin_name: Required command dependency $dep_name not found"
            z::log::info "  Please install $dep_name and try again"
            _zcore_plugin_states[$plugin_name]="$PLUGIN_STATE_FAILED"
            return 1
          fi
        fi
      fi
    done
  done

  z::runtime::check_interrupted || return $?

  # Topological sort using Kahn's algorithm
  local -a queue sorted_order
  local node dependent
  typeset -i current_degree current_depth existing_depth

  # Find nodes with no plugin dependencies
  for node in "${(@k)in_degree}"; do
    if (( in_degree[$node] == 0 )); then
      queue+=("$node")
    fi
  done

  # Process queue
  while (( ${#queue} > 0 )); do
    z::runtime::check_interrupted || return $?

    node="${queue[1]}"
    queue=("${(@)queue[2,-1]}")
    sorted_order+=("$node")

    # Check depth limit
    (( current_depth = 10#${depths[$node]} ))
    if (( current_depth > _zcore_config[plugin_max_depth] )); then
      z::log::error "Plugin dependency depth exceeds limit: $node (depth: $current_depth)"
      return 1
    fi

    # Process dependents
    if [[ -n ${adj_list[$node]:-} ]]; then
      for dependent in ${=adj_list[$node]}; do
        (( in_degree[$dependent] = 10#${in_degree[$dependent]} - 1 ))

        # Update depth
        (( current_depth = 10#${depths[$node]} + 1 ))
        (( existing_depth = 10#${depths[$dependent]:-0} ))

        if (( current_depth > existing_depth )); then
          (( depths[$dependent] = current_depth ))
        fi

        if (( in_degree[$dependent] == 0 )); then
          queue+=("$dependent")
        fi
      done
    fi
  done

  # Check for cycles (only in plugin dependencies)
  if (( ${#sorted_order} != ${#in_degree} )); then
    z::log::error "Circular dependency detected in plugins"

    # Find nodes in cycle
    for node in "${(@k)in_degree}"; do
      if (( in_degree[$node] > 0 )); then
        z::log::error "  Plugin $node is part of dependency cycle (remaining edges: ${in_degree[$node]})"
        _zcore_plugin_states[$node]="$PLUGIN_STATE_FAILED"
      fi
    done

    return 1
  fi

  # Store load order
  _zcore_plugin_load_order=("${sorted_order[@]}")

  z::log::info "Dependency resolution complete. Load order:"
  typeset -i idx=1
  for node in "${sorted_order[@]}"; do
    z::log::info "  ${idx}. $node"
    (( idx = 10#${idx} + 1 ))
  done

  return 0
}

################################################################################
# PLUGIN LOADING
################################################################################

###
# Find plugin main file
#
# @param 1: string - Plugin name
# @param 2: string - Plugin directory path
# @param 3: string - Output variable name for found file path
# @private
# @return 0 if found, 1 if not found
###
__z::plugin::find_plugin_file()
{
  emulate -L zsh
  setopt localoptions no_unset

  local plugin_name="${1-}"
  local plugin_path="${2-}"
  local file_var="${3-}"

  local -a candidates=(
    "$plugin_path/${plugin_name}.plugin.zsh"
    "$plugin_path/init.zsh"
    "$plugin_path/${plugin_name}.zsh"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f $candidate && -r $candidate ]]; then
      typeset -g "${file_var}=${candidate}"
      return 0
    fi
  done

  return 1
}

###
# Load a single plugin
#
# @param 1: string - Plugin name
# @private
# @return 0 on success, 1 on failure
###
__z::plugin::load_single()
{
  emulate -L zsh
  setopt localoptions no_unset warn_create_global

  local plugin_name="${1-}"

  if [[ -z $plugin_name ]]; then
    z::log::error "_load_single: Empty plugin name"
    return 1
  fi

  z::runtime::check_interrupted || return $?

  local current_state="${_zcore_plugin_states[$plugin_name]:-}"

  if [[ $current_state != "$PLUGIN_STATE_DISCOVERED" &&
        $current_state != "$PLUGIN_STATE_VALIDATED" ]]; then
    z::log::error "Plugin $plugin_name: Invalid state for loading: $current_state"
    return 1
  fi

  local plugin_path="${_zcore_plugins["${plugin_name}.path"]:-}"
  if [[ -z $plugin_path || ! -d $plugin_path ]]; then
    z::log::error "Plugin $plugin_name: Path not found or invalid"
    _zcore_plugin_states[$plugin_name]="$PLUGIN_STATE_FAILED"
    return 1
  fi

  local plugin_file
  if ! __z::plugin::find_plugin_file "$plugin_name" "$plugin_path" plugin_file; then
    z::log::error "Plugin $plugin_name: No plugin file found in $plugin_path"
    _zcore_plugin_states[$plugin_name]="$PLUGIN_STATE_FAILED"
    return 1
  fi

  z::log::info "Loading plugin: $plugin_name from $plugin_file"

  local -a functions_before
  functions_before=("${(@k)functions}")
  _zcore_plugin_rollback["${plugin_name}.functions_before"]="${(j:|:)functions_before}"

  if ! z::path::source "$plugin_file"; then
    z::log::error "Plugin $plugin_name: Failed to source $plugin_file"
    _zcore_plugin_states[$plugin_name]="$PLUGIN_STATE_FAILED"
    return 1
  fi

  local on_load_hook="${_zcore_plugins["${plugin_name}.hooks.on_load"]:-}"
  if [[ -n $on_load_hook ]]; then
    if z::probe::func "$on_load_hook"; then
      z::log::debug "Calling on_load hook: $on_load_hook"
      if ! z::func::call "$on_load_hook"; then
        z::log::warn "Plugin $plugin_name: on_load hook failed"
      fi
    else
      z::log::warn "Plugin $plugin_name: on_load hook not found: $on_load_hook"
    fi
  fi

  _zcore_plugin_states[$plugin_name]="$PLUGIN_STATE_LOADED"
  z::log::info "Plugin $plugin_name loaded successfully"

  return 0
}

###
# Rollback plugin loading on failure
#
# @param 1: string - Plugin name
# @private
# @return 0 always
###
__z::plugin::rollback_load()
{
  emulate -L zsh
  setopt localoptions no_unset

  local plugin_name="${1-}"

  z::log::debug "Rolling back plugin: $plugin_name"

  local functions_before_str="${_zcore_plugin_rollback["${plugin_name}.functions_before"]:-}"
  [[ -z $functions_before_str ]] && return 0

  local -a functions_before functions_after
  functions_before=("${(@s:|:)functions_before_str}")
  functions_after=("${(@k)functions}")

  local func
  for func in "${functions_after[@]}"; do
    if (( ! ${functions_before[(Ie)$func]} )); then
      z::func::unset "$func"
      z::log::debug "Rolled back function: $func"
    fi
  done

  unset "_zcore_plugin_rollback[${plugin_name}.functions_before]"

  return 0
}

###
# Load all discovered plugins in dependency order (idempotent)
#
# Usage:
#   z::plugin::load_all
#
# @return 0 on success, 1 if any failed
###
z::plugin::load_all()
{
  emulate -L zsh
  setopt localoptions no_unset warn_create_global

  if (( ${#_zcore_plugin_load_order} == 0 )); then
    z::plugin::resolve_dependencies || return 1
  fi

  z::log::info "Loading plugins..."

  z::runtime::check_interrupted || return $?

  local plugin_name current_state
  typeset -i loaded=0 skipped=0 failed=0

  for plugin_name in "${_zcore_plugin_load_order[@]}"; do
    z::runtime::check_interrupted || return $?

    current_state="${_zcore_plugin_states[$plugin_name]:-}"

    # Skip if already loaded or beyond
    if [[ $current_state == "$PLUGIN_STATE_LOADED" ||
          $current_state == "$PLUGIN_STATE_INITIALIZED" ||
          $current_state == "$PLUGIN_STATE_ENABLED" ||
          $current_state == "$PLUGIN_STATE_DISABLED" ]]; then
      z::log::debug "Plugin $plugin_name already loaded (state: $current_state)"
      (( skipped = 10#${skipped} + 1 ))
      continue
    fi

    # Skip failed plugins
    if [[ $current_state == "$PLUGIN_STATE_FAILED" ]]; then
      z::log::debug "Plugin $plugin_name in failed state, skipping"
      (( failed = 10#${failed} + 1 ))
      continue
    fi

    # Load plugin
    if __z::plugin::load_single "$plugin_name"; then
      (( loaded = 10#${loaded} + 1 ))
    else
      (( failed = 10#${failed} + 1 ))
      __z::plugin::rollback_load "$plugin_name"
    fi
  done

  z::log::info "Plugin loading complete: $loaded loaded, $skipped skipped, $failed failed"

  (( failed == 0 ))
}
################################################################################
# PLUGIN INITIALIZATION
################################################################################

###
# Initialize a loaded plugin (idempotent)
#
# @param 1: string - Plugin name
# @return 0 on success, 1 on failure
###
z::plugin::init()
{
  emulate -L zsh
  setopt localoptions no_unset warn_create_global

  local plugin_name="${1-}"

  if [[ -z $plugin_name ]]; then
    z::log::error "z::plugin::init: Empty plugin name"
    return 1
  fi

  z::runtime::check_interrupted || return $?

  local current_state="${_zcore_plugin_states[$plugin_name]:-}"

  # Already initialized or enabled - nothing to do
  if [[ $current_state == "$PLUGIN_STATE_INITIALIZED" ||
        $current_state == "$PLUGIN_STATE_ENABLED" ||
        $current_state == "$PLUGIN_STATE_DISABLED" ]]; then
    z::log::debug "Plugin $plugin_name already initialized (state: $current_state)"
    return 0
  fi

  # Must be loaded first
  if [[ $current_state != "$PLUGIN_STATE_LOADED" ]]; then
    z::log::error "Plugin $plugin_name: Must be loaded before initialization (current: $current_state)"
    return 1
  fi

  local entry_point="${_zcore_plugins["${plugin_name}.entry_point"]:-}"
  if [[ -z $entry_point ]]; then
    z::log::error "Plugin $plugin_name: No entry_point defined"
    return 1
  fi

  if ! z::probe::func "$entry_point"; then
    z::log::error "Plugin $plugin_name: entry_point function not found: $entry_point"
    _zcore_plugin_states[$plugin_name]="$PLUGIN_STATE_FAILED"
    return 1
  fi

  z::log::info "Initializing plugin: $plugin_name (entry_point: $entry_point)"

  typeset -i exit_code=0
  if ! z::func::call "$entry_point"; then
    exit_code=$?
    z::log::error "Plugin $plugin_name: Initialization failed (exit code: $exit_code)"
    _zcore_plugin_states[$plugin_name]="$PLUGIN_STATE_FAILED"
    return 1
  fi

  _zcore_plugin_states[$plugin_name]="$PLUGIN_STATE_INITIALIZED"
  (( _zcore_plugin_count = 10#${_zcore_plugin_count} + 1 ))

  z::log::info "Plugin $plugin_name initialized successfully"
  return 0
}

################################################################################
# PLUGIN STATE MANAGEMENT
################################################################################

###
# Enable a plugin
#
# @param 1: string - Plugin name
# @return 0 on success, 1 on failure
###
z::plugin::enable()
{
  emulate -L zsh
  setopt localoptions no_unset

  local plugin_name="${1-}"

  if [[ -z $plugin_name ]]; then
    z::log::error "z::plugin::enable: Empty plugin name"
    return 1
  fi

  z::runtime::check_interrupted || return $?

  local current_state="${_zcore_plugin_states[$plugin_name]:-}"

  if [[ $current_state == "$PLUGIN_STATE_ENABLED" ]]; then
    z::log::debug "Plugin $plugin_name already enabled"
    return 0
  fi

  if [[ $current_state != "$PLUGIN_STATE_INITIALIZED" &&
        $current_state != "$PLUGIN_STATE_DISABLED" ]]; then
    z::log::error "Plugin $plugin_name: Invalid state for enabling: $current_state"
    return 1
  fi

  z::log::info "Enabling plugin: $plugin_name"

  local on_enable_hook="${_zcore_plugins["${plugin_name}.hooks.on_enable"]:-}"
  if [[ -n $on_enable_hook ]] && z::probe::func "$on_enable_hook"; then
    if ! z::func::call "$on_enable_hook"; then
      z::log::error "Plugin $plugin_name: on_enable hook failed"
      return 1
    fi
  fi

  _zcore_plugin_states[$plugin_name]="$PLUGIN_STATE_ENABLED"
  z::log::info "Plugin $plugin_name enabled"

  return 0
}

###
# Disable a plugin
#
# @param 1: string - Plugin name
# @return 0 on success
###
z::plugin::disable()
{
  emulate -L zsh
  setopt localoptions no_unset

  local plugin_name="${1-}"

  if [[ -z $plugin_name ]]; then
    z::log::error "z::plugin::disable: Empty plugin name"
    return 1
  fi

  z::runtime::check_interrupted || return $?

  local current_state="${_zcore_plugin_states[$plugin_name]:-}"

  if [[ $current_state == "$PLUGIN_STATE_DISABLED" ]]; then
    z::log::debug "Plugin $plugin_name already disabled"
    return 0
  fi

  if [[ $current_state != "$PLUGIN_STATE_ENABLED" ]]; then
    z::log::warn "Plugin $plugin_name: Not in enabled state (current: $current_state)"
    return 0
  fi

  z::log::info "Disabling plugin: $plugin_name"

  local on_disable_hook="${_zcore_plugins["${plugin_name}.hooks.on_disable"]:-}"
  if [[ -n $on_disable_hook ]] && z::probe::func "$on_disable_hook"; then
    z::func::call "$on_disable_hook" || z::log::warn "on_disable hook failed"
  fi

  _zcore_plugin_states[$plugin_name]="$PLUGIN_STATE_DISABLED"
  z::log::info "Plugin $plugin_name disabled"

  return 0
}

###
# Unload a plugin
#
# @param 1: string - Plugin name
# @return 0 on success
###
z::plugin::unload()
{
  emulate -L zsh
  setopt localoptions no_unset warn_create_global

  local plugin_name="${1-}"

  if [[ -z $plugin_name ]]; then
    z::log::error "z::plugin::unload: Empty plugin name"
    return 1
  fi

  z::runtime::check_interrupted || return $?

  local current_state="${_zcore_plugin_states[$plugin_name]:-}"

  if [[ $current_state == "$PLUGIN_STATE_ENABLED" ]]; then
    z::plugin::disable "$plugin_name"
  fi

  z::log::info "Unloading plugin: $plugin_name"

  local on_unload_hook="${_zcore_plugins["${plugin_name}.hooks.on_unload"]:-}"
  if [[ -n $on_unload_hook ]] && z::probe::func "$on_unload_hook"; then
    z::func::call "$on_unload_hook" || z::log::warn "on_unload hook failed"
  fi

  local exports="${_zcore_plugins["${plugin_name}.exports"]:-}"
  if [[ -n $exports ]]; then
    local -a export_funcs
    export_funcs=("${(@s:|:)exports}")

    local func
    for func in "${export_funcs[@]}"; do
      if z::probe::func "$func"; then
        z::func::unset "$func"
        z::log::debug "Unset function: $func"
      fi
    done
  fi

  unset "_zcore_plugin_states[$plugin_name]"
  if (( _zcore_plugin_count > 0 )); then
    (( _zcore_plugin_count = 10#${_zcore_plugin_count} - 1 ))
  fi

  z::log::info "Plugin $plugin_name unloaded"
  return 0
}

################################################################################
# PLUGIN INFORMATION & LISTING
################################################################################

###
# List all plugins
#
# Usage:
#   z::plugin::list
#
# @return 0 always
###
z::plugin::list()
{
  emulate -L zsh
  setopt localoptions no_unset

  if (( ${#_zcore_plugin_states} == 0 )); then
    print "No plugins discovered."
    return 0
  fi

  print "\nInstalled Plugins:"
  print "==================\n"

  local plugin_name state version
  typeset -i idx=1

  for plugin_name in "${(@k)_zcore_plugin_states}"; do
    state="${_zcore_plugin_states[$plugin_name]}"
    version="${_zcore_plugins["${plugin_name}.version"]:-unknown}"

    local state_display
    case $state in
      "$PLUGIN_STATE_ENABLED")
        state_display="${_zcore_colors[green]}${state}${_zcore_colors[reset]}"
        ;;
      "$PLUGIN_STATE_FAILED")
        state_display="${_zcore_colors[red]}${state}${_zcore_colors[reset]}"
        ;;
      "$PLUGIN_STATE_DISABLED")
        state_display="${_zcore_colors[yellow]}${state}${_zcore_colors[reset]}"
        ;;
      *)
        state_display="$state"
        ;;
    esac

    printf "%2d. %-20s  v%-10s  [%s]\n" \
      "$idx" "$plugin_name" "$version" "$state_display"

    (( idx = 10#${idx} + 1 ))
  done

  print "\nTotal: ${#_zcore_plugin_states} plugins"
  print "Active: $_zcore_plugin_count plugins"
  return 0
}

###
# Show plugin information
#
# Usage:
#   z::plugin::info my-plugin
#
# @param 1: string - Plugin name
# @return 0 on success, 1 if not found
###
z::plugin::info()
{
  emulate -L zsh
  setopt localoptions no_unset

  local plugin_name="${1-}"

  if [[ -z $plugin_name ]]; then
    z::log::error "z::plugin::info: Empty plugin name"
    return 1
  fi

  if [[ -z ${_zcore_plugin_states[$plugin_name]:-} ]]; then
    z::log::error "Plugin not found: $plugin_name"
    return 1
  fi

  print "\nPlugin Information: $plugin_name"
  print "================================\n"

  local -a fields=(
    name version description author license homepage
    requires_zcore entry_point dependencies optional_dependencies
    conflicts exports
  )

  local key value
  for key in "${fields[@]}"; do
    value="${_zcore_plugins["${plugin_name}.${key}"]:-}"

    if [[ -n $value ]]; then
      if [[ $value == *"|"* ]]; then
        print "$key:"
        local item
        for item in ${(s:|:)value}; do
          print "  - $item"
        done
      else
        print "$key: $value"
      fi
    fi
  done

  print "\nState: ${_zcore_plugin_states[$plugin_name]}"
  print "Path: ${_zcore_plugins["${plugin_name}.path"]}"

  return 0
}

################################################################################
# PLUGIN SYSTEM INITIALIZATION
################################################################################

###
# Initialize the complete plugin system (idempotent)
#
# Usage:
#   z::plugin::init_system
#
# @return 0 on success, 1 on failure
###
z::plugin::init_system()
{
  emulate -L zsh
  setopt localoptions no_unset warn_create_global

  z::log::info "Initializing plugin system..."

  z::runtime::check_interrupted || return $?

  # Discover plugins (idempotent)
  if ! z::plugin::discover; then
    z::log::error "Plugin discovery failed"
    return 1
  fi

  z::runtime::check_interrupted || return $?

  # Resolve dependencies
  if ! z::plugin::resolve_dependencies; then
    z::log::error "Dependency resolution failed"
    return 1
  fi

  z::runtime::check_interrupted || return $?

  # Load all plugins (now idempotent)
  if ! z::plugin::load_all; then
    z::log::warn "Some plugins failed to load"
  fi

  z::runtime::check_interrupted || return $?

  # Initialize loaded plugins
  local plugin_name
  typeset -i initialized=0 failed=0

  for plugin_name in "${_zcore_plugin_load_order[@]}"; do
    z::runtime::check_interrupted || return $?

    local state="${_zcore_plugin_states[$plugin_name]}"

    if [[ $state == "$PLUGIN_STATE_LOADED" ]]; then
      if z::plugin::init "$plugin_name"; then
        (( initialized = 10#${initialized} + 1 ))
      else
        (( failed = 10#${failed} + 1 ))
        z::log::warn "Failed to initialize $plugin_name"
      fi
    elif [[ $state == "$PLUGIN_STATE_INITIALIZED" ||
            $state == "$PLUGIN_STATE_ENABLED" ]]; then
      z::log::debug "Plugin $plugin_name already initialized"
    fi
  done

  z::runtime::check_interrupted || return $?

  # Enable initialized plugins
  typeset -i enabled=0
  for plugin_name in "${(@k)_zcore_plugin_states}"; do
    z::runtime::check_interrupted || return $?

    local state="${_zcore_plugin_states[$plugin_name]}"

    if [[ $state == "$PLUGIN_STATE_INITIALIZED" ]]; then
      if z::plugin::enable "$plugin_name"; then
        (( enabled = 10#${enabled} + 1 ))
      else
        z::log::warn "Failed to enable $plugin_name"
      fi
    elif [[ $state == "$PLUGIN_STATE_ENABLED" ]]; then
      z::log::debug "Plugin $plugin_name already enabled"
      (( enabled = 10#${enabled} + 1 ))
    fi
  done

  z::log::info "Plugin system initialized: $enabled active, $failed failed"
  z::log::info "Total plugins: $_zcore_plugin_count"

  return 0
}


###
# Reload a single plugin
# Complete workflow: unload → discover → resolve → load → init → enable
#
# Usage:
#   z::plugin::reload git-helper
#
# @param 1: string - Plugin name
# @return 0 on success, 1 on failure
###
z::plugin::reload()
{
  emulate -L zsh
  setopt localoptions no_unset

  local plugin_name="${1-}"

  if [[ -z $plugin_name ]]; then
    z::log::error "z::plugin::reload: Empty plugin name"
    return 1
  fi

  z::log::info "Reloading plugin: $plugin_name"

  # Unload if currently loaded
  if [[ -n ${_zcore_plugin_states[$plugin_name]:-} ]]; then
    z::plugin::unload "$plugin_name"
  fi

  # Clear from registry to allow re-discovery
  unset "_zcore_plugin_states[$plugin_name]"
  local key
  for key in "${(@k)_zcore_plugins}"; do
    if [[ $key == "${plugin_name}"* ]]; then
      unset "_zcore_plugins[$key]"
    fi
  done

  # Re-discover
  z::plugin::discover || return 1

  # Check if found
  if [[ -z ${_zcore_plugin_states[$plugin_name]:-} ]]; then
    z::log::error "Plugin $plugin_name not found after discovery"
    return 1
  fi

  # Resolve dependencies
  z::plugin::resolve_dependencies || return 1

  # Load
  __z::plugin::load_single "$plugin_name" || return 1

  # Initialize
  z::plugin::init "$plugin_name" || return 1

  # Enable
  z::plugin::enable "$plugin_name" || return 1

  z::log::info "Plugin $plugin_name reloaded successfully"
  return 0
}

###
# Load and enable a single plugin (idempotent)
# Convenience function for manual plugin management
#
# Usage:
#   z::plugin::load git-helper
#
# @param 1: string - Plugin name
# @return 0 on success, 1 on failure
###
z::plugin::load()
{
  emulate -L zsh
  setopt localoptions no_unset

  local plugin_name="${1-}"

  if [[ -z $plugin_name ]]; then
    z::log::error "z::plugin::load: Empty plugin name"
    return 1
  fi

  local current_state="${_zcore_plugin_states[$plugin_name]:-}"

  if [[ -z $current_state ]]; then
    z::log::error "Plugin $plugin_name not discovered. Run z::plugin::discover first."
    return 1
  fi

  # Already enabled - nothing to do
  if [[ $current_state == "$PLUGIN_STATE_ENABLED" ]]; then
    z::log::debug "Plugin $plugin_name already enabled"
    return 0
  fi

  # Failed state - cannot continue
  if [[ $current_state == "$PLUGIN_STATE_FAILED" ]]; then
    z::log::error "Plugin $plugin_name is in failed state"
    return 1
  fi

  # Load if needed
  if [[ $current_state == "$PLUGIN_STATE_DISCOVERED" ||
        $current_state == "$PLUGIN_STATE_VALIDATED" ]]; then
    z::plugin::resolve_dependencies || return 1
    __z::plugin::load_single "$plugin_name" || return 1
    current_state="${_zcore_plugin_states[$plugin_name]}"
  fi

  # Initialize if needed
  if [[ $current_state == "$PLUGIN_STATE_LOADED" ]]; then
    z::plugin::init "$plugin_name" || return 1
    current_state="${_zcore_plugin_states[$plugin_name]}"
  fi

  # Enable if needed
  if [[ $current_state == "$PLUGIN_STATE_INITIALIZED" ||
        $current_state == "$PLUGIN_STATE_DISABLED" ]]; then
    z::plugin::enable "$plugin_name" || return 1
  fi

  z::log::info "Plugin $plugin_name is now enabled"
  return 0
}
# Bulk operations
z::plugin::load_many() {
  local plugin
  for plugin in "$@"; do
    z::plugin::load "$plugin" || z::log::warn "Failed: $plugin"
  done
}
###
# Show plugin state transitions
#
# Usage:
#   z::plugin::status git-helper
#
# @param 1: string - Plugin name
# @return 0 on success, 1 if not found
###
z::plugin::status()
{
  emulate -L zsh
  setopt localoptions no_unset

  local plugin_name="${1-}"

  if [[ -z $plugin_name ]]; then
    z::log::error "z::plugin::status: Empty plugin name"
    return 1
  fi

  if [[ -z ${_zcore_plugin_states[$plugin_name]:-} ]]; then
    z::log::error "Plugin not found: $plugin_name"
    return 1
  fi

  local state="${_zcore_plugin_states[$plugin_name]}"
  local version="${_zcore_plugins["${plugin_name}.version"]:-unknown}"

  print "\nPlugin Status: $plugin_name"
  print "======================="
  print "Version: $version"
  print "State:   $state"
  print "\nState Transition:"

  case $state in
    "$PLUGIN_STATE_DISCOVERED")
      print "  ● discovered"
      print "  ○ loaded       (run: z::plugin::load $plugin_name)"
      print "  ○ initialized"
      print "  ○ enabled"
      ;;
    "$PLUGIN_STATE_LOADED")
      print "  ✓ discovered"
      print "  ● loaded"
      print "  ○ initialized  (run: z::plugin::init $plugin_name)"
      print "  ○ enabled"
      ;;
    "$PLUGIN_STATE_INITIALIZED")
      print "  ✓ discovered"
      print "  ✓ loaded"
      print "  ● initialized"
      print "  ○ enabled      (run: z::plugin::enable $plugin_name)"
      ;;
    "$PLUGIN_STATE_ENABLED")
      print "  ✓ discovered"
      print "  ✓ loaded"
      print "  ✓ initialized"
      print "  ● enabled"
      ;;
    "$PLUGIN_STATE_DISABLED")
      print "  ✓ discovered"
      print "  ✓ loaded"
      print "  ✓ initialized"
      print "  ● disabled     (run: z::plugin::enable $plugin_name)"
      ;;
    "$PLUGIN_STATE_FAILED")
      print "  ✗ failed"
      ;;
  esac

  return 0
}
# Query functions
z::plugin::is_enabled() {
  local state="${_zcore_plugin_states[$1]:-}"
  [[ $state == "$PLUGIN_STATE_ENABLED" ]]
}

z::plugin::is_loaded() {
  [[ -n ${_zcore_plugin_states[$1]:-} ]]
}

################################################################################
# SECTION 11: USER INTERFACE (UI)
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
# SECTION 12: INITIALIZATION
################################################################################

# Install interrupt handlers in interactive session
if [[ -o interactive ]] || [[ ${_zcore_config[install_traps]:-} == true ]]; then
  trap 'z::runtime::handle_interrupt' INT TERM
fi
# z::path::source "event.zsh"
#source "event.zsh"
# Log successful initialization
z::log::debug "Zsh utility library initialized (performance_mode=${_zcore_config[performance_mode]})"
################################################################################
# SECTION 13: EVENT SYSTEM
################################################################################
# zevent.zsh - Event bus system for Zcore framework
# Requires: zcore.zsh

# Event handler storage: split for performance
typeset -gA _zcore_event_handlers_exact     # Exact event matches (O(1) lookup)
typeset -gA _zcore_event_handlers_wildcard  # Wildcard patterns (O(n) scan)

# Handler metadata: handler_id -> metadata (priority, once, etc.)
typeset -gA _zcore_event_handler_meta

# Event history: stores recent events for replay/debugging
typeset -ga _zcore_event_history

# Handler ID counter for unique identification
typeset -gi _zcore_event_handler_id=0

# Event statistics
typeset -gA _zcore_event_stats

# Event handler priorities (higher = runs first)
typeset -gri ZCORE_EVENT_PRIORITY_HIGHEST=100
typeset -gri ZCORE_EVENT_PRIORITY_HIGH=75
typeset -gri ZCORE_EVENT_PRIORITY_NORMAL=50
typeset -gri ZCORE_EVENT_PRIORITY_LOW=25
typeset -gri ZCORE_EVENT_PRIORITY_LOWEST=0

# Initialize event system configuration with validation
z::config::set_int event_max_history 100
z::config::set_int event_handler_timeout 5
z::config::set_int event_max_handlers_per_event 50
z::config::set_bool event_enable_history true
z::config::set_bool event_enable_stats true
z::config::set_bool event_enable_wildcards true

###
# Generate unique handler ID
# @param 1: string - Name of variable to store ID in
# @private
# @return 0 always
###
__z::event::generate_id() {
  emulate -L zsh
  setopt localoptions no_unset warn_create_global

  local output_var="$1"

  # Increment counter atomically
  (( _zcore_event_handler_id += 1 ))

  # Set output variable in caller's scope
  : ${(P)output_var::=handler_${_zcore_event_handler_id}}

  return 0
}

###
# Validate event name format
# @param 1: string - Event name
# @private
# @return 0 if valid, ZCORE_ERROR_INVALID_INPUT if invalid
###
__z::event::validate_event_name() {
  emulate -L zsh
  setopt localoptions no_unset extended_glob

  local event_name="$1"

  # Use Zcore validation
  z::validate::nonempty "$event_name" "Event name" || return $ZCORE_ERROR_INVALID_INPUT

  # Allow alphanumeric, underscore, colon, asterisk, hyphen
  if [[ ! $event_name =~ ^[a-zA-Z0-9_:*-]+$ ]]; then
    z::log::error "Invalid event name format: $event_name (allowed: a-z A-Z 0-9 _ : * -)"
    return $ZCORE_ERROR_INVALID_INPUT
  fi

  return 0
}

###
# Validate handler function exists
# @param 1: string - Handler function name
# @private
# @return 0 if valid, ZCORE_ERROR_NOT_FOUND if invalid
###
__z::event::validate_handler() {
  emulate -L zsh
  setopt localoptions no_unset

  local handler="$1"

  z::validate::nonempty "$handler" "Handler" || return $ZCORE_ERROR_INVALID_INPUT

  if ! z::probe::func "$handler"; then
    z::log::error "Handler function does not exist: $handler"
    return $ZCORE_ERROR_NOT_FOUND
  fi

  return 0
}

###
# Parse handler list into array
# @param 1: string - Pipe-separated handler list
# @param 2: string - Output array name
# @private
# @return 0 always
###
__z::event::parse_handler_list() {
  emulate -L zsh
  setopt localoptions no_unset

  local handler_list="$1"
  local output_array="$2"

  if [[ -z $handler_list ]]; then
    : ${(PA)output_array::=()}
    return 0
  fi

  # Direct parameter expansion - no eval
  : ${(PA)output_array::=${(s:|:)handler_list}}
  return 0
}

###
# Sort handlers by priority (descending)
# @param 1: string - Array name containing handler IDs
# @private
# @return 0 always
###
__z::event::sort_handlers_by_priority() {
  emulate -L zsh
  setopt localoptions no_unset

  local array_name="$1"

  # Build sortable array: "priority:handler_id"
  local -a sortable_handlers
  local handler_id priority_val

  # Use nameref to avoid eval
  local -a handlers=("${(@P)array_name}")

  for handler_id in "${handlers[@]}"; do
    (( priority_val = ${_zcore_event_handler_meta[${handler_id}.priority]:-50} ))
    sortable_handlers+=("${priority_val}:${handler_id}")
  done

  # Sort numerically descending, extract handler IDs
  local -a sorted_entries
  sorted_entries=("${(@On)sortable_handlers}")

  # Extract handler IDs (everything after first colon)
  handlers=("${(@)sorted_entries#*:}")

  # Update caller's array
  : ${(PA)array_name::=${handlers[@]}}

  return 0
}

###
# Match event name against pattern (supports wildcards)
# @param 1: string - Event name
# @param 2: string - Pattern (may contain *)
# @private
# @return 0 if matches, 1 if not
###
__z::event::match_pattern() {
  emulate -L zsh
  setopt localoptions extended_glob no_unset

  local event_name="$1"
  local pattern="$2"

  # Exact match first (fast path)
  [[ $event_name == $pattern ]] && return 0

  # Wildcard matching if enabled
  if [[ ${_zcore_config[event_enable_wildcards]} == true ]]; then
    [[ $event_name == ${~pattern} ]] && return 0
  fi

  return 1
}

###
# Add event to history with timestamp caching
# @param 1: string - Event name
# @param ...: any - Event arguments
# @private
# @return 0 always
###
__z::event::add_to_history() {
  emulate -L zsh
  setopt localoptions no_unset

  [[ ${_zcore_config[event_enable_history]} != true ]] && return 0

  local event_name="$1"
  shift

  # Prefer EPOCHSECONDS (no external process)
  local timestamp="${EPOCHSECONDS:-$(date +%s 2>/dev/null || print 0)}"

  local entry="${timestamp}|${event_name}|$*"
  _zcore_event_history+=("$entry")

  # Trim history if needed
  typeset -i max_history current_size to_remove
  (( max_history = ${_zcore_config[event_max_history]} ))
  (( current_size = ${#_zcore_event_history} ))

  if (( current_size > max_history )); then
    (( to_remove = current_size - max_history ))
    _zcore_event_history=("${(@)_zcore_event_history[to_remove+1,-1]}")
  fi

  return 0
}

###
# Update event statistics
# @param 1: string - Event name
# @param 2: string - Stat type (emitted|handled|failed)
# @private
# @return 0 always
###
__z::event::update_stats() {
  emulate -L zsh
  setopt localoptions no_unset

  [[ ${_zcore_config[event_enable_stats]} != true ]] && return 0

  local event_name="$1"
  local stat_type="$2"

  local key="${event_name}.${stat_type}"
  typeset -i current
  (( current = ${_zcore_event_stats[$key]:-0} + 1 ))
  _zcore_event_stats[$key]=$current

  return 0
}

###
# Remove handler by internal ID
# @param 1: string - Handler ID
# @private
# @return 0 always
###
__z::event::remove_handler_by_id() {
  emulate -L zsh
  setopt localoptions no_unset

  local handler_id="$1"

  local event_pattern="${_zcore_event_handler_meta[${handler_id}.event]:-}"
  [[ -z $event_pattern ]] && return 0

  # Determine which storage map and get handler list
  local handler_list
  if [[ $event_pattern == *'*'* ]]; then
    handler_list="${_zcore_event_handlers_wildcard[$event_pattern]:-}"
  else
    handler_list="${_zcore_event_handlers_exact[$event_pattern]:-}"
  fi

  if [[ -n $handler_list ]]; then
    local -a handlers
    __z::event::parse_handler_list "$handler_list" handlers

    # Filter out this handler
    handlers=("${(@)handlers:#$handler_id}")

    # Update or remove
    if (( ${#handlers} > 0 )); then
      if [[ $event_pattern == *'*'* ]]; then
        _zcore_event_handlers_wildcard[$event_pattern]="${(j:|:)handlers}"
      else
        _zcore_event_handlers_exact[$event_pattern]="${(j:|:)handlers}"
      fi
    else
      # Remove the key entirely
      if [[ $event_pattern == *'*'* ]]; then
        unset "_zcore_event_handlers_wildcard[${event_pattern}]"
      else
        unset "_zcore_event_handlers_exact[${event_pattern}]"
      fi
    fi
  fi

  # Remove metadata
  unset "_zcore_event_handler_meta[${handler_id}.function]"
  unset "_zcore_event_handler_meta[${handler_id}.priority]"
  unset "_zcore_event_handler_meta[${handler_id}.once]"
  unset "_zcore_event_handler_meta[${handler_id}.event]"

  return 0
}

###
# Subscribe to an event
#
# Usage:
#   z::event::subscribe "plugin:loaded" my_handler
#   z::event::subscribe "plugin:*" my_wildcard_handler
#   z::event::subscribe "app:start" my_handler --priority 100
#   z::event::subscribe "user:login" my_once_handler --once
#
# @param 1: string - Event name (supports wildcards with *)
# @param 2: string - Handler function name
# @param 3: string - --priority N (optional, default: 50)
# @param 4: string - --once (optional, handler runs only once)
# @return 0 on success, ZCORE_ERROR_* on failure
###
z::event::subscribe() {
  emulate -L zsh
  setopt localoptions no_unset warn_create_global

  local event_name="$1"
  local handler="$2"
  shift 2

  __z::event::validate_event_name "$event_name" || return $?
  __z::event::validate_handler "$handler" || return $?

  typeset -i priority=$ZCORE_EVENT_PRIORITY_NORMAL
  local once=false

  # Parse options
  while (( $# > 0 )); do
    case "$1" in
      --priority)
        z::validate::integer "${2:-}" "Priority" || return $ZCORE_ERROR_INVALID_INPUT
        (( priority = 10#${2} ))
        z::validate::integer::range "$priority" 0 100 "Priority" || return $ZCORE_ERROR_INVALID_INPUT
        shift 2
        ;;
      --once)
        once=true
        shift
        ;;
      *)
        z::log::warn "Unknown option: $1"
        shift
        ;;
    esac
  done

  # Determine which storage to use and get existing handlers
  local existing_handlers
  if [[ $event_name == *'*'* ]]; then
    # Wildcard pattern
    existing_handlers="${_zcore_event_handlers_wildcard[$event_name]:-}"
  else
    # Exact match
    existing_handlers="${_zcore_event_handlers_exact[$event_name]:-}"
  fi

  # Check handler limit
  local -a handler_array
  __z::event::parse_handler_list "$existing_handlers" handler_array

  typeset -i max_handlers
  (( max_handlers = ${_zcore_config[event_max_handlers_per_event]} ))

  if (( ${#handler_array} >= max_handlers )); then
    z::log::error "Maximum handlers ($max_handlers) reached for event: $event_name"
    return $ZCORE_ERROR_INVALID_INPUT
  fi

  # Generate unique ID and store metadata
  local handler_id
  __z::event::generate_id handler_id

  _zcore_event_handler_meta[${handler_id}.function]="$handler"
  _zcore_event_handler_meta[${handler_id}.priority]="$priority"
  _zcore_event_handler_meta[${handler_id}.once]="$once"
  _zcore_event_handler_meta[${handler_id}.event]="$event_name"

  # Append to handler list in appropriate storage
  local new_handler_list
  if [[ -n $existing_handlers ]]; then
    new_handler_list="${existing_handlers}|${handler_id}"
  else
    new_handler_list="$handler_id"
  fi

  if [[ $event_name == *'*'* ]]; then
    _zcore_event_handlers_wildcard[$event_name]="$new_handler_list"
  else
    _zcore_event_handlers_exact[$event_name]="$new_handler_list"
  fi

  z::log::debug "Subscribed handler '$handler' to event '$event_name' (id: $handler_id, priority: $priority, once: $once)"

  return 0
}

###
# Subscribe to an event (one-time handler)
#
# Usage:
#   z::event::subscribe_once "app:ready" my_init_handler
#   z::event::subscribe_once "app:ready" my_init_handler --priority 100
#
# @param 1: string - Event name
# @param 2: string - Handler function name
# @param ...: any - Additional options (--priority N)
# @return 0 on success, ZCORE_ERROR_* on failure
###
z::event::subscribe_once() {
  emulate -L zsh
  setopt localoptions no_unset

  z::event::subscribe "$1" "$2" "${@:3}" --once
}

###
# Emit an event and call all registered handlers
#
# Usage:
#   z::event::emit "plugin:loaded" "git-helper"
#   z::event::emit "user:login" "$username" "$timestamp"
#
# Handlers receive: handler_func <event_name> <args...>
#
# @param 1: string - Event name
# @param ...: any - Event arguments (passed to handlers after event name)
# @return 0 on success, 1 if any handler failed, 130 if interrupted
###
z::event::emit() {
  emulate -L zsh
  setopt localoptions no_unset warn_create_global

  local event_name="$1"
  shift

  __z::event::validate_event_name "$event_name" || return $?

  z::log::debug "Emitting event: $event_name (args: $#)"

  __z::event::update_stats "$event_name" "emitted"
  __z::event::add_to_history "$event_name" "$@"

  z::runtime::check_interrupted || return $?

  # Collect matching handlers
  local -a all_handler_ids
  local pattern handler_list

  # Fast path: exact match (O(1))
  handler_list="${_zcore_event_handlers_exact[$event_name]:-}"
  if [[ -n $handler_list ]]; then
    __z::event::parse_handler_list "$handler_list" all_handler_ids
  fi

  # Slow path: wildcard matching (O(n) where n = wildcard patterns)
  if [[ ${_zcore_config[event_enable_wildcards]} == true ]]; then
    for pattern in "${(@k)_zcore_event_handlers_wildcard}"; do
      if __z::event::match_pattern "$event_name" "$pattern"; then
        handler_list="${_zcore_event_handlers_wildcard[$pattern]:-}"
        if [[ -n $handler_list ]]; then
          local -a pattern_handlers
          __z::event::parse_handler_list "$handler_list" pattern_handlers
          all_handler_ids+=("${pattern_handlers[@]}")
        fi
      fi
    done
  fi

  if (( ${#all_handler_ids} == 0 )); then
    z::log::debug "No handlers registered for event: $event_name"
    return 0
  fi

  # Sort by priority
  __z::event::sort_handlers_by_priority all_handler_ids

  z::log::debug "Found ${#all_handler_ids} handler(s) for event: $event_name"

  typeset -i failed=0 handled=0
  local -a handlers_to_remove

  # Execute handlers
  local handler_id handler_func once_flag
  for handler_id in "${all_handler_ids[@]}"; do
    z::runtime::check_interrupted || return $?

    handler_func="${_zcore_event_handler_meta[${handler_id}.function]:-}"
    once_flag="${_zcore_event_handler_meta[${handler_id}.once]:-false}"

    if [[ -z $handler_func ]]; then
      z::log::warn "Handler metadata missing for ID: $handler_id"
      continue
    fi

    # Verify handler still exists
    if ! z::probe::func "$handler_func"; then
      z::log::warn "Handler function no longer exists: $handler_func"
      handlers_to_remove+=("$handler_id")
      continue
    fi

    z::log::debug "Calling handler: $handler_func (id: $handler_id)"

    # Execute handler with event name as first argument
    typeset -i exit_code=0
    {
      "$handler_func" "$event_name" "$@"
      exit_code=$?
    } always {
      # Ensure exit code is captured even on interrupt
      (( exit_code == 0 )) || true
    }

    if (( exit_code != 0 )); then
      (( failed += 1 ))
      z::log::warn "Handler '$handler_func' failed with exit code: $exit_code"
      __z::event::update_stats "$event_name" "failed"
    else
      (( handled += 1 ))
      __z::event::update_stats "$event_name" "handled"
    fi

    # Mark for removal if one-time handler
    if [[ $once_flag == true ]]; then
      handlers_to_remove+=("$handler_id")
      z::log::debug "One-time handler will be removed: $handler_func"
    fi
  done

  # Cleanup one-time handlers
  if (( ${#handlers_to_remove} > 0 )); then
    local remove_id
    for remove_id in "${handlers_to_remove[@]}"; do
      __z::event::remove_handler_by_id "$remove_id"
    done
  fi

  z::log::debug "Event '$event_name' completed: $handled handled, $failed failed"

  (( failed == 0 ))
}

###
# Emit an event with timeout protection (subshell overhead)
#
# Usage:
#   z::event::emit_safe "external:hook" "$untrusted_data"
#
# Handlers run in subshells with TMOUT protection.
# Note: Handlers cannot modify parent scope variables.
#
# @param 1: string - Event name
# @param ...: any - Event arguments
# @return 0 on success, 1 if any handler failed, ZCORE_ERROR_TIMEOUT if timeout
###
z::event::emit_safe() {
  emulate -L zsh
  setopt localoptions no_unset warn_create_global

  local event_name="$1"
  shift

  __z::event::validate_event_name "$event_name" || return $?

  z::log::debug "Emitting safe event: $event_name (args: $#)"

  __z::event::update_stats "$event_name" "emitted"
  __z::event::add_to_history "$event_name" "$@"

  z::runtime::check_interrupted || return $?

  # Collect matching handlers (same logic as emit)
  local -a all_handler_ids
  local pattern handler_list

  handler_list="${_zcore_event_handlers_exact[$event_name]:-}"
  if [[ -n $handler_list ]]; then
    __z::event::parse_handler_list "$handler_list" all_handler_ids
  fi

  if [[ ${_zcore_config[event_enable_wildcards]} == true ]]; then
    for pattern in "${(@k)_zcore_event_handlers_wildcard}"; do
      if __z::event::match_pattern "$event_name" "$pattern"; then
        handler_list="${_zcore_event_handlers_wildcard[$pattern]:-}"
        if [[ -n $handler_list ]]; then
          local -a pattern_handlers
          __z::event::parse_handler_list "$handler_list" pattern_handlers
          all_handler_ids+=("${pattern_handlers[@]}")
        fi
      fi
    done
  fi

  if (( ${#all_handler_ids} == 0 )); then
    z::log::debug "No handlers registered for event: $event_name"
    return 0
  fi

  __z::event::sort_handlers_by_priority all_handler_ids

  z::log::debug "Found ${#all_handler_ids} handler(s) for event: $event_name (safe mode)"

  typeset -i failed=0 handled=0 timeout_val
  (( timeout_val = ${_zcore_config[event_handler_timeout]} ))
  local -a handlers_to_remove

  local handler_id handler_func once_flag
  for handler_id in "${all_handler_ids[@]}"; do
    z::runtime::check_interrupted || return $?

    handler_func="${_zcore_event_handler_meta[${handler_id}.function]:-}"
    once_flag="${_zcore_event_handler_meta[${handler_id}.once]:-false}"

    if [[ -z $handler_func ]]; then
      z::log::warn "Handler metadata missing for ID: $handler_id"
      continue
    fi

    if ! z::probe::func "$handler_func"; then
      z::log::warn "Handler function no longer exists: $handler_func"
      handlers_to_remove+=("$handler_id")
      continue
    fi

    z::log::debug "Calling handler (safe): $handler_func (id: $handler_id, timeout: ${timeout_val}s)"

    # Execute in subshell with timeout
    typeset -i exit_code=0
    (
      TMOUT=$timeout_val
      "$handler_func" "$event_name" "$@"
    )
    exit_code=$?

    if (( exit_code == 142 )); then
      # SIGALRM - timeout
      (( failed += 1 ))
      z::log::error "Handler '$handler_func' timed out after ${timeout_val}s"
      __z::event::update_stats "$event_name" "failed"
    elif (( exit_code != 0 )); then
      (( failed += 1 ))
      z::log::warn "Handler '$handler_func' failed with exit code: $exit_code"
      __z::event::update_stats "$event_name" "failed"
    else
      (( handled += 1 ))
      __z::event::update_stats "$event_name" "handled"
    fi

    if [[ $once_flag == true ]]; then
      handlers_to_remove+=("$handler_id")
      z::log::debug "One-time handler will be removed: $handler_func"
    fi
  done

  if (( ${#handlers_to_remove} > 0 )); then
    local remove_id
    for remove_id in "${handlers_to_remove[@]}"; do
      __z::event::remove_handler_by_id "$remove_id"
    done
  fi

  z::log::debug "Safe event '$event_name' completed: $handled handled, $failed failed"

  (( failed == 0 ))
}

###
# Emit event asynchronously (non-blocking)
#
# Usage:
#   z::event::emit_async "metrics:updated" "$stats"
#
# Limitations:
# - No error reporting from handlers
# - No job tracking or cancellation
# - Arguments must be serializable
# - Potential resource exhaustion with high volume
# - Use sparingly for non-critical notifications
#
# @param 1: string - Event name
# @param ...: any - Event arguments
# @return 0 always (does not wait for handlers)
###
z::event::emit_async() {
  emulate -L zsh
  setopt localoptions no_unset

  local event_name="$1"
  shift

  __z::event::validate_event_name "$event_name" || return $?

  z::log::debug "Emitting async event: $event_name"

  # Background execution with cleanup
  {
    z::event::emit "$event_name" "$@"
  } &!

  return 0
}

###
# Unsubscribe from event(s)
#
# Usage:
#   z::event::unsubscribe "plugin:loaded" my_handler
#   z::event::unsubscribe "plugin:loaded"
#   z::event::unsubscribe "*" my_handler
#
# @param 1: string - Event name (supports wildcards)
# @param 2: string - Handler function name (optional, removes all if omitted)
# @return 0 on success, ZCORE_ERROR_* on failure
###
z::event::unsubscribe() {
  emulate -L zsh
  setopt localoptions no_unset

  local event_pattern="$1"
  local handler_func="${2:-}"

  __z::event::validate_event_name "$event_pattern" || return $?

  typeset -i removed=0
  local pattern handler_list

  # Check both storage maps
  local -a all_patterns
  all_patterns=(
    "${(@k)_zcore_event_handlers_exact}"
    "${(@k)_zcore_event_handlers_wildcard}"
  )

  for pattern in "${all_patterns[@]}"; do
    z::runtime::check_interrupted || return $?

    __z::event::match_pattern "$pattern" "$event_pattern" || continue

    # Get handler list from appropriate storage
    if [[ $pattern == *'*'* ]]; then
      handler_list="${_zcore_event_handlers_wildcard[$pattern]:-}"
    else
      handler_list="${_zcore_event_handlers_exact[$pattern]:-}"
    fi

    [[ -z $handler_list ]] && continue

    local -a handlers
    __z::event::parse_handler_list "$handler_list" handlers

    local handler_id stored_func
    for handler_id in "${handlers[@]}"; do
      stored_func="${_zcore_event_handler_meta[${handler_id}.function]:-}"

      if [[ -z $handler_func || $stored_func == $handler_func ]]; then
        __z::event::remove_handler_by_id "$handler_id"
        (( removed += 1 ))
        z::log::debug "Unsubscribed handler: $stored_func (id: $handler_id) from event: $pattern"
      fi
    done
  done

  if (( removed > 0 )); then
    z::log::debug "Unsubscribed $removed handler(s)"
  else
    z::log::debug "No handlers unsubscribed"
  fi

  return 0
}

###
# Check if event has registered handlers
#
# Usage:
#   if z::event::has_handlers "plugin:loaded"; then
#     z::log::info "Has handlers"
#   fi
#
# @param 1: string - Event name (supports wildcards)
# @return 0 if handlers exist, 1 if none
###
z::event::has_handlers() {
  emulate -L zsh
  setopt localoptions no_unset

  local event_name="$1"

  __z::event::validate_event_name "$event_name" || return 1

  # Check exact match
  [[ -n ${_zcore_event_handlers_exact[$event_name]:-} ]] && return 0

  # Check wildcards if enabled
  if [[ ${_zcore_config[event_enable_wildcards]} == true ]]; then
    local pattern
    for pattern in "${(@k)_zcore_event_handlers_wildcard}"; do
      if __z::event::match_pattern "$event_name" "$pattern"; then
        [[ -n ${_zcore_event_handlers_wildcard[$pattern]:-} ]] && return 0
      fi
    done
  fi

  return 1
}

###
# Count handlers for an event
#
# Usage:
#   count=$(z::event::count "plugin:loaded")
#   echo "Handlers: $count"
#
# @param 1: string - Event name (supports wildcards)
# @return 0 always, outputs count to stdout
###
z::event::count() {
  emulate -L zsh
  setopt localoptions no_unset

  local event_name="$1"

  __z::event::validate_event_name "$event_name" || { print 0; return 1; }

  typeset -i total=0
  local -a handlers
  local handler_list

  # Count exact match
  handler_list="${_zcore_event_handlers_exact[$event_name]:-}"
  if [[ -n $handler_list ]]; then
    __z::event::parse_handler_list "$handler_list" handlers
    (( total += ${#handlers} ))
  fi

  # Count wildcard matches
  if [[ ${_zcore_config[event_enable_wildcards]} == true ]]; then
    local pattern
    for pattern in "${(@k)_zcore_event_handlers_wildcard}"; do
      if __z::event::match_pattern "$event_name" "$pattern"; then
        handlers=()
        handler_list="${_zcore_event_handlers_wildcard[$pattern]:-}"
        if [[ -n $handler_list ]]; then
          __z::event::parse_handler_list "$handler_list" handlers
          (( total += ${#handlers} ))
        fi
      fi
    done
  fi

  print $total
  return 0
}

###
# List all registered event handlers
#
# Usage:
#   z::event::list
#   z::event::list "plugin:*"
#
# @param 1: string - Event pattern filter (optional)
# @return 0 always
###
z::event::list() {
  emulate -L zsh
  setopt localoptions no_unset no_xtrace no_verbose

  local filter_pattern="${1:-*}"

  print "\nRegistered Event Handlers:"
  print "=========================="

  typeset -i total=0

  # Declare ALL variables at function scope to prevent leakage
  local event_pattern handler_list
  local color_blue="${_zcore_colors[blue]:-}"
  local color_yellow="${_zcore_colors[yellow]:-}"
  local color_reset="${_zcore_colors[reset]:-}"
  local current_handler func_name priority_val once_val marker
  local -a all_events handlers
  typeset -i i

  # Collect all event patterns from both storage maps
  all_events=(
    "${(@k)_zcore_event_handlers_exact}"
    "${(@k)_zcore_event_handlers_wildcard}"
  )

  if (( ${#all_events} == 0 )); then
    print "No handlers registered.\n"
    return 0
  fi

  for event_pattern in "${all_events[@]}"; do
    __z::event::match_pattern "$event_pattern" "$filter_pattern" || continue

    # Get handler list from appropriate storage
    if [[ $event_pattern == *'*'* ]]; then
      handler_list="${_zcore_event_handlers_wildcard[$event_pattern]:-}"
    else
      handler_list="${_zcore_event_handlers_exact[$event_pattern]:-}"
    fi

    [[ -z $handler_list ]] && continue

    __z::event::parse_handler_list "$handler_list" handlers

    print "\nEvent: ${color_blue}${event_pattern}${color_reset}"
    print "  Handlers: ${#handlers}"

    # Process handlers with pre-declared variables
    for (( i = 1; i <= ${#handlers}; i++ )); do
      current_handler="${handlers[i]}"
      func_name="${_zcore_event_handler_meta[${current_handler}.function]:-unknown}"
      priority_val="${_zcore_event_handler_meta[${current_handler}.priority]:-50}"
      once_val="${_zcore_event_handler_meta[${current_handler}.once]:-false}"

      marker=""
      [[ $once_val == true ]] && marker=" ${color_yellow}[once]${color_reset}"

      print "    - ${func_name} (priority: ${priority_val})${marker}"
      (( total += 1 ))
    done
  done

  print "\nTotal handlers: $total\n"
  return 0
}

###
# Show event statistics
#
# Usage:
#   z::event::stats
#   z::event::stats "plugin:loaded"
#
# @param 1: string - Event name filter (optional)
# @return 0 always
###
z::event::stats() {
  emulate -L zsh
  setopt localoptions no_unset

  local filter="${1:-}"

  print "\nEvent Statistics:"
  print "================="

  if [[ ${_zcore_config[event_enable_stats]} != true ]]; then
    print "Statistics disabled.\n"
    return 0
  fi

  if (( ${#_zcore_event_stats} == 0 )); then
    print "No statistics available.\n"
    return 0
  fi

  # Collect unique event names
  local -a unique_events
  local key event_name

  for key in "${(@k)_zcore_event_stats}"; do
    event_name="${key%.*}"

    [[ -n $filter && $event_name != *${filter}* ]] && continue

    # Check if already processed
    (( ${unique_events[(Ie)$event_name]} )) && continue
    unique_events+=("$event_name")
  done

  if (( ${#unique_events} == 0 )); then
    print "No matching statistics.\n"
    return 0
  fi

  local color_blue="${_zcore_colors[blue]:-}"
  local color_reset="${_zcore_colors[reset]:-}"

  for event_name in "${unique_events[@]}"; do
    local emitted="${_zcore_event_stats[${event_name}.emitted]:-0}"
    local handled="${_zcore_event_stats[${event_name}.handled]:-0}"
    local failed="${_zcore_event_stats[${event_name}.failed]:-0}"

    print "\n${color_blue}${event_name}${color_reset}"
    print "  Emitted: $emitted"
    print "  Handled: $handled"
    print "  Failed:  $failed"
  done

  print ""
  return 0
}

###
# Show event history
#
# Usage:
#   z::event::history
#   z::event::history 20
#   z::event::history 10 "plugin:*"
#
# @param 1: integer - Number of recent events to show (optional, default: 20)
# @param 2: string - Event name filter (optional)
# @return 0 always
###
z::event::history() {
  emulate -L zsh
  setopt localoptions no_unset no_xtrace no_verbose

  typeset -i limit
  (( limit = 10#${1:-20} ))
  local filter="${2:-}"

  print "\nEvent History (last $limit):"
  print "============================"

  if [[ ${_zcore_config[event_enable_history]} != true ]]; then
    print "History disabled.\n"
    return 0
  fi

  if (( ${#_zcore_event_history} == 0 )); then
    print "No history available.\n"
    return 0
  fi

  # Get recent entries
  typeset -i start display_idx
  (( start = ${#_zcore_event_history} - limit + 1 ))
  (( start < 1 )) && (( start = 1 ))

  local -a recent_history
  recent_history=("${(@)_zcore_event_history[start,-1]}")

  # Declare ALL variables at function scope
  local color_blue="${_zcore_colors[blue]:-}"
  local color_reset="${_zcore_colors[reset]:-}"
  local entry ts remainder evt arg formatted_time

  # Display in reverse order (newest first)
  (( display_idx = ${#recent_history} ))

  for entry in "${(@Oa)recent_history}"; do
    z::runtime::check_interrupted || return $?

    ts="${entry%%|*}"
    remainder="${entry#*|}"
    evt="${remainder%%|*}"
    arg="${remainder#*|}"

    # Apply filter
    if [[ -n $filter ]]; then
      __z::event::match_pattern "$evt" "$filter" || { (( display_idx -= 1 )); continue; }
    fi

    # Format timestamp
    if [[ $ts == <-> ]]; then
      formatted_time=$(date -r "$ts" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || print "$ts")
    else
      formatted_time="$ts"
    fi

    print "${display_idx}. [${formatted_time}] ${color_blue}${evt}${color_reset}"
    [[ -n $arg ]] && print "   Args: $arg"

    (( display_idx -= 1 ))
  done

  print ""
  return 0
}

###
# Clear event history
#
# Usage:
#   z::event::clear_history
#
# @return 0 always
###
z::event::clear_history() {
  emulate -L zsh
  setopt localoptions no_unset

  _zcore_event_history=()
  z::log::info "Event history cleared"
  return 0
}

###
# Clear event statistics
#
# Usage:
#   z::event::clear_stats
#
# @return 0 always
###
z::event::clear_stats() {
  emulate -L zsh
  setopt localoptions no_unset

  _zcore_event_stats=()
  z::log::info "Event statistics cleared"
  return 0
}

###
# Reset entire event system
#
# Usage:
#   z::event::reset
#
# @return 0 always
###
z::event::reset() {
  emulate -L zsh
  setopt localoptions no_unset

  _zcore_event_handlers_exact=()
  _zcore_event_handlers_wildcard=()
  _zcore_event_handler_meta=()
  _zcore_event_history=()
  _zcore_event_stats=()
  (( _zcore_event_handler_id = 0 ))

  z::log::info "Event system reset"
  return 0
}

z::log::debug "Event system initialized"
################################################################################
# ZCORE KV STORE (KEY-VALUE DATABASE)
################################################################################
#
# A robust key-value store for zsh with:
#   - Namespaced keys (dot notation)
#   - Type-safe operations
#   - Persistence (save/load to disk)
#   - TTL (Time To Live) support
#   - Transactions
#   - Watch patterns (triggers events)
#   - Event integration
#   - Atomic operations
#   - Export/Import
#   - Statistics and introspection
#
# Version: 1.0.0
################################################################################

################################################################################
# KV STORE STATE
################################################################################

# Main key-value storage
typeset -gA _zcore_kv_store

# Metadata storage (TTL, types, etc.)
typeset -gA _zcore_kv_meta

# TTL expiration times (key -> epoch timestamp)
typeset -gA _zcore_kv_ttl

# Watch patterns and handlers
typeset -gA _zcore_kv_watchers

# Transaction state
typeset -gA _zcore_kv_transaction
typeset -gi _zcore_kv_in_transaction=0

# Statistics
typeset -gA _zcore_kv_stats=(
  [reads]=0
  [writes]=0
  [deletes]=0
  [hits]=0
  [misses]=0
)

# Configuration
typeset -gA _zcore_kv_config=(
  [auto_persist]=false
  [persist_file]=""
  [enable_events]=true
  [enable_ttl]=true
  [max_key_length]=256
  [max_value_length]=65536
)

################################################################################
# INTERNAL HELPERS
################################################################################

###
# Validate key format
# @param 1: string - Key name
# @private
# @return 0 if valid, 1 if invalid
###
__z::kv::validate_key() {
  emulate -L zsh
  local key="$1"

  if [[ -z $key ]]; then
    z::log::error "KV: Key cannot be empty"
    return 1
  fi

  if (( ${#key} > ${_zcore_kv_config[max_key_length]} )); then
    z::log::error "KV: Key too long: ${#key} > ${_zcore_kv_config[max_key_length]}"
    return 1
  fi

  # Allow alphanumeric, dots, underscores, hyphens, AND colons
  if [[ ! $key =~ '^[a-zA-Z0-9._:-]+$' ]]; then
    z::log::error "KV: Invalid key format: $key"
    return 1
  fi

  return 0
}

###
# Check and expire TTL keys
# @param 1: string - Key name
# @private
# @return 0 if valid, 1 if expired
###
__z::kv::check_ttl() {
  emulate -L zsh
  local key="$1"

  if [[ ${_zcore_kv_config[enable_ttl]} != true ]]; then
    return 0
  fi

  if (( ! ${+_zcore_kv_ttl[$key]} )); then
    return 0  # No TTL set
  fi

  typeset -i expire_time current_time
  (( expire_time = ${_zcore_kv_ttl[$key]} ))
  (( current_time = ${EPOCHSECONDS:-$(date +%s)} ))

  if (( current_time >= expire_time )); then
    # Key expired
    z::log::debug "KV: Key expired: $key"
    unset "_zcore_kv_store[$key]"
    unset "_zcore_kv_meta[$key]"
    unset "_zcore_kv_ttl[$key]"
    return 1
  fi

  return 0
}

###
# Trigger watch handlers for key pattern
# @param 1: string - Key that changed
# @param 2: string - New value
# @param 3: string - Operation (set|del)
# @private
# @return 0 always
###
__z::kv::trigger_watchers() {
  emulate -L zsh
  local key="$1"
  local value="$2"
  local operation="${3:-set}"

  if [[ ${_zcore_kv_config[enable_events]} != true ]]; then
    return 0
  fi

  # Emit generic KV event
  z::event::emit "kv:${operation}" "$key" "$value" 2>/dev/null || true

  # Check watch patterns
  local pattern handler_list
  for pattern in "${(@k)_zcore_kv_watchers}"; do
    # Match pattern (support wildcards)
    if [[ $key == ${~pattern} ]]; then
      handler_list="${_zcore_kv_watchers[$pattern]}"

      # Call each handler
      local -a handlers
      handlers=(${(s:|:)handler_list})

      local handler
      for handler in "${handlers[@]}"; do
        if z::probe::func "$handler" 2>/dev/null; then
          "$handler" "$key" "$value" "$operation" 2>/dev/null || true
        fi
      done
    fi
  done

  return 0
}

###
# Auto-persist if enabled
# @private
# @return 0 always
###
__z::kv::auto_persist() {
  emulate -L zsh

  if [[ ${_zcore_kv_config[auto_persist]} == true ]] && \
     [[ -n ${_zcore_kv_config[persist_file]} ]]; then
    z::kv::save "${_zcore_kv_config[persist_file]}" 2>/dev/null || true
  fi

  return 0
}

################################################################################
# CORE OPERATIONS
################################################################################

###
# Set a key-value pair
#
# Usage:
#   z::kv::set "app.name" "MyApp"
#   z::kv::set "counter" "42" --ttl 3600
#   z::kv::set "debug" "true" --type bool
#
# @param 1: string - Key name
# @param 2: string - Value
# @param 3: string - --ttl N (optional, seconds until expiration)
# @param 4: string - --type TYPE (optional, for metadata)
# @return 0 on success, 1 on failure
###
z::kv::set() {
  emulate -L zsh
  setopt localoptions no_unset

  local key="$1"
  local value="$2"
  shift 2

  # Validate key
  __z::kv::validate_key "$key" || return 1

  # Validate value length
  if (( ${#value} > ${_zcore_kv_config[max_value_length]} )); then
    z::log::error "KV: Value too long for key '$key': ${#value} > ${_zcore_kv_config[max_value_length]}"
    return 1
  fi

  # Parse options
  typeset -i ttl=0
  local value_type="string"

  while (( $# > 0 )); do
    case "$1" in
      --ttl)
        if [[ ${2:-} == <-> ]]; then
          (( ttl = 10#${2} ))
          shift 2
        else
          z::log::error "KV: Invalid TTL value: ${2:-}"
          return 1
        fi
        ;;
      --type)
        value_type="${2:-string}"
        shift 2
        ;;
      *)
        z::log::warn "KV: Unknown option: $1"
        shift
        ;;
    esac
  done

  # Store value
  _zcore_kv_store[$key]="$value"
  _zcore_kv_meta[$key]="$value_type"

  # Set TTL if specified
  if (( ttl > 0 )); then
    typeset -i expire_time
    (( expire_time = ${EPOCHSECONDS:-$(date +%s)} + ttl ))
    _zcore_kv_ttl[$key]=$expire_time
    z::log::debug "KV: Set TTL for '$key': ${ttl}s (expires at $expire_time)"
  else
    unset "_zcore_kv_ttl[$key]"
  fi

  # Update stats
  (( _zcore_kv_stats[writes] += 1 ))

  # Trigger watchers and events
  __z::kv::trigger_watchers "$key" "$value" "set"

  # Auto-persist
  __z::kv::auto_persist

  z::log::debug "KV: Set '$key' = '$value' (type: $value_type)"

  return 0
}

###
# Get a value by key
#
# Usage:
#   value=$(z::kv::get "app.name")
#   z::kv::get "counter" || echo "Key not found"
#
# @param 1: string - Key name
# @stdout Value if exists
# @return 0 if found, 1 if not found or expired
###
z::kv::get() {
  emulate -L zsh
  setopt localoptions no_unset

  local key="$1"

  # Validate key
  __z::kv::validate_key "$key" || return 1

  # Check TTL
  if ! __z::kv::check_ttl "$key"; then
    (( _zcore_kv_stats[misses] += 1 ))
    return 1
  fi

  # Check existence
  if (( ! ${+_zcore_kv_store[$key]} )); then
    (( _zcore_kv_stats[misses] += 1 ))
    z::log::debug "KV: Key not found: $key"
    return 1
  fi

  # Update stats
  (( _zcore_kv_stats[reads] += 1 ))
  (( _zcore_kv_stats[hits] += 1 ))

  # Return value
  print -r -- "${_zcore_kv_store[$key]}"
  return 0
}

###
# Delete a key
#
# Usage:
#   z::kv::del "app.name"
#
# @param 1: string - Key name
# @return 0 on success, 1 if key doesn't exist
###
z::kv::del() {
  emulate -L zsh
  setopt localoptions no_unset

  local key="$1"

  # Validate key
  __z::kv::validate_key "$key" || return 1

  # Check existence
  if (( ! ${+_zcore_kv_store[$key]} )); then
    z::log::debug "KV: Key not found for deletion: $key"
    return 1
  fi

  local old_value="${_zcore_kv_store[$key]}"

  # Delete
  unset "_zcore_kv_store[$key]"
  unset "_zcore_kv_meta[$key]"
  unset "_zcore_kv_ttl[$key]"

  # Update stats
  (( _zcore_kv_stats[deletes] += 1 ))

  # Trigger watchers
  __z::kv::trigger_watchers "$key" "$old_value" "del"

  # Auto-persist
  __z::kv::auto_persist

  z::log::debug "KV: Deleted '$key'"

  return 0
}

###
# Check if key exists
#
# Usage:
#   if z::kv::exists "app.name"; then
#     echo "Key exists"
#   fi
#
# @param 1: string - Key name
# @return 0 if exists and not expired, 1 otherwise
###
z::kv::exists() {
  emulate -L zsh
  setopt localoptions no_unset

  local key="$1"

  __z::kv::validate_key "$key" || return 1
  __z::kv::check_ttl "$key" || return 1

  (( ${+_zcore_kv_store[$key]} ))
}

###
# List all keys matching pattern
#
# Usage:
#   z::kv::keys              # All keys
#   z::kv::keys "app.*"      # Keys starting with "app."
#   z::kv::keys "*.config"   # Keys ending with ".config"
#
# @param 1: string - Pattern (optional, default: "*")
# @stdout List of matching keys (one per line)
# @return 0 always
###
z::kv::keys() {
  emulate -L zsh
  setopt localoptions no_unset extended_glob

  local pattern="${1:-*}"

  local key
  for key in "${(@k)_zcore_kv_store}"; do
    # Check TTL
    __z::kv::check_ttl "$key" || continue

    # Match pattern
    if [[ $key == ${~pattern} ]]; then
      print -r -- "$key"
    fi
  done

  return 0
}

################################################################################
# TYPE-SAFE OPERATIONS
################################################################################

###
# Set integer value
# @param 1: string - Key
# @param 2: integer - Value
# @return 0 on success, 1 on failure
###
z::kv::set_int() {
  emulate -L zsh
  local key="$1"
  local value="$2"

  if [[ $value != <-> && $value != -<-> ]]; then
    z::log::error "KV: Not an integer: $value"
    return 1
  fi

  z::kv::set "$key" "$value" --type int
}

###
# Get integer value
# @param 1: string - Key
# @stdout Integer value
# @return 0 on success, 1 on failure
###
z::kv::get_int() {
  emulate -L zsh
  local value
  value=$(z::kv::get "$1") || return 1

  if [[ $value != <-> && $value != -<-> ]]; then
    z::log::error "KV: Not an integer: $value"
    return 1
  fi

  print -r -- "$value"
  return 0
}

###
# Set boolean value
# @param 1: string - Key
# @param 2: bool - Value (true/false, 1/0, yes/no)
# @return 0 on success, 1 on failure
###
z::kv::set_bool() {
  emulate -L zsh
  local key="$1"
  local value="$2"

  # Normalize boolean
  case "${value:l}" in
    true|1|yes|y|on) value="true" ;;
    false|0|no|n|off) value="false" ;;
    *)
      z::log::error "KV: Invalid boolean: $value"
      return 1
      ;;
  esac

  z::kv::set "$key" "$value" --type bool
}

###
# Get boolean value
# @param 1: string - Key
# @stdout "true" or "false"
# @return 0 if true, 1 if false or not found
###
z::kv::get_bool() {
  emulate -L zsh
  local value
  value=$(z::kv::get "$1") || return 1

  case "${value:l}" in
    true|1|yes|y|on)
      print "true"
      return 0
      ;;
    false|0|no|n|off)
      print "false"
      return 1
      ;;
    *)
      z::log::error "KV: Not a boolean: $value"
      return 1
      ;;
  esac
}

###
# Set array value (pipe-separated internally)
# @param 1: string - Key
# @param ...: string - Array elements
# @return 0 on success
###
z::kv::set_array() {
  emulate -L zsh
  local key="$1"
  shift

  local value="${(j:|:)@}"
  z::kv::set "$key" "$value" --type array
}

###
# Get array value
# @param 1: string - Key
# @param 2: string - Output array variable name
# @return 0 on success, 1 on failure
###
z::kv::get_array() {
  emulate -L zsh
  local key="$1"
  local output_var="$2"

  local value
  value=$(z::kv::get "$key") || return 1

  # Split by pipe and assign to array
  eval "${output_var}=(\"\${(@s:|:)value}\")"
  return 0
}

################################################################################
# ATOMIC OPERATIONS
################################################################################

###
# Increment integer value
# @param 1: string - Key
# @param 2: integer - Amount (optional, default: 1)
# @return 0 on success, 1 on failure
###
z::kv::incr() {
  emulate -L zsh
  local key="$1"
  typeset -i amount
  (( amount = ${2:-1} ))

  typeset -i current
  if z::kv::exists "$key"; then
    current=$(z::kv::get_int "$key") || current=0
  else
    current=0
  fi

  (( current += amount ))
  z::kv::set_int "$key" "$current"
}

###
# Decrement integer value
# @param 1: string - Key
# @param 2: integer - Amount (optional, default: 1)
# @return 0 on success, 1 on failure
###
z::kv::decr() {
  emulate -L zsh
  local key="$1"
  typeset -i amount
  (( amount = ${2:-1} ))

  z::kv::incr "$key" $(( -amount ))
}

###
# Append to string value
# @param 1: string - Key
# @param 2: string - Value to append
# @return 0 on success
###
z::kv::append() {
  emulate -L zsh
  local key="$1"
  local append_value="$2"

  local current=""
  if z::kv::exists "$key"; then
    current=$(z::kv::get "$key")
  fi

  z::kv::set "$key" "${current}${append_value}"
}

################################################################################
# TTL OPERATIONS
################################################################################

###
# Get remaining TTL for key
# @param 1: string - Key
# @stdout Remaining seconds (-1 if no TTL, -2 if not found)
# @return 0 always
###
z::kv::ttl() {
  emulate -L zsh
  local key="$1"

  if ! z::kv::exists "$key"; then
    print -- "-2"
    return 0
  fi

  if (( ! ${+_zcore_kv_ttl[$key]} )); then
    print -- "-1"  # No TTL
    return 0
  fi

  typeset -i expire_time current_time remaining
  (( expire_time = ${_zcore_kv_ttl[$key]} ))
  (( current_time = ${EPOCHSECONDS:-$(date +%s)} ))
  (( remaining = expire_time - current_time ))

  if (( remaining < 0 )); then
    remaining=0
  fi

  print -- "$remaining"
  return 0
}

###
# Set TTL for existing key
# @param 1: string - Key
# @param 2: integer - TTL in seconds
# @return 0 on success, 1 if key doesn't exist
###
z::kv::expire() {
  emulate -L zsh
  local key="$1"
  typeset -i ttl
  (( ttl = ${2:-0} ))

  if ! z::kv::exists "$key"; then
    z::log::error "KV: Cannot set TTL on non-existent key: $key"
    return 1
  fi

  if (( ttl <= 0 )); then
    unset "_zcore_kv_ttl[$key]"
    z::log::debug "KV: Removed TTL from '$key'"
  else
    typeset -i expire_time
    (( expire_time = ${EPOCHSECONDS:-$(date +%s)} + ttl ))
    _zcore_kv_ttl[$key]=$expire_time
    z::log::debug "KV: Set TTL for '$key': ${ttl}s"
  fi

  return 0
}

###
# Remove TTL from key (make it persistent)
# @param 1: string - Key
# @return 0 on success
###
z::kv::persist() {
  emulate -L zsh
  local key="$1"

  unset "_zcore_kv_ttl[$key]"
  z::log::debug "KV: Made key persistent: $key"
  return 0
}

################################################################################
# PERSISTENCE
################################################################################

###
# Save KV store to file
#
# Usage:
#   z::kv::save "/tmp/app.db"
#
# @param 1: string - File path
# @return 0 on success, 1 on failure
###
z::kv::save() {
  emulate -L zsh
  setopt localoptions no_unset

  local file="$1"

  if [[ -z $file ]]; then
    z::log::error "KV: No file specified for save"
    return 1
  fi

  z::log::info "KV: Saving to $file"

  {
    print "# ZCORE KV Store Dump"
    print "# Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    print "# Version: 1.0"
    print ""

    local key value value_type
    typeset -i ttl_remaining

    for key in "${(@k)_zcore_kv_store}"; do
      # Skip expired keys
      __z::kv::check_ttl "$key" || continue

      value="${_zcore_kv_store[$key]}"
      value_type="${_zcore_kv_meta[$key]:-string}"

      # Escape special characters
      value="${value//\\/\\\\}"
      value="${value//$'\n'/\\n}"
      value="${value//|/\\|}"

      # Get TTL
      ttl_remaining=$(z::kv::ttl "$key")

      # Format: key|type|ttl|value
      print "${key}|${value_type}|${ttl_remaining}|${value}"
    done
  } > "$file"

  z::log::info "KV: Saved ${#_zcore_kv_store} keys to $file"
  return 0
}

###
# Load KV store from file
#
# Usage:
#   z::kv::load "/tmp/app.db"
#
# @param 1: string - File path
# @return 0 on success, 1 on failure
###
z::kv::load() {
  emulate -L zsh
  setopt localoptions no_unset

  local file="$1"

  if [[ -z $file ]]; then
    z::log::error "KV: No file specified for load"
    return 1
  fi

  if [[ ! -f $file || ! -r $file ]]; then
    z::log::error "KV: Cannot read file: $file"
    return 1
  fi

  z::log::info "KV: Loading from $file"

  typeset -i loaded=0
  local line key value_type ttl_val value

  while IFS= read -r line; do
    # Skip comments and empty lines
    [[ $line =~ '^[[:space:]]*(#.*)?$' ]] && continue

    # Parse: key|type|ttl|value
    key="${line%%|*}"
    local rest="${line#*|}"
    value_type="${rest%%|*}"
    rest="${rest#*|}"
    ttl_val="${rest%%|*}"
    value="${rest#*|}"

    # Unescape special characters
    value="${value//\\n/$'\n'}"
    value="${value//\\\\/\\}"
    value="${value//\\|/|}"

    # Set value
    if [[ $ttl_val == <-> ]] && (( ttl_val > 0 )); then
      z::kv::set "$key" "$value" --type "$value_type" --ttl "$ttl_val"
    else
      z::kv::set "$key" "$value" --type "$value_type"
    fi

    (( loaded += 1 ))
  done < "$file"

  z::log::info "KV: Loaded $loaded keys from $file"
  return 0
}

################################################################################
# WATCH PATTERNS
################################################################################

###
# Watch keys matching pattern
#
# Usage:
#   z::kv::watch "config.*" my_handler
#   my_handler() {
#     local key="$1" value="$2" operation="$3"
#     echo "Changed: $key = $value ($operation)"
#   }
#
# @param 1: string - Key pattern (supports wildcards)
# @param 2: string - Handler function name
# @return 0 on success
###
z::kv::watch() {
  emulate -L zsh
  local pattern="$1"
  local handler="$2"

  if [[ -z $pattern || -z $handler ]]; then
    z::log::error "KV: watch requires pattern and handler"
    return 1
  fi

  if ! z::probe::func "$handler"; then
    z::log::error "KV: Handler function not found: $handler"
    return 1
  fi

  # Add handler to pattern
  local existing="${_zcore_kv_watchers[$pattern]:-}"
  if [[ -n $existing ]]; then
    _zcore_kv_watchers[$pattern]="${existing}|${handler}"
  else
    _zcore_kv_watchers[$pattern]="$handler"
  fi

  z::log::debug "KV: Watching pattern '$pattern' with handler '$handler'"
  return 0
}

###
# Stop watching pattern
# @param 1: string - Key pattern
# @param 2: string - Handler function name (optional, removes all if omitted)
# @return 0 on success
###
z::kv::unwatch() {
  emulate -L zsh
  local pattern="$1"
  local handler="${2:-}"

  if [[ -z $pattern ]]; then
    z::log::error "KV: unwatch requires pattern"
    return 1
  fi

  if [[ -z $handler ]]; then
    # Remove all handlers for pattern
    unset "_zcore_kv_watchers[$pattern]"
    z::log::debug "KV: Removed all watchers for pattern '$pattern'"
  else
    # Remove specific handler
    local existing="${_zcore_kv_watchers[$pattern]:-}"
    if [[ -n $existing ]]; then
      local -a handlers
      handlers=(${(s:|:)existing})
      handlers=(${(@)handlers:#$handler})

      if (( ${#handlers} > 0 )); then
        _zcore_kv_watchers[$pattern]="${(j:|:)handlers}"
      else
        unset "_zcore_kv_watchers[$pattern]"
      fi

      z::log::debug "KV: Removed watcher '$handler' from pattern '$pattern'"
    fi
  fi

  return 0
}

################################################################################
# BULK OPERATIONS
################################################################################

###
# Set multiple key-value pairs
# @param ...: string - Alternating keys and values
# @return 0 on success
###
z::kv::mset() {
  emulate -L zsh

  if (( $# % 2 != 0 )); then
    z::log::error "KV: mset requires even number of arguments (key value pairs)"
    return 1
  fi

  while (( $# >= 2 )); do
    z::kv::set "$1" "$2" || return 1
    shift 2
  done

  return 0
}

###
# Get multiple values
# @param ...: string - Keys
# @stdout Values (one per line, empty line if not found)
# @return 0 always
###
z::kv::mget() {
  emulate -L zsh

  local key value
  for key in "$@"; do
    if value=$(z::kv::get "$key" 2>/dev/null); then
      print -r -- "$value"
    else
      print ""
    fi
  done

  return 0
}

###
# Clear all keys matching pattern
# @param 1: string - Pattern (optional, default: "*" = all keys)
# @return 0 always
###
z::kv::clear() {
  emulate -L zsh
  local pattern="${1:-*}"

  local -a keys_to_delete
  keys_to_delete=($(z::kv::keys "$pattern"))

  typeset -i deleted=0
  local key
  for key in "${keys_to_delete[@]}"; do
    z::kv::del "$key" && (( deleted += 1 ))
  done

  z::log::info "KV: Cleared $deleted keys matching '$pattern'"
  return 0
}

################################################################################
# TRANSACTIONS
################################################################################

###
# Begin transaction
# @return 0 on success, 1 if already in transaction
###
z::kv::begin() {
  emulate -L zsh

  if (( _zcore_kv_in_transaction )); then
    z::log::error "KV: Already in transaction"
    return 1
  fi

  # Backup current state using a better format
  local -a store_backup meta_backup ttl_backup

  local key value
  for key value in "${(@kv)_zcore_kv_store}"; do
    store_backup+=("$key")
    store_backup+=("$value")
  done

  for key value in "${(@kv)_zcore_kv_meta}"; do
    meta_backup+=("$key")
    meta_backup+=("$value")
  done

  for key value in "${(@kv)_zcore_kv_ttl}"; do
    ttl_backup+=("$key")
    ttl_backup+=("$value")
  done

  _zcore_kv_transaction[store]="${(F)store_backup}"
  _zcore_kv_transaction[meta]="${(F)meta_backup}"
  _zcore_kv_transaction[ttl]="${(F)ttl_backup}"

  (( _zcore_kv_in_transaction = 1 ))
  z::log::debug "KV: Transaction started"
  return 0
}

###
# Commit transaction
# @return 0 on success
###
z::kv::commit() {
  emulate -L zsh

  if (( ! _zcore_kv_in_transaction )); then
    z::log::warn "KV: Not in transaction"
    return 0
  fi

  # Clear backup
  _zcore_kv_transaction=()
  (( _zcore_kv_in_transaction = 0 ))

  z::log::debug "KV: Transaction committed"
  return 0
}

###
# Rollback transaction
# @return 0 on success
###
z::kv::rollback() {
  emulate -L zsh

  if (( ! _zcore_kv_in_transaction )); then
    z::log::warn "KV: Not in transaction"
    return 0
  fi

  # Parse and restore backup
  local backup_store="${_zcore_kv_transaction[store]}"
  local backup_meta="${_zcore_kv_transaction[meta]}"
  local backup_ttl="${_zcore_kv_transaction[ttl]}"

  # Clear current state
  _zcore_kv_store=()
  _zcore_kv_meta=()
  _zcore_kv_ttl=()

  # Restore store
  if [[ -n $backup_store ]]; then
    local -a lines
    lines=("${(@f)backup_store}")

    typeset -i i
    for (( i = 1; i <= ${#lines}; i += 2 )); do
      local key="${lines[i]}"
      local value="${lines[i+1]}"
      [[ -n $key ]] && _zcore_kv_store[$key]="$value"
    done
  fi

  # Restore meta
  if [[ -n $backup_meta ]]; then
    local -a lines
    lines=("${(@f)backup_meta}")

    typeset -i i
    for (( i = 1; i <= ${#lines}; i += 2 )); do
      local key="${lines[i]}"
      local value="${lines[i+1]}"
      [[ -n $key ]] && _zcore_kv_meta[$key]="$value"
    done
  fi

  # Restore TTL
  if [[ -n $backup_ttl ]]; then
    local -a lines
    lines=("${(@f)backup_ttl}")

    typeset -i i
    for (( i = 1; i <= ${#lines}; i += 2 )); do
      local key="${lines[i]}"
      local value="${lines[i+1]}"
      [[ -n $key ]] && _zcore_kv_ttl[$key]="$value"
    done
  fi

  _zcore_kv_transaction=()
  (( _zcore_kv_in_transaction = 0 ))

  z::log::debug "KV: Transaction rolled back"
  return 0
}
################################################################################
# INTROSPECTION & STATISTICS
################################################################################

###
# Get KV store statistics
# @return 0 always
###
z::kv::stats() {
  emulate -L zsh

  print "\nKV Store Statistics:"
  print "===================="

  typeset -i total_keys active_keys expired_keys
  (( total_keys = ${#_zcore_kv_store} ))

  # Count active keys (non-expired)
  active_keys=0
  expired_keys=0
  local key
  for key in "${(@k)_zcore_kv_store}"; do
    if __z::kv::check_ttl "$key"; then
      (( active_keys += 1 ))
    else
      (( expired_keys += 1 ))
    fi
  done

  print "Total Keys:     $total_keys"
  print "Active Keys:    $active_keys"
  print "Expired Keys:   $expired_keys"
  print ""
  print "Operations:"
  print "  Reads:        ${_zcore_kv_stats[reads]}"
  print "  Writes:       ${_zcore_kv_stats[writes]}"
  print "  Deletes:      ${_zcore_kv_stats[deletes]}"
  print "  Cache Hits:   ${_zcore_kv_stats[hits]}"
  print "  Cache Misses: ${_zcore_kv_stats[misses]}"

  if (( _zcore_kv_stats[reads] > 0 )); then
    typeset -F hit_rate
    (( hit_rate = (_zcore_kv_stats[hits] * 100.0) / _zcore_kv_stats[reads] ))
    print "  Hit Rate:     ${hit_rate}%"
  fi

  print ""
  print "Watchers:       ${#_zcore_kv_watchers}"
  print "Auto-persist:   ${_zcore_kv_config[auto_persist]}"

  if [[ -n ${_zcore_kv_config[persist_file]} ]]; then
    print "Persist File:   ${_zcore_kv_config[persist_file]}"
  fi

  print ""
  return 0
}

###
# Get total number of keys
# @stdout Number of keys
# @return 0 always
###
z::kv::size() {
  emulate -L zsh
  print -- "${#_zcore_kv_store}"
  return 0
}

###
# Export all data in human-readable format
# @stdout All key-value pairs
# @return 0 always
###
z::kv::export() {
  emulate -L zsh

  print "# ZCORE KV Store Export"
  print "# $(date '+%Y-%m-%d %H:%M:%S')"
  print ""

  local key value value_type
  for key in "${(@k)_zcore_kv_store}"; do
    __z::kv::check_ttl "$key" || continue

    value="${_zcore_kv_store[$key]}"
    value_type="${_zcore_kv_meta[$key]:-string}"

    print "${key} (${value_type}) = ${value}"
  done

  return 0
}

###
# Configure KV store
# @param 1: string - Config key
# @param 2: string - Config value
# @return 0 on success
###
z::kv::config() {
  emulate -L zsh
  local key="$1"
  local value="$2"

  if (( ! ${+_zcore_kv_config[$key]} )); then
    z::log::error "KV: Unknown config key: $key"
    return 1
  fi

  _zcore_kv_config[$key]="$value"
  z::log::debug "KV: Config updated: $key = $value"
  return 0
}

###
# Enable auto-persistence
# @param 1: string - File path
# @return 0 on success
###
z::kv::enable_persist() {
  emulate -L zsh
  local file="$1"

  if [[ -z $file ]]; then
    z::log::error "KV: Persist file path required"
    return 1
  fi

  _zcore_kv_config[auto_persist]=true
  _zcore_kv_config[persist_file]="$file"

  z::log::info "KV: Auto-persistence enabled: $file"
  return 0
}

###
# Disable auto-persistence
# @return 0 always
###
z::kv::disable_persist() {
  emulate -L zsh

  _zcore_kv_config[auto_persist]=false
  z::log::info "KV: Auto-persistence disabled"
  return 0
}

################################################################################
# INITIALIZATION
################################################################################

z::log::debug "KV Store initialized"
################################################################################
# ZCORE KV STORE - ADVANCED FEATURES
################################################################################
#
# Advanced data structures and operations:
#   - Lists (LPUSH, RPUSH, LPOP, RPOP, LRANGE)
#   - Sets (SADD, SREM, SMEMBERS, SISMEMBER)
#   - Sorted Sets (ZADD, ZREM, ZRANGE, ZSCORE)
#   - Hashes (HSET, HGET, HGETALL, HDEL)
#   - Atomic operations (GETSET, SETNX)
#   - Pub/Sub channels
#   - Distributed locking
#   - Batch operations
#   - Conditional updates
#   - Snapshots
#
################################################################################

################################################################################
# ADVANCED STATE
################################################################################

# List storage: key -> pipe-separated values
typeset -gA _zcore_kv_lists

# Set storage: key -> pipe-separated unique values
typeset -gA _zcore_kv_sets

# Sorted set storage: key -> pipe-separated "score:value" pairs
typeset -gA _zcore_kv_zsets

# Hash storage: key.field -> value
typeset -gA _zcore_kv_hashes

# Pub/Sub channels: channel -> subscriber_list
typeset -gA _zcore_kv_pubsub

# Locks: lock_name -> owner_id|expire_time
typeset -gA _zcore_kv_locks

# Snapshot storage
typeset -gA _zcore_kv_snapshots
typeset -gi _zcore_kv_snapshot_id=0

################################################################################
# LIST OPERATIONS (Like Redis Lists)
################################################################################

###
# Push value to left (head) of list
#
# Usage:
#   z::kv::lpush "mylist" "item1"
#   z::kv::lpush "mylist" "item2"  # List is now: item2, item1
#
# @param 1: string - List key
# @param 2: string - Value to push
# @return 0 on success
###
z::kv::lpush() {
  emulate -L zsh
  local key="$1"
  local value="$2"

  __z::kv::validate_key "$key" || return 1

  local existing="${_zcore_kv_lists[$key]:-}"

  if [[ -n $existing ]]; then
    _zcore_kv_lists[$key]="${value}|${existing}"
  else
    _zcore_kv_lists[$key]="$value"
  fi

  z::log::debug "KV: LPUSH '$key' <- '$value'"
  __z::kv::trigger_watchers "$key" "$value" "lpush"

  return 0
}

###
# Push value to right (tail) of list
#
# Usage:
#   z::kv::rpush "mylist" "item1"
#   z::kv::rpush "mylist" "item2"  # List is now: item1, item2
#
# @param 1: string - List key
# @param 2: string - Value to push
# @return 0 on success
###
z::kv::rpush() {
  emulate -L zsh
  local key="$1"
  local value="$2"

  __z::kv::validate_key "$key" || return 1

  local existing="${_zcore_kv_lists[$key]:-}"

  if [[ -n $existing ]]; then
    _zcore_kv_lists[$key]="${existing}|${value}"
  else
    _zcore_kv_lists[$key]="$value"
  fi

  z::log::debug "KV: RPUSH '$key' <- '$value'"
  __z::kv::trigger_watchers "$key" "$value" "rpush"

  return 0
}

###
# Pop value from left (head) of list
#
# Usage:
#   value=$(z::kv::lpop "mylist")
#
# @param 1: string - List key
# @stdout Popped value
# @return 0 on success, 1 if list empty or not found
###
z::kv::lpop() {
  emulate -L zsh
  setopt localoptions no_unset

  local key="$1"

  __z::kv::validate_key "$key" || return 1

  local existing="${_zcore_kv_lists[$key]:-}"

  if [[ -z $existing ]]; then
    z::log::debug "KV: LPOP '$key' - list empty or not found"
    return 1
  fi

  # Split into array
  local -a items
  items=("${(@s:|:)existing}")

  if (( ${#items} == 0 )); then
    z::log::debug "KV: LPOP '$key' - list empty"
    return 1
  fi

  # Get first item
  local popped="${items[1]}"

  # Remove first item and rebuild list
  if (( ${#items} > 1 )); then
    items=("${(@)items[2,-1]}")
    _zcore_kv_lists[$key]="${(j:|:)items}"
  else
    # List is now empty
    unset "_zcore_kv_lists[$key]"
  fi

  z::log::debug "KV: LPOP '$key' -> '$popped' (${#items} remaining)"
  print -r -- "$popped"

  return 0
}
###
# Pop value from right (tail) of list
#
# Usage:
#   value=$(z::kv::rpop "mylist")
#
# @param 1: string - List key
# @stdout Popped value
# @return 0 on success, 1 if list empty or not found
###
z::kv::rpop() {
  emulate -L zsh
  setopt localoptions no_unset

  local key="$1"

  __z::kv::validate_key "$key" || return 1

  local existing="${_zcore_kv_lists[$key]:-}"

  if [[ -z $existing ]]; then
    z::log::debug "KV: RPOP '$key' - list empty or not found"
    return 1
  fi

  # Split into array
  local -a items
  items=("${(@s:|:)existing}")

  if (( ${#items} == 0 )); then
    z::log::debug "KV: RPOP '$key' - list empty"
    return 1
  fi

  # Get last item
  local popped="${items[-1]}"

  # Remove last item and rebuild list
  if (( ${#items} > 1 )); then
    items=("${(@)items[1,-2]}")
    _zcore_kv_lists[$key]="${(j:|:)items}"
  else
    # List is now empty
    unset "_zcore_kv_lists[$key]"
  fi

  z::log::debug "KV: RPOP '$key' -> '$popped' (${#items} remaining)"
  print -r -- "$popped"

  return 0
}
###
# Get range of list elements
#
# Usage:
#   z::kv::lrange "mylist" 0 -1     # All elements
#   z::kv::lrange "mylist" 0 2      # First 3 elements
#   z::kv::lrange "mylist" -3 -1    # Last 3 elements
#
# @param 1: string - List key
# @param 2: integer - Start index (0-based, negative from end)
# @param 3: integer - Stop index (inclusive)
# @stdout List elements (one per line)
# @return 0 on success
###
z::kv::lrange() {
  emulate -L zsh
  local key="$1"
  typeset -i start stop
  (( start = ${2:-0} ))
  (( stop = ${3:--1} ))

  __z::kv::validate_key "$key" || return 1

  local existing="${_zcore_kv_lists[$key]:-}"

  if [[ -z $existing ]]; then
    return 0
  fi

  local -a items
  items=("${(@s:|:)existing}")

  # Handle negative indices
  if (( start < 0 )); then
    (( start = ${#items} + start + 1 ))
  else
    (( start += 1 ))  # Convert to 1-based
  fi

  if (( stop < 0 )); then
    (( stop = ${#items} + stop + 1 ))
  else
    (( stop += 1 ))  # Convert to 1-based
  fi

  # Bounds checking
  (( start < 1 )) && (( start = 1 ))
  (( stop > ${#items} )) && (( stop = ${#items} ))

  if (( start <= stop )); then
    print -l -- "${(@)items[start,stop]}"
  fi

  return 0
}

###
# Get list length
#
# Usage:
#   length=$(z::kv::llen "mylist")
#
# @param 1: string - List key
# @stdout List length
# @return 0 always
###
z::kv::llen() {
  emulate -L zsh
  local key="$1"

  local existing="${_zcore_kv_lists[$key]:-}"

  if [[ -z $existing ]]; then
    print "0"
    return 0
  fi

  local -a items
  items=("${(@s:|:)existing}")

  print "${#items}"
  return 0
}

################################################################################
# SET OPERATIONS (Unique Values)
################################################################################

###
# Add member to set
#
# Usage:
#   z::kv::sadd "myset" "value1"
#   z::kv::sadd "myset" "value2"
#   z::kv::sadd "myset" "value1"  # Ignored (already exists)
#
# @param 1: string - Set key
# @param 2: string - Value to add
# @return 0 if added, 1 if already exists
###
z::kv::sadd() {
  emulate -L zsh
  local key="$1"
  local value="$2"

  __z::kv::validate_key "$key" || return 1

  local existing="${_zcore_kv_sets[$key]:-}"

  # Check if already exists
  if [[ -n $existing ]]; then
    local -a members
    members=("${(@s:|:)existing}")

    if (( ${members[(Ie)$value]} )); then
      z::log::debug "KV: SADD '$key' - '$value' already exists"
      return 1
    fi

    _zcore_kv_sets[$key]="${existing}|${value}"
  else
    _zcore_kv_sets[$key]="$value"
  fi

  z::log::debug "KV: SADD '$key' <- '$value'"
  __z::kv::trigger_watchers "$key" "$value" "sadd"

  return 0
}

###
# Remove member from set
#
# Usage:
#   z::kv::srem "myset" "value1"
#
# @param 1: string - Set key
# @param 2: string - Value to remove
# @return 0 if removed, 1 if not found
###
z::kv::srem() {
  emulate -L zsh
  local key="$1"
  local value="$2"

  __z::kv::validate_key "$key" || return 1

  local existing="${_zcore_kv_sets[$key]:-}"

  if [[ -z $existing ]]; then
    return 1
  fi

  local -a members
  members=("${(@s:|:)existing}")

  # Remove value
  members=("${(@)members:#$value}")

  if (( ${#members} > 0 )); then
    _zcore_kv_sets[$key]="${(j:|:)members}"
  else
    unset "_zcore_kv_sets[$key]"
  fi

  z::log::debug "KV: SREM '$key' <- '$value'"

  return 0
}

###
# Check if member exists in set
#
# Usage:
#   if z::kv::sismember "myset" "value1"; then
#     echo "Value exists"
#   fi
#
# @param 1: string - Set key
# @param 2: string - Value to check
# @return 0 if exists, 1 if not
###
z::kv::sismember() {
  emulate -L zsh
  local key="$1"
  local value="$2"

  local existing="${_zcore_kv_sets[$key]:-}"

  if [[ -z $existing ]]; then
    return 1
  fi

  local -a members
  members=("${(@s:|:)existing}")

  (( ${members[(Ie)$value]} ))
}

###
# Get all set members
#
# Usage:
#   z::kv::smembers "myset"
#
# @param 1: string - Set key
# @stdout Set members (one per line)
# @return 0 always
###
z::kv::smembers() {
  emulate -L zsh
  local key="$1"

  local existing="${_zcore_kv_sets[$key]:-}"

  if [[ -z $existing ]]; then
    return 0
  fi

  local -a members
  members=("${(@s:|:)existing}")

  print -l -- "${members[@]}"
  return 0
}

###
# Get set cardinality (size)
#
# Usage:
#   size=$(z::kv::scard "myset")
#
# @param 1: string - Set key
# @stdout Set size
# @return 0 always
###
z::kv::scard() {
  emulate -L zsh
  local key="$1"

  local existing="${_zcore_kv_sets[$key]:-}"

  if [[ -z $existing ]]; then
    print "0"
    return 0
  fi

  local -a members
  members=("${(@s:|:)existing}")

  print "${#members}"
  return 0
}

################################################################################
# SORTED SET OPERATIONS (Score-based ordering)
################################################################################

###
# Add member to sorted set with score
#
# Usage:
#   z::kv::zadd "leaderboard" 100 "player1"
#   z::kv::zadd "leaderboard" 200 "player2"
#
# @param 1: string - Sorted set key
# @param 2: number - Score
# @param 3: string - Member
# @return 0 on success
###
z::kv::zadd() {
  emulate -L zsh
  local key="$1"
  typeset -F score
  (( score = ${2} ))
  local member="$3"

  __z::kv::validate_key "$key" || return 1

  local existing="${_zcore_kv_zsets[$key]:-}"
  local -a items

  if [[ -n $existing ]]; then
    items=("${(@s:|:)existing}")

    # Remove existing member if present
    local -a filtered
    local item
    for item in "${items[@]}"; do
      local item_member="${item#*:}"
      if [[ $item_member != $member ]]; then
        filtered+=("$item")
      fi
    done
    items=("${filtered[@]}")
  fi

  # Add new scored member
  items+=("${score}:${member}")

  _zcore_kv_zsets[$key]="${(j:|:)items}"

  z::log::debug "KV: ZADD '$key' <- $score:$member"
  __z::kv::trigger_watchers "$key" "$member" "zadd"

  return 0
}

###
# Get score of member in sorted set
#
# Usage:
#   score=$(z::kv::zscore "leaderboard" "player1")
#
# @param 1: string - Sorted set key
# @param 2: string - Member
# @stdout Score
# @return 0 if found, 1 if not found
###
z::kv::zscore() {
  emulate -L zsh
  local key="$1"
  local member="$2"

  local existing="${_zcore_kv_zsets[$key]:-}"

  if [[ -z $existing ]]; then
    return 1
  fi

  local -a items
  items=("${(@s:|:)existing}")

  local item
  for item in "${items[@]}"; do
    local item_score="${item%%:*}"
    local item_member="${item#*:}"

    if [[ $item_member == $member ]]; then
      print -r -- "$item_score"
      return 0
    fi
  done

  return 1
}

###
# Get range of sorted set members by rank
#
# Usage:
#   z::kv::zrange "leaderboard" 0 9           # Top 10
#   z::kv::zrange "leaderboard" 0 -1          # All members
#   z::kv::zrange "leaderboard" 0 2 --rev     # Top 3 (highest scores)
#
# @param 1: string - Sorted set key
# @param 2: integer - Start rank
# @param 3: integer - Stop rank
# @param 4: string - --rev (reverse order, highest first)
# @stdout Members (one per line)
# @return 0 always
###
z::kv::zrange() {
  emulate -L zsh
  local key="$1"
  typeset -i start stop
  (( start = ${2:-0} ))
  (( stop = ${3:--1} ))
  local reverse=false

  [[ ${4:-} == --rev ]] && reverse=true

  local existing="${_zcore_kv_zsets[$key]:-}"

  if [[ -z $existing ]]; then
    return 0
  fi

  local -a items
  items=("${(@s:|:)existing}")

  # Sort by score
  local -a sorted_items
  sorted_items=("${(@n)items}")  # Numeric sort

  # Reverse if requested
  if [[ $reverse == true ]]; then
    sorted_items=("${(@Oa)sorted_items}")
  fi

  # Handle negative indices
  typeset -i actual_start actual_stop
  if (( start < 0 )); then
    (( actual_start = ${#sorted_items} + start + 1 ))
  else
    (( actual_start = start + 1 ))
  fi

  if (( stop < 0 )); then
    (( actual_stop = ${#sorted_items} + stop + 1 ))
  else
    (( actual_stop = stop + 1 ))
  fi

  # Bounds checking
  (( actual_start < 1 )) && (( actual_start = 1 ))
  (( actual_stop > ${#sorted_items} )) && (( actual_stop = ${#sorted_items} ))

  # Output members (without scores)
  if (( actual_start <= actual_stop )); then
    local item
    for item in "${(@)sorted_items[actual_start,actual_stop]}"; do
      print -r -- "${item#*:}"
    done
  fi

  return 0
}

###
# Get range with scores
#
# Usage:
#   z::kv::zrange_withscores "leaderboard" 0 9
#
# @param 1: string - Sorted set key
# @param 2: integer - Start rank
# @param 3: integer - Stop rank
# @stdout "member score" pairs (one per line)
# @return 0 always
###
z::kv::zrange_withscores() {
  emulate -L zsh
  local key="$1"
  typeset -i start stop
  (( start = ${2:-0} ))
  (( stop = ${3:--1} ))

  local existing="${_zcore_kv_zsets[$key]:-}"

  if [[ -z $existing ]]; then
    return 0
  fi

  local -a items
  items=("${(@s:|:)existing}")

  # Sort by score (descending)
  local -a sorted_items
  sorted_items=("${(@On)items}")

  # Handle indices
  typeset -i actual_start actual_stop
  if (( start < 0 )); then
    (( actual_start = ${#sorted_items} + start + 1 ))
  else
    (( actual_start = start + 1 ))
  fi

  if (( stop < 0 )); then
    (( actual_stop = ${#sorted_items} + stop + 1 ))
  else
    (( actual_stop = stop + 1 ))
  fi

  (( actual_start < 1 )) && (( actual_start = 1 ))
  (( actual_stop > ${#sorted_items} )) && (( actual_stop = ${#sorted_items} ))

  if (( actual_start <= actual_stop )); then
    local item
    for item in "${(@)sorted_items[actual_start,actual_stop]}"; do
      local item_score="${item%%:*}"
      local item_member="${item#*:}"
      print "${item_member} ${item_score}"
    done
  fi

  return 0
}

###
# Remove member from sorted set
#
# Usage:
#   z::kv::zrem "leaderboard" "player1"
#
# @param 1: string - Sorted set key
# @param 2: string - Member to remove
# @return 0 if removed, 1 if not found
###
z::kv::zrem() {
  emulate -L zsh
  local key="$1"
  local member="$2"

  __z::kv::validate_key "$key" || return 1

  local existing="${_zcore_kv_zsets[$key]:-}"

  if [[ -z $existing ]]; then
    return 1
  fi

  local -a items filtered
  items=("${(@s:|:)existing}")

  local item
  for item in "${items[@]}"; do
    local item_member="${item#*:}"
    if [[ $item_member != $member ]]; then
      filtered+=("$item")
    fi
  done

  if (( ${#filtered} > 0 )); then
    _zcore_kv_zsets[$key]="${(j:|:)filtered}"
  else
    unset "_zcore_kv_zsets[$key]"
  fi

  z::log::debug "KV: ZREM '$key' <- '$member'"

  return 0
}

################################################################################
# HASH OPERATIONS (Field-Value pairs)
################################################################################

###
# Set hash field
#
# Usage:
#   z::kv::hset "user:1000" "name" "John"
#   z::kv::hset "user:1000" "email" "john@example.com"
#
# @param 1: string - Hash key
# @param 2: string - Field name
# @param 3: string - Value
# @return 0 on success
###
z::kv::hset() {
  emulate -L zsh
  local key="$1"
  local field="$2"
  local value="$3"

  __z::kv::validate_key "$key" || return 1

  local hash_key="${key}.${field}"
  _zcore_kv_hashes[$hash_key]="$value"

  z::log::debug "KV: HSET '$key' '$field' = '$value'"
  __z::kv::trigger_watchers "$key" "$field:$value" "hset"

  return 0
}

###
# Get hash field value
#
# Usage:
#   name=$(z::kv::hget "user:1000" "name")
#
# @param 1: string - Hash key
# @param 2: string - Field name
# @stdout Field value
# @return 0 if found, 1 if not found
###
z::kv::hget() {
  emulate -L zsh
  local key="$1"
  local field="$2"

  local hash_key="${key}.${field}"

  if (( ! ${+_zcore_kv_hashes[$hash_key]} )); then
    return 1
  fi

  print -r -- "${_zcore_kv_hashes[$hash_key]}"
  return 0
}

###
# Get all hash fields and values
#
# Usage:
#   z::kv::hgetall "user:1000"
#
# @param 1: string - Hash key
# @stdout "field value" pairs (one per line)
# @return 0 always
###
z::kv::hgetall() {
  emulate -L zsh
  local key="$1"

  local hash_key field value
  for hash_key in "${(@k)_zcore_kv_hashes}"; do
    if [[ $hash_key == ${key}.* ]]; then
      field="${hash_key#${key}.}"
      value="${_zcore_kv_hashes[$hash_key]}"
      print "${field} ${value}"
    fi
  done

  return 0
}

###
# Delete hash field
#
# Usage:
#   z::kv::hdel "user:1000" "email"
#
# @param 1: string - Hash key
# @param 2: string - Field name
# @return 0 if deleted, 1 if not found
###
z::kv::hdel() {
  emulate -L zsh
  local key="$1"
  local field="$2"

  local hash_key="${key}.${field}"

  if (( ! ${+_zcore_kv_hashes[$hash_key]} )); then
    return 1
  fi

  unset "_zcore_kv_hashes[$hash_key]"
  z::log::debug "KV: HDEL '$key' '$field'"

  return 0
}

###
# Check if hash field exists
#
# Usage:
#   if z::kv::hexists "user:1000" "email"; then
#     echo "Field exists"
#   fi
#
# @param 1: string - Hash key
# @param 2: string - Field name
# @return 0 if exists, 1 if not
###
z::kv::hexists() {
  emulate -L zsh
  local key="$1"
  local field="$2"

  local hash_key="${key}.${field}"
  (( ${+_zcore_kv_hashes[$hash_key]} ))
}

###
# Get all hash field names
#
# Usage:
#   z::kv::hkeys "user:1000"
#
# @param 1: string - Hash key
# @stdout Field names (one per line)
# @return 0 always
###
z::kv::hkeys() {
  emulate -L zsh
  local key="$1"

  local hash_key field
  for hash_key in "${(@k)_zcore_kv_hashes}"; do
    if [[ $hash_key == ${key}.* ]]; then
      field="${hash_key#${key}.}"
      print -r -- "$field"
    fi
  done

  return 0
}

###
# Get all hash values
#
# Usage:
#   z::kv::hvals "user:1000"
#
# @param 1: string - Hash key
# @stdout Values (one per line)
# @return 0 always
###
z::kv::hvals() {
  emulate -L zsh
  local key="$1"

  local hash_key
  for hash_key in "${(@k)_zcore_kv_hashes}"; do
    if [[ $hash_key == ${key}.* ]]; then
      print -r -- "${_zcore_kv_hashes[$hash_key]}"
    fi
  done

  return 0
}

################################################################################
# ATOMIC OPERATIONS
################################################################################

###
# Set value and return old value (atomic)
#
# Usage:
#   old_value=$(z::kv::getset "counter" "10")
#
# @param 1: string - Key
# @param 2: string - New value
# @stdout Old value (empty if key didn't exist)
# @return 0 always
###
z::kv::getset() {
  emulate -L zsh
  local key="$1"
  local new_value="$2"

  local old_value=""
  if z::kv::exists "$key"; then
    old_value=$(z::kv::get "$key")
  fi

  z::kv::set "$key" "$new_value"

  print -r -- "$old_value"
  return 0
}

###
# Set value only if key doesn't exist (SET if Not eXists)
#
# Usage:
#   if z::kv::setnx "lock" "owner_id"; then
#     echo "Lock acquired"
#   fi
#
# @param 1: string - Key
# @param 2: string - Value
# @return 0 if set, 1 if key already exists
###
z::kv::setnx() {
  emulate -L zsh
  local key="$1"
  local value="$2"

  if z::kv::exists "$key"; then
    z::log::debug "KV: SETNX '$key' - already exists"
    return 1
  fi

  z::kv::set "$key" "$value"
  return 0
}

###
# Set value only if key exists
#
# Usage:
#   if z::kv::setxx "existing_key" "new_value"; then
#     echo "Value updated"
#   fi
#
# @param 1: string - Key
# @param 2: string - Value
# @return 0 if set, 1 if key doesn't exist
###
z::kv::setxx() {
  emulate -L zsh
  local key="$1"
  local value="$2"

  if ! z::kv::exists "$key"; then
    z::log::debug "KV: SETXX '$key' - key doesn't exist"
    return 1
  fi

  z::kv::set "$key" "$value"
  return 0
}

################################################################################
# DISTRIBUTED LOCKING
################################################################################

###
# Acquire distributed lock
#
# Usage:
#   if z::kv::lock "resource_name" 30; then
#     # Critical section
#     z::kv::unlock "resource_name"
#   fi
#
# @param 1: string - Lock name
# @param 2: integer - TTL in seconds (optional, default: 10)
# @param 3: string - Owner ID (optional, default: $$)
# @return 0 if acquired, 1 if already locked
###
z::kv::lock() {
  emulate -L zsh
  local lock_name="$1"
  typeset -i ttl
  (( ttl = ${2:-10} ))
  local owner="${3:-$$}"

  __z::kv::validate_key "$lock_name" || return 1

  # Check if lock exists and is still valid
  if (( ${+_zcore_kv_locks[$lock_name]} )); then
    local lock_data="${_zcore_kv_locks[$lock_name]}"
    local lock_owner="${lock_data%%|*}"
    typeset -i lock_expire
    (( lock_expire = ${lock_data#*|} ))

    typeset -i current_time
    (( current_time = ${EPOCHSECONDS:-$(date +%s)} ))

    if (( current_time < lock_expire )); then
      z::log::debug "KV: Lock '$lock_name' already held by $lock_owner"
      return 1
    fi
  fi

  # Acquire lock
  typeset -i expire_time
  (( expire_time = ${EPOCHSECONDS:-$(date +%s)} + ttl ))

  _zcore_kv_locks[$lock_name]="${owner}|${expire_time}"

  z::log::debug "KV: Lock acquired: '$lock_name' by $owner (TTL: ${ttl}s)"
  z::event::emit "kv:lock:acquired" "$lock_name" "$owner" 2>/dev/null || true

  return 0
}

###
# Release distributed lock
#
# Usage:
#   z::kv::unlock "resource_name"
#
# @param 1: string - Lock name
# @param 2: string - Owner ID (optional, default: $$, must match acquirer)
# @return 0 if released, 1 if not held or wrong owner
###
z::kv::unlock() {
  emulate -L zsh
  local lock_name="$1"
  local owner="${2:-$$}"

  if (( ! ${+_zcore_kv_locks[$lock_name]} )); then
    z::log::debug "KV: Lock '$lock_name' not held"
    return 1
  fi

  local lock_data="${_zcore_kv_locks[$lock_name]}"
  local lock_owner="${lock_data%%|*}"

  if [[ $lock_owner != $owner ]]; then
    z::log::error "KV: Cannot unlock '$lock_name' - owned by $lock_owner, not $owner"
    return 1
  fi

  unset "_zcore_kv_locks[$lock_name]"

  z::log::debug "KV: Lock released: '$lock_name' by $owner"
  z::event::emit "kv:lock:released" "$lock_name" "$owner" 2>/dev/null || true

  return 0
}

###
# Try to acquire lock with retry
#
# Usage:
#   z::kv::lock_wait "resource" 30 5 0.5  # 30s TTL, 5 retries, 0.5s interval
#
# @param 1: string - Lock name
# @param 2: integer - TTL in seconds
# @param 3: integer - Max retries (default: 3)
# @param 4: float - Retry interval in seconds (default: 1)
# @return 0 if acquired, 1 if failed after retries
###
z::kv::lock_wait() {
  emulate -L zsh
  local lock_name="$1"
  typeset -i ttl retries
  (( ttl = ${2:-10} ))
  (( retries = ${3:-3} ))
  typeset -F interval
  (( interval = ${4:-1} ))

  typeset -i attempt
  for (( attempt = 0; attempt <= retries; attempt++ )); do
    if z::kv::lock "$lock_name" "$ttl"; then
      return 0
    fi

    if (( attempt < retries )); then
      z::log::debug "KV: Lock attempt $((attempt + 1)) failed, retrying in ${interval}s..."
      sleep "$interval"
    fi
  done

  z::log::error "KV: Failed to acquire lock '$lock_name' after $retries retries"
  return 1
}

################################################################################
# PUB/SUB CHANNELS
################################################################################

###
# Subscribe to channel
#
# Usage:
#   z::kv::subscribe "notifications" my_handler
#   my_handler() {
#     local channel="$1" message="$2"
#     echo "Received on $channel: $message"
#   }
#
# @param 1: string - Channel name
# @param 2: string - Handler function
# @return 0 on success
###
z::kv::subscribe() {
  emulate -L zsh
  local channel="$1"
  local handler="$2"

  if [[ -z $channel || -z $handler ]]; then
    z::log::error "KV: subscribe requires channel and handler"
    return 1
  fi

  if ! z::probe::func "$handler"; then
    z::log::error "KV: Handler function not found: $handler"
    return 1
  fi

  local existing="${_zcore_kv_pubsub[$channel]:-}"

  if [[ -n $existing ]]; then
    _zcore_kv_pubsub[$channel]="${existing}|${handler}"
  else
    _zcore_kv_pubsub[$channel]="$handler"
  fi

  z::log::debug "KV: Subscribed '$handler' to channel '$channel'"
  return 0
}

###
# Unsubscribe from channel
#
# Usage:
#   z::kv::unsubscribe "notifications" my_handler
#   z::kv::unsubscribe "notifications"  # Remove all
#
# @param 1: string - Channel name
# @param 2: string - Handler function (optional)
# @return 0 on success
###
z::kv::unsubscribe() {
  emulate -L zsh
  local channel="$1"
  local handler="${2:-}"

  if [[ -z $handler ]]; then
    unset "_zcore_kv_pubsub[$channel]"
    z::log::debug "KV: Unsubscribed all from channel '$channel'"
  else
    local existing="${_zcore_kv_pubsub[$channel]:-}"
    if [[ -n $existing ]]; then
      local -a handlers
      handlers=("${(@s:|:)existing}")
      handlers=("${(@)handlers:#$handler}")

      if (( ${#handlers} > 0 )); then
        _zcore_kv_pubsub[$channel]="${(j:|:)handlers}"
      else
        unset "_zcore_kv_pubsub[$channel]"
      fi

      z::log::debug "KV: Unsubscribed '$handler' from channel '$channel'"
    fi
  fi

  return 0
}

###
# Publish message to channel
#
# Usage:
#   z::kv::publish "notifications" "New message arrived"
#
# @param 1: string - Channel name
# @param 2: string - Message
# @return 0 always
###
z::kv::publish() {
  emulate -L zsh
  local channel="$1"
  local message="$2"

  z::log::debug "KV: Publishing to channel '$channel': $message"

  local handler_list="${_zcore_kv_pubsub[$channel]:-}"

  if [[ -z $handler_list ]]; then
    z::log::debug "KV: No subscribers for channel '$channel'"
    return 0
  fi

  local -a handlers
  handlers=("${(@s:|:)handler_list}")

  local handler
  for handler in "${handlers[@]}"; do
    if z::probe::func "$handler"; then
      "$handler" "$channel" "$message" 2>/dev/null || true
    fi
  done

  return 0
}

################################################################################
# SNAPSHOTS
################################################################################

###
# Create snapshot of current KV state
#
# Usage:
#   snapshot_id=$(z::kv::snapshot_create "before_upgrade")
#
# @param 1: string - Snapshot name/label
# @stdout Snapshot ID
# @return 0 on success
###
z::kv::snapshot_create() {
  emulate -L zsh
  setopt localoptions no_unset

  local label="${1:-snapshot}"

  # Generate ID without using command substitution that might reset counter
  typeset -gi _zcore_kv_snapshot_id
  (( _zcore_kv_snapshot_id += 1 ))
  local snapshot_id="snap_${_zcore_kv_snapshot_id}"

  # Serialize all data structures using (F) for newline joining
  local -a store_data meta_data lists_data sets_data zsets_data hashes_data

  local k v
  for k v in "${(@kv)_zcore_kv_store}"; do
    store_data+=("$k")
    store_data+=("$v")
  done

  for k v in "${(@kv)_zcore_kv_meta}"; do
    meta_data+=("$k")
    meta_data+=("$v")
  done

  for k v in "${(@kv)_zcore_kv_lists}"; do
    lists_data+=("$k")
    lists_data+=("$v")
  done

  for k v in "${(@kv)_zcore_kv_sets}"; do
    sets_data+=("$k")
    sets_data+=("$v")
  done

  for k v in "${(@kv)_zcore_kv_zsets}"; do
    zsets_data+=("$k")
    zsets_data+=("$v")
  done

  for k v in "${(@kv)_zcore_kv_hashes}"; do
    hashes_data+=("$k")
    hashes_data+=("$v")
  done

  _zcore_kv_snapshots[${snapshot_id}.label]="$label"
  _zcore_kv_snapshots[${snapshot_id}.timestamp]="${EPOCHSECONDS:-$(date +%s)}"
  _zcore_kv_snapshots[${snapshot_id}.store]="${(F)store_data}"
  _zcore_kv_snapshots[${snapshot_id}.meta]="${(F)meta_data}"
  _zcore_kv_snapshots[${snapshot_id}.lists]="${(F)lists_data}"
  _zcore_kv_snapshots[${snapshot_id}.sets]="${(F)sets_data}"
  _zcore_kv_snapshots[${snapshot_id}.zsets]="${(F)zsets_data}"
  _zcore_kv_snapshots[${snapshot_id}.hashes]="${(F)hashes_data}"

  z::log::info "KV: Snapshot created: $snapshot_id ($label)"
  print -r -- "$snapshot_id"

  return 0
}
###
# Restore from snapshot
#
# Usage:
#   z::kv::snapshot_restore "snap_1"
#
# @param 1: string - Snapshot ID
# @return 0 on success, 1 if not found
###
z::kv::snapshot_restore() {
  emulate -L zsh
  local snapshot_id="$1"

  if [[ -z ${_zcore_kv_snapshots[${snapshot_id}.label]:-} ]]; then
    z::log::error "KV: Snapshot not found: $snapshot_id"
    return 1
  fi

  local label="${_zcore_kv_snapshots[${snapshot_id}.label]}"
  z::log::info "KV: Restoring snapshot: $snapshot_id ($label)"

  # Clear current state
  _zcore_kv_store=()
  _zcore_kv_meta=()
  _zcore_kv_lists=()
  _zcore_kv_sets=()
  _zcore_kv_zsets=()
  _zcore_kv_hashes=()

  # Restore each data structure
  local -a lines
  local key value
  typeset -i i

  # Restore store
  lines=("${(@f)_zcore_kv_snapshots[${snapshot_id}.store]}")
  for (( i = 1; i <= ${#lines}; i += 2 )); do
    key="${lines[i]}"
    value="${lines[i+1]}"
    [[ -n $key ]] && _zcore_kv_store[$key]="$value"
  done

  # Restore meta
  lines=("${(@f)_zcore_kv_snapshots[${snapshot_id}.meta]}")
  for (( i = 1; i <= ${#lines}; i += 2 )); do
    key="${lines[i]}"
    value="${lines[i+1]}"
    [[ -n $key ]] && _zcore_kv_meta[$key]="$value"
  done

  # Restore lists
  lines=("${(@f)_zcore_kv_snapshots[${snapshot_id}.lists]}")
  for (( i = 1; i <= ${#lines}; i += 2 )); do
    key="${lines[i]}"
    value="${lines[i+1]}"
    [[ -n $key ]] && _zcore_kv_lists[$key]="$value"
  done

  # Restore sets
  lines=("${(@f)_zcore_kv_snapshots[${snapshot_id}.sets]}")
  for (( i = 1; i <= ${#lines}; i += 2 )); do
    key="${lines[i]}"
    value="${lines[i+1]}"
    [[ -n $key ]] && _zcore_kv_sets[$key]="$value"
  done

  # Restore zsets
  lines=("${(@f)_zcore_kv_snapshots[${snapshot_id}.zsets]}")
  for (( i = 1; i <= ${#lines}; i += 2 )); do
    key="${lines[i]}"
    value="${lines[i+1]}"
    [[ -n $key ]] && _zcore_kv_zsets[$key]="$value"
  done

  # Restore hashes
  lines=("${(@f)_zcore_kv_snapshots[${snapshot_id}.hashes]}")
  for (( i = 1; i <= ${#lines}; i += 2 )); do
    key="${lines[i]}"
    value="${lines[i+1]}"
    [[ -n $key ]] && _zcore_kv_hashes[$key]="$value"
  done

  z::log::info "KV: Snapshot restored: $snapshot_id"
  z::event::emit "kv:snapshot:restored" "$snapshot_id" 2>/dev/null || true

  return 0
}

###
# List all snapshots
#
# Usage:
#   z::kv::snapshot_list
#
# @return 0 always
###
z::kv::snapshot_list() {
  emulate -L zsh

  print "\nKV Snapshots:"
  print "============="

  local -a snapshot_ids
  local key
  for key in "${(@k)_zcore_kv_snapshots}"; do
    if [[ $key == snap_*.label ]]; then
      snapshot_ids+=("${key%.label}")
    fi
  done

  if (( ${#snapshot_ids} == 0 )); then
    print "No snapshots available.\n"
    return 0
  fi

  # Sort by ID
  snapshot_ids=("${(@n)snapshot_ids}")

  local snap_id label timestamp time_str
  for snap_id in "${snapshot_ids[@]}"; do
    label="${_zcore_kv_snapshots[${snap_id}.label]}"
    timestamp="${_zcore_kv_snapshots[${snap_id}.timestamp]}"

    time_str=$(date -r "$timestamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$timestamp")

    print "  $snap_id: $label [$time_str]"
  done

  print ""
  return 0
}

###
# Delete snapshot
#
# Usage:
#   z::kv::snapshot_delete "snap_1"
#
# @param 1: string - Snapshot ID
# @return 0 on success
###
z::kv::snapshot_delete() {
  emulate -L zsh
  local snapshot_id="$1"

  local key
  for key in "${(@k)_zcore_kv_snapshots}"; do
    if [[ $key == ${snapshot_id}.* ]]; then
      unset "_zcore_kv_snapshots[$key]"
    fi
  done

  z::log::info "KV: Snapshot deleted: $snapshot_id"
  return 0
}

################################################################################
# CONDITIONAL OPERATIONS
################################################################################

###
# Set value if current value matches expected
#
# Usage:
#   if z::kv::cas "counter" "10" "11"; then
#     echo "Updated from 10 to 11"
#   fi
#
# @param 1: string - Key
# @param 2: string - Expected current value
# @param 3: string - New value
# @return 0 if updated, 1 if value doesn't match
###
z::kv::cas() {
  emulate -L zsh
  local key="$1"
  local expected="$2"
  local new_value="$3"

  local current=""
  if z::kv::exists "$key"; then
    current=$(z::kv::get "$key")
  fi

  if [[ $current != $expected ]]; then
    z::log::debug "KV: CAS failed for '$key' - expected '$expected', got '$current'"
    return 1
  fi

  z::kv::set "$key" "$new_value"
  z::log::debug "KV: CAS succeeded for '$key': '$expected' -> '$new_value'"

  return 0
}

################################################################################
# BATCH OPERATIONS
################################################################################

###
# Execute multiple operations atomically
#
# Usage:
#   z::kv::batch <<EOF
#     set key1 value1
#     set key2 value2
#     incr counter
#     del old_key
#   EOF
#
# @stdin Batch commands (one per line)
# @return 0 on success, 1 if any command failed
###
z::kv::batch() {
  emulate -L zsh

  z::kv::begin || return 1

  typeset -i failed=0
  local line cmd

  while IFS= read -r line; do
    # Skip empty lines and comments
    [[ $line =~ '^[[:space:]]*(#.*)?$' ]] && continue

    # Parse command
    local -a parts
    parts=("${(@s: :)line}")

    cmd="${parts[1]}"

    case "$cmd" in
      set)
        z::kv::set "${parts[2]}" "${parts[3]}" || (( failed += 1 ))
        ;;
      get)
        z::kv::get "${parts[2]}" || (( failed += 1 ))
        ;;
      del)
        z::kv::del "${parts[2]}" || (( failed += 1 ))
        ;;
      incr)
        z::kv::incr "${parts[2]}" || (( failed += 1 ))
        ;;
      decr)
        z::kv::decr "${parts[2]}" || (( failed += 1 ))
        ;;
      *)
        z::log::warn "KV: Unknown batch command: $cmd"
        (( failed += 1 ))
        ;;
    esac
  done

  if (( failed > 0 )); then
    z::log::error "KV: Batch operation failed ($failed errors), rolling back"
    z::kv::rollback
    return 1
  fi

  z::kv::commit
  z::log::debug "KV: Batch operation completed successfully"

  return 0
}

################################################################################
# UTILITY OPERATIONS
################################################################################

###
# Rename key
#
# Usage:
#   z::kv::rename "old_key" "new_key"
#
# @param 1: string - Old key
# @param 2: string - New key
# @return 0 on success, 1 if old key doesn't exist
###
z::kv::rename() {
  emulate -L zsh
  local old_key="$1"
  local new_key="$2"

  if ! z::kv::exists "$old_key"; then
    z::log::error "KV: Cannot rename - key not found: $old_key"
    return 1
  fi

  local value=$(z::kv::get "$old_key")
  local value_type="${_zcore_kv_meta[$old_key]:-string}"

  z::kv::set "$new_key" "$value" --type "$value_type"
  z::kv::del "$old_key"

  z::log::debug "KV: Renamed '$old_key' to '$new_key'"

  return 0
}

###
# Copy key
#
# Usage:
#   z::kv::copy "source_key" "dest_key"
#
# @param 1: string - Source key
# @param 2: string - Destination key
# @return 0 on success, 1 if source doesn't exist
###
z::kv::copy() {
  emulate -L zsh
  local source="$1"
  local dest="$2"

  if ! z::kv::exists "$source"; then
    z::log::error "KV: Cannot copy - key not found: $source"
    return 1
  fi

  local value=$(z::kv::get "$source")
  local value_type="${_zcore_kv_meta[$source]:-string}"

  z::kv::set "$dest" "$value" --type "$value_type"

  z::log::debug "KV: Copied '$source' to '$dest'"

  return 0
}

###
# Get random key
#
# Usage:
#   random_key=$(z::kv::randomkey)
#
# @stdout Random key name
# @return 0 if keys exist, 1 if store empty
###
z::kv::randomkey() {
  emulate -L zsh

  local -a all_keys
  all_keys=("${(@k)_zcore_kv_store}")

  if (( ${#all_keys} == 0 )); then
    return 1
  fi

  # Get random index
  typeset -i random_idx
  (( random_idx = (RANDOM % ${#all_keys}) + 1 ))

  print -r -- "${all_keys[random_idx]}"
  return 0
}

###
# Scan keys with cursor (for large datasets)
#
# Usage:
#   z::kv::scan 0 "user:*" 10  # Get first 10 matching keys
#
# @param 1: integer - Cursor (0 to start)
# @param 2: string - Pattern (optional)
# @param 3: integer - Count (optional, default: 10)
# @stdout "cursor key1 key2 ..." (cursor 0 means done)
# @return 0 always
###
z::kv::scan() {
  emulate -L zsh
  typeset -i cursor count
  (( cursor = ${1:-0} ))
  local pattern="${2:-*}"
  (( count = ${3:-10} ))

  local -a all_keys matching_keys
  all_keys=("${(@k)_zcore_kv_store}")

  # Filter by pattern
  local key
  for key in "${all_keys[@]}"; do
    if [[ $key == ${~pattern} ]]; then
      matching_keys+=("$key")
    fi
  done

  typeset -i total start end next_cursor
  (( total = ${#matching_keys} ))
  (( start = cursor + 1 ))
  (( end = start + count - 1 ))
  (( end > total )) && (( end = total ))

  if (( start > total )); then
    print "0"
    return 0
  fi

  if (( end >= total )); then
    (( next_cursor = 0 ))
  else
    (( next_cursor = end ))
  fi

  # Output: cursor followed by keys
  print -n "$next_cursor"

  if (( start <= end )); then
    local -a result_keys
    result_keys=("${(@)matching_keys[start,end]}")
    print -n " ${(j: :)result_keys}"
  fi

  print ""
  return 0
}

################################################################################
# ADVANCED STATISTICS
################################################################################

###
# Get memory usage estimate
#
# Usage:
#   z::kv::memory
#
# @stdout Memory usage info
# @return 0 always
###
z::kv::memory() {
  emulate -L zsh

  print "\nKV Memory Usage:"
  print "================"

  typeset -i total_bytes=0

  # Calculate store size
  typeset -i store_bytes=0
  local key value
  for key value in "${(@kv)_zcore_kv_store}"; do
    (( store_bytes += ${#key} + ${#value} ))
  done

  # Calculate lists size
  typeset -i lists_bytes=0
  for key value in "${(@kv)_zcore_kv_lists}"; do
    (( lists_bytes += ${#key} + ${#value} ))
  done

  # Calculate sets size
  typeset -i sets_bytes=0
  for key value in "${(@kv)_zcore_kv_sets}"; do
    (( sets_bytes += ${#key} + ${#value} ))
  done

  # Calculate zsets size
  typeset -i zsets_bytes=0
  for key value in "${(@kv)_zcore_kv_zsets}"; do
    (( zsets_bytes += ${#key} + ${#value} ))
  done

  # Calculate hashes size
  typeset -i hashes_bytes=0
  for key value in "${(@kv)_zcore_kv_hashes}"; do
    (( hashes_bytes += ${#key} + ${#value} ))
  done

  (( total_bytes = store_bytes + lists_bytes + sets_bytes + zsets_bytes + hashes_bytes ))

  print "Store:        ${store_bytes} bytes (${#_zcore_kv_store} keys)"
  print "Lists:        ${lists_bytes} bytes (${#_zcore_kv_lists} lists)"
  print "Sets:         ${sets_bytes} bytes (${#_zcore_kv_sets} sets)"
  print "Sorted Sets:  ${zsets_bytes} bytes (${#_zcore_kv_zsets} zsets)"
  print "Hashes:       ${hashes_bytes} bytes (${#_zcore_kv_hashes} hashes)"
  print "Total:        ${total_bytes} bytes"

  # Human readable
  typeset -F kb mb
  (( kb = total_bytes / 1024.0 ))
  (( mb = kb / 1024.0 ))

  if (( mb >= 1 )); then
    printf "              %.2f MB\n" "$mb"
  elif (( kb >= 1 )); then
    printf "              %.2f KB\n" "$kb"
  fi

  print ""
  return 0
}

###
# Get detailed info about a key
#
# Usage:
#   z::kv::info "mykey"
#
# @param 1: string - Key name
# @return 0 if found, 1 if not found
###
z::kv::info() {
  emulate -L zsh
  local key="$1"

  print "\nKey Information: $key"
  print "===================="

  # Check in store
  if (( ${+_zcore_kv_store[$key]} )); then
    local value="${_zcore_kv_store[$key]}"
    local value_type="${_zcore_kv_meta[$key]:-string}"

    print "Type:       string/value"
    print "Data Type:  $value_type"
    print "Value:      $value"
    print "Size:       ${#value} bytes"

    local ttl_val=$(z::kv::ttl "$key")
    if [[ $ttl_val == -1 ]]; then
      print "TTL:        No expiration"
    elif [[ $ttl_val == -2 ]]; then
      print "TTL:        Key not found"
    else
      print "TTL:        ${ttl_val}s remaining"
    fi

    print ""
    return 0
  fi

  # Check in lists
  if (( ${+_zcore_kv_lists[$key]} )); then
    local list_data="${_zcore_kv_lists[$key]}"
    local -a items
    items=("${(@s:|:)list_data}")

    print "Type:       list"
    print "Length:     ${#items}"
    print "Size:       ${#list_data} bytes"
    print ""
    return 0
  fi

  # Check in sets
  if (( ${+_zcore_kv_sets[$key]} )); then
    local set_data="${_zcore_kv_sets[$key]}"
    local -a members
    members=("${(@s:|:)set_data}")

    print "Type:       set"
    print "Cardinality: ${#members}"
    print "Size:       ${#set_data} bytes"
    print ""
    return 0
  fi

  # Check in zsets
  if (( ${+_zcore_kv_zsets[$key]} )); then
    local zset_data="${_zcore_kv_zsets[$key]}"
    local -a items
    items=("${(@s:|:)zset_data}")

    print "Type:       sorted set"
    print "Members:    ${#items}"
    print "Size:       ${#zset_data} bytes"
    print ""
    return 0
  fi

  # Check in hashes
  typeset -i hash_fields=0
  local hash_key
  for hash_key in "${(@k)_zcore_kv_hashes}"; do
    if [[ $hash_key == ${key}.* ]]; then
      (( hash_fields += 1 ))
    fi
  done

  if (( hash_fields > 0 )); then
    print "Type:       hash"
    print "Fields:     $hash_fields"
    print ""
    return 0
  fi

  print "Key not found in any data structure.\n"
  return 1
}

z::log::debug "KV Store advanced features initialized"
