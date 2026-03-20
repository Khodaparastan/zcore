#!/usr/bin/env zsh

# ==============================================================================
# Z FRAMEWORK
# ==============================================================================

# Ensure EPOCHSECONDS is available when possible (no-op if unavailable)
zmodload -F zsh/datetime b:EPOCHSECONDS 2>/dev/null || true

typeset -gA _z_config
_z_config[log_error]=0
_z_config[log_warn]=1
_z_config[log_info]=2
_z_config[log_debug]=3
_z_config[exit_general_error]=1
_z_config[exit_interrupted]=130
_z_config[progress_update_interval]=10
_z_config[timeout_default]=30
_z_config[log_max_depth]=50
_z_config[cache_max_size]=100
_z_config[performance_mode]=${Z_CONFIG_PERFORMANCE_MODE:-false}
_z_config[show_progress]=${Z_CONFIG_SHOW_PROGRESS:-true}
# Optional: allow to extend/override init whitelist via regex (empty by default)
_z_config[init_whitelist_regex]=''

# Global verbosity level
# 0 = error only, 1 = warn, 2 = info (default), 3 = debug
typeset -gi _z_verbose_level=${_z_config[log_info]}
if [[ "${z_config_verbose:-}" == <-> ]]; then
  if (( z_config_verbose > _z_config[log_info] )) &&
    [[ "${_z_config[performance_mode]}" != "true" ]]; then
    _z_verbose_level=$z_config_verbose
  elif (( z_config_verbose <= _z_config[log_info] )); then
    _z_verbose_level=$z_config_verbose
  fi
fi

# Function to enable debug mode
z::log::enable_debug()
{
  emulate -L zsh
  _z_verbose_level=${_z_config[log_debug]}
  z::log::info "Debug mode enabled"
}

# Function to check current verbosity level
z::log::get_level()
{
  emulate -L zsh
  local level_name
  case $_z_verbose_level in
    (${_z_config[log_error]}) level_name="error" ;;
    (${_z_config[log_warn]}) level_name="warn" ;;
    (${_z_config[log_info]}) level_name="info" ;;
    (${_z_config[log_debug]}) level_name="debug" ;;
    (*) level_name="unknown" ;;
  esac
  print -r -- "Current verbosity level: $_z_verbose_level ($level_name)"
}

# Function to toggle progress bars on/off
z::log::toggle_progress()
{
  emulate -L zsh
  if [[ "${_z_config[show_progress]:-}" == "true" ]]; then
    _z_config[show_progress]=false
    z::log::info "Progress bars disabled"
  else
    _z_config[show_progress]=true
    z::log::info "Progress bars enabled"
  fi
}

# Function to clear any lingering progress output
z::ui::progress::clear()
{
  emulate -L zsh
  if [[ -t 2 ]]; then
    printf '\r\e[K' >&2
  fi
}

# Performance mode override
if [[ -n ${Z_CONFIG_PERFORMANCE_MODE:-} ]]; then
  _z_config[performance_mode]="${Z_CONFIG_PERFORMANCE_MODE}"
fi

# Progress bar override
if [[ -n ${Z_CONFIG_SHOW_PROGRESS:-} ]]; then
  _z_config[show_progress]="${Z_CONFIG_SHOW_PROGRESS}"
fi

# Global state variables
typeset -gi _z_config_interrupted=0
typeset -gi _log_depth=0
typeset -gi _cached_term_width=0
typeset -gi _z_prev_columns=0

# Function existence cache
typeset -gA _func_cache
typeset -ga _func_cache_order

# Command existence cache
typeset -gA _cmd_cache
typeset -ga _cmd_cache_order

# Timeout command detection (GNU timeout or coreutils gtimeout on macOS)
typeset -g _z_timeout_cmd=""
if (( $+commands[timeout] )); then
  _z_timeout_cmd="timeout"
elif (( $+commands[gtimeout] )); then
  _z_timeout_cmd="gtimeout"
fi

typeset -gA _z_colors
if [[ -t 2 && -z ${NO_COLOR:-} && ${TERM:-} != "dumb" ]] &&
   (( $+commands[tput] )) &&
   tput setaf 1 >/dev/null 2>&1; then
  _z_colors=(
    [red]="$(tput setaf 1)"
    [green]="$(tput setaf 2)"
    [blue]="$(tput setaf 4)"
    [yellow]="$(tput setaf 3)"
    [reset]="$(tput sgr0)"
  )
else
  _z_colors=([red]="" [green]="" [blue]="" [yellow]="" [reset]="")
fi

# Timestamp caching for performance
typeset -g _cached_timestamp=""
typeset -gi _timestamp_epoch=0

# --- Logging ---

__z::log::update_ts()
{
  emulate -L zsh
  local -i current_epoch=${EPOCHSECONDS:-$(date +%s 2>/dev/null)}
  if (( current_epoch != _timestamp_epoch )); then
    _timestamp_epoch=$current_epoch
    if ! print -v _cached_timestamp -f "%(%Y-%m-%d %H:%M:%S)T" "$current_epoch" 2>/dev/null; then
      if ! _cached_timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null); then
        _cached_timestamp="unknown-time"
      fi
    fi
  fi
}

__z::log::engine()
{
  emulate -L zsh
  setopt localoptions no_unset warn_create_global

  # Infinite recursion prevention
  if (( _log_depth > _z_config[log_max_depth] )); then
    print -r -- "FATAL: Recursion in __z::log::engine" >&2
    return 1
  fi
  (( _log_depth++ ))

  # log level validation
  local -i level
  if [[ -z ${1-} || $1 != <-> ]]; then
    print -r -- "[error] Invalid log level: '${1-}'" >&2
    (( _log_depth-- ))
    return 1
  fi
  level=$1
  shift

  # Early return for filtered messages
  if (( level > _z_verbose_level )); then
    (( _log_depth-- ))
    return 0
  fi

  __z::log::update_ts

  # Mapping level to prefix and color
  local prefix=""
  case $level in
    (${_z_config[log_error]}) prefix="${_z_colors[red]}[error]${_z_colors[reset]}" ;;
    (${_z_config[log_warn]})  prefix="${_z_colors[yellow]}[warn]${_z_colors[reset]}" ;;
    (${_z_config[log_info]})  prefix="${_z_colors[blue]}[info]${_z_colors[reset]}" ;;
    (${_z_config[log_debug]}) prefix="${_z_colors[green]}[debug]${_z_colors[reset]}" ;;
    (*)                           prefix="[unknown]" ;;
  esac

  local msg="${(j: :)@}"
  print -r -- "${_cached_timestamp} ${prefix} ${msg}" >&2

  (( _log_depth-- ))
  return 0
}

# Logging interface functions
z::log::error()
{
  emulate -L zsh
  __z::log::engine ${_z_config[log_error]} "$@"
}
z::log::warn()
{
  emulate -L zsh
  __z::log::engine ${_z_config[log_warn]} "$@"
}
z::log::info()
{
  emulate -L zsh
  __z::log::engine ${_z_config[log_info]} "$@"
}
z::log::debug()
{
  emulate -L zsh
  __z::log::engine ${_z_config[log_debug]} "$@"
}

# --- Interrupt Handling ---

z::runtime::handle_interrupt()
{
  emulate -L zsh

  # Only handle actual interrupts, not normal editing
  if [[ -n ${ZLE_STATE:-} ]]; then
    return 0 # Don't handle interrupts during ZLE (line editing)
  fi

  if (( _z_config_interrupted == 0 )); then
    _z_config_interrupted=1
    z::ui::progress::clear
    z::log::warn "Interrupt received. Gracefully shutting down..."
  fi
}

z::sys::interrupted()
{
  emulate -L zsh
  if (( _z_config_interrupted )); then
    z::log::info "Operation cancelled by user."
    return ${_z_config[exit_interrupted]}
  fi
  return 0
}

z::config::set()
{
  emulate -L zsh
  local key="${1-}" value="${2-}"

  if [[ -z "$key" ]]; then
    z::log::error "z::config::set: Configuration key cannot be empty."
    return 1
  fi

  if (( !${+_z_config[$key]} )); then
    z::log::warn "z::config::set: Unknown configuration key: '$key'."
    return 1
  fi

  case "$key" in
    log_* | exit_* | *interval | *timeout | *depth | *size)
      if [[ "$value" != <-> ]]; then
        z::log::error "z::config::set: Value for '$key' must be an integer, but got '$value'."
        return 1
      fi
      # Validate cache_max_size bounds
      if [[ "$key" == "cache_max_size" ]] && (( value < 10 || value > 10000 )); then
        z::log::error "z::config::set: cache_max_size must be between 10 and 10000"
        return 1
      fi
      ;;
    *mode | show_progress)
      if [[ "$value" != "true" && "$value" != "false" ]]; then
        z::log::error "z::config::set: Value for '$key' must be 'true' or 'false', but got '$value'."
        return 1
      fi
      ;;
  esac

  _z_config[$key]="$value"
  z::log::debug "Configuration updated: $key = $value"
  return 0
}

# --- Fatal Error Handling ---

z::runtime::die()
{
  emulate -L zsh
  local message="${1-}"
  local -i exit_code=${2:-${_z_config[exit_general_error]}}

  z::ui::progress::clear
  z::log::error "FATAL: $message"

  # Return in sourced context, exit otherwise
  if [[ -n $ZSH_EVAL_CONTEXT && $ZSH_EVAL_CONTEXT == *:file:* ]]; then
    return $exit_code
  else
    exit $exit_code
  fi
}

# ==============================================================================
# 1. PLATFORM DETECTION
# ==============================================================================
z::sys::platform()
{
  emulate -L zsh
  setopt no_unset typeset_silent

  

  if [[ -n "${_PLATFORM_DETECTED:-}" ]]; then
    return 0
  fi

  # Defensive fallback if OSTYPE is empty
  local ostype_value="${OSTYPE:-}"
  if [[ -z "$ostype_value" ]]; then
    case "$(uname -s 2> /dev/null)" in
      Darwin)                              ostype_value="darwin" ;;
      Linux)                               ostype_value="linux" ;;
      FreeBSD | OpenBSD | NetBSD | DragonFly) ostype_value="bsd" ;;
      CYGWIN* | MSYS* | MINGW*)            ostype_value="cygwin" ;;
      *)                                   ostype_value="unknown" ;;
    esac
  fi

  # Set platform variables based on $ostype_value
  case "$ostype_value" in
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
  local -i is_wsl=0
  if (( IS_LINUX )); then
    if [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSLENV:-}" || -f "/proc/sys/fs/binfmt_misc/WSLInterop" ]]; then
      is_wsl=1
    elif [[ -r "/proc/version" ]]; then
      local proc_version=""
      if IFS= read -r proc_version < /proc/version 2> /dev/null; then
        if [[ "$proc_version" == *[Mm]icrosoft* || "$proc_version" == *[Ww][Ss][Ll]* ]]; then
          is_wsl=1
        fi
      fi
    fi
  fi
  typeset -gri IS_WSL=$is_wsl

  # Check for Termux on Android - Linux only
  local -i is_termux=0
  if (( IS_LINUX )) && [[ -d "/data/data/com.termux/files/usr" ]]; then
    is_termux=1
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


# ==============================================================================
# 2. COMMAND & ALIAS HANDLING
# ==============================================================================

z::env::alias_set()
{
  emulate -L zsh
  setopt no_unset warn_create_global

  local alias_name="${1-}" alias_value="${2-}"
  if [[ -z $alias_name || -z $alias_value || $alias_name == *[[:space:]=]* ]]; then
    z::log::error "Invalid alias definition: name='$alias_name' value='$alias_value'"
    return 1
  fi

  if ! builtin alias "${alias_name}=${alias_value}" 2> /dev/null; then
    z::log::error "Failed to create alias: $alias_name='$alias_value'"
    return 1
  fi
  z::log::debug "Created alias: $alias_name='$alias_value'"
  return 0
}

z::env::path_add()
{
  emulate -L zsh
  local dir="$1"
  local position="${2:-append}"

  if [[ -z "$dir" ]]; then
    z::log::error "Empty directory provided to z::env::path_add"
    return 1
  fi

  local original_dir="$dir"
  if ! dir=$(z::path::resolve "$dir"); then
    z::log::debug "Failed to resolve directory path for PATH: $original_dir"
    return 1
  fi

  if [[ ! -d "$dir" ]]; then
    z::log::debug "Directory does not exist, not adding to PATH: $dir"
    return 0
  fi

  if [[ ":${PATH}:" == *":${dir}:"* ]]; then
    z::log::debug "Directory already in PATH: $dir"
    return 0
  fi

  case "$position" in
    prepend) export PATH="$dir:$PATH" ;;
    append)  export PATH="$PATH:$dir" ;;
    *)
      z::log::error "Invalid position for z::env::path_add: $position (use prepend or append)"
      return 1
      ;;
  esac

  # Rehash and clear command cache to avoid stale $commands hits
  builtin hash -r 2> /dev/null || true
  z::cache::cmd::clear

  z::log::debug "Added to PATH ($position): $dir"
  return 0
}

# ==============================================================================
# 3. DYNAMIC & SAFE EXECUTION
# ==============================================================================

# Private helper: shell init detection
__z::exec::is_init_cmd()
{
  emulate -L zsh
  local input="$1"

  # Optional user-provided whitelist regex
  if [[ -n ${_z_config[init_whitelist_regex]:-} ]]; then
    if [[ "$input" =~ ${_z_config[init_whitelist_regex]} ]]; then
      return 0
    fi
  fi

  # Works for: direct use, env-wrapped, eval "$( ... )", and similar forms.
  if [[ "$input" =~ '(starship|mise|direnv|zoxide|atuin|mcfly|fzf|oh-my-posh)[[:space:]]+init([[:space:]]|$)' ]]; then
    return 0
  fi
  return 1
}

# Private helper: dangerous pattern detection
__z::exec::check_segment()
{
  emulate -L zsh
  local cmd="$1"
  shift
  local -a args=("$@")

  if [[ $cmd == rm ]]; then
    local -i have_r=0 have_f=0
    local a
    for a in "${args[@]}"; do
      if [[ $a == --* ]]; then
        continue
      elif [[ $a == -* ]]; then
        [[ $a == *r* ]] && have_r=1
        [[ $a == *f* ]] && have_f=1
        continue
      fi
    done
    if (( have_r && have_f )); then
      for a in "${args[@]}"; do
        case "$a" in
          / | /* | ~ | ~/* | '$HOME' | '$HOME'/*)
            z::log::error "Dangerous rm target: $a"
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
        case "$base" in
          sd* | hd* | nvme* | disk* | rdisk*)
            z::log::error "Dangerous dd of= raw device: $dev"
            return 1
            ;;
        esac
      fi
    done
  fi

  if [[ $cmd == mkfs.* ]]; then
    local a
    for a in "${args[@]}"; do
      if [[ $a == /dev/* ]]; then
        z::log::error "Dangerous mkfs target: $a"
        return 1
      fi
    done
  fi

  if [[ $cmd == chmod ]]; then
    local mode="" a
    local -i nmode=-1 saw_root=0 recursive=0 symb_wide=0
    for a in "${args[@]}"; do
      # options
      if [[ $a == -* ]]; then
        [[ $a == *R* ]] && recursive=1
        continue
      fi
      # numeric mode
      if [[ -z $mode && $a == <-> ]]; then
        mode="$a"
        continue
      fi
      # symbolic mode - very limited risky patterns
      if [[ -z $mode && ( $a == *a+w* || $a == *a+rwx* || $a == *o+w* || $a == *u=rwx* ) ]]; then
        symb_wide=1
        continue
      fi
      # target path
      if [[ $a == / ]]; then
        saw_root=1
        continue
      fi
    done
    if [[ -n $mode ]]; then
      local -i tmp
      (( tmp = 10#${mode} ))
      nmode=$tmp
    fi
    if (( recursive && saw_root && (nmode == 777 || symb_wide == 1) )); then
      z::log::error "Dangerous chmod recursive wide-open on /"
      return 1
    fi
    if (( saw_root && nmode == 777 )); then
      z::log::error "Dangerous chmod 777 on /"
      return 1
    fi
  fi

  if [[ $cmd == killall || $cmd == pkill ]]; then
    local a
    for a in "${args[@]}"; do
      case "$a" in
        -9 | -KILL | -SIGKILL)
          z::log::error "Dangerous kill signal -9 detected"
          return 1
          ;;
      esac
    done
  fi

  if [[ $cmd == userdel ]]; then
    local a
    for a in "${args[@]}"; do
      [[ $a == -r ]] && {
        z::log::error "Dangerous userdel -r"
        return 1
      }
    done
  fi

  if [[ $cmd == groupdel ]]; then
    z::log::error "Dangerous groupdel detected"
    return 1
  fi

  return 0
}

__z::exec::has_dangerous_metachars()
{
  emulate -L zsh
  local input="$1"
  [[ -z "$input" ]] && return 1
  [[ "$input" =~ '[;&()]' ]] || [[ "$input" == *'`'* ]]
}

__z::exec::scan_patterns()
{
  emulate -L zsh
  setopt localoptions typeset_silent
  local input="${1-}"
  [[ -z $input ]] && return 0

  if __z::exec::is_init_cmd "$input"; then
    return 0
  fi

  # Tokenize using zsh's lexer
  local -a words
  words=(${(z)input})
  (( ${#words} == 0 )) && return 0

  # Guard: pipe to a shell
  local -i i j
  local next_cmd base
  for (( i = 1; i <= ${#words}; i++ )); do
    if [[ ${words[i]} == '|' ]]; then
      (( j = i + 1 ))
      # Find the first real command in the next segment
      while (( j <= ${#words} )); do
        case "${words[j]}" in
          '|' | '||' | '&&' | ';' | '&')
            break
            ;;
          nocorrect | noglob | builtin | command | exec | time | nice | nohup | sudo | doas | env)
            (( j++ ))
            continue
            ;;
          [[:alpha:]_][[:alnum:]_]*=*)
            (( j++ ))
            continue
            ;;
        esac
        next_cmd="${words[j]}"
        break
      done
      if [[ -n ${next_cmd:-} ]]; then
        base="${next_cmd:t}"
        case "$base" in
          sh | bash | zsh | ksh | dash)
            z::log::error "Dangerous pattern: pipe to shell"
            return 1
            ;;
        esac
      fi
    fi
  done

  # Guard: common fork bomb
  if [[ $input =~ ':\(\)\{[[:space:]]*:[[:space:]]*\|[[:space:]]*&[[:space:]]*;[[:space:]]*:[[:space:]]*\}' ]]; then
    z::log::error "Dangerous pattern: fork bomb"
    return 1
  fi

  # Build and check segments split across |, ||, &&, ;, &
  local -a seg=()
  local w
  for w in "${words[@]}"; do
    case "$w" in
      '|' | '||' | '&&' | ';' | '&')
        if (( ${#seg} )); then
          local cmd="${seg[1]}"
          local -a args=("${(@)seg[2,-1]}")
          __z::exec::check_segment "$cmd" "${args[@]}" || return 1
          seg=()
        else
          return 1
        fi
        ;;
      nocorrect | noglob | builtin | command | exec | time | nice | nohup | sudo | doas | env)
        # Skip precommands only at segment start
        if (( ${#seg} == 0 )); then
          continue
        else
          seg+=("$w")
        fi
        ;;
      [[:alpha:]_][[:alnum:]_]*=*)
        # Skip leading assignments in a segment
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

# Safe command execution (without eval, with pipefail)
z::exec::run()
{
  emulate -L zsh
  local input="$1"
  local -i timeout=${2:-${_z_config[timeout_default]}}

  if [[ -z "$input" ]]; then
    z::log::error "Empty input for z::exec::run"
    return 1
  fi

  # Short-term guard: block ;, &, ( ) unless explicitly whitelisted init
  if ! __z::exec::is_init_cmd "$input"; then
    if __z::exec::has_dangerous_metachars "$input"; then
      z::log::error "Rejected dangerous metacharacters in input"
      return 1
    fi
  fi

  # Security scan
  __z::exec::scan_patterns "$input" || return 1

  

  local -i exit_code=0

  if [[ -n "${_z_timeout_cmd:-}" ]]; then
    "${_z_timeout_cmd}" "$timeout" zsh -o pipefail -c "$input" || exit_code=$?
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

z::exec::eval()
{
  emulate -L zsh
  local input="$1"
  local -i timeout=${2:-${_z_config[timeout_default]}}
  local force_current_shell="${3:-false}"

  if [[ -z "$input" ]]; then
    z::log::error "Empty input for z::exec::eval"
    return 1
  fi

  if [[ "$force_current_shell" == "true" ]]; then
    z::log::debug "Forcing eval in current shell for init script"
    
    local -i exit_code=0
    eval "$input" || exit_code=$?
    if (( exit_code != 0 )); then
      z::log::warn "Forced eval failed with exit code $exit_code"
    fi
    return $exit_code
  fi

  local is_shell_init=false
  __z::exec::is_init_cmd "$input" && is_shell_init=true

  local is_package_install=false
  if [[ $input =~ '(^|[[:space:]])(npm|yarn|pip|pip3|cargo|brew|apt|yum|dnf|pacman)[[:space:]]+(add|install)($|[[:space:]])' ]]; then
    is_package_install=true
  fi

  # Security scan (skipped for known safe patterns)
  if [[ "${_z_config[performance_mode]}" != "true" ]] &&
    [[ "$is_shell_init" != "true" ]] &&
    [[ "$is_package_install" != "true" ]]; then
    __z::exec::scan_patterns "$input" || return 1
  fi

  

  if [[ "$is_shell_init" == "true" ]]; then
    z::log::debug "Detected shell init command (running in subshell): ${input}"
  fi

  z::exec::run "$input" "$timeout"
}

###
# Initializes a tool by safely evaluating its shell hook output.
#
# @param 1: string - The name of the command-line tool (e.g., "direnv").
# @param 2: string - The subcommand to generate the hook (default: "init").
# @param 3: string - The shell argument for the hook (default: "zsh").
# @return 0 on success, 1 on failure.
###
z::exec::from_hook()
{
  emulate -L zsh
  local tool_name="$1"
  local subcommand="${2:-init}"
  local shell_arg="${3:-zsh}"

  

  if ! z::probe::cmd "$tool_name"; then
    z::log::debug "$tool_name not found, skipping"
    return 0 # Return 0 because not finding the tool isn't a failure
  fi

  local init_code
  if init_code="$("$tool_name" "$subcommand" "$shell_arg" 2> /dev/null)" &&
    [[ -n "$init_code" ]]; then
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

# ==============================================================================
# 4. FILESYSTEM & SOURCING
# ==============================================================================

z::path::resolve()
{
  emulate -L zsh
  local path="$1"
  if [[ -z "$path" || "$path" =~ ^[[:space:]]*$ ]]; then
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
  if [[ "$path" != /* ]]; then
    path="${PWD%/}/$path"
  fi

  # Prefer zsh's realpath-like modifier (:A) for portability and speed
  local normalized
  normalized="${path:A}"
  if [[ -n "$normalized" ]]; then
    printf '%s' "$normalized"
    return 0
  fi

  # Fallback: POSIX-friendly manual resolution without readlink -f
  local current_path="$path"
  local -i guard=0
  local -i max_guard=100 # Increased from 40 for complex symlink chains
  local -a visited_paths=()

  if command -v readlink > /dev/null 2>&1; then
    while [[ -L "$current_path" && guard < max_guard ]]; do
      # Cycle detection
      if (( ${visited_paths[(Ie)$current_path]} )); then
        z::log::warn "Symlink cycle detected at $current_path"
        printf '%s' "$path"
        return 1
      fi
      visited_paths+=("$current_path")
      local target
      target=$(readlink "$current_path" 2> /dev/null) || break
      [[ -z "$target" ]] && break
      if [[ "$target" == /* ]]; then
        current_path="$target"
      else
        current_path="${current_path:h}/$target"
      fi
      (( guard++ ))
    done

    if (( guard >= max_guard )); then
      z::log::warn "Symlink resolution exceeded maximum depth ($max_guard)"
    fi
  fi

  if [[ -d "${current_path:h}" ]]; then
    local physical_dir
    if physical_dir=$(
      cd -P "${current_path:h}" 2> /dev/null && pwd -P
    ); then
      current_path="${physical_dir}/${current_path:t}"
    fi
  fi

  printf '%s' "$current_path"
}

z::file::source()
{
  emulate -L zsh
  local file="$1"
  shift
  if [[ -z "$file" ]]; then
    z::log::error "Empty file path for source"
    return 1
  fi

  local resolved_file="$file"

  # Always do cheap tilde expansion (even in performance mode) to avoid surprises
  case "$resolved_file" in
    '~' | '~/'*)   resolved_file="${HOME}${resolved_file#~}" ;;
    '~+' | '~+/'*) resolved_file="${PWD}${resolved_file#~+}" ;;
    '~-' | '~-/'*) resolved_file="${OLDPWD:-$PWD}${resolved_file#~-}" ;;
  esac

  # Skip expensive path normalization in performance mode
  if [[ "${_z_config[performance_mode]}" != "true" ]]; then
    if ! resolved_file=$(z::path::resolve "$resolved_file"); then
      z::log::error "Failed to resolve path: $file"
      return 1
    fi
  fi

  if [[ ! -f "$resolved_file" || ! -r "$resolved_file" ]]; then
    z::log::warn "File not found or not readable: $resolved_file"
    return 1
  fi

  

  local -i exit_code=0
  source "$resolved_file" "$@" || exit_code=$?

  if (( exit_code != 0 )); then
    z::log::warn "Failed to source $resolved_file (code: $exit_code)"
  else
    # Clear function cache after successful sourcing to avoid stale entries
    z::cache::func::clear
  fi
  return $exit_code
}

# ==============================================================================
# 5. FUNCTION INTROSPECTION & CACHING
# ==============================================================================

z::cache::func::_purge()
{
  emulate -L zsh
  # Remove oldest entries when cache is full
  local -i cache_size=${#_func_cache[@]}
  if (( cache_size > _z_config[cache_max_size] )); then
    local -i excess=$(( cache_size - _z_config[cache_max_size] ))
    local -i to_remove=$(( excess / 2 + 1 ))
    local -i removed=0
    local key

    while (( removed < to_remove && ${#_func_cache_order[@]} > 0 )); do
      key="${_func_cache_order[1]}"
      # Drop the first (oldest) entry from the order array using slicing
      _func_cache_order=("${_func_cache_order[@]:1}")

      # Remove from the assoc cache if present
      if (( ${+_func_cache[$key]} )); then
        unset "_func_cache[$key]"
      fi

      (( removed++ ))
    done

    z::log::debug "Cleaned function cache: removed $removed entries, new size: ${#_func_cache[@]}"
  fi
}

z::cache::cmd::_purge()
{
  emulate -L zsh
  local -i cache_size=${#_cmd_cache[@]}
  if (( cache_size > _z_config[cache_max_size] )); then
    local -i excess=$(( cache_size - _z_config[cache_max_size] ))
    local -i to_remove=$(( excess / 2 + 1 ))
    local -i removed=0
    local key

    while (( removed < to_remove && ${#_cmd_cache_order[@]} > 0 )); do
      key="${_cmd_cache_order[1]}"
      # Drop the first (oldest) entry from the order array using slicing
      _cmd_cache_order=("${_cmd_cache_order[@]:1}")

      if (( ${+_cmd_cache[$key]} )); then
        unset "_cmd_cache[$key]"
      fi

      (( removed++ ))
    done

    z::log::debug "Cleaned command cache: removed $removed entries, new size: ${#_cmd_cache[@]}"
  fi
}

# New: explicit cache clear helpers
z::cache::cmd::clear()
{
  emulate -L zsh
  _cmd_cache=()
  _cmd_cache_order=()
  z::log::debug "Cleared command cache"
}

z::cache::func::clear()
{
  emulate -L zsh
  _func_cache=()
  _func_cache_order=()
  z::log::debug "Cleared function cache"
}

# Command existence check with caching
z::probe::cmd()
{
  emulate -L zsh
  local cmd="$1"
  [[ -z "$cmd" ]] && return 1

  local cache_key="cmd_${cmd//[^a-zA-Z0-9_]/_}"
  if (( ${+_cmd_cache[$cache_key]} )); then
    return ${_cmd_cache[$cache_key]}
  fi

  local -i result=1
  (( $+commands[$cmd] )) && result=0

  # De-duplicate order before appending to avoid unbounded growth
  _cmd_cache_order=("${(@)_cmd_cache_order:#$cache_key}")
  _cmd_cache[$cache_key]=$result
  _cmd_cache_order+=("$cache_key")

  (( ${#_cmd_cache[@]} > _z_config[cache_max_size] )) && z::cache::cmd::_purge

  return $result
}

z::probe::func()
{
  emulate -L zsh
  local func="$1"
  if [[ -z "$func" ]]; then
    return 1
  fi

  local cache_key="func_exists_${func//[^a-zA-Z0-9_]/_}"
  if (( ${+_func_cache[$cache_key]} )); then
    return ${_func_cache[$cache_key]}
  fi

  local -i result=1
  if (( $+functions[$func] )); then
    result=0
  fi

  # De-duplicate order before appending to avoid unbounded growth
  _func_cache_order=("${(@)_func_cache_order:#$cache_key}")
  _func_cache[$cache_key]=$result
  _func_cache_order+=("$cache_key")

  # Always purge; internal threshold check handles cost
  z::cache::func::_purge

  return $result
}

z::func::call()
{
  emulate -L zsh
  local func="$1"
  if [[ -z "$func" ]]; then
    z::log::error "Empty function name for z::func::call"
    return 1
  fi
  shift

  if ! z::probe::func "$func"; then
    case "$func" in
      _git_prompt_info | __zconvey_on_period_passed* | _*prompt* | _*git*)
        return 1 # Silently skip known dynamic functions
        ;;
      *)
        z::log::warn "Function '$func' not found"
        return 1
        ;;
    esac
  fi

  

  local -i exit_code=0
  "$func" "$@" || exit_code=$?

  if (( exit_code != 0 )); then
    z::log::warn "Function '$func' failed with code $exit_code"
  fi
  return $exit_code
}

# ==============================================================================
# 6. STATE MANAGEMENT
# ==============================================================================

# Private helper: core unset implementation shared by public APIs
z::state::_unset_impl()
{
  emulate -L zsh
  setopt typeset_silent no_unset

  local target="${1-}"
  local unset_type="${2:-auto}"

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

  local -i found=0 success=0 rc_var=0 rc_func=0

  # Handle variable unsetting
  if [[ $unset_type == var || $unset_type == auto ]]; then
    if (( ${+parameters[$target]} )); then
      found=1
      # Check if readonly
      if [[ ${(tP)target} == *readonly* ]]; then
        z::log::debug "Cannot unset readonly var: $target"
        rc_var=1
      else
        unset -v -- "$target" 2> /dev/null || rc_var=$?
        (( rc_var == 0 )) && success=1
      fi
    fi
  fi

  # Handle function unsetting
  if [[ $unset_type == func || $unset_type == auto ]]; then
    if (( ${+functions[$target]} )); then
      found=1
      unset -f -- "$target" 2> /dev/null || rc_func=$?
      if (( rc_func == 0 )); then
        success=1
        # Update function-existence cache
        local cache_key="func_exists_${target//[^A-Za-z0-9_]/_}"
        if (( ${+_func_cache[$cache_key]} )); then
          unset "_func_cache[$cache_key]"
          _func_cache_order=("${(@)_func_cache_order:#$cache_key}")
        fi
      fi
    fi
  fi

  if (( !found )); then
    z::log::debug "Target not found for unset: $target"
    return 1
  fi

  if (( success )); then
    z::log::debug "Unset: $target"
    return 0
  fi

  z::log::warn "Failed to unset $target"
  return $(( rc_func != 0 ? rc_func : rc_var ))
}

# Public: unset a variable only
# Usage: z::var::unset VAR_NAME
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

# Public: unset a function only
# Usage: z::func::unset FUNC_NAME
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

# Backward-compatible combined API (auto/var/func)
# Usage: z::state::unset TARGET [auto|var|func]
z::state::unset()
{
  emulate -L zsh
  setopt typeset_silent no_unset
  local target="${1-}"
  local unset_type="${2:-auto}"
  z::state::_unset_impl "$target" "$unset_type"
}

# ==============================================================================
# 7. USER INTERFACE (UI)
# ==============================================================================
z::ui::term::width()
{
  emulate -L zsh
  local -i width tput_width

  # Use cached width if COLUMNS hasn't changed and cache is valid
  if (( _cached_term_width > 0 && _z_prev_columns == ${COLUMNS:-0} )); then
    print -r -- "$_cached_term_width"
    return 0
  fi

  if [[ -n "${COLUMNS:-}" ]] &&
    [[ "$COLUMNS" =~ ^[0-9]+$ ]] &&
    (( COLUMNS >= 10 )); then
    width=$COLUMNS
  elif (( $+commands[tput] )) &&
    tput_width=$(tput cols 2> /dev/null) &&
    [[ "$tput_width" =~ ^[0-9]+$ ]] &&
    (( tput_width >= 10 )); then
    width=$tput_width
  else
    width=80
  fi

  _cached_term_width=$width
  _z_prev_columns=${COLUMNS:-0}
  print -r -- "$width"
}

z::ui::progress::_should_show()
{
  emulate -L zsh
  local -i current=$1 total=$2 interval=${_z_config[progress_update_interval]:-20}

  if (( current == 1 || current == total )); then
    return 0
  fi

  if (( total <= 10 )); then
    return 1
  fi

  if (( total <= 50 )); then
    (( current % 5 == 0 )) && return 0
    return 1
  fi

  if (( current % interval == 0 )) || (( total - current < interval )); then
    return 0
  fi

  return 1
}

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
  local -a groups=()
  local s="$n"
  while (( ${#s} > 3 )); do
    groups=("${s[-3,-1]}" "${(@)groups}")
    s="${s[1,-4]}"
  done
  local out="$s"
  if (( ${#groups} )); then
    out+=",${(j:,:)groups}"
  fi
  print -r -- "${sign}${out}"
}

z::progress::show()
{
  emulate -L zsh
  setopt typeset_silent

  if [[ ${1-} != <-> || ${2-} != <-> ]]; then
    z::log::debug "Invalid progress params: must be integers."
    return 1
  fi
  local -i current=$1 total=$2

  local label="${3:-items}"
  if (( total <= 0 || current < 0 || current > total )); then
    z::log::debug "Invalid progress range: $current/$total."
    return 1
  fi

  if (( _z_verbose_level < _z_config[log_info] )) ||
    [[ ! -t 2 ]] ||
    [[ "${_z_config[show_progress]:-true}" == "false" ]]; then
    return 0
  fi

  z::ui::progress::_should_show "$current" "$total" || return 0

  local -i term_width
  term_width=$(z::ui::term::width)

  local -F percent
  if (( total > 0 )); then
    (( percent = (current * 100.0) / total ))
  else
    percent=0.0
  fi

  local -i bar_width
  if (( term_width > 40 )); then
    bar_width=20
  else
    bar_width=10
  fi
  local -i filled=$(( (percent * bar_width) / 100 ))
  (( filled < 0 )) && filled=0
  (( filled > bar_width )) && filled=$bar_width
  local -i empty_len=$(( bar_width - filled ))

  local bar_fill bar_empty
  if (( filled > 0 )); then
    print -v bar_fill -f "%${filled}s" ""
    bar_fill=${bar_fill// /█}
  else
    bar_fill=""
  fi
  if (( empty_len > 0 )); then
    print -v bar_empty -f "%${empty_len}s" ""
    bar_empty=${bar_empty// /░}
  else
    bar_empty=""
  fi
  local progress_bar="${bar_fill}${bar_empty}"

  local current_fmt total_fmt
  current_fmt=$(z::util::comma "$current")
  total_fmt=$(z::util::comma "$total")

  if (( term_width > 70 )); then
    printf '\r[%s] %3.0f%% | %s: %s / %s ' "$progress_bar" "$percent" "$label" "$current_fmt" "$total_fmt" >&2
  else
    printf '\r[%s] %3.0f%% (%s/%s)' "$progress_bar" "$percent" "$current_fmt" "$total_fmt" >&2
  fi

  (( current == total )) && printf '\n' >&2
}

# ==============================================================================
# 8. INITIALIZATION
# ==============================================================================

# Install interrupt handlers
trap 'z::runtime::handle_interrupt' INT TERM

# Initialize library
z::log::debug "Zsh utility library initialized (performance_mode=${_z_config[performance_mode]})"
