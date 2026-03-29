#!/usr/bin/env zsh

################################################################################
# ZCORE v0.3.0
################################################################################
#
#  Layers:
#      ZLOG (Logging)   - No dependencies
#      Internal CACHING - Depends on: Logging
#      ZKV (KV STORE)   - Depends on: Logging
#      ZBUS (Event BUS) - Depends on: Logging, zkv
#
# Integration layer connects pillars AFTER all are loaded
#
# Version: v0.3.0
# License: MIT
################################################################################
# Double-sourcing Guard
# Prevents this module from being initialized multiple times in the same session.
# Returns 0 when already loaded (whether sourced or executed).
if [[ ${_zcore_loaded:-} == 1 ]]; then return 0 2>/dev/null || exit 0; fi
typeset -g _zcore_loaded=1
typeset -gr ZCORE_VERSION="0.3.0"


# Ensure EPOCHSECONDS is available when possible (no-op if unavailable)
zmodload -F zsh/datetime b:EPOCHSECONDS 2>/dev/null || true

# Standard return codes
typeset -gri ZCORE_SUCCESS=0
typeset -gri ZCORE_ERROR_GENERAL=1
typeset -gri ZCORE_ERROR_NOT_FOUND=2
typeset -gri ZCORE_ERROR_INVALID_INPUT=3
typeset -gri ZCORE_ERROR_PERMISSION=4
typeset -gri ZCORE_ERROR_TIMEOUT=124
typeset -gri ZCORE_ERROR_INTERRUPTED=130


###
# Current logging verbosity level
# 0 = error only, 1 = warn, 2 = info (default), 3 = debug
###
typeset -gA _zcore_subsys
_zcore_subsys[kv]=0;_zcore_subsys[bus]=0;_zcore_subsys[cache]=0;



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
  setopt extendedglob warncreateglobal typesetsilent noshortloops nopromptsubst
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
  if (( _zcore_subsys[bus]==1 )); then
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
  setopt extendedglob warncreateglobal typesetsilent noshortloops nopromptsubst

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
  setopt extendedglob warncreateglobal typesetsilent noshortloops nopromptsubst

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
  setopt extendedglob warncreateglobal typesetsilent noshortloops nopromptsubst

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
  setopt extendedglob warncreateglobal typesetsilent noshortloops nopromptsubst
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
  setopt extendedglob warncreateglobal typesetsilent noshortloops nopromptsubst

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
  setopt extendedglob warncreateglobal typesetsilent noshortloops nopromptsubst

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
  setopt extendedglob warncreateglobal typesetsilent noshortloops nopromptsubst

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
  setopt extendedglob warncreateglobal typesetsilent noshortloops nopromptsubst


  local name="$1" context="${2:-Identifier}"

  if [[ -z $name ]]; then
    z::log::error "${context} cannot be empty"
    return 1
  fi

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
  setopt extendedglob warncreateglobal typesetsilent noshortloops nopromptsubst

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
  setopt extendedglob warncreateglobal typesetsilent noshortloops nopromptsubst

  local value="$1" field_name="${2:-Value}"

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
  setopt extendedglob warncreateglobal typesetsilent noshortloops nopromptsubst

  local value="$1" field_name="${4:-Value}"
  typeset -i min_val max_val int_value

  if [[ -z ${2-} || -z ${3-} ]]; then
    z::log::error "z::validate::integer::range: min and max parameters required"
    return 1
  fi

  (( min_val = ${2} ))
  (( max_val = ${3} ))
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
#   z::probe::path "$config_file" 'file' "Config file" || return 1
###
z::probe::path()
{
  emulate -L zsh
  setopt extendedglob warncreateglobal typesetsilent noshortloops nopromptsubst
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
      z::log::error "z::probe::path: invalid path_type '${path_type}' (must be file, dir, or any)"
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
#   z::probe::path::readable "$input_file" "Input file" || return 1
###
z::probe::path::readable()
{
  emulate -L zsh
  setopt extendedglob warncreateglobal typesetsilent noshortloops nopromptsubst

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
#   z::probe::path::writable "$output_file" "Output file" || return 1
###
z::probe::path::writable()
{
  emulate -L zsh
  setopt extendedglob warncreateglobal typesetsilent noshortloops nopromptsubst

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
  setopt extendedglob warncreateglobal typesetsilent noshortloops nopromptsubst
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
  setopt extendedglob warncreateglobal typesetsilent noshortloops nopromptsubst

  local value="$1" field_name="${2:-Value}"

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
# CACHE - Depends ONLY on Logging
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

  if ((_zcore_subsys[kv]==1)); then
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
    if ((_zcore_subsys[bus]==1)); then
      z::event::emit "cache:miss" "$key" "expired" || true
    fi
    return $ZCORE_ERROR_NOT_FOUND
  fi

  if (( ! ${+_zcore_cache_store[$key]} )); then
    local namespace="${key%%:*}"
    typeset -i misses
    (( misses = ${_zcore_cache_stats[${namespace}.misses]:-0} + 1 ))
    _zcore_cache_stats[${namespace}.misses]=$misses

    if (( _zcore_subsys[bus]==1 )); then
      z::event::emit "cache:miss" "$key" "not_found" || true
    fi
    return $ZCORE_ERROR_NOT_FOUND
  fi

  local namespace="${key%%:*}"
  typeset -i hits
  (( hits = ${_zcore_cache_stats[${namespace}.hits]:-0} + 1 ))
  _zcore_cache_stats[${namespace}.hits]=$hits
  if (( _zcore_subsys[bus]==1 )); then
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
  if (( _zcore_subsys[bus]==1 )); then
    z::event::emit "cache:delete" "$key" || true
  fi
  return 0
}

z::probe::cache() {
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
  if ((_zcore_subsys[bus]==1)); then
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
# LAYER 2: SYSTEM CORE
################################################################################

typeset -gi _zcore_interrupted=0

__z::sys::handle_interrupt() {
  emulate -L zsh
  setopt extendedglob warncreateglobal typesetsilent noshortloops nopromptsubst
  if [[ -n ${ZLE_STATE:-} ]]; then
    return 0
  fi

  if (( _zcore_interrupted == 0 )); then
    (( _zcore_interrupted = 1 ))
    z::progress::clear
    z::log::warn "Interrupt received. Gracefully shutting down..."

    if ((_zcore_subsys[bus]==1)); then
      z::event::emit "sys:interrupted"
    fi
  fi
  return 0
}

z::sys::interrupted() {
  emulate -L zsh
  setopt extendedglob warncreateglobal typesetsilent noshortloops nopromptsubst
  if (( _zcore_interrupted )); then
    z::log::info "Operation cancelled by user."
    return $ZCORE_ERROR_INTERRUPTED
  fi
  return 0
}

z::sys::die()
{
  emulate -L zsh
  # setopt no_unset
  setopt extendedglob warncreateglobal typesetsilent noshortloops nopromptsubst
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
  setopt extendedglob warncreateglobal typesetsilent noshortloops nopromptsubst

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

  if ((_zcore_subsys[bus]==1)); then
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

  z::kv::set "config:log_level" "$_zlog_config[level]" --type int
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

  if ((_zcore_subsys[bus]==1)); then
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

z::probe::cmd() {
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

  if ! z::probe::cmd "$cmd"; then
    z::log::error "Command not found: $cmd"
    return $ZCORE_ERROR_NOT_FOUND
  fi

  print -r -- "${commands[$cmd]}"
  return 0
}

z::probe::func() {
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

  if ! z::probe::func "$func"; then
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

  typeset -i exit_code=0
  "$func" "$@" || exit_code=$?

  if (( exit_code != 0 )); then
    z::log::warn "Function '$func' failed: $exit_code"
  fi

  if ((_zcore_subsys[bus]==1)); then
    z::event::emit "func:called" "$func" "$exit_code" || true
  fi

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

    if ((_zcore_subsys[bus]==1)); then
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

z::probe::var() {
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

  if z::probe::var "$name"; then
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

  if ((_zcore_subsys[bus]==1)); then
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

    if ((_zcore_subsys[bus]==1)); then
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


  typeset -i exit_code=0
  source "$resolved_file" "$@" || exit_code=$?

  if (( exit_code != 0 )); then
    z::log::warn "Failed to source: exit code $exit_code"
  else
    # z::cache::clear "func:*"

    if ((_zcore_subsys[bus]==1)); then
      z::event::emit "file:sourced" "$resolved_file" || true
    fi
  fi

  return $exit_code
}

z::probe::file() { emulate -L zsh; [[ -f ${1:-} ]]; }
z::file::readable() { emulate -L zsh; [[ -r ${1:-} ]]; }
z::file::writable() { emulate -L zsh; [[ -w ${1:-} ]]; }
z::probe::dir() { emulate -L zsh; [[ -d ${1:-} ]]; }



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

  if ((_zcore_subsys[bus]==1)); then
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

  if ((_zcore_subsys[bus]==1)); then
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
  setopt typesetsilent noshortloops nopromptsubst extendedglob
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


  if (( _zcore_subsys[bus]==1 )); then
    z::event::emit "exec:start" "$input" || true
  fi

  typeset -i exit_code=0

  if [[ -n ${_zcore_timeout_cmd:-} ]]; then
    ${_zcore_timeout_cmd} "$timeout" zsh -o pipefail -c "$input" || exit_code=$?
    if (( exit_code == 124 )); then
      z::log::warn "Timeout after ${timeout}s"

      if (( _zcore_subsys[bus]==1 )); then
        z::event::emit "exec:timeout" "$input" "$timeout" || true
      fi
    fi
  else
    zsh -o pipefail -c "$input" || exit_code=$?
  fi

  if (( exit_code != 0 && exit_code != 124 )); then
    z::log::warn "Command failed: exit code $exit_code"
  fi

  if (( _zcore_subsys[bus]==1 )); then
    z::event::emit "exec:complete" "$input" "$exit_code" || true
  fi

  return $exit_code
}

z::exec::eval() {
  emulate -L zsh
  local input="${1:-}"
  local cmd="${4:-unknown}"
  typeset -i timeout
  timeout=$(z::config::get timeout_default || print 30)
  (( timeout = 10#${2:-$timeout} ))
  local force_shell="${3:-false}"

  if [[ -z $input ]]; then
    z::log::error "Command required"
    return $ZCORE_ERROR_INVALID_INPUT
  fi

  if [[ $force_shell == true ]]; then
    z::log::info "Forced eval in current shell: $cmd"


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

    if [[ -n $callback ]] && z::probe::func "$callback"; then
      "$callback" "$exit_code" "$result"
    fi

    if (( _zcore_subsys[bus]==1 )); then
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



  if ! z::probe::cmd "$tool_name"; then
    z::log::debug "$tool_name not found"
    return 0
  fi

  local init_code init_command
  if init_code=$("$tool_name" "$subcommand" "$shell_arg") && [[ -n $init_code ]]; then
    init_command="$tool_name $subcommand $shell_arg"
    if z::exec::eval "$init_code" 30 true $init_command; then
      z::log::debug "$tool_name initialized"

      if (( _zcore_subsys[bus]==1 )); then
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
  zparseopts -F -D -E -A opts -- f n force no-newline

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
  if (( ${_zlog_config[level]} < _ZLOG_LEVEL_INFO )) || \
    [[ ! -t 2 ]] || \
    [[ $(z::config::get show_progress) == false ]]; then
    return 0
  fi

  # Throttle updates for performance
  __z::progress::should_show "$current" "$total" || return 0

  typeset -i term_width percent_int filled bar_width empty_len
  (( term_width = $(z::ui::width) ))

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
ZCORE - Quick Reference
======================================
EOF
  return 0
}

if (( _zcore_subsys[bus]==1 )); then
  if [[ -f "$ZCORE_LIBDIR/zbus.zsh" ]]; then
    source "$ZCORE_LIBDIR/zbus.zsh"
    z::event::emit "zcore:initialized" "$ZCORE_VERSION" || true
    z::log::debug "Event system auto-loaded ✓"
  else
    z::log::debug "Event system not found (optional)"
  fi
fi
################################################################################
# INITIALIZATION
################################################################################

z::sys::platform

if [[ -o interactive ]] || [[ ${ZCORE_INSTALL_TRAPS:-} == true ]]; then
  trap '__z::sys::handle_interrupt' INT TERM
fi


z::log::info "zCore initialized .::. Cache $( (( ${+functions[z::cache::get]} )) && echo '✓' || echo '✗') | KV Store $( (( ${+functions[z::kv::get]} )) && echo '✓' || echo '✗') | Event Bus $( (( ${+functions[z::event::emit]} )) && echo '✓' || echo '✗')"
