#!/usr/bin/env zsh
#
# Description:
# A comprehensive, production-ready utility library for Zsh. It provides a
# robust framework for logging, safe execution, command handling, filesystem
# operations, state management, and UI feedback in complex shell environments.
#
# Last Modified: 2025-08-01

# --- Table of Contents ---
# 1. Core Framework (Config, Logging, Interrupts, Fatal Errors)
# 2. Command & Alias Handling
# 3. Dynamic & Safe Execution
# 4. Filesystem & Sourcing
# 5. Function Introspection & Caching
# 6. State Management
# 7. User Interface (UI)
# 8. Initialization

# ==============================================================================
# 1. CORE FRAMEWORK
# ==============================================================================

typeset -gA _zsh_config
_zsh_config[log_error]=0
_zsh_config[log_warn]=1
_zsh_config[log_info]=2
_zsh_config[log_debug]=3
_zsh_config[exit_general_error]=1
_zsh_config[exit_interrupted]=130
_zsh_config[progress_update_interval]=10
_zsh_config[timeout_default]=30
_zsh_config[log_max_depth]=100
_zsh_config[cache_max_size]=100
_zsh_config[performance_mode]=false

# Global verbosity level.
typeset -gi _zsh_config_verbose
if [[ -n ${zsh_config_verbose:-} && ${zsh_config_verbose} == <-> ]]; then
	_zsh_config_verbose=${zsh_config_verbose}
else
	_zsh_config_verbose=${_zsh_config[log_info]}
fi

# Override performance mode with an environment variable if set.
if [[ -n ${ZSH_CONFIG_PERFORMANCE_MODE:-} ]]; then
	_zsh_config[performance_mode]="${ZSH_CONFIG_PERFORMANCE_MODE}"
fi
# Global state variables.
typeset -gi _zsh_config_interrupted=0
typeset -gi _log_depth=0
typeset -gi _in_function_check=0     # reserved for future use
typeset -gi _cached_term_width=0     # reserved for future use

# Centralized cache initialization.
typeset -gA _function_cache
typeset -ga _cache_order
typeset -gi _cache_size=0

# Color setup (cached once for performance).
typeset -gA _zsh_colors
if [[ -t 2 && -z ${NO_COLOR:-} ]] && (( $+commands[tput] )) && tput setaf 1 >/dev/null 2>&1; then
	_zsh_colors=(
		[red]="$(tput setaf 1)" [green]="$(tput setaf 2)" [blue]="$(tput setaf 4)"
		[yellow]="$(tput setaf 3)" [reset]="$(tput sgr0)"
	)
else
	_zsh_colors=([red]="" [green]="" [blue]="" [yellow]="" [reset]="")
fi

# --- Logging ---

###
# Logs a message to stderr with a level, timestamp, and color.
# @param integer Log level.
# @param string ... Message to log.
###
_log_engine() {
	emulate -L zsh

	if (( _log_depth > _zsh_config[log_max_depth] )); then
		print -r -- "FATAL: Recursion in _log_engine" >&2
		return 1
	fi
	(( _log_depth++ ))

	local -i level
	if [[ -z ${1-} || $1 != <-> ]]; then
		print -r -- "[error] Invalid log level: '${1-}'" >&2
		(( _log_depth-- ))
		return 1
	fi
	level=$1
	shift

	if (( level > _zsh_config_verbose )); then
		(( _log_depth-- ))
		return 0
	fi

	local prefix=""
	case $level in
		(${_zsh_config[log_error]}) prefix="${_zsh_colors[red]}[error]${_zsh_colors[reset]}" ;;
		(${_zsh_config[log_warn]})  prefix="${_zsh_colors[yellow]}[warn]${_zsh_colors[reset]}" ;;
		(${_zsh_config[log_info]})  prefix="${_zsh_colors[blue]}[info]${_zsh_colors[reset]}" ;;
		(${_zsh_config[log_debug]}) prefix="${_zsh_colors[green]}[debug]${_zsh_colors[reset]}" ;;
		(*)                         prefix="[unknown]" ;;
	esac

	# Build timestamp via prompt expansion only for the time part
	local ts
	print -P -v ts -- "%D{%Y-%m-%d %H:%M:%S}"

	# Compose and emit (avoid -P here to prevent prompt escape expansion in user text)
	print -r -- "${ts} ${prefix} $*" >&2

	(( _log_depth-- ))
	return 0
}
_log_error() { _log_engine ${_zsh_config[log_error]} "$@"; }
_log_warn()  { _log_engine ${_zsh_config[log_warn]}  "$@"; }
_log_info()  { _log_engine ${_zsh_config[log_info]}  "$@"; }
_log_debug() { _log_engine ${_zsh_config[log_debug]} "$@"; }

# --- Interrupt Handling ---
# --- Interrupt Handling ---

###
# Trap handler for INT and TERM signals.
###
_handle_interrupt() {
	emulate -L zsh
	if (( _zsh_config_interrupted == 0 )); then
		_zsh_config_interrupted=1
		_log_warn "Interrupt received. Gracefully shutting down..."
	fi
	# zsh traps persist; no need to re-arm here
}

###
# Checks if an interrupt has been received.
###
_check_interrupted() {
	emulate -L zsh
	if (( _zsh_config_interrupted )); then
		_log_info "Operation cancelled by user."
		return ${_zsh_config[exit_interrupted]}
	fi
	return 0
}

# --- Fatal Errors ---

###
# Logs a fatal error and exits or returns.
# @param string Error message.
# @param integer Exit code (optional).
###
_die() {
	emulate -L zsh
	local message="${1-}"
	local -i exit_code=${2:-${_zsh_config[exit_general_error]}}

	_log_error "FATAL: $message"

	# If running code sourced from a file, return; otherwise exit the process
	local ctx="${ZSH_EVAL_CONTEXT:-}"
	if [[ $ctx == *:file:* ]]; then
		return $exit_code
	else
		exit $exit_code
	fi
}


# ==============================================================================
# 2. COMMAND & ALIAS HANDLING
# ==============================================================================

###
# Safely creates an alias, validating the target command.
# @param string Alias name.
# @param string Alias value (the command).
###
_safe_alias() {
	emulate -L zsh

	local alias_name="${1-}" alias_value="${2-}"
	if [[ -z $alias_name || -z $alias_value || $alias_name == *[[:space:]=]* ]]; then
		_log_error "Invalid alias definition: name='$alias_name' value='$alias_value'"
		return 1
	fi

	# In performance mode, skip command validation.
	if [[ ${_zsh_config[performance_mode]:-} != "true" ]]; then
		# Derive the command name from the alias value, respecting shell word rules
		local -a tokens premods skip_validation
		premods=(nocorrect noglob builtin command exec time nice nohup sudo doas env)
		skip_validation=(j z zi autojump)  # Commands that may be loaded later

		local cmd_name='' t
		tokens=(${(z)alias_value})

		# Track certain precommands to skip their flags/args
		local -i seen_env=0 seen_sudo=0 seen_time=0 seen_nice=0 seen_nohup=0

		for t in "${tokens[@]}"; do
			# Skip precommand modifiers (not real executables). (Ie) returns 0 if not found.
			if (( ${premods[(Ie)$t]} )); then
				case $t in
					env)        seen_env=1 ;;
					sudo|doas)  seen_sudo=1 ;;
					time)       seen_time=1 ;;
					nice)       seen_nice=1 ;;
					nohup)      seen_nohup=1 ;;
				esac
				continue
			fi

			# Skip NAME=VALUE assignments anywhere
			if [[ $t == [[:alpha:]_][[:alnum:]_]*=* ]]; then
				continue
			fi

			# Skip options that belong to certain precommands
			if (( seen_env || seen_sudo || seen_time || seen_nice || seen_nohup )); then
				if [[ $t == -- || $t == -* ]]; then
					continue
				fi
			fi

			cmd_name=$t
			break
		done

		# Validate command unless explicitly skipped
		if [[ -n $cmd_name ]] && (( ${skip_validation[(Ie)$cmd_name]} == 0 )); then
			if ! command -v -- "$cmd_name" >/dev/null 2>&1; then
				_log_debug "Command '$cmd_name' not yet available for alias '$alias_name'"
			fi
		fi
	fi

	if ! builtin alias "${alias_name}=${alias_value}" 2>/dev/null; then
		_log_error "Failed to create alias: $alias_name='$alias_value'"
		return 1
	fi
	_log_debug "Created alias: $alias_name='$alias_value'"
	return 0
}

###
# Adds a directory to the PATH environment variable if it exists and is not already present.
# @param string Directory to add.
# @param string Position to add the directory ("append" or "prepend"). Defaults to "append".
###
_add_to_path() {
    local dir="$1"
    local position="${2:-append}"

    if [[ -z "$dir" ]]; then
        _log_error "Empty directory provided to _add_to_path"
        return 1
    fi

    local original_dir="$dir"
    if ! dir=$(_resolve_path "$dir"); then
        _log_debug "Failed to resolve directory path for PATH: $original_dir"
        return 1
    fi

    if [[ ! -d "$dir" ]]; then
        _log_debug "Directory does not exist, not adding to PATH: $dir"
        return 1
    fi

    if [[ ":${PATH}:" == *":${dir}:"* ]]; then
        _log_debug "Directory already in PATH: $dir"
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
            _log_error "Invalid position for _add_to_path: $position (use prepend or append)"
            return 1
            ;;
    esac

    _log_debug "Added to PATH ($position): $dir"
    return 0
}


# ==============================================================================
# 3. DYNAMIC & SAFE EXECUTION
# ==============================================================================

###
# Safely evaluates a string of shell code with security checks.
# @param string Code to evaluate.
# @param integer Timeout in seconds (optional).
# @param boolean Force execution in the current shell (optional).
###
_safe_eval() {
    local input="$1"
    local -i timeout=${2:-${_zsh_config[timeout_default]}}
    local force_current_shell="${3:-false}"
    if [[ -z "$input" ]]; then
        _log_error "Empty input for _safe_eval"
        return 1
    fi

    local eval_code=""
    local is_shell_init=false
    if [[ "$input" =~ ^(starship|mise|direnv|zoxide|atuin|mcfly|fzf|oh-my-posh).*init ]]; then
        is_shell_init=true
    fi

    # --- Execution Method ---
    local -i exit_code=0
    if [[ "${_zsh_config[performance_mode]}" == "true" ]] && [[ "$is_shell_init" == "true" ]]; then
        # FAST MODE: Direct, less safe execution for init scripts.
        _log_debug "Running init in performance mode: $input"
        eval "$($input)" || exit_code=$?

    elif [[ "$is_shell_init" == "true" ]]; then
        # SAFE MODE: Isolate init scripts in a subshell.
        _log_debug "Detected shell init command: $input"
        local temp_stderr
        temp_stderr=$(mktemp 2>/dev/null || print -r -- "${TMPDIR:-/tmp}/zsh_eval_$$")

        eval_code=$(zsh -c "$input" 2>"$temp_stderr") || exit_code=$?

        local stderr_output
        stderr_output=$(<"$temp_stderr" 2>/dev/null)
        rm -f "$temp_stderr" 2>/dev/null

        if (( exit_code != 0 )); then
            _log_error  "Init command failed: $input (code: $exit_code)"
            [[ -n "$stderr_output" ]] && _log_debug "Stderr: $stderr_output"
            return $exit_code
        fi
        if [[ -z "$eval_code" ]]; then
            _log_warn "Init command gave empty output: $input"
            return 1
        fi
        # Fall through to execute the generated code.
        input="$eval_code"
    fi

    # --- Security Scan (for non-init or generated code) ---
    if [[ "${_zsh_config[performance_mode]}" != "true" ]]; then
        local -ra dangerous_patterns=(
            'rm[[:space:]]\+-[^[:space:]]*[rf]' 'sudo[[:space:]]\+rm' 'dd[[:space:]]\+'
            '>[[:space:]]*/dev/(sd|hd|nvme)' 'mkfs\.' 'chmod[[:space:]]\+777' ':[[:space:]]*\(\)[[:space:]]*\{'
            'curl[^|]*\|[^|]*sh' 'wget[^|]*\|[^|]*sh' 'base64[[:space:]]\+-d' 'find[[:space:]]\+.*-delete'
        )
        local pattern
        for pattern in "${dangerous_patterns[@]}"; do
            if [[ "$input" =~ $pattern ]]; then
                _log_error "Potentially dangerous eval detected (pattern: $pattern)"
                return 1
            fi
        done
    fi

    _check_interrupted || return $?

    # --- Final Execution ---
    local run_in_current_shell=false
    if [[ "$force_current_shell" == "true" ]] || [[ "$is_shell_init" == "true" ]]; then
        run_in_current_shell=true
    fi

    if [[ "$run_in_current_shell" == "true" ]]; then
        eval "$input" || exit_code=$?
    elif (( $+commands[timeout] )); then
        timeout "$timeout" zsh -c "$input" || exit_code=$?
        if (( exit_code == 124 )); then
            _log_warn "Eval timed out after ${timeout}s"
        fi
    else
        _log_warn "Timeout command not found, skipping non-init eval for safety."
        return 1
    fi

    if (( exit_code != 0 && exit_code != 124 )); then
        _log_warn "Eval failed with exit code $exit_code"
    fi
    return $exit_code
}


# ==============================================================================
# 4. FILESYSTEM & SOURCING
# ==============================================================================

###
# Resolves a path, handling tilde expansion and symlinks.
# @param string Path to resolve.
# @return Prints the resolved path to stdout.
###
_resolve_path() {
    local path="$1"
    if [[ -z "$path" || "$path" =~ ^[[:space:]]*$ ]]; then
        _log_error "Empty or whitespace path provided to _resolve_path"
        return 1
    fi

    # Handle tilde expansion manually for robustness.
    case "$path" in
        '~'*) path="${HOME}${path#\~}" ;;
    esac

    # Resolve directory and symlinks.
    if [[ -d "${path%/*}" ]]; then
        local resolved_dir
        if resolved_dir="$(cd "${path%/*}" 2>/dev/null && pwd -P)"; then
            path="${resolved_dir}/${path##*/}"
        fi
    fi
    if [[ -L "$path" ]]; then
        local resolved_link
        if resolved_link=$(readlink -f "$path" 2>/dev/null); then
            path="$resolved_link"
        fi
    fi
    printf '%s' "$path"
}

###
# Safely sources a file after validation.
# @param string Path to the file to source.
# @param ...    Arguments to pass to the sourced file.
###
_safe_source() {
    local file="$1"
    shift
    if [[ -z "$file" ]]; then
        _log_error "Empty file path for source"
        return 1
    fi

    local resolved_file="$file"
    # Skip expensive path resolution in performance mode.
    if [[ "${_zsh_config[performance_mode]}" != "true" ]]; then
        if ! resolved_file=$(_resolve_path "$file"); then
            _log_error "Failed to resolve path: $file"
            return 1
        fi
    fi

    if [[ ! -f "$resolved_file" || ! -r "$resolved_file" ]]; then
        _log_warn "File not found or not readable: $resolved_file"
        return 1
    fi

    _check_interrupted || return $?

    local -i exit_code=0
    source "$resolved_file" "$@" || exit_code=$?

    if (( exit_code != 0 )); then
        _log_warn "Failed to source $resolved_file (code: $exit_code)"
    fi
    return $exit_code
}


# ==============================================================================
# 5. FUNCTION INTROSPECTION & CACHING
# ==============================================================================

###
# Checks if a function exists, using a cache with LRU eviction.
# @param string Function name.
###
_function_exists() {
    local func="$1"
    if [[ -z "$func" ]]; then
        return 1
    fi

    (( _in_function_check++ ))
    if (( _in_function_check > 1 )); then
        (( _in_function_check-- ))
        return 1 # Recursion guard
    fi

    local cache_key="func_exists_${func//[^a-zA-Z0-9_]/_}"
    if [[ -n "${_function_cache[$cache_key]:-}" ]]; then
        (( _in_function_check-- ))
        return ${_function_cache[$cache_key]}
    fi

    typeset -f "$func" >/dev/null 2>&1
    local result=$?

    _function_cache[$cache_key]=$result
    _cache_order+=($cache_key)
    (( _cache_size++ ))

    # Skip expensive LRU cache eviction in performance mode.
    if [[ "${_zsh_config[performance_mode]}" != "true" ]]; then
        while (( _cache_size > _zsh_config[cache_max_size] )); do
            if (( ${#_cache_order[@]} > 0 )); then
                local oldest=${_cache_order[1]}
                if [[ -n "$oldest" && -n "${_function_cache[$oldest]:-}" ]]; then
                    unset "_function_cache[$oldest]"
                    (( _cache_size-- ))
                fi
                _cache_order=("${_cache_order[@]:1}")
            else
                _cache_size=0
                break
            fi
        done
    fi

    (( _in_function_check-- ))
    return $result
}

###
# Safely calls a function if it exists.
# @param string Function name to call.
# @param ...    Arguments to pass to the function.
###
_safe_call() {
    local func="$1"
    if [[ -z "$func" ]]; then
        _log_error "Empty function name for _safe_call"
        return 1
    fi
    shift

    if ! _function_exists "$func"; then
        case "$func" in
            _git_prompt_info|__zconvey_on_period_passed*|_*prompt*|_*git*)
                return 1 # Silently skip known dynamic functions
                ;;
            *)
                _log_warn "Function '$func' not found"
                return 1
                ;;
        esac
    fi

    _check_interrupted || return $?

    local -i exit_code=0
    "$func" "$@" || exit_code=$?

    if (( exit_code != 0 )); then
        _log_warn "Function '$func' failed with code $exit_code"
    fi
    return $exit_code
}


# ==============================================================================
# 6. STATE MANAGEMENT
# ==============================================================================

###
# Safely unsets a variable or function.
# @param string Target name to unset.
# @param string Type to unset (auto, var, func). Defaults to auto.
###

_safe_unset() {
	emulate -L zsh
	setopt typeset_silent

	local target="${1-}"
	local unset_type="${2:-auto}"

	if [[ -z $target ]]; then
		_log_error "Empty target for unset"
		return 1
	fi

	case $unset_type in
		var|func|auto) ;;
		*)
			_log_error "Invalid unset type: $unset_type"
			return 1
			;;
	esac

	local -i found=0 success=0 rc_var=0 rc_func=0

	# Handle variable unsetting
	if [[ $unset_type == var || $unset_type == auto ]]; then
		if (( ${+parameters[$target]} )); then
			found=1
			# Detect readonly via type string of the parameter named by $target
			if [[ ${(tP)target} == *readonly* ]]; then
				_log_debug "Cannot unset readonly var: $target"
				rc_var=1
			else
				unset -v -- "$target" 2>/dev/null || rc_var=$?
				(( rc_var == 0 )) && success=1
			fi
		fi
	fi

	# Handle function unsetting
	if [[ $unset_type == func || $unset_type == auto ]]; then
		if (( ${+functions[$target]} )); then
			found=1
			unset -f -- "$target" 2>/dev/null || rc_func=$?
			if (( rc_func == 0 )); then
				success=1
				# Update function-existence cache if present
				local cache_key="func_exists_${target//[^A-Za-z0-9_]/_}"
				if (( ${+_function_cache} )) && (( ${+_function_cache[$cache_key]} )); then
					unset "_function_cache[$cache_key]"
					if (( ${+_cache_order} )) && [[ ${(t)_cache_order} == *array* ]]; then
						_cache_order=("${(@)_cache_order:#$cache_key}")
					fi
					if (( ${+_cache_size} )); then
						_cache_size=${#_function_cache[@]}
					fi
				fi
			fi
		fi
	fi

	if (( ! found )); then
		_log_debug "Target not found for unset: $target"
		return 1
	fi

	if (( success )); then
		_log_debug "Unset: $target"
		return 0
	fi

	_log_warn "Failed to unset $target"
	return $(( rc_func != 0 ? rc_func : rc_var ))
}

# ==============================================================================
# 7. USER INTERFACE (UI)
# ==============================================================================

###
# Detects and caches the terminal width.
###
_detect_terminal_width() {
    local width
    if [[ -n "${COLUMNS:-}" ]] && [[ "$COLUMNS" =~ ^[0-9]+$ ]] && (( COLUMNS >= 10 && COLUMNS <= 9999 )); then
        _cached_term_width=$COLUMNS
    elif command -v tput >/dev/null 2>&1 && width=$(tput cols 2>/dev/null) && [[ "$width" =~ ^[0-9]+$ ]] && (( width >= 10 && width <= 9999 )); then
        _cached_term_width=$width
    else
        _cached_term_width=80
    fi
    return 0
}

###
# Determines if a progress update should be displayed.
# @param integer Current item number.
# @param integer Total number of items.
###
_should_show_progress() {
    local -i current=$1 total=$2 interval=${_zsh_config[progress_update_interval]}
    if (( current == 1 || current == total || current % interval == 0 || (total > interval && total - current < interval) )); then
        return 0
    else
        return 1
    fi
}

###
# Displays a progress bar.
# @param integer Current item number.
# @param integer Total number of items.
# @param string  Label for items (optional).
###
_show_progress() {
    local -i current total
    if ! current="$1" 2>/dev/null || ! total="$2" 2>/dev/null; then
        _log_debug "Invalid progress params"
        return 1
    fi

    local label="${3:-items}"
    if (( total <= 0 || current < 0 || current > total )); then
        _log_debug "Invalid progress range"
        return 1
    fi

    # Only display at info level. At debug level, the logs provide the progress.
    # Also, do not display if not in an interactive terminal.
    if (( _zsh_config_verbose != _zsh_config[log_info] )) || [[ ! -t 2 ]]; then
        return 0
    fi

    if ! _should_show_progress "$current" "$total"; then
        return 0
    fi

    _detect_terminal_width

    local -i percent=$(( total > 0 ? (current * 100) / total : 0 ))
    (( percent > 100 )) && percent=100

    local current_fmt total_fmt
    printf -v current_fmt "%'d" "$current" 2>/dev/null || current_fmt="$current"
    printf -v total_fmt "%'d" "$total" 2>/dev/null || total_fmt="$total"

    if (( _cached_term_width > 50 )); then
        printf '\r[%3d%%] processing %s %s of %s...' "$percent" "$label" "$current_fmt" "$total_fmt" >&2
    else
        printf '\r[%3d%%] %s %s/%s' "$percent" "$label" "$current_fmt" "$total_fmt" >&2
    fi

    if (( current == total )); then
        printf '\r\e[K\n' >&2
    fi
}


# ==============================================================================
# 8. INITIALIZATION
# ==============================================================================

# Install the interrupt handler.
trap '_handle_interrupt' INT TERM

# Log the initialization of the library itself.
_log_debug "Zsh utility library initialized."

