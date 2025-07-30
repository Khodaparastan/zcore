#!/usr/bin/env zsh

# Use local scope for ssh_hosts to avoid global pollution
typeset -gU _zsh_ssh_hosts_cache

_setup_completions() {
  emulate -L zsh
  setopt LOCAL_OPTIONS EXTENDED_GLOB NULL_GLOB

  # Validate environment
  if ! (( ${+EPOCHSECONDS} )); then
    print -P "%F{red}[zsh] Error: EPOCHSECONDS not available (zsh too old?)%f" >&2
    return 1
  fi

  local xdg_cache_home="${XDG_CACHE_HOME:-$HOME/.cache}"
  local zcompdump_dir="${xdg_cache_home}/zsh"
  local compcache_dir="${zcompdump_dir}/compcache"
  local zver="${ZSH_VERSION%.*}"
  local host_id="${HOST:-${HOSTNAME:-localhost}}"
  local zcompdump_file="${zcompdump_dir}/zcompdump-${host_id}-${zver}"

  # # Create directories with proper error handling
  # if ! command mkdir -p "$zcompdump_dir" "$compcache_dir" 2>/dev/null; then
  #   # Check if directories exist but aren't writable
  #   if [[ -d $zcompdump_dir && ! -w $zcompdump_dir ]]; then
  #     print -P "%F{red}[zsh] Error: Completion directory not writable: $zcompdump_dir%f" >&2
  #   else
  #     print -P "%F{red}[zsh] Error: Cannot create completion directories%f" >&2
  #   fi
  #   return 1
  # fi
  #
  # local rebuild=0
  # local rebuild_reason=""
  #
  # # Check if rebuild needed
  # if [[ ! -f $zcompdump_file ]]; then
  #   rebuild=1
  #   rebuild_reason="dump file missing"
  # elif [[ ! -s $zcompdump_file ]]; then
  #   rebuild=1
  #   rebuild_reason="dump file empty"
  # else
  #   # Get file modification time with better platform handling
  #   local current_time=$EPOCHSECONDS
  #   local file_mtime
  #
  #   if (( ${+builtins[zstat]} )); then
  #     file_mtime=$(zstat +mtime "$zcompdump_file" 2>/dev/null)
  #   elif [[ $OSTYPE == darwin* ]]; then
  #     file_mtime=$(command stat -f %m "$zcompdump_file" 2>/dev/null)
  #   else
  #     file_mtime=$(command stat -c %Y "$zcompdump_file" 2>/dev/null)
  #   fi
  #
  #   if [[ -z $file_mtime ]]; then
  #     rebuild=1
  #     rebuild_reason="cannot determine dump file age"
  #   elif (( current_time - file_mtime > 604800 )); then
  #     rebuild=1
  #     rebuild_reason="dump file older than 7 days"
  #   else
  #     # Check for newer completion files
  #     local -a scan_dirs=(
  #       "/usr/share/zsh/${zver}/functions"
  #       "/usr/share/zsh/site-functions"
  #       "/usr/local/share/zsh/site-functions"
  #       "${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions"
  #       "${XDG_DATA_HOME:-$HOME/.local/share}/zsh/completions"
  #       "$HOME/.zsh/completions"
  #       "${ZDOTDIR:-$HOME}/.zsh/completions"
  #     )
  #
  #     [[ -n $HOMEBREW_PREFIX ]] && scan_dirs+=("$HOMEBREW_PREFIX/share/zsh/site-functions")
  #
  #     # Remove non-existent directories first
  #     scan_dirs=( ${^scan_dirs}(N-/) )
  #
  #     local sd newer_file
  #     for sd in "${scan_dirs[@]}"; do
  #       # Check directory modification time first
  #       if [[ $sd -nt $zcompdump_file ]]; then
  #         rebuild=1
  #         rebuild_reason="completion directory $sd is newer"
  #         break
  #       fi
  #
  #       # Only scan files if directory isn't newer
  #       for newer_file in "$sd"/**/*(.Nom[1]); do
  #         if [[ $newer_file -nt $zcompdump_file ]]; then
  #           rebuild=1
  #           rebuild_reason="newer completion files found in $sd"
  #           break 2
  #         fi
  #       done
  #     done
  #   fi
  # fi
  #
  # # Enhanced security check
  # if [[ -f $zcompdump_file ]] && ! ((rebuild)); then
  #   local file_uid file_gid file_mode
  #
  #   if (( ${+builtins[zstat]} )); then
  #     local -a stat_info
  #     stat_info=( $(zstat +uid +gid +mode "$zcompdump_file" 2>/dev/null) )
  #     file_uid=${stat_info[1]}
  #     file_gid=${stat_info[2]}
  #     file_mode=${stat_info[3]}
  #   else
  #     # More robust ls parsing
  #     local ls_line
  #     ls_line=$(command ls -lnd "$zcompdump_file" 2>/dev/null) || {
  #       rebuild=1
  #       rebuild_reason="cannot stat dump file"
  #     }
  #
  #     if [[ -n $ls_line ]]; then
  #       local -a ls_fields=( ${(s: :)ls_line} )
  #       file_uid=${ls_fields[3]}
  #       file_gid=${ls_fields[4]}
  #
  #       # Parse permissions more accurately
  #       local perms=${ls_fields[1]}
  #       file_mode=0
  #       [[ ${perms:8:1} == "w" ]] && (( file_mode |= 0002 ))
  #       [[ ${perms:5:1} == "w" ]] && (( file_mode |= 0020 ))
  #     fi
  #   fi
  #
  #   # Check ownership and permissions
  #   if [[ -n $file_uid ]]; then
  #     if [[ $file_uid != $UID ]]; then
  #       rebuild=1
  #       rebuild_reason="dump file not owned by current user"
  #     elif (( file_mode & 0002 )); then
  #       rebuild=1
  #       rebuild_reason="dump file is world-writable"
  #     fi
  #   fi
  # fi
  #
  # # Rebuild if needed
  # if ((rebuild)); then
  #   print -P "%F{yellow}[zsh] Rebuilding completions ($rebuild_reason)...%f"
  #   command rm -f "$zcompdump_file" 2>/dev/null
  #
  #   if compinit -d "$zcompdump_file" 2>/dev/null; then
  #     print -P "%F{green}[zsh] Completion dump rebuilt ➜ ${zcompdump_file:t}%f"
  #   else
  #     print -P "%F{red}[zsh] Error: Failed to rebuild completions%f" >&2
  #     # Try without dump file as fallback
  #     compinit -C 2>/dev/null || return 1
  #   fi
  # else
  #   compinit -C -d "$zcompdump_file" 2>/dev/null || {
  #     print -P "%F{red}[zsh] Error: Failed to initialize completions%f" >&2
  #     return 1
  #   }
  # fi

  _configure_completion_styles
  return 0
}

_get_ssh_completion_hosts() {
  emulate -L zsh
  setopt LOCAL_OPTIONS EXTENDED_GLOB NULL_GLOB NO_NOMATCH

  local cache_file="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/ssh_hosts_cache"
  local cache_age=3600  # 1 hour

  # Check cache validity
  if [[ -f $cache_file && -r $cache_file ]]; then
    local current_time=$EPOCHSECONDS
    local cache_mtime
    
    if (( ${+builtins[zstat]} )); then
      cache_mtime=$(zstat +mtime "$cache_file" 2>/dev/null)
    elif [[ $OSTYPE == darwin* ]]; then
      cache_mtime=$(command stat -f %m "$cache_file" 2>/dev/null)
    else
      cache_mtime=$(command stat -c %Y "$cache_file" 2>/dev/null)
    fi
    
    if [[ -n $cache_mtime ]] && (( current_time - cache_mtime < cache_age )); then
      local -a cached_hosts=("${(@f)$(<$cache_file)}")
      if (( ${#cached_hosts[@]} > 0 )); then
        _zsh_ssh_hosts_cache=("${cached_hosts[@]}")
        print -l "${cached_hosts[@]}"
        return 0
      fi
    fi
  fi

  local -aU discovered_hosts=()
  local -a negative_patterns=()

  # Parse SSH config files
  local -a conf_files=()
  [[ -r $HOME/.ssh/config ]] && conf_files+=("$HOME/.ssh/config")
  [[ -d $HOME/.ssh/config.d ]] && conf_files+=("$HOME"/.ssh/config.d/*.conf(N.))

  # Enhanced SSH config parser
  _process_ssh_config() {
    local config_file=$1
    local base_dir=${config_file:h}
    local depth=${2:-0}
    
    # Prevent infinite recursion
    ((depth > 10)) && return
    
    [[ -r $config_file ]] || return
    
    local line
    while IFS= read -r line || [[ -n $line ]]; do
      # Skip comments and empty lines
      [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
      
      # Handle Include directive (case-insensitive)
      if [[ $line =~ ^[[:space:]]*[Ii]nclude[[:space:]]+(.+)[[:space:]]*$ ]]; then
        local include_pattern=${match[1]//\"/}  # Remove quotes
        
        # Resolve relative paths
        [[ $include_pattern != /* ]] && include_pattern="${base_dir}/${include_pattern}"
        
        # Safely expand pattern
        local include_file
        for include_file in ${~include_pattern}(N); do
          [[ -r $include_file ]] && _process_ssh_config "$include_file" $((depth + 1))
        done
      elif [[ $line =~ ^[[:space:]]*[Hh]ost[[:space:]]+(.+)[[:space:]]*$ ]]; then
        local hosts_part=${match[1]//\"/}  # Remove quotes
        local -a host_list=("${(@s: :)hosts_part}")
        
        local word
        for word in "${host_list[@]}"; do
          # Handle negation patterns
          if [[ $word == \!* ]]; then
            negative_patterns+=("${word#!}")
            continue
          fi
          
          # Skip wildcards, localhost, and IPs
          [[ $word == (*[\*\?\[\]]*|localhost|127.*|::1|*:*) ]] && continue
          
          # Validate hostname (no trailing dots, proper format)
          if [[ $word =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*$ ]]; then
            discovered_hosts+=("$word")
          fi
        done
      fi
    done < "$config_file"
  }

  # Process all config files
  local f
  for f in "${conf_files[@]}"; do
    _process_ssh_config "$f" 0
  done

  # Parse known_hosts if not hashed
  local -a known_hosts_files=()
  [[ -r $HOME/.ssh/known_hosts ]] && known_hosts_files+=("$HOME/.ssh/known_hosts")
  [[ -r /etc/ssh/ssh_known_hosts ]] && known_hosts_files+=("/etc/ssh/ssh_known_hosts")

  local kh_file
  for kh_file in "${known_hosts_files[@]}"; do
    [[ -r $kh_file ]] || continue
    
    # Skip if file appears to be hashed (check first few lines)
    local is_hashed=0
    local line_count=0
    while IFS= read -r line && ((++line_count <= 5)); do
      [[ $line == \|* ]] && { is_hashed=1; break; }
    done < "$kh_file"
    
    ((is_hashed)) && continue
    
    # Parse known hosts
    local host_entry
    while IFS=' ' read -r host_entry _; do
      [[ -z $host_entry || $host_entry == [\#\|]* ]] && continue
      
      # Handle comma-separated hosts
      local -a hosts_in_entry=("${(@s:,:)host_entry}")
      local single_host
      
      for single_host in "${hosts_in_entry[@]}"; do
        # Remove port notation
        single_host=${single_host#\[}
        single_host=${single_host%%\]:*}
        single_host=${single_host%%:*}
        
        # Skip IPs and .local domains
        [[ -z $single_host || $single_host == (127.*|::1|*.local|*:*) ]] && continue
        
        # Validate hostname
        if [[ $single_host =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*$ ]]; then
          discovered_hosts+=("$single_host")
        fi
      done
    done < "$kh_file"
  done

  # Remove duplicates
  discovered_hosts=("${(@u)discovered_hosts}")
  
  # Apply negative patterns safely
  if (( ${#negative_patterns[@]} > 0 )); then
    local -a filtered_hosts=()
    local host pattern
    
    for host in "${discovered_hosts[@]}"; do
      local exclude=0
      for pattern in "${negative_patterns[@]}"; do
        # Use safe pattern matching
        if [[ $host == ${~pattern} ]] 2>/dev/null; then
          exclude=1
          break
        fi
      done
      ((exclude)) || filtered_hosts+=("$host")
    done
    discovered_hosts=("${filtered_hosts[@]}")
  fi
  
  # Sort hosts
  discovered_hosts=("${(@o)discovered_hosts}")
  
  # Update global cache
  _zsh_ssh_hosts_cache=("${discovered_hosts[@]}")
  
  # Write to cache file
  if (( ${#discovered_hosts[@]} > 0 )); then
    local cache_dir=${cache_file:h}
    if [[ -d $cache_dir ]] || command mkdir -p "$cache_dir" 2>/dev/null; then
      {
        print -l "${discovered_hosts[@]}" > "$cache_file"
      } 2>/dev/null || {
        command rm -f "$cache_file" 2>/dev/null
        : # Ignore cache write failures
      }
    fi
  fi

  print -l "${discovered_hosts[@]}"
}

_configure_completion_styles() {
  emulate -L zsh
  
  # Core completion settings
  zstyle ':completion:*' menu select=2
  zstyle ':completion:*' use-cache true
  zstyle ':completion:*' cache-path "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/compcache"
  zstyle ':completion:*' rehash true
  zstyle ':completion:*' completer _expand _complete _correct
  zstyle ':completion:*' max-errors 2
  zstyle ':completion:*' squeeze-slashes true
  zstyle ':completion:*' accept-exact-dirs true
  zstyle ':completion:*' group-name ''
  zstyle ':completion:*' auto-description 'specify: %d'

  # Case-insensitive matching with better patterns
  zstyle ':completion:*' matcher-list \
    'm:{[:lower:][:upper:]}={[:upper:][:lower:]}' \
    'r:|[._-]=* r:|=*' \
    'l:|=* r:|=*'

  # Formatting
  zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
  zstyle ':completion:*:messages' format '%F{blue}%d%f'
  zstyle ':completion:*:warnings' format '%F{red}No matches found: %d%f'
  zstyle ':completion:*:errors' format '%F{red}%d%f'
  zstyle ':completion:*:corrections' format '%F{magenta}%d (errors: %e)%f'

  # Colors - use LS_COLORS if available, otherwise use defaults
  if [[ -n $LS_COLORS ]]; then
    zstyle ':completion:*:default' list-colors "${(s.:.)LS_COLORS}"
  else
    # Organized default colors
    local default_colors=(
      'di=1;34'    # directories: bold blue
      'ln=1;36'    # links: bold cyan
      'so=1;35'    # sockets: bold magenta
      'pi=1;33'    # pipes: bold yellow
      'ex=1;32'    # executables: bold green
      'bd=1;33'    # block devices: bold yellow
      'cd=1;33'    # char devices: bold yellow
      'su=1;31'    # setuid: bold red
      'sg=1;33'    # setgid: bold yellow
      'tw=1;32'    # sticky other-writable: bold green
      'ow=1;34'    # other-writable: bold blue
    )
    zstyle ':completion:*:default' list-colors "${(j.:.)default_colors}"
  fi
  
  # Directory completion
  zstyle ':completion:*:*:cd:*' tag-order local-directories directory-stack path-directories
  zstyle ':completion:*:*:cd:*:directory-stack' menu yes select
  zstyle ':completion:*:-tilde-:*' group-order 'named-directories' 'path-directories' 'expand'

  # Process completion with platform-aware ps command
  local ps_cmd ps_kill_cmd
  if [[ $OSTYPE == darwin* ]] || [[ $OSTYPE == *bsd* ]]; then
    ps_cmd="ps -u ${USER:-$(whoami)} -o pid,ppid,state,start,pcpu,pmem,command"
    ps_kill_cmd="ps -u ${USER:-$(whoami)} -o pid,user,comm"
  else
    ps_cmd="ps -u ${USER:-$(whoami)} -o pid,ppid,state,stime,pcpu,pmem,args"
    ps_kill_cmd="ps -u ${USER:-$(whoami)} -o pid,user,comm -w -w"
  fi
  
  zstyle ':completion:*:processes' command "$ps_cmd"
  zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#) ([0-9a-z-]#)*=01;34=0=01'
  zstyle ':completion:*:*:kill:*:processes' command "$ps_kill_cmd"

  # Manual pages
  zstyle ':completion:*:manuals' separate-sections true
  zstyle ':completion:*:manuals.*' insert-tab true
  zstyle ':completion:*:man:*' menu yes select

  # Organized ignored patterns
  local -a ignored_patterns=(
    # macOS system files
    '.DS_Store' '.localized' '._*' '.Spotlight-V100' '.Trashes' '.fseventsd'
    # Windows system files
    'ehthumbs.db' 'Thumbs.db' 'desktop.ini'
    # Editor backup files
    '*.bak' '*.swp' '*.swo' '*.tmp' '*.temp' '*~'
    # Version control
    '.git' '.hg' '.svn' '.bzr' 'CVS'
    # Build/cache directories
    'node_modules' '__pycache__' '.pytest_cache' '.mypy_cache'
    # System directories
    '(*/)#lost+found' '(*/)#.cache'
    # Other
    '*(#i).Trash*' '*.log' '*.pid'
  )
  zstyle ':completion:*' ignored-patterns "${ignored_patterns[@]}"

  # SSH hosts configuration
  if (( ${+functions[_get_ssh_completion_hosts]} )); then
    local -a ssh_hosts_array=()
    
    # Use cached hosts if available
    if (( ${#_zsh_ssh_hosts_cache[@]} > 0 )); then
      ssh_hosts_array=("${_zsh_ssh_hosts_cache[@]}")
    else
      ssh_hosts_array=("${(@f)$(_get_ssh_completion_hosts 2>/dev/null)}")
    fi
    
    if (( ${#ssh_hosts_array[@]} > 0 )); then
      zstyle ':completion:*:(ssh|scp|sftp|rsync):*' hosts "${ssh_hosts_array[@]}"
      zstyle ':completion:*:(ssh|scp|sftp|rsync):*:hosts' list-colors '=*=01;32'
      zstyle ':completion:*:hosts' hosts "${ssh_hosts_array[@]}"
    fi
  fi
}

_git_prompt_info() {
  emulate -L zsh
  setopt LOCAL_OPTIONS NO_NOMATCH
  
  # Quick check if we're in a git repo
  local git_dir
  git_dir=$(command git rev-parse --git-dir 2>/dev/null) || return
  
  # Get branch/status info efficiently
  local branch_name git_status=""
  local git_color="green"
  
  # Try to get branch name
  branch_name=$(command git symbolic-ref --short HEAD 2>/dev/null)
  
  if [[ -z $branch_name ]]; then
    # Detached HEAD - try tag first, then short SHA
    branch_name=$(command git describe --tags --exact-match HEAD 2>/dev/null) || \
    branch_name=$(command git rev-parse --short HEAD 2>/dev/null) || \
    branch_name="detached"
  fi
  
  # Check working directory status
  local has_changes=0 has_untracked=0
  
  # Use git status porcelain for efficiency
  local status_output
  status_output=$(command git status --porcelain=v1 2>/dev/null)
  
  if [[ -n $status_output ]]; then
    # Parse status
    local line
    while IFS= read -r line; do
      if [[ $line == "??"* ]]; then
        has_untracked=1
      else
        has_changes=1
      fi
      # Early exit if we found both
      ((has_changes && has_untracked)) && break
    done <<< "$status_output"
  fi
  
  # Set status indicators and color
  if ((has_changes)); then
    git_status="*"
    git_color="yellow"
  fi
  
  if ((has_untracked)); then
    git_status="${git_status}+"
    git_color="red"
  fi
  
  # Check for stash (works with worktrees too)
  if command git rev-parse --verify --quiet refs/stash &>/dev/null; then
    git_status="${git_status}$"
  fi
  
  printf "%%F{%s} (%s%s)%%f" "$git_color" "$branch_name" "$git_status"
}

_setup_prompt() {
  emulate -L zsh
  setopt PROMPT_SUBST

  # Cache git availability check
  if [[ -z $_zsh_git_available ]]; then
    if (( ${+commands[git]} )); then
      typeset -g _zsh_git_available=1
    else
      typeset -g _zsh_git_available=0
    fi
  fi

  # Check color support
  local use_color=1
  [[ -n $NO_COLOR || $TERM == dumb ]] && use_color=0

  if ((use_color)); then
    if ((_zsh_git_available)); then
      PS1='%F{cyan}%n@%m%f:%F{blue}%~%f$(_git_prompt_info)%F{green}❯%f '
    else
      PS1='%F{cyan}%n@%m%f:%F{blue}%~%f%F{green}❯%f '
    fi
    RPS1='%(?..%F{red}✗%f )%F{244}%T%f'
    PS2='%F{green}❯%f '
  else
    # No color prompts
    PS1='%n@%m:%~%(?..!)> '
    RPS1='%T'
    PS2='> '
  fi

  # Set terminal title if supported
  case $TERM in
    xterm*|rxvt*|screen*|tmux*)
      precmd() { print -Pn "\e]0;%n@%m:%~\a" }
      ;;
  esac
}
