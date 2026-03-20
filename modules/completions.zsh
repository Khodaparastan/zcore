#!/usr/bin/env zsh
#
# MODULE CONSTANTS
# ==============================================================================
# Hostname validation regex (ERE-compatible for zsh =~)
# Matches valid hostnames per RFC 1123: alphanumeric, hyphens, dots
typeset -gr _Z_HOSTNAME_REGEX='^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*$'

# Maximum recursion depth for SSH config Include directives
typeset -gir _Z_SSH_CONFIG_MAX_DEPTH=10

# ==============================================================================
# PRIVATE HELPERS
# ==============================================================================

# Internal: Recursively parses an ssh_config file for host definitions.
# Supports Include directives and negative patterns.
#   $1: string  - Path to the ssh_config file.
#   $2: integer - Current recursion depth to prevent infinite loops.
#   $3: string  - Name of the array storing discovered hosts (passed by name).
#   $4: string  - Name of the array storing negative patterns (passed by name).
__z::mod::completions::process_ssh_config() {
    emulate -L zsh
    setopt typeset_silent local_options extended_glob

    local config_file="$1"
    local -i depth=${2:-0}
    local hosts_arr_name="$3"
    local negs_arr_name="$4"

    # Indirect array access without namerefs (zsh 5.0+ compatible)
    if (( depth > _Z_SSH_CONFIG_MAX_DEPTH )); then
        z::log::warn "SSH config include depth limit reached for: $config_file"
        return 0
    fi
    [[ -r "$config_file" ]] || return 0


    local base_dir="${config_file:h}"
    local line trimmed key rest
    while IFS= read -r line || [[ -n "$line" ]]; do
        

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
                    __z::mod::completions::process_ssh_config "$inc" $(( depth + 1 )) "$hosts_arr_name" "$negs_arr_name"
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
                    # Indirect array append
                    eval "${negs_arr_name}+=(\"\${w#!}\")"
                    continue
                fi
                # Skip wildcards, localhost, IPs, IPv6, and .local mDNS
                [[ "$w" == (*[\*\?\[\]]*|localhost|127.*|::1|*:*|*.local) ]] && continue
                # Validate hostname format using module constant (ERE syntax)
                if [[ "$w" =~ $_Z_HOSTNAME_REGEX ]]; then
                    # Indirect array append
                    eval "${hosts_arr_name}+=(\"\$w\")"
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
__z::mod::completions::get_ssh_hosts() {
    emulate -L zsh
    setopt local_options null_glob typeset_silent


    local cache_file="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/ssh_hosts_cache"
    local -i cache_age=3600

    # Try to get config value, fall back to default silently
    if typeset -f z::config::get >/dev/null 2>&1; then
        local _tmp_age
        z::config::get 'ssh_hosts_cache_age' _tmp_age 3600
        cache_age=${_tmp_age:-3600}
    fi

    local -i current_time=${EPOCHSECONDS:-$(command date +%s)}

    # Determine stat command and OS type once
    local -i have_zstat=0
    if zmodload -e zsh/stat 2>/dev/null || zmodload -F zsh/stat b:zstat 2>/dev/null; then
        have_zstat=1
    fi

    local uname_s="${_Z_UNAME_S:-$(uname -s 2>/dev/null)}"
    local -i is_bsd_system=0
    [[ "$uname_s" == (Darwin|FreeBSD|OpenBSD|NetBSD) ]] && is_bsd_system=1

    # Serve from cache if it's fresh
    if [[ -r "$cache_file" ]]; then
        local -i cache_mtime=0
        if (( have_zstat )); then
            cache_mtime=$(zstat +mtime -- "$cache_file" 2>/dev/null || print 0)
        elif (( is_bsd_system )); then
            cache_mtime=$(command stat -f %m -- "$cache_file" || print 0)
        else
            cache_mtime=$(command stat -c %Y -- "$cache_file" || print 0)
        fi

        if (( cache_mtime > 0 && current_time - cache_mtime < cache_age )); then
            local -a cached_hosts=("${(@f)$(< "$cache_file")}")
            if (( ${#cached_hosts} > 0 )); then
                typeset -ga _zcore_ssh_hosts_cache
                _zcore_ssh_hosts_cache=("${cached_hosts[@]}")
                print -l -- "${cached_hosts[@]}"
                z::log::debug "Served SSH hosts from fresh cache."
                return 0
            fi
        fi
    fi

    z::log::debug "SSH host cache is stale or missing; rebuilding."
    typeset -ga _zcore_ssh_hosts_cache
    local -a discovered_hosts=()
    local -a negative_patterns=()

    # SSH config sources
    local -a conf_files=()
    [[ -r "$HOME/.ssh/config" ]] && conf_files+=("$HOME/.ssh/config")
    [[ -d "$HOME/.ssh/config.d" ]] && conf_files+=("$HOME/.ssh/config.d"/*.conf(N))
    [[ -r "/etc/ssh/ssh_config" ]] && conf_files+=("/etc/ssh/ssh_config")
    [[ -d "/etc/ssh/ssh_config.d" ]] && conf_files+=("/etc/ssh/ssh_config.d"/*.conf(N))

    local f
    for f in "${conf_files[@]}"; do
        
        __z::mod::completions::process_ssh_config "$f" 0 discovered_hosts negative_patterns
    done

    # known_hosts parsing
    local -a known_hosts_files=()
    [[ -r "$HOME/.ssh/known_hosts" ]] && known_hosts_files+=("$HOME/.ssh/known_hosts")
    [[ -r "/etc/ssh/ssh_known_hosts" ]] && known_hosts_files+=("/etc/ssh/ssh_known_hosts")

    local kh host_entry
    for kh in "${known_hosts_files[@]}"; do
        
        while IFS=' ' read -r host_entry _; do
            
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
                # Validate hostname format using module constant
                if [[ "$h" =~ $_Z_HOSTNAME_REGEX ]]; then
                    discovered_hosts+=("$h")
                fi
            done
        done < "$kh"
    done

    # Apply negative patterns
    if (( ${#negative_patterns} > 0 )); then
        local -a filtered_hosts=()
        local host pat
        for host in "${discovered_hosts[@]}"; do
            
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
    if (( ${#_zcore_ssh_hosts_cache} > 0 )); then
        local cache_dir="${cache_file:h}"
        if [[ -d "$cache_dir" ]] || command mkdir -p -- "$cache_dir"; then
            if ! print -l -- "${_zcore_ssh_hosts_cache[@]}" >| "$cache_file"; then
                z::log::warn "Failed to write SSH hosts cache to $cache_file"
            else
                z::log::debug "Wrote ${#_zcore_ssh_hosts_cache} hosts to cache."
            fi
        else
            z::log::warn "Cannot create cache directory: $cache_dir"
        fi
    fi

    print -l -- "${_zcore_ssh_hosts_cache[@]}"
    return 0
}

# Internal: Configures all zstyle settings for the completion system.
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
    zstyle ':completion:*' accept-exact '*(N)'
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

    # Specific command behaviors
    zstyle ':completion:*:*:cd:*'       tag-order local-directories directory-stack path-directories
    zstyle ':completion:*:-tilde-:*'    group-order 'named-directories' 'path-directories' 'expand'
    zstyle ':completion:*:manuals'      separate-sections true
    zstyle ':completion:*:man:*'        menu select

    # Ignored patterns
    zstyle ':completion:*' ignored-patterns \
        '.DS_Store' '.localized' '._*' '.Spotlight-V100' '.Trashes' \
        'Thumbs.db' 'desktop.ini' '*.bak' '*~' '.git' '.hg' '.svn' \
        'node_modules' '__pycache__' '.pytest_cache' \
        '(*/)#lost+found' '(*/)#.cache' '*.log' '*.pid'

    # Process completion using cached platform detection
    local uname_s="${_Z_UNAME_S:-$(uname -s 2>/dev/null)}"
    local -i is_bsd_system=0
    [[ "$uname_s" == (Darwin|FreeBSD|OpenBSD|NetBSD) ]] && is_bsd_system=1

    local ps_cmd ps_kill_cmd
    local current_user="${USER:-$(id -un 2>/dev/null || print "nobody")}"
    if (( is_bsd_system )); then
        ps_cmd="ps -u ${current_user} -o pid,ppid,state,start,pcpu,pmem,command"
        ps_kill_cmd="ps -u ${current_user} -o pid,user,comm"
    else
        ps_cmd="ps -u ${current_user} -o pid,ppid,state,stime,pcpu,pmem,args"
        ps_kill_cmd="ps -u ${current_user} -o pid,user,comm -w -w"
    fi
    zstyle ':completion:*:processes' command "$ps_cmd"
    zstyle ':completion:*:*:kill:*:processes' command "$ps_kill_cmd"

    # SSH-like commands host completion
    local -a ssh_hosts_array=()
    if (( ${+_zcore_ssh_hosts_cache} && ${#_zcore_ssh_hosts_cache} > 0 )); then
        ssh_hosts_array=("${_zcore_ssh_hosts_cache[@]}")
    else
        # Build (and populate cache) on demand; ignore errors
        ssh_hosts_array=("${(@f)$(__z::mod::completions::get_ssh_hosts 2>/dev/null)}")
    fi

    if (( ${#ssh_hosts_array} > 0 )); then
        zstyle ':completion:*:(ssh|scp|sftp|rsync):*' hosts "${ssh_hosts_array[@]}"
        zstyle ':completion:*:hosts'                   hosts "${ssh_hosts_array[@]}"
    fi

    z::log::debug "Completion styles configured."
}

# Public init: prepares cache paths, loads modules, and configures styles
__z::mod::completions::init() {
    emulate -L zsh
    setopt local_options typeset_silent

    
    z::log::info "Initializing completions module..."

    # Cache OS type for module lifetime
    typeset -g _Z_UNAME_S
    _Z_UNAME_S="$(uname -s 2>/dev/null || print "Unknown")"

    local cache_root="${XDG_CACHE_HOME:-$HOME/.cache}"
    local compcache_dir="$cache_root/zsh/compcache"
    if [[ ! -d "$compcache_dir" ]]; then
        if command mkdir -p -- "$compcache_dir" 2>/dev/null; then
            z::log::debug "Created completion cache directory: $compcache_dir"
        else
            z::log::warn "Failed to create completion cache directory: $compcache_dir"
        fi
    fi

    # Load complist for menu-select UI
    zmodload -i zsh/complist 2>/dev/null

    __z::mod::completions::configure_styles

    z::log::info "Completion system configured successfully."
}

# Auto-initialize the module when it is sourced (if the init function exists).
if z::probe::func "__z::mod::completions::init"; then
    __z::mod::completions::init
fi
