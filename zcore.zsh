
#!/usr/bin/env zsh

################################################################################
# ZCORE FRAMEWORK v0.2
################################################################################
#
# Three independent pillars:
#   🔴 PILLAR 1: LOGGING    - No dependencies
#   🔵 PILLAR 2: CACHE      - Depends on: Logging
#   🟠 PILLAR 3: KV STORE   - Depends on: Logging
#
# Integration layer connects pillars AFTER all are loaded
#
# Version: 0.2.0
# License: MIT
################################################################################
# Double-sourcing Guard
# Prevents this module from being initialized multiple times in the same session.
# Returns 0 when already loaded (whether sourced or executed).
if [[ ${_zcore_loaded:-} == 1 ]]; then return 0 2>/dev/null || exit 0; fi
typeset -g _zcore_loaded=1
typeset -gr ZCORE_VERSION="0.2.0"


# Ensure EPOCHSECONDS is available when possible (no-op if unavailable)
# zmodload -F zsh/datetime b:EPOCHSECONDS 2>/dev/null || true

################################################################################
# CONSTANTS
################################################################################
typeset -gA _zcore_logging

# Logging level constants
typeset -gri ZCORE_LOG_LEVEL_ERROR=0    # Critical errors only
typeset -gri ZCORE_LOG_LEVEL_WARN=1     # Warnings and errors
typeset -gri ZCORE_LOG_LEVEL_INFO=2     # Informational messages (default)
typeset -gri ZCORE_LOG_LEVEL_DEBUG=3    # Verbose debugging output
# Standard return codes
typeset -gri ZCORE_SUCCESS=0
typeset -gri ZCORE_ERROR_GENERAL=1
typeset -gri ZCORE_ERROR_NOT_FOUND=2
typeset -gri ZCORE_ERROR_INVALID_INPUT=3
typeset -gri ZCORE_ERROR_PERMISSION=4
typeset -gri ZCORE_ERROR_TIMEOUT=124
typeset -gri ZCORE_ERROR_INTERRUPTED=130


# Logging recursion guard
_zcore_logging[depth]=0                   # Current logging call depth
###
# Current logging verbosity level
# 0 = error only, 1 = warn, 2 = info (default), 3 = debug
###
_zcore_logging[timeout_default]=30           # Default command timeout (seconds)
_zcore_logging[max_depth]=50             # Max recursion depth for logging
# Logging levels (numeric) - reference constants
_zcore_logging[error]=$ZCORE_LOG_LEVEL_ERROR
_zcore_logging[warn]=$ZCORE_LOG_LEVEL_WARN
_zcore_logging[info]=$ZCORE_LOG_LEVEL_INFO
_zcore_logging[debug]=$ZCORE_LOG_LEVEL_DEBUG
_zcore_logging[level]=${_zcore_logging[error]}
################################################################################
# PILLAR 1: LOGGING 🔴
################################################################################
# ZERO dependencies - pure output system
################################################################################
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



typeset -gA _zcore_colors
if [[ -t 2 && -z ${NO_COLOR:-} && ( ${TERM:-} != dumb || -n ${COLORTERM:-} ) ]] &&
   (( $+commands[tput] )) && tput setaf 1 >/dev/null 2>&1; then
     _zcore_colors=(
         'black'       "$(tput setaf 0)"
         'red'         "$(tput setaf 1)"
         'green'       "$(tput setaf 2)"
         'yellow'      "$(tput setaf 3)"
         'blue'        "$(tput setaf 4)"
         'magenta'     "$(tput setaf 5)"
         'cyan'        "$(tput setaf 6)"
         'white'       "$(tput setaf 7)"

         'bright_black'   "$(tput setaf 8)"
         'bright_red'     "$(tput setaf 9)"
         'bright_green'   "$(tput setaf 10)"
         'bright_yellow'  "$(tput setaf 11)"
         'bright_blue'    "$(tput setaf 12)"
         'bright_magenta' "$(tput setaf 13)"
         'bright_cyan'    "$(tput setaf 14)"
         'bright_white'   "$(tput setaf 15)"

         'reset'       "$(tput sgr0)"
         'bold'        "$(tput bold)"
         'dim'         "$(tput dim)"
         'underline'   "$(tput smul)"
         'blink'       "$(tput blink)"
         'reverse'     "$(tput rev)"
         'hidden'      "$(tput invis)"
     )
else
  _zcore_colors=('red' "" 'green' "" 'blue' "" 'yellow' "" '' "" 'magenta' "" 'reset' "" 'bold' "")
fi
###
# Cached timestamp for performance
# Updated only when EPOCHSECONDS changes to avoid repeated date calls
###
typeset -g _cached_timestamp=""      # Last formatted timestamp
typeset -gi _timestamp_epoch=0       # Epoch second of last timestamp update


################################################################################
# LOGGING SUBSYSTEM
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
  (( max_depth = _zcore_logging[max_depth] ))
  (( max_depth <= 0 )) && (( max_depth = 50 ))  # sane fallback

  if (( _zcore_logging[depth] > max_depth )); then
    print -r -- "FATAL: Recursion in __z::log::engine" >&2
    return 1
  fi

  # Use always block to ensure depth cleanup
  {
  (( _zcore_logging[depth] += 1 ))


  # Log level validation with base-10 enforcement
  typeset -i level
  if [[ -z ${1-} || $1 != <-> ]]; then
    print -r -- "[error] Invalid log level: '${1-}'" >&2
    return 1
  fi
  (( level = 10#${1} ))
  shift

  # Early return for filtered messages
  if (( level > _zcore_logging[level] )); then
    return 0
  fi

  __z::log::update_ts

  # Map level to prefix and color
  local prefix=""
  case $level in
    (${_zcore_logging[error]}) prefix="${_zcore_colors[red]}[error]${_zcore_colors[reset]}" ;;
    (${_zcore_logging[warn]})  prefix="${_zcore_colors[yellow]}[warn]${_zcore_colors[reset]}" ;;
    (${_zcore_logging[info]})  prefix="${_zcore_colors[green]}[info]${_zcore_colors[reset]}" ;;
    (${_zcore_logging[debug]}) prefix="${_zcore_colors[magenta]}[debug]${_zcore_colors[reset]}" ;;
    (*)                            prefix="[unknown]" ;;
  esac

  local msg="${(j: :)@}"
  print -r -- "${_cached_timestamp} ${prefix} ${msg}" >&2
  } always {
  (( _zcore_logging[depth] -= 1 ))
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
  __z::log::engine ${_zcore_logging[error]} "$@"
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
  __z::log::engine ${_zcore_logging[warn]} "$@"
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
  __z::log::engine ${_zcore_logging[info]} "$@"
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
  __z::log::engine ${_zcore_logging[debug]} "$@"
}
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
    (${_zcore_logging[error]}) print -r -- "error" ;;
    (${_zcore_logging[warn]})  print -r -- "warn" ;;
    (${_zcore_logging[info]})  print -r -- "info" ;;
    (${_zcore_logging[debug]}) print -r -- "debug" ;;
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
      error) (( level = _zcore_logging[error] )) ;;
      warn)  (( level = _zcore_logging[warn]  )) ;;
      info)  (( level = _zcore_logging[info]  )) ;;
      debug) (( level = _zcore_logging[debug] )) ;;
      *) return 1 ;;
    esac
  fi

  if (( level < _zcore_logging[error] || level > _zcore_logging[debug] )); then
    return 1
  fi

  print -r -- "$level"
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
    print -r -- "$_zcore_logging[level]"
    return 0
  fi

  local level_name
  level_name=$(__z::log::level_name "$_zcore_logging[level]")
  print -r -- "Current verbosity level: $_zcore_logging[level] ($level_name)"
  return 0
}
###
# Set verbosity level programmatically with validation
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
  if ! parsed=$(__z::log::parse_level "$input"); then
    z::log::error "$_zcore_colors[green][log::set_level]$_zcore_colors[reset] Invalid level: '$input' (use: 0-3 or error|warn|info|debug)"
    return 1
  fi
  typeset -i new_level
  (( new_level = 10#${parsed} ))
 local old_level=$_zcore_logging[level]
  if (( $new_level == $old_level )); then
    z::log::warn "$_zcore_colors[green][log::set_level]$_zcore_colors[reset] Log level is already set to $(__z::log::level_name "$input") '$parsed'"
    return 1
  fi


  (( _zcore_logging[level] = new_level ))

  local old_name new_name
  old_name=$(__z::log::level_name "$old_level")
  new_name=$(__z::log::level_name "$new_level")

  z::log::info "Verbosity changed: $old_level ($old_name) → $new_level ($new_name)"

  # Update KV if loaded
  if (( ${+functions[z::kv::set_int]} )); then
    z::kv::set_int "config:log_level" "$new_level" || true
  fi

  # Emit event if loaded
  if (( ${+functions[z::event::emit]} )); then
    z::event::emit "log:level_changed" "$old_level" "$new_level" || true
  fi
  return 0
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

################################################################################
# PILLAR 2: CACHE 🔵
################################################################################
# Depends ONLY on: Logging
# Does NOT depend on: Events, KV
################################################################################

typeset -gA _zcore_cache_store
typeset -gA _zcore_cache_ttl
typeset -gA _zcore_cache_stats

__z::cache::check_ttl() {
  emulate -L zsh
  local key="$1"

  if (( ! ${+_zcore_cache_ttl[$key]} )); then
    return 0
  fi

  typeset -i expire_time current_time
  (( expire_time = ${_zcore_cache_ttl[$key]} ))
  (( current_time = ${EPOCHSECONDS:-$(date +%s)} ))

  if (( current_time >= expire_time )); then
    z::log::debug "Cache expired: $key"
    unset "_zcore_cache_store[$key]"
    unset "_zcore_cache_ttl[$key]"

    local namespace="${key%%:*}"
    typeset -i expired
    (( expired = ${_zcore_cache_stats[${namespace}.expired]:-0} + 1 ))
    _zcore_cache_stats[${namespace}.expired]=$expired

    return 1
  fi

  return 0
}

z::cache::set() {
  emulate -L zsh
  local key="${1:-}"
  local value="${2:-}"
  shift 2

  if [[ -z $key ]]; then
    z::log::error "Cache key required"
    return $ZCORE_ERROR_INVALID_INPUT
  fi

  typeset -i ttl=0
  while (( $# > 0 )); do
    case "$1" in
      --ttl)
        if [[ ${2:-} == <-> ]]; then
          (( ttl = 10#${2} ))
          shift 2
        else
          z::log::error "Invalid TTL: ${2:-}"
          return $ZCORE_ERROR_INVALID_INPUT
        fi
        ;;
      *)
        shift
        ;;
    esac
  done

  _zcore_cache_store[$key]="$value"

  if (( ttl > 0 )); then
    typeset -i expire_time
    (( expire_time = ${EPOCHSECONDS:-$(date +%s)} + ttl ))
    _zcore_cache_ttl[$key]=$expire_time
  else
    unset "_zcore_cache_ttl[$key]"
  fi

  local namespace="${key%%:*}"
  typeset -i writes
  (( writes = ${_zcore_cache_stats[${namespace}.writes]:-0} + 1 ))
  _zcore_cache_stats[${namespace}.writes]=$writes

  z::log::debug "Cache set: $key (ttl: ${ttl}s)"

  # OPTIONAL: Emit event if loaded (no hard dependency)
  if (( ${+functions[z::event::emit]} )); then
    z::event::emit "cache:set" "$key" "$value" || true
  fi

  return 0
}

z::cache::get() {
  emulate -L zsh
  local key="${1:-}"

  if [[ -z $key ]]; then
    z::log::error "Cache key required"
    return $ZCORE_ERROR_INVALID_INPUT
  fi

  if ! __z::cache::check_ttl "$key"; then
    local namespace="${key%%:*}"
    typeset -i misses
    (( misses = ${_zcore_cache_stats[${namespace}.misses]:-0} + 1 ))
    _zcore_cache_stats[${namespace}.misses]=$misses

    # OPTIONAL: Emit event
    if (( ${+functions[z::event::emit]} )); then
      z::event::emit "cache:miss" "$key" "expired" || true
    fi

    return $ZCORE_ERROR_NOT_FOUND
  fi

  if (( ! ${+_zcore_cache_store[$key]} )); then
    local namespace="${key%%:*}"
    typeset -i misses
    (( misses = ${_zcore_cache_stats[${namespace}.misses]:-0} + 1 ))
    _zcore_cache_stats[${namespace}.misses]=$misses

    # OPTIONAL: Emit event
    if (( ${+functions[z::event::emit]} )); then
      z::event::emit "cache:miss" "$key" "not_found" || true
    fi

    return $ZCORE_ERROR_NOT_FOUND
  fi

  local namespace="${key%%:*}"
  typeset -i hits
  (( hits = ${_zcore_cache_stats[${namespace}.hits]:-0} + 1 ))
  _zcore_cache_stats[${namespace}.hits]=$hits

  # OPTIONAL: Emit event
  if (( ${+functions[z::event::emit]} )); then
    z::event::emit "cache:hit" "$key" || true
  fi

  print -r -- "${_zcore_cache_store[$key]}"
  return 0
}

z::cache::del() {
  emulate -L zsh
  local key="${1:-}"

  if [[ -z $key ]]; then
    return $ZCORE_ERROR_INVALID_INPUT
  fi

  unset "_zcore_cache_store[$key]"
  unset "_zcore_cache_ttl[$key]"

  z::log::debug "Cache deleted: $key"

  # OPTIONAL: Emit event
  if (( ${+functions[z::event::emit]} )); then
    z::event::emit "cache:delete" "$key" || true
  fi

  return 0
}

z::cache::exists() {
  emulate -L zsh
  local key="${1:-}"
  __z::cache::check_ttl "$key" || return 1
  (( ${+_zcore_cache_store[$key]} ))
}

z::cache::clear() {
  emulate -L zsh
  local pattern="${1:-*}"

  typeset -i cleared=0
  local key

  for key in "${(@k)_zcore_cache_store}"; do
    if [[ $key == ${~pattern} ]]; then
      z::cache::del "$key"
      (( cleared += 1 ))
    fi
  done

  z::log::debug "Cache cleared: $cleared entries"

  # OPTIONAL: Emit event
  if (( ${+functions[z::event::emit]} )); then
    z::event::emit "cache:cleared" "$pattern" "$cleared" || true
  fi

  return 0
}

z::cache::stats() {
  emulate -L zsh
  local namespace="${1:-}"

  print "\nCache Statistics:"
  print "================="

  if [[ -n $namespace ]]; then
    print "Namespace: $namespace"
    print "  Hits:    ${_zcore_cache_stats[${namespace}.hits]:-0}"
    print "  Misses:  ${_zcore_cache_stats[${namespace}.misses]:-0}"
    print "  Writes:  ${_zcore_cache_stats[${namespace}.writes]:-0}"
    print "  Expired: ${_zcore_cache_stats[${namespace}.expired]:-0}"

    typeset -i total
    (( total = ${_zcore_cache_stats[${namespace}.hits]:-0} + ${_zcore_cache_stats[${namespace}.misses]:-0} ))
    if (( total > 0 )); then
      typeset -F hit_rate
      (( hit_rate = (${_zcore_cache_stats[${namespace}.hits]:-0} * 100.0) / total ))
      print "  Hit Rate: ${hit_rate}%"
    fi
  else
    typeset -A namespaces
    local key ns
    for key in "${(@k)_zcore_cache_stats}"; do
      ns="${key%.*}"
      namespaces[$ns]=1
    done

    for ns in "${(@k)namespaces}"; do
      print "\n$ns:"
      print "  Hits:    ${_zcore_cache_stats[${ns}.hits]:-0}"
      print "  Misses:  ${_zcore_cache_stats[${ns}.misses]:-0}"
      print "  Writes:  ${_zcore_cache_stats[${ns}.writes]:-0}"
      print "  Expired: ${_zcore_cache_stats[${ns}.expired]:-0}"
    done
  fi

  print "\nTotal Entries: ${#_zcore_cache_store}"
  print ""
  return 0
}

z::cache::memoize() {
  emulate -L zsh
  local cache_key="${1:-}"
  typeset -i ttl
  (( ttl = ${2:-0} ))
  local func="${3:-}"
  shift 3

  if [[ -z $cache_key || -z $func ]]; then
    z::log::error "Cache key and function required"
    return $ZCORE_ERROR_INVALID_INPUT
  fi

  local cached
  if cached=$(z::cache::get "$cache_key"); then
    print -r -- "$cached"
    return 0
  fi

  if (( ! ${+functions[$func]} )); then
    z::log::error "Function not found: $func"
    return $ZCORE_ERROR_NOT_FOUND
  fi

  local result
  result=$("$func" "$@") || return $?

  if (( ttl > 0 )); then
    z::cache::set "$cache_key" "$result" --ttl "$ttl"
  else
    z::cache::set "$cache_key" "$result"
  fi

  print -r -- "$result"
  return 0
}



################################################################################
# PILLAR 3: KV STORE 🟠
################################################################################
# Depends ONLY on: Logging
# Does NOT depend on: Events, Cache
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

  z::log::debug "KV: Cleared $deleted keys matching '$pattern'"
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


################################################################################
# LAYER 2: SYSTEM CORE
################################################################################

typeset -gi _zcore_interrupted=0

__z::sys::handle_interrupt() {
  emulate -L zsh
  setopt no_unset
  if [[ -n ${ZLE_STATE:-} ]]; then
    return 0
  fi

  if (( _zcore_interrupted == 0 )); then
    (( _zcore_interrupted = 1 ))
    z::progress::clear
    z::log::warn "Interrupt received. Gracefully shutting down..."

    if (( ${+functions[z::event::emit]} )); then
      z::event::emit "sys:interrupted"
    fi
  fi
  return 0
}

z::sys::interrupted() {
  emulate -L zsh
  setopt no_unset
  if (( _zcore_interrupted )); then
    z::log::info "Operation cancelled by user."
    return $ZCORE_ERROR_INTERRUPTED
  fi
  return 0
}

z::sys::die()
{
  emulate -L zsh
  setopt no_unset
  local message="${1-}"
  typeset -i exit_code
  (( exit_code = 10#${2:-${_zcore_config[exit_general_error]}} ))

  z::progress::clear
  z::log::error "FATAL (exit $exit_code): $message"


  # Return in sourced context, exit otherwise
  if [[ -n $ZSH_EVAL_CONTEXT && $ZSH_EVAL_CONTEXT == *:file:* ]]; then
    return $exit_code
  else
    exit $exit_code
  fi
}

z::sys::platform() {
  emulate -L zsh
  setopt no_unset typeset_silent

  # Check cache
  local cached_platform
  if cached_platform=$(z::cache::get "sys:platform"); then
    return 0
  fi

  local ostype_value="${OSTYPE:-}"
  if [[ -z $ostype_value ]]; then
    case "$(uname -s 2>/dev/null)" in
      Darwin)  ostype_value="darwin" ;;
      Linux)   ostype_value="linux" ;;
      *BSD*)   ostype_value="bsd" ;;
      CYGWIN*) ostype_value="cygwin" ;;
      *)       ostype_value="unknown" ;;
    esac
  fi

  local platform_name="unknown"
  case $ostype_value in
    darwin*)
      typeset -gri IS_MACOS=1 IS_LINUX=0 IS_BSD=0 IS_CYGWIN=0
      platform_name="macos"
      ;;
    linux*)
      typeset -gri IS_MACOS=0 IS_LINUX=1 IS_BSD=0 IS_CYGWIN=0
      platform_name="linux"
      ;;
    *bsd*|dragonfly*|netbsd*|openbsd*|freebsd*)
      typeset -gri IS_MACOS=0 IS_LINUX=0 IS_BSD=1 IS_CYGWIN=0
      platform_name="bsd"
      ;;
    cygwin*|msys*|mingw*)
      typeset -gri IS_MACOS=0 IS_LINUX=0 IS_BSD=0 IS_CYGWIN=1
      platform_name="cygwin"
      ;;
    *)
      typeset -gri IS_MACOS=0 IS_LINUX=0 IS_BSD=0 IS_CYGWIN=0
      ;;
  esac

  typeset -i is_wsl=0
  if (( IS_LINUX )); then
    if [[ -n ${WSL_DISTRO_NAME:-} || -n ${WSLENV:-} || -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
      (( is_wsl = 1 ))
    elif [[ -r /proc/version ]]; then
      local proc_version=""
      if IFS= read -r proc_version < /proc/version 2>/dev/null; then
        if [[ $proc_version == *[Mm]icrosoft* || $proc_version == *[Ww][Ss][Ll]* ]]; then
          (( is_wsl = 1 ))
        fi
      fi
    fi
  fi
  typeset -gri IS_WSL=$is_wsl

  typeset -i is_termux=0
  if (( IS_LINUX )) && [[ -d /data/data/com.termux/files/usr ]]; then
    (( is_termux = 1 ))
  fi
  typeset -gri IS_TERMUX=$is_termux

  if (( IS_MACOS || IS_LINUX || IS_BSD || IS_CYGWIN )); then
    typeset -gri IS_UNKNOWN=0
  else
    typeset -gri IS_UNKNOWN=1
  fi

  # Cache platform (no expiration)
  z::cache::set "sys:platform" "$platform_name"
  z::cache::set "sys:is_macos" "$IS_MACOS"
  z::cache::set "sys:is_linux" "$IS_LINUX"
  z::cache::set "sys:is_wsl" "$IS_WSL"

  z::log::debug "Platform: $platform_name"

  if (( ${+functions[z::event::emit]} )); then
    z::event::emit "sys:platform_detected" "$platform_name" 2>/dev/null || true
  fi

  return 0
}

z::sys::is_macos() { z::sys::platform; return $(( ! IS_MACOS )); }
z::sys::is_linux() { z::sys::platform; return $(( ! IS_LINUX )); }
z::sys::is_bsd() { z::sys::platform; return $(( ! IS_BSD )); }
z::sys::is_wsl() { z::sys::platform; return $(( ! IS_WSL )); }

################################################################################
# LAYER 3: CONFIGURATION (Built on KV)
################################################################################

__z::config::init_defaults() {
  emulate -L zsh

  z::kv::set "config:log_level" "$_zcore_logging[level]" --type int
  z::kv::set "config:cache_max_size" "100" --type int
  z::kv::set "config:timeout_default" "30" --type int
  z::kv::set "config:performance_mode" "false" --type bool
  z::kv::set "config:show_progress" "true" --type bool
  z::kv::set "config:symlink_max_iterations" "40" --type int
  z::kv::set "config:progress_update_interval" "10" --type int

  if [[ -n ${ZCORE_PERFORMANCE_MODE:-} ]]; then
    z::kv::set_bool "config:performance_mode" "$ZCORE_PERFORMANCE_MODE"
  fi

  if [[ -n ${ZCORE_SHOW_PROGRESS:-} ]]; then
    z::kv::set_bool "config:show_progress" "$ZCORE_SHOW_PROGRESS"
  fi

  z::log::debug "Configuration defaults initialized"
  return 0
}

z::config::get() {
  emulate -L zsh
  local key="${1:-}"

  if [[ -z $key ]]; then
    z::log::error "Config key required"
    return $ZCORE_ERROR_INVALID_INPUT
  fi

  z::kv::get "config:${key}"
}

z::config::set() {
  emulate -L zsh
  local key="${1:-}"
  local value="${2:-}"

  if [[ -z $key ]]; then
    z::log::error "Config key required"
    return $ZCORE_ERROR_INVALID_INPUT
  fi

  case $key in
    *_mode|show_*|enable_*)
      if [[ $value != true && $value != false ]]; then
        z::log::error "Boolean required for $key"
        return $ZCORE_ERROR_INVALID_INPUT
      fi
      z::kv::set_bool "config:${key}" "$value"
      ;;
    *_size|*_timeout|*_depth|*_threshold|*_interval|*_iterations|*_level)
      if [[ $value != <-> ]]; then
        z::log::error "Integer required for $key"
        return $ZCORE_ERROR_INVALID_INPUT
      fi
      z::kv::set_int "config:${key}" "$value"
      ;;
    *)
      z::kv::set "config:${key}" "$value"
      ;;
  esac

  z::log::debug "Config updated: $key = $value"

  # OPTIONAL: Emit event
  if (( ${+functions[z::event::emit]} )); then
    z::event::emit "config:changed" "$key" "$value" || true
  fi

  return 0
}

z::config::watch() {
  emulate -L zsh
  local pattern="${1:-}"
  local handler="${2:-}"

  if [[ -z $pattern || -z $handler ]]; then
    z::log::error "Pattern and handler required"
    return $ZCORE_ERROR_INVALID_INPUT
  fi

  z::kv::watch "config:${pattern}" "$handler"
}

z::config::show() {
  emulate -L zsh

  print "\nConfiguration:"
  print "=============="

  local -a config_keys
  config_keys=($(z::kv::keys "config:*"))

  local key display_key value
  for key in "${config_keys[@]}"; do
    display_key="${key#config:}"
    value=$(z::kv::get "$key" || print "N/A")
    printf "  %-30s = %s\n" "$display_key" "$value"
  done

  print ""
  return 0
}

z::config::save() {
  emulate -L zsh
  local file="${1:-}"

  if [[ -z $file ]]; then
    z::log::error "File path required"
    return $ZCORE_ERROR_INVALID_INPUT
  fi

  {
    print "# ZCORE Configuration v3.0"
    print "# Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    print ""

    local -a config_keys
    config_keys=($(z::kv::keys "config:*"))

    local key display_key value
    for key in "${config_keys[@]}"; do
      display_key="${key#config:}"
      value=$(z::kv::get "$key" || print "")
      print "${display_key}=${value}"
    done
  } > "$file"

  z::log::info "Configuration saved: $file"
  return 0
}

z::config::load() {
  emulate -L zsh
  local file="${1:-}"

  if [[ -z $file ]]; then
    z::log::error "File path required"
    return $ZCORE_ERROR_INVALID_INPUT
  fi

  if [[ ! -f $file || ! -r $file ]]; then
    z::log::error "Cannot read: $file"
    return $ZCORE_ERROR_NOT_FOUND
  fi

  local line key value
  while IFS= read -r line; do
    [[ $line =~ ^[[:space:]]*# ]] && continue
    [[ $line =~ ^[[:space:]]*$ ]] && continue

    if [[ $line =~ ^([^=]+)=(.*)$ ]]; then
      key="${match[1]}"
      value="${match[2]}"
      z::config::set "$key" "$value" || z::log::warn "Failed: $key=$value"
    fi
  done < "$file"

  z::log::info "Configuration loaded: $file"
  return 0
}

__z::config::init_defaults



################################################################################
# LAYER 5: INTROSPECTION
################################################################################

z::cmd::probe() {
  emulate -L zsh
  local cmd="${1:-}"
  [[ -z $cmd ]] && return $ZCORE_ERROR_INVALID_INPUT

  local cache_key="cmd:available:${cmd}"
  local cached
  if cached=$(z::cache::get "$cache_key" ); then
    return $cached
  fi

  typeset -i result=1
  (( $+commands[$cmd] )) && (( result = 0 ))

  z::cache::set "$cache_key" "$result" --ttl 300

  return $result
}

z::cmd::which() {
  emulate -L zsh
  local cmd="${1:-}"

  if ! z::cmd::probe "$cmd"; then
    z::log::error "Command not found: $cmd"
    return $ZCORE_ERROR_NOT_FOUND
  fi

  print -r -- "${commands[$cmd]}"
  return 0
}

z::func::probe() {
  emulate -L zsh
  local func="${1:-}"
  [[ -z $func ]] && return $ZCORE_ERROR_INVALID_INPUT

  local cache_key="func:available:${func}"
  local cached
  if cached=$(z::cache::get "$cache_key"); then
    return $cached
  fi

  typeset -i result=1
  (( $+functions[$func] )) && (( result = 0 ))

  z::cache::set "$cache_key" "$result" --ttl 60

  return $result
}

z::func::call() {
emulate -L zsh
local func="$1"

# Validate input
if [[ -z $func ]]; then
  z::log::error "Empty function name for z::func::call"
    return $ZCORE_ERROR_INVALID_INPUT
  fi
  shift

  if ! z::func::probe "$func"; then
    case $func in
      _git_prompt_info|__zconvey_on_period_passed*|_*prompt*|_*git*)
        return $ZCORE_ERROR_NOT_FOUND
        ;;
      *)
        z::log::warn "Function not found: $func"
        return $ZCORE_ERROR_NOT_FOUND
        ;;
    esac
  fi

  z::sys::interrupted || return $?

  typeset -i exit_code=0
  "$func" "$@" || exit_code=$?

  if (( exit_code != 0 )); then
    z::log::warn "Function '$func' failed: $exit_code"
  fi

  # if (( ${+functions[z::event::emit]} )); then
  #   z::event::emit "func:called" "$func" "$exit_code" || true
  # fi

  return $exit_code
}

z::func::unset() {
  emulate -L zsh
  setopt typeset_silent no_unset
  local target="${1:-}"

  if [[ -z $target ]]; then
    z::log::error "Function name required"
    return $ZCORE_ERROR_INVALID_INPUT
  fi

  if ! (( ${+functions[$target]} )); then
    return $ZCORE_ERROR_NOT_FOUND
  fi

  if unset -f -- "$target"; then
    z::cache::del "func:available:${target}"
    z::log::debug "Unset function: $target"

    if (( ${+functions[z::event::emit]} )); then
      z::event::emit "func:unset" "$target" || true
    fi

    return 0
  fi

  return $ZCORE_ERROR_GENERAL
}

z::func::list() {
  emulate -L zsh
  local pattern="${1:-*}"

  local func
  for func in ${(Mok)functions:#${~pattern}}; do
    print -r -- "$func"
  done
  return 0
}



################################################################################
# LAYER 6: VARIABLE MANAGEMENT
################################################################################

z::var::exists() {
  emulate -L zsh
  local name="${1:-}"
  [[ -z $name ]] && return $ZCORE_ERROR_INVALID_INPUT
  (( ${+parameters[$name]} ))
}

z::var::get() {
  emulate -L zsh
  local name="${1:-}" default="${2:-}"

  if [[ -z $name ]]; then
    print -r -- "$default"
    return 0
  fi

  if z::var::exists "$name"; then
    print -r -- "${(P)name}"
  else
    print -r -- "$default"
  fi
  return 0
}

z::var::set() {
  emulate -L zsh
  local name="${1:-}" value="${2:-}"

  if [[ -z $name ]]; then
    z::log::error "Variable name required"
    return $ZCORE_ERROR_INVALID_INPUT
  fi

  typeset -g "$name=$value"
  z::log::debug "Set variable: $name=$value"

  if (( ${+functions[z::event::emit]} )); then
    z::event::emit "var:set" "$name" "$value" || true
  fi

  return 0
}

z::var::unset() {
  emulate -L zsh
  setopt typeset_silent no_unset
  local target="${1:-}"

  if [[ -z $target ]]; then
    z::log::error "Variable name required"
    return $ZCORE_ERROR_INVALID_INPUT
  fi

  if ! (( ${+parameters[$target]} )); then
    return $ZCORE_ERROR_NOT_FOUND
  fi

  if [[ ${(tP)target} == *readonly* ]]; then
    z::log::error "Cannot unset readonly: $target"
    return $ZCORE_ERROR_PERMISSION
  fi

  if unset -v -- "$target"; then
    z::log::info "Unset variable: $target"

    if (( ${+functions[z::event::emit]} )); then
      z::event::emit "var:unset" "$target" || true
    fi

    return 0
  fi

  return $ZCORE_ERROR_GENERAL
}



################################################################################
# LAYER 7: FILESYSTEM
################################################################################

z::file::resolve() {
  emulate -L zsh
  local path="${1:-}"

  if [[ -z $path || $path =~ ^[[:space:]]*$ ]]; then
    z::log::error "Empty path"
    return $ZCORE_ERROR_INVALID_INPUT
  fi

  local cache_key="path:resolve:${path}"
  local cached
  if cached=$(z::cache::get "$cache_key"); then
    print -r -- "$cached"
    return 0
  fi

  # Tilde expansion
  if [[ $path == '~' || $path == '~/'* ]]; then
    path="${HOME}${path#\~}"
  elif [[ $path == '~+' || $path == '~+/'* ]]; then
    path="${PWD}${path#\~+}"
  elif [[ $path == '~-' || $path == '~-/'* ]]; then
    path="${OLDPWD:-$PWD}${path#\~-}"
  fi

  if [[ $path != /* ]]; then
    path="${PWD%/}/$path"
  fi

  local normalized
  normalized="${path:A}"
  if [[ -n $normalized ]]; then
    z::cache::set "$cache_key" "$normalized" --ttl 300
    printf '%s' "$normalized"
    return 0
  fi

  local current_path="$path"
  typeset -A visited_paths
  typeset -i iteration_count=0
  typeset -i max_iterations
  max_iterations=$(z::config::get symlink_max_iterations || print 40)
  (( max_iterations = 10#${max_iterations} ))

  if command -v readlink >/dev/null 2>&1; then
    while [[ -L $current_path ]]; do
      (( iteration_count += 1 ))
      if (( iteration_count > max_iterations )); then
        z::log::warn "Symlink resolution exceeded max"
        printf '%s' "$path"
        return $ZCORE_ERROR_GENERAL
      fi

      if (( ${+visited_paths[$current_path]} )); then
        z::log::warn "Symlink cycle detected"
        printf '%s' "$path"
        return $ZCORE_ERROR_GENERAL
      fi
      visited_paths[$current_path]=1

      local target
      target=$(readlink "$current_path" 2>/dev/null) || break
      [[ -z $target ]] && break

      if [[ $target == /* ]]; then
        current_path="$target"
      else
        current_path="${current_path:h}/$target"
      fi
    done
  fi

  if [[ -d ${current_path:h} ]]; then
    local physical_dir
    if physical_dir=$(cd -P "${current_path:h}" 2>/dev/null && pwd -P); then
      current_path="${physical_dir}/${current_path:t}"
    fi
  fi

  z::cache::set "$cache_key" "$current_path" --ttl 300

  printf '%s' "$current_path"
  return 0
}

z::file::source() {
local use_global_scope=false
if [[ ${1-} == --global ]]; then
  use_global_scope=true
  shift
fi

# Only use local emulation if not loading global config
if [[ $use_global_scope != true ]]; then
  emulate -L zsh
fi
  local file="${1:-}"
  shift

  if [[ -z $file ]]; then
    z::log::error "File path required"
    return $ZCORE_ERROR_INVALID_INPUT
  fi

  local resolved_file="$file"

  case $resolved_file in
    '~'|'~/'*)   resolved_file="${HOME}${resolved_file#~}" ;;
    '~+'|'~+/'*) resolved_file="${PWD}${resolved_file#~+}" ;;
    '~-'|'~-/'*) resolved_file="${OLDPWD:-$PWD}${resolved_file#~-}" ;;
  esac

  local perf_mode
  perf_mode=$(z::config::get performance_mode || print "false")

  if [[ $perf_mode != true ]]; then
    if ! resolved_file=$(z::file::resolve "$resolved_file"); then
      z::log::error "Failed to resolve: $file"
      return $ZCORE_ERROR_NOT_FOUND
    fi
  fi

  if [[ ! -f $resolved_file || ! -r $resolved_file ]]; then
    z::log::warn "File not readable: $resolved_file"
    return $ZCORE_ERROR_NOT_FOUND
  fi

  z::sys::interrupted || return $?

  typeset -i exit_code=0
  source "$resolved_file" "$@" || exit_code=$?

  if (( exit_code != 0 )); then
    z::log::warn "Failed to source: exit code $exit_code"
  else
    # z::cache::clear "func:*"

    if (( ${+functions[z::event::emit]} )); then
      z::event::emit "file:sourced" "$resolved_file" || true
    fi
  fi

  return $exit_code
}

z::file::exists() { emulate -L zsh; [[ -f ${1:-} ]]; }
z::file::readable() { emulate -L zsh; [[ -r ${1:-} ]]; }
z::file::writable() { emulate -L zsh; [[ -w ${1:-} ]]; }
z::file::is_directory() { emulate -L zsh; [[ -d ${1:-} ]]; }



################################################################################
# LAYER 8: ENVIRONMENT
################################################################################

z::env::path_add() {
  emulate -L zsh
  local dir="$1"
  local position="${2:-append}"

  if [[ -z $dir ]]; then
    z::log::error "Empty directory provided to z::path::add"
    return $ZCORE_ERROR_INVALID_INPUT
  fi

  local original_dir="$dir"
  if ! dir=$(z::file::resolve "$dir"); then
    z::log::debug "Failed to resolve directory path for PATH: $original_dir"
    return 1
  fi

  # Skip non-existent directories silently
  if [[ ! -d $dir ]]; then
    z::log::debug "Directory does not exist, not adding to PATH: $dir"
    return $ZCORE_ERROR_NOT_FOUND
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

      return $ZCORE_ERROR_INVALID_INPUT
      ;;
  esac

  builtin hash -r 2>/dev/null || true
  # z::cache::clear "cmd:*"

  z::log::debug "Added to PATH ($position): $dir"

  if (( ${+functions[z::event::emit]} )); then
    z::event::emit "env:path_added" "$dir" "$position" 2>/dev/null || true
  fi

  return 0
}

z::env::path_remove() {
  emulate -L zsh
  local dir="${1:-}"

  if [[ -z $dir ]]; then
    z::log::error "Directory required"
    return $ZCORE_ERROR_INVALID_INPUT
  fi

  if ! dir=$(z::file::resolve "$dir"); then
    dir="${1}"
  fi

  local -a path_array
  path_array=(${(s.:.)PATH})
  path_array=(${path_array:#$dir})
  export PATH="${(j.:.)path_array}"

  builtin hash -r || true
  # z::cache::clear "cmd:*"

  z::log::debug "Removed from PATH: $dir"

  if (( ${+functions[z::event::emit]} )); then
    z::event::emit "env:path_removed" "$dir" || true
  fi

  return 0
}

z::env::path_has() {
  emulate -L zsh
  local dir="${1:-}"
  [[ -z $dir ]] && return $ZCORE_ERROR_INVALID_INPUT
  [[ ":${PATH}:" == *":${dir}:"* ]]
}

z::env::alias_set() {
  emulate -L zsh
  setopt no_unset warn_create_global
  local alias_name="${1:-}" alias_value="${2:-}"

  if [[ -z $alias_name || -z $alias_value || $alias_name == *[[:space:]=]* ]]; then
    z::log::error "Invalid alias"
    return $ZCORE_ERROR_INVALID_INPUT
  fi

  if ! builtin alias "${alias_name}=${alias_value}"; then
    z::log::error "Failed to create alias"
    return $ZCORE_ERROR_GENERAL
  fi

  z::log::debug "Created alias: $alias_name='$alias_value'" 2>/dev/null
  return 0
}

z::env::alias_unset() {
  emulate -L zsh
  local alias_name="${1:-}"

  if [[ -z $alias_name ]]; then
    z::log::error "Alias name required"
    return $ZCORE_ERROR_INVALID_INPUT
  fi

  if ! builtin unalias "$alias_name"; then
    return $ZCORE_ERROR_NOT_FOUND
  fi

  z::log::debug "Unset alias: $alias_name"
  return 0
}

z::env::export() {
  emulate -L zsh
  local name="${1:-}" value="${2:-}"

  if [[ -z $name ]]; then
    z::log::error "Variable name required"
    return $ZCORE_ERROR_INVALID_INPUT
  fi

  export "$name=$value"
  z::log::info "Exported: $name=$value"
  return 0
}


################################################################################
# LAYER 9: EXECUTION
################################################################################

typeset -g _zcore_timeout_cmd=""
if (( $+commands[timeout] )); then
  _zcore_timeout_cmd="timeout"
elif (( $+commands[gtimeout] )); then
  _zcore_timeout_cmd="gtimeout"
fi

__z::exec::is_init_cmd() {
  emulate -L zsh
  local input="$1"
  [[ $input =~ '(starship|mise|direnv|zoxide|atuin|mcfly|fzf|oh-my-posh)[[:space:]]+init([[:space:]]|$)' ]]
}

__z::exec::has_dangerous_metachars() {
  emulate -L zsh
  local input="$1"
  [[ -z $input ]] && return 1
  [[ $input =~ '[;&()]' ]] || [[ $input == *'`'* ]]
}

__z::exec::check_segment() {
  emulate -L zsh
  local cmd="$1"
  shift
  local -a args=("$@")

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
    if (( have_r && have_f )); then
      for a in "${args[@]}"; do
        case $a in
          /|/*|~|~/*|'$HOME'|'$HOME'/*)
            z::log::error "Dangerous rm: $a"
            return 1
            ;;
        esac
      done
    fi
  fi

  if [[ $cmd == dd ]]; then
    local kv dev base
    for kv in "${args[@]}"; do
      if [[ $kv == of=/dev/* ]]; then
        dev="${kv#of=}"
        base="${dev#/dev/}"
        case $base in
          sd*|hd*|nvme*|disk*|rdisk*)
            z::log::error "Dangerous dd: $dev"
            return 1
            ;;
        esac
      fi
    done
  fi

  return 0
}

__z::exec::scan_patterns() {
  emulate -L zsh
  setopt localoptions typeset_silent
  local input="${1:-}"
  [[ -z $input ]] && return 0

  local perf_mode
  perf_mode=$(z::config::get performance_mode || print "false")

  if [[ $perf_mode == true ]]; then
    if [[ $input != *'rm '* && $input != *'dd '* && $input != *'|'* ]]; then
      return 0
    fi
  fi

  if __z::exec::is_init_cmd "$input"; then
    return 0
  fi

  local -a words
  words=(${(z)input})
  (( ${#words} == 0 )) && return 0

  typeset -i i j
  local next_cmd base
  for (( i = 1; i <= ${#words}; i++ )); do
    if [[ ${words[i]} == '|' ]]; then
      (( j = i + 1 ))
      while (( j <= ${#words} )); do
        case ${words[j]} in
          '|'|'||'|'&&'|';'|'&') break ;;
          nocorrect|noglob|builtin|command|exec|time|nice|nohup|sudo|doas|env)
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
          sh|bash|zsh|ksh|dash)
            z::log::error "Dangerous: pipe to shell"
            return 1
            ;;
        esac
      fi
    fi
  done

  if [[ $input =~ ':\(\)' && $input =~ ':\|:' ]]; then
    z::log::error "Dangerous: fork bomb"
    return 1
  fi

  local -a seg=()
  local w
  for w in "${words[@]}"; do
    case $w in
      '|'|'||'|'&&'|';'|'&')
        if (( ${#seg} )); then
          local cmd="${seg[1]}"
          local -a args=("${(@)seg[2,-1]}")
          __z::exec::check_segment "$cmd" "${args[@]}" || return 1
          seg=()
        fi
        ;;
      nocorrect|noglob|builtin|command|exec|time|nice|nohup|sudo|doas|env)
        if (( ${#seg} == 0 )); then
          continue
        else
          seg+=("$w")
        fi
        ;;
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

  if (( ${#seg} )); then
    local cmd="${seg[1]}"
    local -a args=("${(@)seg[2,-1]}")
    __z::exec::check_segment "$cmd" "${args[@]}" || return 1
  fi

  return 0
}

z::exec::run() {
  emulate -L zsh
  local input="${1:-}"
  typeset -i timeout
  timeout=$(z::config::get timeout_default || print 30)
  (( timeout = 10#${2:-$timeout} ))

  if [[ -z $input ]]; then
    z::log::error "Command required"
    return $ZCORE_ERROR_INVALID_INPUT
  fi

  if ! __z::exec::is_init_cmd "$input"; then
    if __z::exec::has_dangerous_metachars "$input"; then
      z::log::error "Rejected dangerous metacharacters"
      return $ZCORE_ERROR_PERMISSION
    fi
  fi

  __z::exec::scan_patterns "$input" || return $?
  z::sys::interrupted || return $?

  if (( ${+functions[z::event::emit]} )); then
    z::event::emit "exec:start" "$input" || true
  fi

  typeset -i exit_code=0

  if [[ -n ${_zcore_timeout_cmd:-} ]]; then
    ${_zcore_timeout_cmd} "$timeout" zsh -o pipefail -c "$input" || exit_code=$?
    if (( exit_code == 124 )); then
      z::log::warn "Timeout after ${timeout}s"

      if (( ${+functions[z::event::emit]} )); then
        z::event::emit "exec:timeout" "$input" "$timeout" || true
      fi
    fi
  else
    zsh -o pipefail -c "$input" || exit_code=$?
  fi

  if (( exit_code != 0 && exit_code != 124 )); then
    z::log::warn "Command failed: exit code $exit_code"
  fi

  if (( ${+functions[z::event::emit]} )); then
    z::event::emit "exec:complete" "$input" "$exit_code" || true
  fi

  return $exit_code
}

z::exec::eval() {
  emulate -L zsh
  local input="${1:-}"
  typeset -i timeout
  timeout=$(z::config::get timeout_default || print 30)
  (( timeout = 10#${2:-$timeout} ))
  local force_shell="${3:-false}"

  if [[ -z $input ]]; then
    z::log::error "Command required"
    return $ZCORE_ERROR_INVALID_INPUT
  fi

  if [[ $force_shell == true ]]; then
    z::log::warn "Forced eval in current shell"
    z::sys::interrupted || return $?

    typeset -i exit_code=0
    builtin eval -- "$input" || exit_code=$?

    if (( exit_code != 0 )); then
      z::log::warn "Forced eval failed: $exit_code"
    fi
    return $exit_code
  fi

  local is_shell_init=false
  __z::exec::is_init_cmd "$input" && is_shell_init=true

  local perf_mode
  perf_mode=$(z::config::get performance_mode || print "false")

  if [[ $perf_mode != true ]] && [[ $is_shell_init != true ]]; then
    __z::exec::scan_patterns "$input" || return $?
  fi

  z::sys::interrupted || return $?

  z::exec::run "$input" "$timeout"
}

z::exec::async() {
  emulate -L zsh
  local cmd="${1:-}" callback="${2:-}"

  {
    emulate -L zsh
    local result
    result=$(z::exec::run "$cmd" 2>&1)
    local exit_code=$?

    if [[ -n $callback ]] && z::func::probe "$callback"; then
      "$callback" "$exit_code" "$result"
    fi

    if (( ${+functions[z::event::emit]} )); then
      z::event::emit "exec:async_complete" "$cmd" "$exit_code" || true
    fi
  } &

  local job_id=$!
  print -r -- "$job_id"
  return 0
}

z::exec::wait_all() {
  emulate -L zsh
  wait
  return 0
}

z::exec::from_hook() {
  emulate -L zsh
  local tool_name="${1:-}"
  local subcommand="${2:-init}"
  local shell_arg="${3:-zsh}"

  z::sys::interrupted || return $?

  if ! z::cmd::probe "$tool_name"; then
    z::log::debug "$tool_name not found"
    return 0
  fi

  local init_code
  if init_code=$("$tool_name" "$subcommand" "$shell_arg") && [[ -n $init_code ]]; then
    if z::exec::eval "$init_code" 30 true; then
      z::log::debug "$tool_name initialized"

      if (( ${+functions[z::event::emit]} )); then
        z::event::emit "exec:hook_loaded" "$tool_name" || true
      fi

      return 0
    else
      z::log::warn "Failed to init $tool_name"
      return $ZCORE_ERROR_GENERAL
    fi
  else
    z::log::warn "Failed to get hook from $tool_name"
    return $ZCORE_ERROR_GENERAL
  fi
}

z::exec::scan() {
  emulate -L zsh
  local input="${1:-}"
  [[ -z $input ]] && return $ZCORE_ERROR_INVALID_INPUT
  __z::exec::scan_patterns "$input"
}

z::exec::is_safe() {
  emulate -L zsh
  z::exec::scan "$@"
}



################################################################################
# LAYER 10: UI
################################################################################

z::ui::width() {
  emulate -L zsh

  local cached
  if cached=$(z::cache::get "ui:term_width"); then
    print -r -- "$cached"
    return 0
  fi

  typeset -i width=80
  local columns_current="${COLUMNS:-}"

  if [[ -n $columns_current && $columns_current == <-> ]]; then
    (( width = 10#${columns_current} ))
  elif (( $+commands[tput] )); then
    local tput_width
    if tput_width=$(tput cols) && [[ $tput_width == <-> ]]; then
      (( width = 10#${tput_width} ))
    fi
  fi

  z::cache::set "ui:term_width" "$width" --ttl 1
  print -r -- "$width"
  return 0
}

z::ui::height() {
  emulate -L zsh
  typeset -i rows=24

  if [[ -n ${LINES:-} && ${LINES} == <-> ]]; then
    (( rows = 10#${LINES} ))
  elif (( $+commands[tput] )); then
    local tput_height
    if tput_height=$(tput lines) && [[ $tput_height == <-> ]]; then
      (( rows = 10#${tput_height} ))
    fi
  fi

  print -r -- "$rows"
  return 0
}

# z::ui::clear_line [OPTIONS]
#
# Clears the current line on stderr (useful for progress bars, prompts).
#
# Options:
#   -n, --no-newline  Do not move to next line after clearing (default)
#   -f, --force       Force clear even if not a terminal
#
# Examples:
#   z::ui::clear_line           # Clear line, move to next
#   z::ui::clear_line -n        # Clear line, stay on same line
#   z::ui::clear_line -f        # Force clear even if not a terminal
#
# Returns:
#   0 on success, 1 on error
z::ui::clear_line() {
  emulate -L zsh
  local -A opts
  zparseopts -D -E -A opts -- f n force no-newline

  local force=$(z::opt::has opts 'f' 'force' && print 1 || print 0)
  local newline=$(z::opt::has opts 'n' 'no-newline' && print 0 || print 1)

  [[ $force -eq 0 && ! -t 2 ]] && return 0

  printf '\r\e[K'

  [[ $newline -eq 1 ]] && printf '\n' >&2

  return 0
}


z::ui::clear() {
  emulate -L zsh
  if [[ -t 1 ]]; then
    clear
  fi
  return 0
}

z::ui::color() {
  emulate -L zsh

  # If no arguments, return default color
  if [[ $# -eq 0 ]]; then
    print -r -- "${_zcore_colors[reset]:-}"
    return 0
  fi

  local name="${1}"
  local text="${@:2}"

  # If no text (i.e., only color), return the color code
  if [[ $# -eq 1 ]]; then
    print -r -- "${_zcore_colors[$name]:-}"
    return 0
  fi

  # Otherwise, print colored text
  print -r -- "${_zcore_colors[$name]:-}" "${text}" "${_zcore_colors[reset]:-}"
  return 0
}


################################################################################
# PROGRESS
################################################################################

__z::progress::should_show()
{
  emulate -L zsh
  typeset -i current total interval
  (( current = 10#${1} ))
  (( total = 10#${2} ))
  (( interval = 10#$(z::config::get progress_update_intervala)))

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


z::progress::show()
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
  if (( ${_zcore_logging[level]} < ${_zcore_logging[info]} )) || \
    [[ ! -t 2 ]] || \
    [[ $(z::config::get show_progress) == false ]]; then
    return 0
  fi

  # Throttle updates for performance
  z::progress::_should_show "$current" "$total" || return 0

  typeset -i term_width percent_int filled bar_width empty_len
  (( term_width = $(z::term::width) ))

  # Calculate percentage safely
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

z::progress::clear() { emulate -L zsh; z::clear_line; }

z::progress::enable() {
  emulate -L zsh
  z::config::set show_progress true
}

z::progress::disable() {
  emulate -L zsh
  z::config::set show_progress false
}

z::progress::spinner() {
  emulate -L zsh
  local message="${1:-Working...}"

  local show_progress
  show_progress=$(z::config::get show_progress || print "true")

  if [[ ! -t 2 ]] || [[ $show_progress == false ]]; then
    return 0
  fi

  local -a frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  typeset -i frame_idx
  (( frame_idx = EPOCHSECONDS % ${#frames[@]} + 1 ))

  printf '\r%s %s' "${frames[frame_idx]}" "$message" >&2
  return 0
}



################################################################################
# DEBUGGING
################################################################################
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
  local -i i
  print "Stack trace:" >&2
  for (( i = 1; i < ${#funcstack[@]}; i++ )); do
    print "  $i: ${funcstack[i]} (${funcfiletrace[i]})" >&2
  done
  return 0
}

z::debug::dump() {
  emulate -L zsh
  z::config::show
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
  local operation="${1:-operation}"
  z::kv::set "profiling.$1.start" "${EPOCHREALTIME:-0}"
  z::log::debug "[Profiler]" 'Profiling instace initiated for operation:' "$operation"
  return 0
}

z::debug::profile_end() {

  emulate -L zsh

  local operation="${1:-operation}"
  local start end duration round

  (( start = $(z::kv::get "profiling.$1.start") ))
  end="${EPOCHREALTIME}"
  duration=$(echo "$end - $start" | bc)
  z::kv::set "profiling.$1.end" $end
  z::kv::set "profiling.$1.duration" $duration
  round=$(printf "%.3f" $duration)
  z::log::debug "[Profiler]" 'Profiling for operation:' "$operation" 'Finished with result:' "${round}s"
  if (( ${+functions[z::event::emit]} )); then
    z::event::emit "debug:profile" "$operation" "$duration" || true
  fi

  return 0
}

z::debug::assert() {
  emulate -L zsh
  typeset -i condition
  (( condition = ${1:-1} ))
  local message="${2:-Assertion failed}"

  if (( condition != 0 )); then
    z::debug::trace
    z::sys::die "$message" $ZCORE_ERROR_GENERAL
  fi
  return 0
}



################################################################################
# HELP SYSTEM
################################################################################

z::help::list() {
  emulate -L zsh
  local namespace="${1:-z::}"

  local func
  for func in ${(Mok)functions:#${namespace}*}; do
    [[ $func == *::_* ]] && continue
    print -r -- "$func"
  done
  return 0
}

z::help::quick() {
  emulate -L zsh

  cat <<'EOF'
ZCORE Framework v3.0 - Quick Reference
======================================

🔴 LOGGING PILLAR:
  z::log::error "msg"          - Log error
  z::log::warn "msg"           - Log warning
  z::log::info "msg"           - Log info
  z::log::debug "msg"          - Log debug
  z::log::set_level level      - Set log level

🔵 CACHE PILLAR:
  z::cache::set key val [--ttl N] - Set cache
  z::cache::get key            - Get cache
  z::cache::del key            - Delete
  z::cache::clear [pattern]    - Clear cache
  z::cache::stats [ns]         - Statistics
  z::cache::memoize key ttl fn - Memoize

🟠 KV STORE PILLAR:
  z::kv::set key val [--ttl N] - Set value
  z::kv::get key               - Get value
  z::kv::del key               - Delete
  z::kv::exists key            - Check exists
  z::kv::keys [pattern]        - List keys
  z::kv::incr key [n]          - Increment
  z::kv::watch pattern handler - Watch changes
  z::kv::save file             - Save to disk
  z::kv::load file             - Load from disk
  z::kv::lock name [ttl]       - Acquire lock
  z::kv::unlock name           - Release lock
  z::kv::begin                 - Start transaction
  z::kv::commit                - Commit
  z::kv::rollback              - Rollback

🟣 EVENT SYSTEM (if loaded):
  z::event::on event handler   - Register
  z::event::emit event [args]  - Emit
  z::event::off event [handler]- Remove
  z::event::list [pattern]     - List handlers
  z::event::stats [filter]     - Statistics

CONFIGURATION (KV-backed):
  z::config::get key           - Get config
  z::config::set key value     - Set config
  z::config::watch pattern fn  - Watch changes
  z::config::show              - Show all
  z::config::save file         - Save
  z::config::load file         - Load

SYSTEM:
  z::sys::platform             - Detect platform
  z::sys::is_macos             - Check macOS
  z::sys::interrupted          - Check interrupt
  z::sys::die "msg" [code]     - Fatal error

EXECUTION:
  z::exec::run "cmd"           - Safe run
  z::exec::eval "cmd"          - Evaluate
  z::exec::async "cmd" cb      - Background
  z::exec::from_hook tool      - Init hook

FILES:
  z::file::resolve path        - Resolve
  z::file::source file         - Source
  z::file::exists path         - Check

COMMANDS & FUNCTIONS:
  z::cmd::probe name    - Check cmd
  z::func::probe name     - Check func
  z::func::call name args...   - Call func

VALIDATION:
  z::validate::not_empty n v   - Not empty
  z::validate::is_integer n v  - Integer
  z::validate::in_range n v m M- Range

PROGRESS:
  z::progress::show cur tot lbl- Show bar
  z::progress::enable          - Enable
  z::progress::disable         - Disable

For more: z::help::list [namespace]
EOF
  return 0
}


################################################################################
# AUTO-LOAD EVENT SYSTEM (Optional)
################################################################################

ZCORE_DIR="${${(%):-%x}:A:h}"
if [[ -f "$ZCORE_DIR/zcore-event.zsh" ]]; then
  source "$ZCORE_DIR/zcore-event.zsh"
  z::log::debug "Event system auto-loaded ✓"
else
  z::log::debug "Event system not found (optional)"
fi

################################################################################
# INITIALIZATION
################################################################################

z::sys::platform

if [[ -o interactive ]] || [[ ${ZCORE_INSTALL_TRAPS:-} == true ]]; then
  trap '__z::sys::handle_interrupt' INT TERM
fi

if (( ${+functions[z::event::emit]} )); then
  z::event::emit "zcore:initialized" "$ZCORE_VERSION" || true
fi

z::log::info "ZCORE v3.0 initialized"
z::log::info "Logging ✓ | Cache ✓ | KV Store ✓ | Events $( (( ${+functions[z::event::emit]} )) && echo '✓' || echo '✗' )"
