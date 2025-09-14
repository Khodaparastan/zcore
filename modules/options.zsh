_configure_setopts() {
    # Helper: safe logging if available
    _zlog_debug() { whence -w z::log::debug >/dev/null 2>&1 && z::log::debug "$@"; }
    _zlog_warn()  { whence -w z::log::warn  >/dev/null 2>&1 && z::log::warn  "$@"; }

    # Only run interruption check if present
    if whence -w z::runtime::check_interrupted >/dev/null 2>&1; then
        z::runtime::check_interrupted || return $?
    fi

    # History sizes as integers (global)
    typeset -gi HISTSIZE=$(( ${HISTSIZE:-50000} ))
    typeset -gi SAVEHIST=$(( ${SAVEHIST:-50000} ))
    (( SAVEHIST > HISTSIZE )) && SAVEHIST=$HISTSIZE

    # Determine history path (prefer XDG), fallback on failure
    local hist_file_path
    hist_file_path="${HISTFILE:-${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history}"

    # Ensure directory exists with secure perms; avoid clobbering if already strict
    local hist_dir_to_check="${hist_file_path:h}"
    if [[ -n $hist_dir_to_check && ! -d $hist_dir_to_check ]]; then
        if mkdir -p -m 700 "$hist_dir_to_check" 2>/dev/null; then
            _zlog_debug "Created history directory: $hist_dir_to_check"
        else
            _zlog_warn "Failed to create history directory: $hist_dir_to_check; falling back to \$HOME"
            hist_file_path="$HOME/.zsh_history"
            hist_dir_to_check="$HOME"
        fi
    fi

    # Tighten perms only if too permissive and owned by user
    if [[ -n $hist_dir_to_check && -d $hist_dir_to_check && -O $hist_dir_to_check ]]; then
        local dmode
        dmode=$(stat -c '%a' "$hist_dir_to_check" 2>/dev/null || stat -f '%Lp' "$hist_dir_to_check" 2>/dev/null)
        if [[ -n $dmode ]]; then
            if ((( (8#$dmode) & 077 ))); then
                chmod 700 "$hist_dir_to_check" 2>/dev/null \
                    && _zlog_debug "Set permissions on history directory: $hist_dir_to_check" \
                    || _zlog_warn "Failed to set permissions on history directory: $hist_dir_to_check"
            fi
        fi
    fi

    # Ensure history file exists and is private (0600)
    if [[ -n $hist_file_path && ! -e $hist_file_path ]]; then
        if : >> "$hist_file_path" 2>/dev/null; then
            _zlog_debug "Created history file: $hist_file_path"
        else
            _zlog_warn "Failed to create history file: $hist_file_path; falling back to \$HOME/.zsh_history"
            hist_file_path="$HOME/.zsh_history"
            [[ -e $hist_file_path ]] || : >> "$hist_file_path" 2>/dev/null
        fi
    fi
    if [[ -n $hist_file_path && -e $hist_file_path && -O $hist_file_path ]]; then
        local fmode
        fmode=$(stat -c '%a' "$hist_file_path" 2>/dev/null || stat -f '%Lp' "$hist_file_path" 2>/dev/null)
        if [[ -n $fmode ]]; then
            if ((( (8#$fmode) & 077 ))); then
                chmod 600 "$hist_file_path" 2>/dev/null \
                    && _zlog_debug "Set permissions on history file: $hist_file_path" \
                    || _zlog_warn "Failed to set permissions on history file: $hist_file_path"
            fi
        fi
    fi

    # Export HISTFILE globally
    typeset -g HISTFILE="$hist_file_path"

    # History behavior
    setopt EXTENDED_HISTORY
    setopt APPEND_HISTORY
    setopt INC_APPEND_HISTORY_TIME

    # Prefer deterministic per-session history; enable sharing only if requested
    if [[ "${_zcore_config[history_share]:-false}" == "true" ]]; then
        setopt SHARE_HISTORY
    else
        unsetopt SHARE_HISTORY
    fi

    # Dedupe/curation
    setopt HIST_IGNORE_SPACE
    setopt HIST_EXPIRE_DUPS_FIRST
    setopt HIST_IGNORE_DUPS
    setopt HIST_FIND_NO_DUPS
    setopt HIST_REDUCE_BLANKS
    if [[ ! -o SHARE_HISTORY ]]; then
        setopt HIST_SAVE_NO_DUPS
    else
        unsetopt HIST_SAVE_NO_DUPS
    fi
    unsetopt HIST_IGNORE_ALL_DUPS

    # Navigation/Completion/Interaction (interactive only)
    if [[ -o interactive ]]; then
        setopt AUTO_CD
        setopt AUTO_PUSHD
        setopt PUSHD_IGNORE_DUPS
        setopt AUTO_MENU
        setopt ALWAYS_TO_END
        setopt INTERACTIVE_COMMENTS
        setopt NOTIFY
        setopt LONG_LIST_JOBS
    fi

    # Command hashing (performance-aware)
    if [[ "${_zcore_config[performance_mode]:-}" == "true" ]]; then
        unsetopt HASH_LIST_ALL
    else
        if [[ "${_zcore_config[hash_list_all]:-false}" == "true" ]]; then
            setopt HASH_LIST_ALL
        else
            unsetopt HASH_LIST_ALL
        fi
    fi

    # Safety/UX
    setopt NO_CLOBBER
    setopt NO_BEEP
    case "${TERM:-}" in
        xterm*|screen*|tmux*|vt100*|alacritty*|wezterm*|kitty*)
            setopt NO_FLOW_CONTROL
            ;;
        *)
            ;;
    esac

    _zlog_debug "Shell options configured successfully"
    _zlog_debug "History: HISTSIZE=$HISTSIZE, SAVEHIST=$SAVEHIST, HISTFILE=$HISTFILE"
    return 0
}
