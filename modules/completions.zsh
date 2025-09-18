#!/usr/bin/env zsh
#
# Zsh Completions Module
# Configures completion styles and provides custom completion sources.
#

# ==============================================================================
# OPTIONAL COMPAT SHIMS (only if framework is absent)
# ==============================================================================
if ! typeset -f z::func::exists >/dev/null 2>&1; then
    z::func::exists() { whence -w -- "$1" >/dev/null 2>&1; }
fi
if ! typeset -f z::log::debug >/dev/null 2>&1; then
    z::log::debug() { :; }
    z::log::info()  { :; }
    z::log::warn()  { :; }
    z::log::error() { :; }
fi
if ! typeset -f z::runtime::check_interrupted >/dev/null 2>&1; then
    z::runtime::check_interrupted() { return 0; }
fi
if ! typeset -f z::config::get >/dev/null 2>&1; then
    # z::config::get key nameref default
    z::config::get() {
        emulate -L zsh
        setopt typeset_silent
        local key="$1" dest_name="$2" default="$3"
        typeset -n _dst="$dest_name"
        if [[ -n "${(P)key:-}" ]]; then
            _dst="${(P)key}"
        else
            _dst="$default"
        fi
    }
fi

# ==============================================================================
# PRIVATE HELPERS
# ==============================================================================

# Internal: Recursively parses an ssh_config file for host definitions.
# Supports Include directives and negative patterns.
#   $1: string  - Path to the ssh_config file.
#   $2: integer - Current recursion depth to prevent infinite loops.
#   $3: string  - Nameref to the array storing discovered hosts.
#   $4: string  - Nameref to the array storing negative patterns.
z::mod::completions::_process_ssh_config() {
    emulate -L zsh
    setopt typeset_silent local_options extended_glob

    local config_file="$1"
    local -i depth=${2:-0}
    local hosts_ref_name="$3"
    local neg_ref_name="$4"

    typeset -n _hosts_ref="$hosts_ref_name"
    typeset -n _negs_ref="$neg_ref_name"

    if (( depth > 10 )); then
        z::log::warn "SSH config include depth limit reached for: $config_file"
        return 0
    fi
    [[ -r "$config_file" ]] || return 0

    z::runtime::check_interrupted || return $?

    local base_dir="${config_file:h}"
    local line trimmed key rest
    while IFS= read -r line || [[ -n "$line" ]]; do
        z::runtime::check_interrupted || return $?

        # Trim leading spaces
        trimmed="${line##[[:space:]]#}"
        # Skip blanks and comments
        [[ -z "$trimmed" || "${trimmed[1]}" == '#' ]] && continue

        # Split into key and the rest (preserve quoting in rest)
        key="${trimmed%%[[:space:]]*}"
        rest="${trimmed#$key}"
        rest="${rest##[[:space:]]#}"
        key="${key:l}"  # lowercase

        # Handle Include directives
        if [[ "$key" == "include" && -n "$rest" ]]; then
            # Split like shell words, respecting quotes
            local -a patterns
            patterns=("${(z)rest}")
            local include_pattern inc
            for include_pattern in "${patterns[@]}"; do
                # Dequote simple double-quotes
                include_pattern="${include_pattern//\"/}"
                [[ "$include_pattern" != /* ]] && include_pattern="$base_dir/$include_pattern"
                # Expand glob(s)
                for inc in ${~include_pattern}(N); do
                    [[ -r "$inc" ]] || continue
                    z::log::debug "Processing included SSH config: $inc"
                    z::mod::completions::_process_ssh_config "$inc" $(( depth + 1 )) "$hosts_ref_name" "$neg_ref_name"
                done
            done
            continue
        fi

        # Handle Host definitions
        if [[ "$key" == "host" && -n "$rest" ]]; then
            local -a host_list
            host_list=("${(z)rest}")
            local w
            for w in "${host_list[@]}"; do
                # Negative patterns
                if [[ "$w" == '!'* ]]; then
                    _negs_ref+=("${w#!}")
                    continue
                fi
                # Skip wildcards, localhost, IPs, IPv6, and .local mDNS
                [[ "$w" == (*[\*\?\[\]]*|localhost|127.*|::1|*:*|*.local) ]] && continue
                # Validate hostname format (ERE)
                if [[ "$w" =~ '^([A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)*$' ]]; then
                    _hosts_ref+=("$w")
                fi
            done
            continue
        fi
    done < "$config_file"

    return 0
}

# Internal: Generates a list of SSH hosts from config and known_hosts files.
# The result is cached for performance.
# Output: A list of hostnames, one per line.
z::mod::completions::_get_ssh_hosts() {
    emulate -L zsh
    setopt local_options null_glob typeset_silent

    z::runtime::check_interrupted || return $?

    # Prefer builtin zstat for speed if available
    zmodload -F zsh/stat b:zstat 2>/dev/null

    local cache_file="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/ssh_hosts_cache"
    local -i cache_age
    z::config::get 'ssh_hosts_cache_age' cache_age 3600
    local -i current_time=${EPOCHSECONDS:-$(command date +%s)}

    # Decide how to stat mtime
    local -i have_zstat=0
    if whence -w zstat >/dev/null 2>&1; then
        have_zstat=1
    fi
    local uname_s; uname_s="$(uname -s 2>/dev/null)"
    local is_bsd_ps=0
    [[ "$uname_s" == "Darwin" || "$uname_s" == (FreeBSD|OpenBSD|NetBSD) ]] && is_bsd_ps=1

    # Serve from cache if it's fresh
    if [[ -r "$cache_file" ]]; then
        local cache_mtime
        if (( have_zstat )); then
            cache_mtime=$(zstat +mtime -- "$cache_file" 2>/dev/null)
        elif (( is_bsd_ps )); then
            cache_mtime=$(command stat -f %m "$cache_file" 2>/dev/null)
        else
            cache_mtime=$(command stat -c %Y "$cache_file" 2>/dev/null)
        fi

        if [[ -n "$cache_mtime" ]] && (( current_time - cache_mtime < cache_age )); then
            local -a cached_hosts=("${(@f)$(< "$cache_file")}")
            if (( ${#cached_hosts} )); then
                typeset -g _zcore_ssh_hosts_cache
                _zcore_ssh_hosts_cache=("${cached_hosts[@]}")
                print -l -- "${cached_hosts[@]}"
                z::log::debug "Served SSH hosts from fresh cache."
                return 0
            fi
        fi
    fi

    z::log::debug "SSH host cache is stale or missing; rebuilding."
    typeset -g _zcore_ssh_hosts_cache
    typeset -a discovered_hosts=()
    typeset -a negative_patterns=()

    # SSH config sources
    local -a conf_files=()
    [[ -r "$HOME/.ssh/config" ]] && conf_files+=("$HOME/.ssh/config")
    [[ -d "$HOME/.ssh/config.d" ]] && conf_files+=("$HOME/.ssh/config.d"/*.conf(N))
    [[ -r "/etc/ssh/ssh_config" ]] && conf_files+=("/etc/ssh/ssh_config")
    [[ -d "/etc/ssh/ssh_config.d" ]] && conf_files+=("/etc/ssh/ssh_config.d"/*.conf(N))

    local f
    for f in "${conf_files[@]}"; do
        z::runtime::check_interrupted || return $?
        z::mod::completions::_process_ssh_config "$f" 0 discovered_hosts negative_patterns
    done

    # known_hosts parsing
    local -a known_hosts_files=()
    [[ -r "$HOME/.ssh/known_hosts" ]] && known_hosts_files+=("$HOME/.ssh/known_hosts")
    [[ -r "/etc/ssh/ssh_known_hosts" ]] && known_hosts_files+=("/etc/ssh/ssh_known_hosts")

    local kh host_entry
    for kh in "${known_hosts_files[@]}"; do
        z::runtime::check_interrupted || return $?
        while IFS=' ' read -r host_entry _; do
            z::runtime::check_interrupted || return $?
            # Skip comments and hashed entries
            [[ -z "$host_entry" || "$host_entry" == [\#\|]* ]] && continue

            # Split host list (comma-separated)
            local -a hosts_in_entry
            hosts_in_entry=("${(@s:,:)host_entry}")
            local h
            for h in "${hosts_in_entry[@]}"; do
                # Strip [host]:port and raw :port
                h="${h#\[}"
                h="${h%%\]:*}"
                h="${h%%:*}"
                # Filter localhost, IPs, IPv6, mDNS
                [[ -z "$h" || "$h" == (127.*|::1|*.local|*:*|localhost) ]] && continue
                if [[ "$h" =~ '^([A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)*$' ]]; then
                    discovered_hosts+=("$h")
                fi
            done
        done < "$kh"
    done

    # Apply negative patterns
    if (( ${#negative_patterns} )); then
        local -a filtered_hosts=()
        local host pat
        for host in "${discovered_hosts[@]}"; do
            z::runtime::check_interrupted || return $?
            local -i skip=0
            for pat in "${negative_patterns[@]}"; do
                if [[ "$host" == ${~pat} ]]; then
                    skip=1
                    break
                fi
            done
            (( ! skip )) && filtered_hosts+=("$host")
        done
        discovered_hosts=("${filtered_hosts[@]}")
    fi

    # Unique + sort once
    _zcore_ssh_hosts_cache=("${(@ou)discovered_hosts}")

    # Write cache file
    if (( ${#_zcore_ssh_hosts_cache} )); then
        local cache_dir="${cache_file:h}"
        if [[ -d "$cache_dir" ]] || command mkdir -p "$cache_dir" 2>/dev/null; then
            if ! print -l -- "${_zcore_ssh_hosts_cache[@]}" >| "$cache_file"; then
                z::log::warn "Failed to write SSH hosts cache to $cache_file"
            else
                z::log::debug "Wrote ${#_zcore_ssh_hosts_cache} hosts to cache."
            fi
        fi
    fi

    print -l -- "${_zcore_ssh_hosts_cache[@]}"
    return 0
}

###
# Internal: Configures all `zstyle` settings for the completion system.
###
z::mod::completions::_configure_styles() {
    emulate -L zsh
    z::runtime::check_interrupted || return $?

    # Core completion styles
    zstyle ':completion:*' menu select=2
    zstyle ':completion:*' use-cache on
    zstyle ':completion:*' cache-path "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/compcache"
    zstyle ':completion:*' rehash on
    zstyle ':completion:*' completer _expand _complete _correct
    zstyle ':completion:*' max-errors 2
    zstyle ':completion:*' squeeze-slashes true
    zstyle ':completion:*' accept-exact-dirs true
    zstyle ':completion:*' group-name ''
    zstyle ':completion:*' auto-description 'specify: %d'

    # Matching rules
    zstyle ':completion:*' matcher-list \
        'm:{[:lower:][:upper:]}={[:upper:][:lower:]}' \
        'r:|[._-]=* r:|=*' \
        'l:|=* r:|=*'

    # Formatting and colors
    zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
    zstyle ':completion:*:messages' format '%F{blue}%d%f'
    zstyle ':completion:*:warnings' format '%F{red}No matches found: %d%f'
    zstyle ':completion:*:errors' format '%F{red}%d%f'
    zstyle ':completion:*:corrections' format '%F{magenta}%d (errors: %e)%f'

    if [[ -n "${LS_COLORS:-}" ]]; then
        zstyle ':completion:*:default' list-colors "${(s.:.)LS_COLORS}"
    else
        zstyle ':completion:*:default' list-colors \
            'di=1;34' 'ln=1;36' 'so=1;35' 'pi=1;33' 'ex=1;32' \
            'bd=1;33' 'cd=1;33' 'su=1;31' 'sg=1;33' 'tw=1;32' 'ow=1;34'
    fi

    # Specific command behaviors
    zstyle ':completion:*:*:cd:*' tag-order local-directories directory-stack path-directories
    zstyle ':completion:*:-tilde-:*' group-order 'named-directories' 'path-directories' 'expand'
    zstyle ':completion:*:manuals' separate-sections true
    zstyle ':completion:*:man:*' menu yes select

    # Ignored patterns
    zstyle ':completion:*' ignored-patterns \
        '.DS_Store' '.localized' '._*' '.Spotlight-V100' '.Trashes' \
        'Thumbs.db' 'desktop.ini' '*.bak' '*~' '.git' '.hg' '.svn' \
        'node_modules' '__pycache__' '.pytest_cache' \
        '(*/)#lost+found' '(*/)#.cache' '*.log' '*.pid'

    # Process completion using platform detection from zcore
    local ps_cmd ps_kill_cmd
    if ((IS_MACOS || IS_BSD)); then
        ps_cmd="ps -u ${USER:-$(whoami)} -o pid,ppid,state,start,pcpu,pmem,command"
        ps_kill_cmd="ps -u ${USER:-$(whoami)} -o pid,user,comm"
    else # Assumes Linux-like ps
        ps_cmd="ps -u ${USER:-$(whoami)} -o pid,ppid,state,stime,pcpu,pmem,args"
        ps_kill_cmd="ps -u ${USER:-$(whoami)} -o pid,user,comm -w -w"
    fi
    zstyle ':completion:*:processes' command "$ps_cmd"
    zstyle ':completion:*:*:kill:*:processes' command "$ps_kill_cmd"

    # SSH-like commands host completion
    if z::func::exists z::mod::completions::_get_ssh_hosts; then
        local -a ssh_hosts_array=()
        if ((${#_zcore_ssh_hosts_cache})); then
            ssh_hosts_array=("${_zcore_ssh_hosts_cache[@]}")
        else
            ssh_hosts_array=("${(@f)$(z::mod::completions::_get_ssh_hosts 2> /dev/null)}")
        fi

        if ((${#ssh_hosts_array})); then
            zstyle ':completion:*:(ssh|scp|sftp|rsync):*' hosts "${ssh_hosts_array[@]}"
            zstyle ':completion:*:hosts' hosts "${ssh_hosts_array[@]}"
        fi
    fi

    z::log::debug "Completion styles configured."
    return 0
}

# ==============================================================================
# MAIN INITIALIZATION
# ==============================================================================

###
# Public entry point for the completions module.
###
z::mod::completions::init() {
    emulate -L zsh
    z::runtime::check_interrupted || return $?
    z::log::info "Initializing completions module..."

    local cache_root="${XDG_CACHE_HOME:-$HOME/.cache}"
    local compcache_dir="$cache_root/zsh/compcache"
    if [[ ! -d "$compcache_dir" ]]; then
        if command mkdir -p "$compcache_dir"; then
            z::log::debug "Created completion cache directory: $compcache_dir"
        else
            z::log::warn "Failed to create completion cache directory: $compcache_dir"
        fi
    fi

    zmodload -i zsh/complist 2> /dev/null
	z::mod::completions::_configure_styles

	z::log::info "Completion system configured successfully."
}

# Auto-initialize the module when it is sourced.
if z::func::exists "z::mod::completions::init"; then
	z::mod::completions::init
fi
