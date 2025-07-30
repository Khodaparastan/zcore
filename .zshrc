#!/usr/bin/env zsh
if [[ -n "${_zsh_config_loaded:-}" ]]; then
    return 0
fi
typeset -gr _zsh_config_loaded=1

umask 022

local major_version="${ZSH_VERSION%%.*}"
if [[ ! "${major_version}" =~ ^[0-9]+$ ]] || (( major_version < 5 )); then
    print -u2 "error: zsh 5.0+ required (current: ${ZSH_VERSION})"
    print -u2 "please upgrade zsh or use bash compatibility mode."
    return 1
fi

typeset -gA _zsh_config
_zsh_config=(
    [log_error]=0
    [log_warn]=1
    [log_info]=2
    [log_debug]=3
    [exit_general_error]=1
    [exit_interrupted]=130
    [progress_update_interval]=10
    [timeout_default]=30
    [cache_max_size]=100
    [cache_lru_size]=20
    [missing_config_threshold]=50  # percent for warning on missing configs
    [log_max_depth]=100  # recursion limit for _log
)

typeset -gi _zsh_config_verbose
typeset -gi _zsh_config_interrupted=0

if [[ "${zsh_config_verbose:-}" =~ ^[0-9]+$ ]]; then
    _zsh_config_verbose=${zsh_config_verbose}
else
    _zsh_config_verbose=${_zsh_config[log_info]}
fi

typeset -gA _function_cache
typeset -ga _cache_order
typeset -gi _cache_size=0

typeset -gA _zsh_colors
if [[ -t 2 && -z ${no_color:-} ]] && command -v tput >/dev/null 2>&1; then
    if tput setaf 1 >/dev/null 2>&1; then
        _zsh_colors=(
            [red]="$(tput setaf 1)"
            [green]="$(tput setaf 2)"
            [blue]="$(tput setaf 4)"
            [yellow]="$(tput setaf 3)"
            [reset]="$(tput sgr0)"
        )
    else
        _zsh_colors=([red]="" [green]="" [blue]="" [yellow]="" [reset]="")
    fi
else
    _zsh_colors=([red]="" [green]="" [blue]="" [yellow]="" [reset]="")
fi

typeset -gi _log_depth=0

_log() {
    (( _log_depth++ ))
    if (( _log_depth > _zsh_config[log_max_depth] )); then
        print -u2 "recursion limit exceeded in _log; aborting to prevent stack overflow"
        (( _log_depth-- ))
        return 1
    fi

    local -i level
    if ! level="$1" 2>/dev/null || (( level < 0 )); then
        (( _log_depth-- ))
        print -u2 "[error] invalid log level: ${1}"
        return 1
    fi
    shift

    (( level > _zsh_config_verbose )) && { (( _log_depth-- )); return 0; }

    local prefix=""
    case $level in
        ${_zsh_config[log_error]}) prefix="${_zsh_colors[red]}[error]${_zsh_colors[reset]}" ;;
        ${_zsh_config[log_info]})  prefix="${_zsh_colors[blue]}[info]${_zsh_colors[reset]}" ;;
        ${_zsh_config[log_warn]})  prefix="${_zsh_colors[yellow]}[warn]${_zsh_colors[reset]}" ;;
        ${_zsh_config[log_debug]}) prefix="${_zsh_colors[green]}[debug]${_zsh_colors[reset]}" ;;
        *) prefix="[unknown]" ;;
    esac

    local message=""
    print -P -v message -- "%D{%Y-%m-%d %H:%M:%S} ${prefix} ${*}"  # Timestamp (consider TZ=America/New_York externally if needed)
    print -r -- "${message}" >&2

    (( _log_depth-- ))
    return 0
}

_handle_interrupt() {
    _zsh_config_interrupted=1
    _log ${_zsh_config[log_warn]} "interrupt received - will stop at next safe point"

    trap '_handle_interrupt' INT TERM
}

trap '_handle_interrupt' INT TERM

_check_interrupted() {
    if ((_zsh_config_interrupted)); then
        _log ${_zsh_config[log_info]} "operation cancelled by user"
        return ${_zsh_config[exit_interrupted]}
    fi
    return 0
}

_die() {
    local message=$1
    local -i exit_code=${2:-${_zsh_config[exit_general_error]}}
    _log ${_zsh_config[log_error]} "$message"

    if (( ${#${(M)zsh_eval_context:#*file}} > 0 )); then
        _log ${_zsh_config[log_debug]} "returning from die in sourced context"
        return $exit_code
    else
        exit $exit_code
    fi
}

_show_progress() {
    local current_param="$1"
    local total_param="$2"
    local label="${3:-items}" 

    local -i current
    local -i total
    if ! current="$current_param" 2>/dev/null || ! total="$total_param" 2>/dev/null; then
        _log ${_zsh_config[log_debug]} "invalid progress params: current=${current_param}, total=${total_param}"
        return 0
    fi

    if ((total <= 0 || current < 0 || current > total)); then
        return 0
    fi

    if ((_zsh_config_verbose >= _zsh_config[log_info])) && [[ -t 2 ]]; then
        if ((current == 1 || current == total || current % _zsh_config[progress_update_interval] == 0)); then
            local -i percent=$((current * 100 / total))
            local -i term_width=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}
            # Format numbers with grouping separator (,)
            local current_fmt="${current//(#b)([0-9])([0-9][0-9][0-9])/${match[1]},${match[2]}}"
            local total_fmt="${total//(#b)([0-9])([0-9][0-9][0-9])/${match[1]},${match[2]}}"
            if ((term_width > 50)); then
                printf '\r[%3d%%] processing %s %s of %s...' "$percent" "$label" "$current_fmt" "$total_fmt" >&2
            else
                printf '\r[%3d%%] %s %s/%s' "$percent" "$label" "$current_fmt" "$total_fmt" >&2
            fi
            ((current == total)) && printf '\r\e[K\n' >&2  # Clear line on completion
        fi
    fi
}

_function_exists() {
    local func="$1"

    if [[ -z "$func" ]]; then
        return 1
    fi

    if [[ -n "${_function_cache[$func]:-}" ]]; then
        _cache_order=(${_cache_order:#$func})
        _cache_order=("$func" ${_cache_order})
        return ${_function_cache[$func]}
    fi

    if ((_cache_size >= _zsh_config[cache_max_size])); then
        if (( ${#_cache_order[@]} > 0 )); then
            local old_func="${_cache_order[-1]}"
            unset "_function_cache[$old_func]"
            _cache_order=("${(@)_cache_order[1,-2]}")
            ((_cache_size--))
        fi
    fi

    local -i result=1
    if typeset -f "$func" >/dev/null 2>&1; then
        result=0
    fi

    _function_cache[$func]=$result
    _cache_order=("$func" "${(@)_cache_order}")
    ((_cache_size++))

    return $result
}

_safe_call() {
    local func="$1"
    shift

    if [[ -z "$func" ]]; then
        _log ${_zsh_config[log_error]} "empty function name provided"
        return 1
    fi

    if ! _function_exists "$func"; then
        case "$func" in
            _git_prompt_info|__zconvey_on_period_passed*|_*prompt*|_*git*)
                return 1
                ;;
            *)
                _log ${_zsh_config[log_warn]} "function $func not found"
                return 1
                ;;
        esac
    fi

    _check_interrupted || return $?

    local -i exit_code=0
    "$func" "$@" || exit_code=$?

    if ((exit_code != 0)); then
        _log ${_zsh_config[log_warn]} "function $func failed with exit code $exit_code"
    fi

    return $exit_code
}

_safe_alias() {
    local alias_name="$1"
    local alias_value="$2"

    if [[ -z "$alias_name" || -z "$alias_value" ]]; then
        _log ${_zsh_config[log_error]} "empty alias name or value provided"
        return 1
    fi
    if [[ "$alias_name" = *[[:space:]=]* ]]; then
        _log ${_zsh_config[log_error]} "invalid alias name: $alias_name (cannot contain spaces or =)"
        return 1
    fi

    local cmd
    setopt localoptions noglob
    cmd=$(whence -w "${alias_value%% *}" 2>/dev/null)

    if [[ -z "$cmd" || "$cmd" == *": none" ]]; then
        _log ${_zsh_config[log_warn]} "cannot extract valid command from alias value: $alias_value (setting alias anyway)"
    fi

    alias "$alias_name"="$alias_value"
    _log ${_zsh_config[log_debug]} "created alias: $alias_name='$alias_value'"
    return 0
}

_safe_eval() {
    local input="$1"
    local -i timeout=${2:-${_zsh_config[timeout_default]}}
    local force_current_shell="${3:-false}"

    if [[ -z "$input" ]]; then
        _log ${_zsh_config[log_error]} "empty input provided to _safe_eval"
        return 1
    fi

    local eval_code=""
    local is_shell_init=false

    if [[ "$input" =~ ^(starship|mise|direnv|zoxide|atuin|mcfly|fzf|oh-my-posh).*init ]]; then
        is_shell_init=true
        _log ${_zsh_config[log_debug]} "detected shell initialization command: $input"

        local -i cmd_exit_code=0
        local stderr_output=""
        eval_code=$(zsh -c "$input" 2> >(stderr_output=$(cat); typeset -p stderr_output) ) || cmd_exit_code=$?

        if [[ -n "$stderr_output" ]]; then
            _log ${_zsh_config[log_warn]} "initialization command produced stderr: ${stderr_output:0:100}..."
        fi

        if ((cmd_exit_code != 0)); then
            _log ${_zsh_config[log_error]} "failed to execute initialization command: $input"
            return $cmd_exit_code
        fi

        if [[ -z "$eval_code" ]]; then
            _log ${_zsh_config[log_warn]} "initialization command returned empty output: $input"
            return 1
        fi

        _log ${_zsh_config[log_debug]} "generated ${#eval_code} characters of initialization code"

    else
        if [[ "$input" =~ add-zsh-hook ]] ||
           [[ "$input" =~ precmd ]] ||
           [[ "$input" =~ preexec ]] ||
           [[ "$input" =~ prompt ]] ||
           [[ "$input" =~ ps1 ]] ||
           [[ "$input" =~ export[[:space:]]+.*shell ]] ||
           [[ "$input" =~ bindkey ]] ||
           [[ "$input" =~ compdef ]] ||
           [[ "$input" =~ autoload ]] ||
           [[ "$input" =~ function[[:space:]]+.*\( ]] ||
           [[ "$input" =~ .*\(\)[[:space:]]+\{ ]]; then
            is_shell_init=true
            eval_code="$input"
            _log ${_zsh_config[log_debug]} "detected shell initialization code (${#eval_code} chars)"
        else
            eval_code="$input"
        fi

        if (( _zsh_config_verbose >= _zsh_config[log_debug] )) && [[ "$is_shell_init" != "true" ]]; then
            _log ${_zsh_config[log_debug]} "no init patterns matched for input: ${input:0:50}..."
        fi
    fi

    local -ra dangerous_patterns=(
        'rm[[:space:]]+-[^[:space:]]*[rf]'
        'sudo[[:space:]]+rm'
        'dd[[:space:]]+[^[:space:]]*[io]f='
        '>[[:space:]]*/dev/(sd[a-z]+|hd[a-z]+|nvme[0-9]+n[0-9]+)'
        'mkfs\.[[:alnum:]]+'
        'chmod[[:space:]]+777[[:space:]]'
        ':[[:space:]]*\(\)[[:space:]]*{.*:.*&.*}'
        'curl[^|]*\|[^|]*sh'
        'wget[^|]*\|[^|]*sh'
        '\$\([^)]*rm[[:space:]]+(-[^[:space:]]*)?[^)]*\)'
        '`[^`]*rm[[:space:]]+[^`]*`'
        'echo[[:space:]]+>[[:space:]]*/etc/'
        'eval[[:space:]]+.*rm'  
        'sh[[:space:]]+-c[[:space:]]+.*rm' 
        'base64[[:space:]]+-d[[:space:]]+\|[[:space:]]*sh' 
        'exec[[:space:]]+rm' 
        'shred[[:space:]]+'  
        'wipe[[:space:]]+'   
        'find[[:space:]]+.*-delete'  
        'poweroff|reboot|halt'  
        'export[[:space:]]+(PATH|LD_PRELOAD)=.*'  
    )

    local pattern
    for pattern in "${dangerous_patterns[@]}"; do
        if [[ "$eval_code" =~ $pattern ]]; then
            _log ${_zsh_config[log_error]} "potentially dangerous eval code detected: matches $pattern"
            return 1
        fi
    done

    _check_interrupted || return $?

    local run_in_current_shell=false
    if [[ "$force_current_shell" == "true" ]] || [[ "$is_shell_init" == "true" ]]; then
        run_in_current_shell=true
    fi

    local -i exit_code=0

    if [[ "$run_in_current_shell" == "true" ]]; then
        _log ${_zsh_config[log_debug]} "running eval in current shell context"
        eval "$eval_code" || exit_code=$?
    elif (( $+commands[timeout] )); then
        _log ${_zsh_config[log_debug]} "running eval in isolated shell with timeout"
        timeout "$timeout" zsh -c "$eval_code" || exit_code=$?
        if ((exit_code == 124)); then
            _log ${_zsh_config[log_warn]} "eval timed out after ${timeout}s"
            return 124  # return distinctly for timeout
        fi
    else
        _log ${_zsh_config[log_warn]} "no timeout available; skipping non-init eval for security"
        return 1  # skip instead of running in current shell
    fi

    if ((exit_code != 0 && exit_code != 124)); then
        _log ${_zsh_config[log_warn]} "eval failed with exit code $exit_code"
    elif ((exit_code == 0)) && [[ "$is_shell_init" == "true" ]]; then
        local tool_name="shell"
        if [[ "$input" =~ ^([a-zA-Z0-9_-]+) ]]; then
            tool_name="${match[1]}"
        fi
        _log ${_zsh_config[log_debug]} "successfully initialized: $tool_name"
    fi

    return $exit_code
}

_safe_unset() {
    local target="$1"
    local unset_type="${2:-auto}"

    if [[ -z "$target" ]]; then
        _log ${_zsh_config[log_error]} "Empty target provided to unset"
        return 1
    fi

    local type_info=$(typeset -p "$target" 2>/dev/null)

    local -i found=0
    local -i exit_code=0

    case "$unset_type" in
        var)
            if [[ -n "$type_info" ]]; then
                if [[ "$type_info" == *readonly* ]]; then
                    _log ${_zsh_config[log_debug]} "Cannot unset readonly variable: $target"
                    return 1
                fi
                unset -v "$target" 2>/dev/null || exit_code=$?
                found=1
            fi
            ;;
        func)
            if _function_exists "$target"; then
                unset -f "$target" 2>/dev/null || exit_code=$?
                if [[ -n "${_function_cache[$target]:-}" ]]; then
                    unset "_function_cache[$target]"
                    _cache_order=(${_cache_order:#$target})
                    ((_cache_size--))
                fi
                found=1
            fi
            ;;
        auto)
            if [[ -n "$type_info" ]]; then
                if [[ "$type_info" == *readonly* ]]; then
                    _log ${_zsh_config[log_debug]} "Skipping readonly variable: $target"
                else
                    unset -v "$target" 2>/dev/null || exit_code=$?
                    found=1
                fi
            fi
            # Check for function independently (namespaces are separate)
            if _function_exists "$target"; then
                unset -f "$target" 2>/dev/null || exit_code=$?
                if [[ -n "${_function_cache[$target]:-}" ]]; then
                    unset "_function_cache[$target]"
                    _cache_order=(${_cache_order:#$target})
                    ((_cache_size--))
                fi
                found=1
            fi
            ;;
        *)
            _log ${_zsh_config[log_error]} "Invalid unset type: $unset_type (use auto, var, or func)"
            return 1
            ;;
    esac

    if ((found == 0)); then
        _log ${_zsh_config[log_debug]} "Target not found for unset: $target"
        return 1
    fi

    if ((exit_code != 0)); then
        _log ${_zsh_config[log_warn]} "Failed to unset $target with exit code $exit_code"
    else
        _log ${_zsh_config[log_debug]} "Successfully unset: $target"
    fi

    return $exit_code
}

_resolve_path() {
    local path="$1"

    if [[ -z "$path" ]]; then
        return 1
    fi

    path="${path/#\\\\~/$HOME}"
    path="${path/#\~/$HOME}"

    local resolved="${path:A}"
    if [[ "$resolved" != "$path" ]]; then
        path="$resolved"
        _log ${_zsh_config[log_debug]} "Resolved path: $path"
    elif [[ -L "$path" ]]; then
        _log ${_zsh_config[log_debug]} "Failed to resolve symlink: $path"
        return 1
    fi

    printf '%s' "$path"
}

_safe_source() {
    local file="$1"
    shift

    if [[ -z "$file" ]]; then
        _log ${_zsh_config[log_error]} "Empty file path provided to source"
        return 1
    fi

    file=$(_resolve_path "$file") || return 1

    if [[ ! -e "$file" ]]; then
        _log ${_zsh_config[log_warn]} "File not found: $file"
        return 1
    fi

    if [[ ! -r "$file" ]]; then
        _log ${_zsh_config[log_warn]} "File not readable: $file"
        return 1
    fi

    if [[ ! -f "$file" ]]; then
        _log ${_zsh_config[log_warn]} "Not a regular file: $file"
        return 1
    fi

    _check_interrupted || return $?

    local -i exit_code=0
    source "$file" "$@" || exit_code=$?

    if ((exit_code != 0)); then
        _log ${_zsh_config[log_warn]} "Failed to source $file with exit code $exit_code"
    else
        _log ${_zsh_config[log_debug]} "Successfully sourced: $file"
    fi

    return $exit_code
}

_add_to_path() {
    local dir="$1"
    local position="${2:-append}"

    if [[ -z "$dir" ]]; then
        _log ${_zsh_config[log_error]} "Empty directory provided"
        return 1
    fi

    dir=$(_resolve_path "$dir") || return 1

    if [[ ! -d "$dir" ]]; then
        _log ${_zsh_config[log_debug]} "Directory does not exist: $dir"
        return 1
    fi

    if [[ ":${PATH}:" == *":${dir}:"* ]]; then
        _log ${_zsh_config[log_debug]} "Directory already in PATH: $dir"
        return 0
    fi

    case "$position" in
        prepend)
            export PATH="$dir:$PATH"
            ;;
        append)
            export PATH="$PATH:$dir"
            ;;
        *)
            _log ${_zsh_config[log_error]} "Invalid position: $position (use prepend or append)"
            return 1
            ;;
    esac

    _log ${_zsh_config[log_debug]} "Added to PATH ($position): $dir"
    return 0
}
trap '_handle_interrupt' INT TERM
_detect_platform() {
    if [[ -n "${_PLATFORM_DETECTED:-}" ]]; then
        return 0
    fi

    typeset -gxri IS_MACOS=$([[ $OSTYPE == darwin* ]] && echo 1 || echo 0)
    typeset -gxri IS_LINUX=$([[ $OSTYPE == linux* ]] && echo 1 || echo 0)
    typeset -gxri IS_BSD=$([[ $OSTYPE == bsd* || $OSTYPE == dragonfly* || $OSTYPE == netbsd* || $OSTYPE == openbsd* ]] && echo 1 || echo 0)
    typeset -gxri IS_CYGWIN=$([[ $OSTYPE == cygwin* || $OSTYPE == msys* || $OSTYPE == mingw* ]] && echo 1 || echo 0)

    typeset -gxri IS_WSL=0
    if ((IS_LINUX)); then
        if [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSLENV:-}" || -f "/proc/sys/fs/binfmt_misc/WSLInterop" || "$(</proc/version 2>/dev/null)" == *microsoft* ]]; then
            typeset -gxri IS_WSL=1
        fi
    fi

    typeset -gxri IS_TERMUX=$([[ $IS_LINUX == 1 && -d "/data/data/com.termux" ]] && echo 1 || echo 0)
    typeset -gxri IS_UNKNOWN=$(( IS_MACOS || IS_LINUX || IS_BSD || IS_CYGWIN ? 0 : 1 ))

    typeset -gr _PLATFORM_DETECTED=1

    if ((IS_UNKNOWN)); then
        _log ${_zsh_config[log_warn]} "Unknown platform: $OSTYPE"
    fi

    _log ${_zsh_config[log_debug]} "Platform: macOS=$IS_MACOS Linux=$IS_LINUX BSD=$IS_BSD WSL=$IS_WSL Cygwin=$IS_CYGWIN Termux=$IS_TERMUX"
}

_setup_gcloud_sdk() {
    _detect_platform 

    local gcloud_base="${GCLOUD_SDK_PATH:-}"
    local gcloud_python="${GCLOUD_PYTHON_PATH:-}"

    if [[ -z "$gcloud_base" && $+commands[gcloud] ]]; then
        gcloud_base=$(dirname "$(dirname "$(command -v gcloud)")")
    elif [[ -z "$gcloud_base" ]]; then
        local -a possible_bases=("$HOME/.local/google-cloud-sdk" "$HOME/google-cloud-sdk" "/usr/lib/google-cloud-sdk" "/usr/local/google-cloud-sdk" "/opt/google-cloud-sdk")
        for base in "${possible_bases[@]}"; do
            if [[ -d "$base" ]]; then
                gcloud_base="$base"
                break
            fi
        done
    fi

    if [[ -z "$gcloud_python" ]]; then
        if ((IS_MACOS)); then
            gcloud_python="$HOME/.local/google-cloud-sdk/gcp-venv/bin/python"
            if [[ ! -x "$gcloud_python" ]]; then
                gcloud_python="$(command -v python3 2>/dev/null || command -v python 2>/dev/null)"
            fi
        else
            gcloud_python="$(command -v python3 2>/dev/null || command -v python 2>/dev/null)"
        fi
    fi

    if [[ ! -d "$gcloud_base" ]]; then
        _log ${_zsh_config[log_debug]} "Google Cloud SDK not found"
        return 1
    fi

    local -a gcloud_files=(
        "$gcloud_base/path.zsh.inc"
        "$gcloud_base/completion.zsh.inc"
    )

    local file
    local -i success=0
    for file in "${gcloud_files[@]}"; do
        if _safe_source "$file"; then
            ((success++))
        else
            _log ${_zsh_config[log_warn]} "Failed to source gcloud file: $file"
        fi
    done

    if [[ -n "$gcloud_python" && -x "$gcloud_python" ]]; then
        export CLOUDSDK_PYTHON="$gcloud_python"
        _log ${_zsh_config[log_debug]} "Set CLOUDSDK_PYTHON to: $gcloud_python"
    elif [[ -n "$gcloud_python" ]]; then
        _log ${_zsh_config[log_warn]} "Specified gcloud_python not executable: $gcloud_python"
    fi

    if ((success > 0)); then
        _log ${_zsh_config[log_info]} "Google Cloud SDK initialized ($success files loaded)"
        return 0
    else
        return 1
    fi
}

_load_config_files() {
    local config_base="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"

    local -a config_files=(
        "modules/environment.zsh"
        "modules/path.zsh"
        "modules/options.zsh"
        "modules/aliases.zsh"
        "modules/load_zi.zsh"
        "modules/completions.zsh"
        "modules/keybindings.zsh"
        "modules/utils.zsh"
        "modules/python.sh"
        "modules/funcs.zsh"
    )

    local config_file
    local -i missing_files=0
    local -i loaded_files=0
    local -i total_files=${#config_files[@]}

    local -i missing_threshold=${_zsh_config[missing_config_threshold]:-50}

    local -i current=0
    for config_file in "${config_files[@]}"; do
        ((current++))
        _check_interrupted || return $?

        local full_path=$(_resolve_path "$config_base/$config_file") || continue

        _show_progress $current $total_files "config"

        if [[ -f "$full_path" ]]; then
            if _safe_source "$full_path"; then
                ((loaded_files++))
                _log ${_zsh_config[log_debug]} "Loaded config file: $full_path"
            else
                _log ${_zsh_config[log_error]} "Failed to source: $full_path"
                return 1
            fi
        else
            _log ${_zsh_config[log_warn]} "Config file not found: $full_path"
            ((missing_files++))
        fi
    done

    if ((missing_files > (total_files * missing_threshold / 100) )); then
        _log ${_zsh_config[log_warn]} "Many config files missing ($missing_files/$total_files). Check your zsh configuration."
    fi

    _log ${_zsh_config[log_info]} "Loaded $loaded_files/$total_files config files"
    return 0
}

setup_platform_aliases() {
    _detect_platform  

    if _safe_alias y 'yazi'; then
        _log ${_zsh_config[log_debug]} "Set alias: y='yazi'"
    fi
    if _safe_alias dev 'cd ~/dev'; then
        _log ${_zsh_config[log_debug]} "Set alias: dev='cd ~/dev'"
    fi
    if _safe_alias zss 'cd ~/.ssh'; then
        _log ${_zsh_config[log_debug]} "Set alias: zss='cd ~/.ssh'"
    fi
    if _safe_alias zdd 'cd ${XDG_CONFIG_HOME:-$HOME/.config}'; then
        _log ${_zsh_config[log_debug]} "Set alias: zdd='cd ${XDG_CONFIG_HOME:-$HOME/.config}'"
    fi
    # if _safe_alias z 'j'; then
    #     _log ${_zsh_config[log_debug]} "Set alias: z='j'"
    # fi
    alias z='j'
    alias skr='ssh-keygen -R '
    alias sci='ssh-copy-id -i '
    alias ssi='ssh -i '
    if ((IS_MACOS)); then
        (( $+commands[yabai] )) && {
            if _safe_alias ybr 'yabai --restart-service'; then
                _log ${_zsh_config[log_debug]} "Set alias: ybr='yabai --restart-service'"
            fi
        }

        local surge_cli='/Applications/Surge.app/Contents/Resources/surge-cli'
        [[ -x "$surge_cli" ]] && {
            if _safe_alias surge "$surge_cli"; then
                _log ${_zsh_config[log_debug]} "Set alias: surge='$surge_cli'"
            fi
        }

        if _safe_alias o 'open'; then
            _log ${_zsh_config[log_debug]} "Set alias: o='open'"
        fi
        if _safe_alias clip 'pbcopy'; then
            _log ${_zsh_config[log_debug]} "Set alias: clip='pbcopy'"
        fi
    elif ((IS_LINUX)); then
        if _safe_alias o 'xdg-open'; then
            _log ${_zsh_config[log_debug]} "Set alias: o='xdg-open'"
        fi

        if (( $+commands[xclip] )); then
            if _safe_alias clip 'xclip -selection clipboard'; then
                _log ${_zsh_config[log_debug]} "Set alias: clip='xclip -selection clipboard'"
            fi
        elif (( $+commands[xsel] )); then
            if _safe_alias clip 'xsel --clipboard --input'; then
                _log ${_zsh_config[log_debug]} "Set alias: clip='xsel --clipboard --input'"
            fi
        else
            _log ${_zsh_config[log_warn]} "No clipboard tool found (xclip or xsel) for Linux"
        fi
    elif ((IS_BSD)); then
        if _safe_alias o 'xdg-open'; then
            _log ${_zsh_config[log_debug]} "Set alias: o='xdg-open'"
        fi
        if _safe_alias clip 'xclip -selection clipboard'; then
            _log ${_zsh_config[log_debug]} "Set alias: clip='xclip -selection clipboard'"
        else
            _log ${_zsh_config[log_warn]} "No clipboard tool found (xclip) for BSD"
        fi
    elif ((IS_CYGWIN)); then
        if _safe_alias o 'cygstart'; then
            _log ${_zsh_config[log_debug]} "Set alias: o='cygstart'"
        fi
        if _safe_alias clip 'cat > /dev/clipboard'; then
            _log ${_zsh_config[log_debug]} "Set alias: clip='cat > /dev/clipboard'"
        fi
    fi
}

_setup_external_tools() {
    if (( $+commands[mise] )); then
        if _safe_eval "$(mise activate zsh)" 10 true; then
            _log ${_zsh_config[log_debug]} "mise activated"
        else
            _log ${_zsh_config[log_warn]} "Failed to activate mise"
        fi
    fi

    if (( $+commands[direnv] )); then
        if _safe_eval "$(direnv hook zsh)" 10 true; then
            _log ${_zsh_config[log_debug]} "direnv hook installed"
        else
            _log ${_zsh_config[log_warn]} "Failed to install direnv hook"
        fi
    fi

    if ((IS_MACOS)); then
        local autojump_script='/opt/homebrew/etc/profile.d/autojump.sh'
        if _safe_source "$autojump_script"; then
            _log ${_zsh_config[log_debug]} "autojump loaded"
        else
            _log ${_zsh_config[log_warn]} "Failed to load autojump"
        fi

        local homebrew_curl='/opt/homebrew/opt/curl/bin'
        if _add_to_path "$homebrew_curl" prepend; then
            _log ${_zsh_config[log_debug]} "Homebrew curl added to PATH"
        fi
    fi

    local daytona_completion="$HOME/.daytona.completion_script.zsh"
    _safe_source "$daytona_completion"
}

_create_stub_functions() {
    if ! _function_exists _git_prompt_info; then
        _git_prompt_info() { return 0; }
    fi

    local -a zconvey_functions=(
        __zconvey_on_period_passed26
        __zconvey_on_period_passed30
        __zconvey_on_period_passed
    )

    local func
    for func in "${zconvey_functions[@]}"; do
        if ! _function_exists "$func"; then
            typeset -gf "$func" "() { return 0; }"
        fi
    done
}

_main() {
    zmodload zsh/datetime
    local start_time=$EPOCHREALTIME

    _detect_platform

    _create_stub_functions

    if ! _load_config_files; then
        if ((_zsh_config_interrupted)); then
            _log ${_zsh_config[log_info]} "Configuration loading interrupted"
            return ${_zsh_config[exit_interrupted]}
        fi
        _log ${_zsh_config[log_error]} "Critical error loading configuration files"
        return 1
    fi

    local -a init_functions=(
        _initialize_environment
        _build_path
        _setup_environment
        _configure_shell
        _setup_ls
        _setup_tree_fallback
        _setup_additional_utilities
        _setup_smart_cd
        _define_aliases
    )

    local func
    local -i total_functions=${#init_functions[@]}
    local -i current_function=0
    for func in "${init_functions[@]}"; do
        if ((_zsh_config_interrupted)); then
            _log ${_zsh_config[log_info]} "Initialization interrupted at $func"
            return ${_zsh_config[exit_interrupted]}
        fi

        ((current_function++))
        _show_progress $current_function $total_functions "function"

        if _function_exists "$func"; then
            if ! _safe_call "$func"; then
                if [[ "$func" == "_initialize_environment" || "$func" == "_build_path" || "$func" == "_setup_environment" ]]; then
                    _log ${_zsh_config[log_error]} "Critical error in $func"
                    return 1
                else
                    _log ${_zsh_config[log_warn]} "Non-critical function failed: $func"
                fi
            fi
        else
            _log ${_zsh_config[log_debug]} "Module function not found: $func"
        fi
    done

    setup_platform_aliases

    if _function_exists _install_zi && _safe_call _install_zi; then
        if _function_exists _load_plugins; then
            _safe_call _load_plugins
        fi
    else
        _log ${_zsh_config[log_warn]} "ZI plugin manager not available. Some features might be missing."
    fi

    _function_exists _setup_completions && _safe_call _setup_completions
    _function_exists _setup_keybindings && _safe_call _setup_keybindings
    _function_exists _setup_prompt && _safe_call _setup_prompt

    _setup_external_tools

    if (( $+commands[gcloud] )); then
        _setup_gcloud_sdk
    fi

    if (( $+commands[starship] )); then
        if _safe_eval "starship init zsh" 10 true; then
            _log ${_zsh_config[log_debug]} "Starship prompt initialized"
        else
            _log ${_zsh_config[log_warn]} "Failed to initialize Starship prompt"
        fi
    fi

    if ((_zsh_config_interrupted)); then
        _log ${_zsh_config[log_info]} "Initialization completed but was interrupted"
        return ${_zsh_config[exit_interrupted]}
    fi

    local end_time=$EPOCHREALTIME
    local init_duration=$((end_time - start_time))
    _log ${_zsh_config[log_info]} "Zsh initialized in $(printf "%.4f" $init_duration)s"
}

_cleanup_functions() {
    local -aU cleanup_functions=(${(ok)functions[(I)_*]})

    local -a module_functions=(
        _initialize_environment _setup_xdg _create_xdg_dirs
        _setup_package_managers _detect_homebrew _build_path
        _configure_shell _setup_environment _setup_editor_environment
        _setup_development_environment _setup_xdg_compliance
        _setup_security_environment _setup_performance_environment
        _setup_terminal_environment _setup_cloud_environment
        _safe_exec _check_network _resolve_path _create_stub_functions
    )

    cleanup_functions+=(${module_functions[@]})

    local -a preserve_functions=(
        _log _die _handle_interrupt _check_interrupted
        _function_exists _safe_call _safe_alias _safe_eval
        _safe_unset _safe_source _add_to_path _cleanup_functions _cleanup_variables
        _resolve_path _git_prompt_info __zconvey_on_period_passed26
        __zconvey_on_period_passed30 __zconvey_on_period_passed
    )
    cleanup_functions=(${cleanup_functions:|preserve_functions})

    local func
    for func in "${cleanup_functions[@]}"; do
        if _function_exists "$func"; then
            _safe_unset "$func" func
        fi
    done
}

_cleanup_variables() {
    local -a preserve_vars=(
        _zsh_config_loaded IS_MACOS IS_LINUX IS_BSD
        IS_WSL IS_CYGWIN IS_TERMUX IS_UNKNOWN _PLATFORM_DETECTED
    )

    local -a cleanup_vars=(
        _zsh_colors _zsh_config_verbose
        _zsh_config_interrupted _ZSH_TREE_FALLBACK_DEFINED
        _function_cache _cache_order _cache_size
        _log_depth _log_max_depth _cached_term_width
    )

    local var
    for var in "${cleanup_vars[@]}"; do
        local type_info=$(typeset -p "$var" 2>/dev/null)
        if [[ -n "$type_info" ]]; then
            _safe_unset "$var" var
        fi
    done

    unset -v _zsh_config  
}

_main
{
    _cleanup_variables
    _safe_unset _cleanup_variables func
    _cleanup_functions
    _safe_unset _cleanup_functions func
} &>/dev/null  # Silence both stdout and stderr for cleanup

trap - INT TERM

return 0

