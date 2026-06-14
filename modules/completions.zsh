#!/usr/bin/env zsh
#
# Completions Module
#

# ==============================================================================
# MODULE CONSTANTS
# ==============================================================================

# Load datetime/stat once at module load — both are cheap idempotent zmodloads.
zmodload -F zsh/datetime b:EPOCHSECONDS 2>/dev/null
zmodload    zsh/stat                    2>/dev/null

# RFC 1123 hostname
typeset -gr _Z_HOSTNAME_REGEX='^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*$'

# Maximum Include recursion depth for SSH config parsing
typeset -gir _Z_SSH_CONFIG_MAX_DEPTH=10

# ==============================================================================
# PRIVATE HELPERS
# ==============================================================================

###
# Cross-platform mtime helper.  Prefers builtin `zstat` (no fork).
###
__z::mod::completions::_mtime() {
  emulate -L zsh
  local f=$1
  local -a st
  if (( ${+builtins[zstat]} )) && zstat -A st +mtime -- "$f" 2>/dev/null; then
    print -r -- "${st[1]:-0}"
    return 0
  fi
  case "${_Z_UNAME_S:-$(uname -s 2>/dev/null)}" in
    Darwin|*BSD) command stat -f %m -- "$f" 2>/dev/null || print 0 ;;
    *)           command stat -c %Y -- "$f" 2>/dev/null || print 0 ;;
  esac
}

###
# Recursively parses an ssh_config for host definitions.
###
__z::mod::completions::process_ssh_config() {
  emulate -L zsh
  setopt local_options extended_glob typeset_silent

  local config_file=$1
  local -i depth=${2:-0}
  local hosts_arr_name=$3 negs_arr_name=$4

  if (( depth > _Z_SSH_CONFIG_MAX_DEPTH )); then
    z::log::warn "SSH config include depth limit reached for: $config_file"
    return 0
  fi
  [[ -r "$config_file" ]] || return 0

  local base_dir="${config_file:h}"
  local line trimmed key rest w include_pattern inc
  local -a patterns host_list __tmp

  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed=${line##[[:space:]]#}
    [[ -z "$trimmed" || ${trimmed[1]} == '#' ]] && continue

    key=${trimmed%%[[:space:]]*}
    rest=${trimmed#$key}
    rest=${rest##[[:space:]]#}
    key=${key:l}

    # ── Include directives ───────────────────────────────────────────────
    if [[ "$key" == "include" && -n "$rest" ]]; then
      patterns=("${(z)rest}")
      for include_pattern in "${patterns[@]}"; do
        include_pattern=${include_pattern//\"/}
        [[ "$include_pattern" != /* ]] && include_pattern="$base_dir/$include_pattern"
        for inc in ${~include_pattern}(N); do
          [[ -r "$inc" ]] || continue
          z::log::debug "Processing included SSH config: $inc"
          __z::mod::completions::process_ssh_config \
            "$inc" $(( depth + 1 )) "$hosts_arr_name" "$negs_arr_name"
        done
      done
      continue
    fi

    # ── Host definitions ─────────────────────────────────────────────────
    if [[ "$key" == "host" && -n "$rest" ]]; then
      host_list=("${(z)rest}")
      for w in "${host_list[@]}"; do
        if [[ "$w" == '!'* ]]; then
          __tmp=( "${(@P)negs_arr_name}" "${w#!}" )
          set -A "$negs_arr_name" "${__tmp[@]}"
          continue
        fi
        [[ "$w" == (*[\*\?\[\]]*|localhost|127.*|::1|*:*|*.local) ]] && continue
        if [[ "$w" =~ $_Z_HOSTNAME_REGEX ]]; then
          __tmp=( "${(@P)hosts_arr_name}" "$w" )
          set -A "$hosts_arr_name" "${__tmp[@]}"
        fi
      done
      continue
    fi
  done < "$config_file"

  return 0
}

###
# Generates a deduplicated, sorted list of SSH hosts.  Cached on disk.
###
__z::mod::completions::get_ssh_hosts() {
  emulate -L zsh
  setopt local_options null_glob typeset_silent

  local cache_file="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/ssh_hosts_cache"
  local -i cache_age=3600

  if (( ${+functions[z::config::get]} )); then
    z::config::get 'ssh_hosts_cache_age' 2>/dev/null && cache_age=${REPLY:-3600}
  fi

  local -i current_time=${EPOCHSECONDS:-$(command date +%s)}

  # ── Serve from cache if fresh ─────────────────────────────────────────
  if [[ -r "$cache_file" ]]; then
    local -i cache_mtime
    cache_mtime=$(__z::mod::completions::_mtime "$cache_file")
    if (( cache_mtime > 0 && current_time - cache_mtime < cache_age )); then
      local -a cached_hosts=("${(@f)$(< "$cache_file")}")
      if (( ${#cached_hosts} > 0 )); then
        typeset -ga _z_ssh_hosts_cache
        _z_ssh_hosts_cache=("${cached_hosts[@]}")
        print -l -- "${cached_hosts[@]}"
        z::log::debug "Served SSH hosts from fresh cache."
        return 0
      fi
    fi
  fi

  # ── Rebuild cache ─────────────────────────────────────────────────────
  z::log::debug "SSH host cache is stale or missing; rebuilding."
  typeset -ga _z_ssh_hosts_cache
  local -a discovered_hosts=() negative_patterns=() conf_files=()

  [[ -r "$HOME/.ssh/config"     ]] && conf_files+=("$HOME/.ssh/config")
  [[ -d "$HOME/.ssh/config.d"   ]] && conf_files+=("$HOME/.ssh/config.d"/*.conf(N))
  [[ -r "/etc/ssh/ssh_config"   ]] && conf_files+=("/etc/ssh/ssh_config")
  [[ -d "/etc/ssh/ssh_config.d" ]] && conf_files+=("/etc/ssh/ssh_config.d"/*.conf(N))

  local f
  for f in "${conf_files[@]}"; do
    __z::mod::completions::process_ssh_config "$f" 0 discovered_hosts negative_patterns
  done

  # ── known_hosts ───────────────────────────────────────────────────────
  local -a known_hosts_files=()
  [[ -r "$HOME/.ssh/known_hosts"   ]] && known_hosts_files+=("$HOME/.ssh/known_hosts")
  [[ -r "/etc/ssh/ssh_known_hosts" ]] && known_hosts_files+=("/etc/ssh/ssh_known_hosts")

  local -a hosts_in_entry
  local kh host_entry h
  for kh in "${known_hosts_files[@]}"; do
    while IFS=' ' read -r host_entry _; do
      [[ -z "$host_entry" || "$host_entry" == [\#\|]* ]] && continue
      hosts_in_entry=("${(@s:,:)host_entry}")
      for h in "${hosts_in_entry[@]}"; do
        h=${h#\[}
        h=${h%%\]:*}
        h=${h%%:*}
        [[ -z "$h" || "$h" == (127.*|::1|*.local|*:*|localhost) ]] && continue
        [[ "$h" =~ $_Z_HOSTNAME_REGEX ]] && discovered_hosts+=("$h")
      done
    done < "$kh"
  done

  # ── Apply negative patterns ───────────────────────────────────────────
  if (( ${#negative_patterns} > 0 )); then
    local -a filtered_hosts=()
    local host pat
    local -i skip
    for host in "${discovered_hosts[@]}"; do
      skip=0
      for pat in "${negative_patterns[@]}"; do
        if [[ "$host" == ${~pat} ]]; then skip=1; break; fi
      done
      (( skip )) || filtered_hosts+=("$host")
    done
    discovered_hosts=("${filtered_hosts[@]}")
  fi

  _z_ssh_hosts_cache=("${(@ou)discovered_hosts}")

  # ── Write cache ───────────────────────────────────────────────────────
  if (( ${#_z_ssh_hosts_cache} > 0 )); then
    local cache_dir="${cache_file:h}"
    if [[ -d "$cache_dir" ]] || command mkdir -p -- "$cache_dir"; then
      if ! print -l -- "${_z_ssh_hosts_cache[@]}" >| "$cache_file"; then
        z::log::warn "Failed to write SSH hosts cache to $cache_file"
      else
        z::log::debug "Wrote ${#_z_ssh_hosts_cache} hosts to cache."
      fi
    else
      z::log::warn "Cannot create cache directory: $cache_dir"
    fi
  fi

  print -l -- "${_z_ssh_hosts_cache[@]}"
  return 0
}

###
# Configures all zstyle settings for the completion system.
###
__z::mod::completions::configure_styles() {
  emulate -L zsh
  setopt local_options typeset_silent

  zstyle ':completion:*' menu select=2
  zstyle ':completion:*' use-cache on
  zstyle ':completion:*' cache-path "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/compcache"
  zstyle ':completion:*' rehash on
  zstyle ':completion:*' completer _expand _complete _correct
  zstyle ':completion:*' max-errors 2
  zstyle ':completion:*' squeeze-slashes true
  zstyle ':completion:*' accept-exact true
  zstyle ':completion:*' accept-exact-dirs true
  zstyle ':completion:*' group-name ''
  zstyle ':completion:*' auto-description 'specify: %d'

  zstyle ':completion:*' matcher-list \
    'm:{[:lower:][:upper:]}={[:upper:][:lower:]}' \
    'r:|[._-]=* r:|=*' \
    'l:|=* r:|=*'

  zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
  zstyle ':completion:*:messages'     format '%F{blue}%d%f'
  zstyle ':completion:*:warnings'     format '%F{red}No matches found: %d%f'
  zstyle ':completion:*:errors'       format '%F{red}%d%f'

  if [[ -n "${LS_COLORS:-}" ]]; then
    zstyle ':completion:*:default' list-colors "${(s.:.)LS_COLORS}"
  else
    zstyle ':completion:*:default' list-colors \
      'di=1;34' 'ln=1;36' 'so=1;35' 'pi=1;33' 'ex=1;32' \
      'bd=1;33' 'cd=1;33' 'su=1;31' 'sg=1;33' 'tw=1;32' 'ow=1;34'
  fi

  zstyle ':completion:*:*:cd:*'    tag-order local-directories directory-stack path-directories
  zstyle ':completion:*:-tilde-:*' group-order 'named-directories' 'path-directories' 'expand'
  zstyle ':completion:*:manuals'   separate-sections true

  zstyle ':completion:*' ignored-patterns \
    '.DS_Store' '.localized' '._*' '.Spotlight-V100' '.Trashes' \
    'Thumbs.db' 'desktop.ini' '*.bak' '*~' '.git' '.hg' '.svn' \
    'node_modules' '__pycache__' '.pytest_cache' \
    '(*/)#lost+found' '(*/)#.cache' '*.log' '*.pid'

  # ── Process completion ────────────────────────────────────────────────
  local uname_s="${_Z_UNAME_S:-Unknown}"
  local -i is_bsd=0
  [[ "$uname_s" == (Darwin|FreeBSD|OpenBSD|NetBSD) ]] && is_bsd=1

  local current_user="${USER:-${LOGNAME:-nobody}}"
  local ps_cmd ps_kill_cmd
  if (( is_bsd )); then
    ps_cmd="ps -u ${current_user} -o pid,ppid,state,start,pcpu,pmem,command"
    ps_kill_cmd="ps -u ${current_user} -o pid,user,comm"
  else
    ps_cmd="ps -u ${current_user} -o pid,ppid,state,stime,pcpu,pmem,args"
    ps_kill_cmd="ps -u ${current_user} -o pid,user,comm -w -w"
  fi
  zstyle ':completion:*:processes'          command "$ps_cmd"
  zstyle ':completion:*:*:kill:*:processes' command "$ps_kill_cmd"

  # ── SSH host completion ───────────────────────────────────────────────
  local -a ssh_hosts_array=()
  if (( ${+_z_ssh_hosts_cache} && ${#_z_ssh_hosts_cache} > 0 )); then
    ssh_hosts_array=("${_z_ssh_hosts_cache[@]}")
  else
    ssh_hosts_array=("${(@f)$(__z::mod::completions::get_ssh_hosts)}")
  fi

  if (( ${#ssh_hosts_array} > 0 )); then
    zstyle ':completion:*:(ssh|scp|sftp|rsync):*' hosts "${ssh_hosts_array[@]}"
    zstyle ':completion:*:hosts'                  hosts "${ssh_hosts_array[@]}"
  fi

  z::log::debug "Completion styles configured."
}

# ==============================================================================
# PUBLIC ENTRY POINT
# ==============================================================================

__z::mod::completions::init() {
  emulate -L zsh
  setopt local_options typeset_silent

  z::log::info "Initializing completions module..."

  if (( IS_MACOS )); then
    typeset -g _Z_UNAME_S=Darwin
  elif (( IS_LINUX )); then
    typeset -g _Z_UNAME_S=Linux
  else
    typeset -g _Z_UNAME_S="${_Z_UNAME_S:-$(uname -s 2>/dev/null || print Unknown)}"
  fi

  local compcache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/compcache"
  if [[ ! -d "$compcache_dir" ]]; then
    if command mkdir -p -- "$compcache_dir" 2>/dev/null; then
      z::log::debug "Created completion cache directory: $compcache_dir"
    else
      z::log::warn "Failed to create completion cache directory: $compcache_dir"
    fi
  fi

  zmodload -i zsh/complist 2>/dev/null

  __z::mod::completions::configure_styles

  z::log::info "Completion system configured successfully."
}

# ==============================================================================
# MODULE EXECUTION
# ==============================================================================

__z::mod::completions::init
