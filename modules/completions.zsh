#!/usr/bin/env zsh

# Unique global cache for SSH hosts (no global pollution duplicates)
typeset -gU _zcore_ssh_hosts_cache

# Internal: parse an ssh_config file (with Include support) into host and negative pattern arrays
# Usage: _zcore__ssh__process_config <config_file> <depth> <hosts_array_name> <neg_patterns_array_name>
_zcore__ssh__process_config() {
    emulate -L zsh -o no_aliases
    setopt typeset_silent local_options extended_glob

    local config_file=$1
    local -i depth=${2:-0}
    local hosts_ref_name=$3
    local neg_ref_name=$4

    # namerefs to caller arrays
    typeset -n _hosts_ref="$hosts_ref_name"
    typeset -n _negs_ref="$neg_ref_name"

    (( depth > 10 )) && return 0
    [[ -r $config_file ]] || return 0

    z::runtime::check_interrupted || return $?

    local base_dir=${config_file:h}
    local line trimmed
    while IFS= read -r line || [[ -n $line ]]; do
        z::runtime::check_interrupted || return $?

        trimmed=${line##[[:space:]]#}
        [[ -z $trimmed || ${trimmed[1]} == \# ]] && continue

        # Include (case-insensitive)
        if [[ $trimmed == (#mi)[[:space:]]#include[[:space:]]#(*) ]]; then
            local include_pattern=${match[1]//\"/}
            [[ $include_pattern != /* ]] && include_pattern="$base_dir/$include_pattern"
            local inc
            for inc in ${~include_pattern}(N); do
                [[ -r $inc ]] && _zcore__ssh__process_config "$inc" $((depth + 1)) "$hosts_ref_name" "$neg_ref_name"
            done
            continue
        fi

        # Host (case-insensitive)
        if [[ $trimmed == (#mi)[[:space:]]#host[[:space:]]#(*) ]]; then
            local hosts_part=${match[1]//\"/}
            local -a host_list=(${=hosts_part})
            local w
            for w in "${host_list[@]}"; do
                if [[ $w == \!* ]]; then
                    _negs_ref+=("${w#!}")
                    continue
                fi
                # Skip wildcards, localhost, IPs, IPv6, and .local mDNS
                [[ $w == (*[\*\?\[\]]*|localhost|127.*|::1|*:*|*.local) ]] && continue
                # Validate hostname
                if [[ $w =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*$ ]]; then
                    _hosts_ref+=("$w")
                fi
            done
            continue
        fi
    done < "$config_file"
    return 0
}

# Completions setup (no compinit here; zi handles loading/caching)
_setup_completions() {
    emulate -L zsh -o no_aliases
    setopt local_options extended_glob null_glob

  z::runtime::check_interrupted || return $?

  # Ensure cache dir exists for completion helpers that honor use-cache
  local cache_root=${XDG_CACHE_HOME:-$HOME/.cache}
  local compcache_dir=$cache_root/zsh/compcache
    [[ -d $compcache_dir ]] || mkdir -p "$compcache_dir" 2>/dev/null

  # Nice list/menu features if available (safe no-op if missing)
  zmodload -i zsh/complist 2>/dev/null

  _configure_completion_styles
  return 0
}

_get_ssh_completion_hosts() {
    emulate -L zsh -o no_aliases
    setopt local_options null_glob typeset_silent

  z::runtime::check_interrupted || return $?

  # Prefer zstat for speed if available
  zmodload -F zsh/stat b:zstat 2>/dev/null

  local cache_file=${XDG_CACHE_HOME:-$HOME/.cache}/zsh/ssh_hosts_cache
    local -i cache_age=${ZCORE_SSH_HOSTS_CACHE_AGE:-3600}  # seconds
    local -i current_time=${EPOCHSECONDS:-$(command date +%s 2>/dev/null || echo 0)}

  # Serve from cache if fresh
  if [[ -r $cache_file ]]; then
        local cache_mtime=""
    if (( $+builtins[zstat] )); then
      cache_mtime=$(zstat +mtime -- "$cache_file" 2>/dev/null)
    elif [[ $OSTYPE == darwin* ]]; then
            cache_mtime=$(command stat -f %m "$cache_file" 2>/dev/null)
    else
            cache_mtime=$(command stat -c %Y "$cache_file" 2>/dev/null)
    fi
    if [[ -n $cache_mtime ]] && (( current_time - cache_mtime < cache_age )); then
      local -a cached_hosts=("${(@f)$(<"$cache_file")}")
      if (( ${#cached_hosts} )); then
        _zcore_ssh_hosts_cache=("${cached_hosts[@]}")
        print -l -- "${cached_hosts[@]}"
        return 0
      fi
    fi
  fi

    typeset -aU discovered_hosts=()
    typeset -a negative_patterns=()

	# SSH config sources
	local -a conf_files=()
	[[ -r $HOME/.ssh/config     ]] && conf_files+=("$HOME/.ssh/config")
    [[ -d $HOME/.ssh/config.d   ]] && conf_files+=($HOME/.ssh/config.d/*.conf)
	[[ -r /etc/ssh/ssh_config   ]] && conf_files+=("/etc/ssh/ssh_config")
    [[ -d /etc/ssh/ssh_config.d ]] && conf_files+=(/etc/ssh/ssh_config.d/*.conf(N))

  local f
  for f in "${conf_files[@]}"; do
    z::runtime::check_interrupted || return $?
        _zcore__ssh__process_config "$f" 0 discovered_hosts negative_patterns
  done

  # known_hosts parsing (skip hashed lines per-line)
  local -a known_hosts_files=()
  [[ -r $HOME/.ssh/known_hosts     ]] && known_hosts_files+=("$HOME/.ssh/known_hosts")
  [[ -r /etc/ssh/ssh_known_hosts   ]] && known_hosts_files+=("/etc/ssh/ssh_known_hosts")

    local kh host_entry
  for kh in "${known_hosts_files[@]}"; do
    z::runtime::check_interrupted || return $?

    [[ -r $kh ]] || continue
    while IFS=' ' read -r host_entry _; do
      z::runtime::check_interrupted || return $?

      [[ -z $host_entry || $host_entry == [\#\|]* ]] && continue
      local -a hosts_in_entry=("${(@s:,:)host_entry}")
      local h
      for h in "${hosts_in_entry[@]}"; do
        # Strip brackets/ports, skip IPs, IPv6, .local, localhost
        h=${h#\[}; h=${h%%\]:*}; h=${h%%:*}
        [[ -z $h || $h == (127.*|::1|*.local|*:*|localhost) ]] && continue
        if [[ $h =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*$ ]]; then
          discovered_hosts+=("$h")
        fi
      done
    done < "$kh"
  done

  # Unique and sort
  discovered_hosts=("${(@ou)discovered_hosts}")

    # Apply negative patterns
	if (( ${#negative_patterns} )); then
		local -a out=()
		local host pat
		for host in "${discovered_hosts[@]}"; do
			z::runtime::check_interrupted || return $?

            local -i skip=0
			for pat in "${negative_patterns[@]}"; do
				if [[ $host == ${~pat} ]]; then
					skip=1; break
				fi
			done
			(( ! skip )) && out+=("$host")
		done
		discovered_hosts=("${out[@]}")
	fi
  # Update global cache and write file
  _zcore_ssh_hosts_cache=("${discovered_hosts[@]}")
  if (( ${#discovered_hosts} )); then
    local cache_dir=${cache_file:h}
        if [[ -d $cache_dir ]] || mkdir -p "$cache_dir" 2>/dev/null; then
      { print -l -- "${discovered_hosts[@]}" >| "$cache_file"; } 2>/dev/null || :
    fi
  fi

  print -l -- "${discovered_hosts[@]}"
    return 0
}

_configure_completion_styles() {
    emulate -L zsh -o no_aliases

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

  # Formatting
  zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
  zstyle ':completion:*:messages'     format '%F{blue}%d%f'
  zstyle ':completion:*:warnings'     format '%F{red}No matches found: %d%f'
  zstyle ':completion:*:errors'       format '%F{red}%d%f'
  zstyle ':completion:*:corrections'  format '%F{magenta}%d (errors: %e)%f'

  # Colors
    if [[ -n ${LS_COLORS:-} ]]; then
    zstyle ':completion:*:default' list-colors "${(s.:.)LS_COLORS}"
  else
    local default_colors=(
      'di=1;34' 'ln=1;36' 'so=1;35' 'pi=1;33' 'ex=1;32'
      'bd=1;33' 'cd=1;33' 'su=1;31' 'sg=1;33' 'tw=1;32' 'ow=1;34'
    )
    zstyle ':completion:*:default' list-colors "${(j.:.)default_colors}"
  fi

  # Directories
  zstyle ':completion:*:*:cd:*' tag-order local-directories directory-stack path-directories
  zstyle ':completion:*:*:cd:*:directory-stack' menu yes select
  zstyle ':completion:*:-tilde-:*' group-order 'named-directories' 'path-directories' 'expand'

  # Processes
  local ps_cmd ps_kill_cmd
  if [[ $OSTYPE == darwin* || $OSTYPE == *bsd* ]]; then
    ps_cmd="ps -u ${USER:-$(whoami)} -o pid,ppid,state,start,pcpu,pmem,command"
    ps_kill_cmd="ps -u ${USER:-$(whoami)} -o pid,user,comm"
  else
    ps_cmd="ps -u ${USER:-$(whoami)} -o pid,ppid,state,stime,pcpu,pmem,args"
    ps_kill_cmd="ps -u ${USER:-$(whoami)} -o pid,user,comm -w -w"
  fi
  zstyle ':completion:*:processes' command "$ps_cmd"
  zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#) ([0-9a-z-]#)*=01;34=0=01'
  zstyle ':completion:*:*:kill:*:processes' command "$ps_kill_cmd"

  # Man pages
  zstyle ':completion:*:manuals'    separate-sections true
  zstyle ':completion:*:manuals.*'  insert-tab true
  zstyle ':completion:*:man:*'      menu yes select

  # Ignored patterns
  local -a ignored_patterns=(
    '.DS_Store' '.localized' '._*' '.Spotlight-V100' '.Trashes' '.fseventsd'
    'ehthumbs.db' 'Thumbs.db' 'desktop.ini'
    '*.bak' '*.swp' '*.swo' '*.tmp' '*.temp' '*~'
    '.git' '.hg' '.svn' '.bzr' 'CVS'
    'node_modules' '__pycache__' '.pytest_cache' '.mypy_cache'
    '(*/)#lost+found' '(*/)#.cache'
    '*(#i).Trash*' '*.log' '*.pid'
  )
  zstyle ':completion:*' ignored-patterns "${ignored_patterns[@]}"

  # SSH-like commands: provide host list
  if (( $+functions[_get_ssh_completion_hosts] )); then
    local -a ssh_hosts_array=()
    if (( ${#_zcore_ssh_hosts_cache} )); then
      ssh_hosts_array=("${_zcore_ssh_hosts_cache[@]}")
    else
      ssh_hosts_array=("${(@f)$(_get_ssh_completion_hosts 2>/dev/null)}")
    fi
    if (( ${#ssh_hosts_array} )); then
      zstyle ':completion:*:(ssh|scp|sftp|rsync):*' hosts "${ssh_hosts_array[@]}"
      zstyle ':completion:*:(ssh|scp|sftp|rsync):*:hosts' list-colors '=*=01;32'
      zstyle ':completion:*:hosts' hosts "${ssh_hosts_array[@]}"
    fi
  fi
    return 0
}

_git_prompt_info() {
    emulate -L zsh -o no_aliases
    setopt local_options no_nomatch

  z::runtime::check_interrupted || return $?

  command git rev-parse --git-dir &>/dev/null || return

  local branch_name git_status='' git_color='green'

  branch_name=$(command git symbolic-ref --short HEAD 2>/dev/null)
  if [[ -z $branch_name ]]; then
    branch_name=$(command git describe --tags --exact-match HEAD 2>/dev/null) \
      || branch_name=$(command git rev-parse --short HEAD 2>/dev/null) \
      || branch_name='detached'
  fi

    local -i has_changes=0 has_untracked=0
  local status_output
  status_output=$(command git status --porcelain=v1 2>/dev/null)
  if [[ -n $status_output ]]; then
    local l
    while IFS= read -r l; do
      if [[ $l == '??'* ]]; then
        has_untracked=1
      else
        has_changes=1
      fi
      (( has_changes && has_untracked )) && break
    done <<< "$status_output"
  fi

  (( has_changes ))   && { git_status+='*'; git_color='yellow'; }
  (( has_untracked )) && { git_status+='+'; git_color='red'; }
  command git rev-parse --verify --quiet refs/stash &>/dev/null && git_status+='$'

  printf '%%F{%s} (%s%s)%%f' "$git_color" "$branch_name" "$git_status"
    return 0
}

_setup_prompt() {
    emulate -L zsh -o no_aliases
    setopt local_options prompt_subst

  z::runtime::check_interrupted || return $?

  # Cache git availability
    if [[ -z ${_zcore_git_available:-} ]]; then
    (( ${+commands[git]} )) && typeset -g _zcore_git_available=1 || typeset -g _zcore_git_available=0
  fi

    local -i use_color=1
    [[ -n ${NO_COLOR:-} || ${TERM:-} == dumb ]] && use_color=0

  if (( use_color )); then
    if (( _zcore_git_available )); then
      PS1='%F{cyan}%n@%m%f:%F{blue}%~%f$(_git_prompt_info)%F{green}❯%f '
    else
      PS1='%F{cyan}%n@%m%f:%F{blue}%~%f%F{green}❯%f '
    fi
    RPS1='%(?..%F{red}✗%f )%F{244}%T%f'
    PS2='%F{green}❯%f '
  else
    PS1='%n@%m:%~%(?..!)> '
    RPS1='%T'
    PS2='> '
  fi

#Terminal title without overwriting other precmd handlers
	autoload -Uz add-zsh-hook 2>/dev/null || true
	_zcore_precmd_set_title() { print -Pn '\e]0;%n@%m:%~\a' }
	add-zsh-hook precmd _zcore_precmd_set_title 2>/dev/null || {
		# Fallback if add-zsh-hook is unavailable
		if [[ -z ${(M)precmd_functions:#_zcore_precmd_set_title} ]]; then
			precmd_functions+=_zcore_precmd_set_title
		fi
	}
    return 0
}
