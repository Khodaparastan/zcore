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
  z::kv::open profiling 2>/dev/null || true
  z::kv::set profiling "$1.start" "${EPOCHREALTIME:-0}"
  z::log::debug "[Profiler]" 'Profiling instace initiated for operation:' "$operation"
  return 0
}

z::debug::profile_end() {

  emulate -L zsh

  local operation="${1:-operation}"
  local start end duration round

  (( start = $(z::kv::get profiling "$1.start") ))
  end="${EPOCHREALTIME}"
  duration=$(echo "$end - $start" | bc)
  z::kv::set profiling "$1.end" $end
  z::kv::set profiling "$1.duration" $duration
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

  z::kv::open config

  z::kv::set config "log_level"               "$_zlog_config[level]" --type int
  z::kv::set config "cache_max_size"           "100"   --type int
  z::kv::set config "timeout_default"          "30"    --type int
  z::kv::set config "performance_mode"         "false" --type bool
  z::kv::set config "show_progress"            "true"  --type bool
  z::kv::set config "symlink_max_iterations"   "40"    --type int
  z::kv::set config "progress_update_interval" "10"    --type int

  if [[ -n ${ZCORE_PERFORMANCE_MODE:-} ]]; then
    z::kv::set_bool config "performance_mode" "$ZCORE_PERFORMANCE_MODE"
  fi

  if [[ -n ${ZCORE_SHOW_PROGRESS:-} ]]; then
    z::kv::set_bool config "show_progress" "$ZCORE_SHOW_PROGRESS"
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

  z::kv::get config "${key}"
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
      z::kv::set_bool config "${key}" "$value"
      ;;
    *_size|*_timeout|*_depth|*_threshold|*_interval|*_iterations|*_level)
      if [[ $value != <-> ]]; then
        z::log::error "Integer required for $key"
        return $ZCORE_ERROR_INVALID_INPUT
      fi
      z::kv::set_int config "${key}" "$value"
      ;;
    *)
      z::kv::set config "${key}" "$value"
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

  z::kv::watch config "${pattern}" "$handler"
}

z::config::show() {
  emulate -L zsh

  print "\nConfiguration:"
  print "=============="

  local -a config_keys
  z::kv::keys config "*"
  config_keys=("${reply[@]}")

  local key value
  for key in "${config_keys[@]}"; do
    value=$(z::kv::get config "$key" || print "N/A")
    printf "  %-30s = %s\n" "$key" "$value"
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
    z::kv::keys config "*"
    config_keys=("${reply[@]}")

    local key value
    for key in "${config_keys[@]}"; do
      value=$(z::kv::get config "$key" || print "")
      print "${key}=${value}"
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

# __z::config::init_defaults







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

if [[ -o interactive ]] || [[ ${ZCORE_INSTALL_TRAPS:-} == true ]]; then
  trap '__z::sys::handle_interrupt' INT TERM
fi


z::log::info "zCore initialized .::. Cache $( (( ${+functions[z::cache::get]} )) && echo '✓' || echo '✗') | KV Store $( (( ${+functions[z::kv::get]} )) && echo '✓' || echo '✗') | Event Bus $( (( ${+functions[z::event::emit]} )) && echo '✓' || echo '✗')"
