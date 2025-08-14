#!/usr/bin/env zsh
if [[ -n "${_zsh_config_loaded:-}" ]]; then
    return 0
fi
typeset -gr _zsh_config_loaded=1
setopt PROMPT_SUBST PROMPT_PERCENT
umask 022

local major_version="${ZSH_VERSION%%.*}"
if [[ ! "${major_version}" =~ ^[0-9]+$ ]] || ((major_version < 5)); then
    print -u2 "error: zsh 5.0+ required (current: ${ZSH_VERSION})"
    print -u2 "please upgrade zsh or use bash compatibility mode."
    return 1
fi
source $HOME/.config/zsh/lib/core.zsh
setup_platform_aliases() {
    _detect_platform

    # --- General Aliases ---
    _safe_alias y 'yazi'
    _safe_alias dev 'cd ~/dev'
    _safe_alias zss 'cd ~/.ssh'
    _safe_alias zdd 'cd ${XDG_CONFIG_HOME:-$HOME/.config}'
    _safe_alias z 'j'
    _safe_alias skr 'ssh-keygen -R'
    _safe_alias sci 'ssh-copy-id -i'
    _safe_alias ssi 'ssh -i'

    # --- Platform-Specific Aliases ---
    if ((IS_MACOS)); then
        _safe_alias o 'open'
        _safe_alias clip 'pbcopy'

        # Set alias only if the command exists
        if command -v yabai >/dev/null 2>&1; then
            _safe_alias ybr 'yabai --restart-service'
        fi

        # Set alias only if the executable exists
        local surge_cli='/Applications/Surge.app/Contents/Resources/surge-cli'
        [[ -x "$surge_cli" ]] && _safe_alias surge "$surge_cli"

    elif ((IS_LINUX)); then
        _safe_alias o 'xdg-open'
        if command -v xclip >/dev/null 2>&1; then
            _safe_alias clip 'xclip -selection clipboard'
        elif command -v xsel >/dev/null 2>&1; then
            _safe_alias clip 'xsel --clipboard --input'
        else
            _log_warn "No clipboard tool found (xclip or xsel) for Linux"
        fi

    elif ((IS_BSD)); then
        _safe_alias o 'xdg-open'
        if command -v xclip >/dev/null 2>&1; then
            _safe_alias clip 'xclip -selection clipboard'
        else
            _log_warn "No clipboard tool found (xclip) for BSD"
        fi

    elif ((IS_CYGWIN)); then
        _safe_alias o 'cygstart'
        _safe_alias clip 'cat > /dev/clipboard'
    fi

    # Ensure the function always returns success if it completes.
    return 0
}

###
# Detects the Google Cloud SDK installation, sets the Python interpreter,
# and sources the necessary shell integration files.
###
_setup_gcloud_sdk() {
    _detect_platform

    # --- Find GCloud SDK Base Path ---
    local gcloud_base="${GCLOUD_SDK_PATH:-}" # 1. Check environment variable first.
    if [[ -z "$gcloud_base" ]]; then
        # 2. Check common installation locations.
        local -a possible_bases=("$HOME/.local/google-cloud-sdk" "$HOME/google-cloud-sdk" "/usr/lib/google-cloud-sdk")
        for base in "${possible_bases[@]}"; do
            if [[ -d "$base/bin" ]]; then
                gcloud_base="$base"
                break
            fi
        done
    fi
    if [[ -z "$gcloud_base" ]] && command -v gcloud >/dev/null 2>&1; then
        # 3. As a last resort, derive from the command path.
        gcloud_base="$(dirname "$(dirname "$(command -v gcloud)")")"
    fi

    if [[ -z "$gcloud_base" || ! -d "$gcloud_base" ]]; then
        _log_debug "Google Cloud SDK not found."
        return 1
    fi

    # --- Source SDK files ---
    local -a gcloud_files=(
        "$gcloud_base/path.zsh.inc"
        "$gcloud_base/completion.zsh.inc"
    )
    local -i success_count=0
    for file in "${gcloud_files[@]}"; do
        if _safe_source "$file"; then
            ((success_count++))
        fi
    done

    # --- Set Python Interpreter ---
    local gcloud_python="${GCLOUD_PYTHON_PATH:-}"
    if [[ -z "$gcloud_python" ]]; then
        # Prefer the SDK's bundled Python if it exists.
        if [[ -x "$gcloud_base/gcp-venv/bin/python" ]]; then
            gcloud_python="$gcloud_base/gcp-venv/bin/python"
        else
            # Fallback to system python3.
            gcloud_python="$(command -v python3 2>/dev/null)"
        fi
    fi

    if [[ -n "$gcloud_python" && -x "$gcloud_python" ]]; then
        export CLOUDSDK_PYTHON="$gcloud_python"
        _log_debug "Set CLOUDSDK_PYTHON to: $gcloud_python"
    fi

    if ((success_count > 0)); then
        _log_debug "Google Cloud SDK initialized ($success_count files loaded)"
        return 0
    fi
    return 1
}

###
# Loads all specified Zsh configuration files from the modules directory.
###
_load_config_files() {
    local config_base="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
    local -ar config_files=(
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

    local -i loaded_files=0
    local -i total_files=${#config_files[@]}
    local -i current_file_num=0

    for config_file in "${config_files[@]}"; do
        ((current_file_num++))
        _check_interrupted || return $?

        _show_progress $current_file_num $total_files "config"

        local full_path="$config_base/$config_file"
        if _safe_source "$full_path"; then
            ((loaded_files++))
        else
            # _safe_source already logs a warning, so we don't need to log again.
            # You could add an error here if a missing file should be fatal.
            : # No-op
        fi
    done

    _log_info "Loaded $loaded_files/$total_files config files"
    return 0
}

###
# Sets up external shell tools like mise, direnv, and autojump.
###
_setup_external_tools() {
    # Initialize mise if available.
    if command -v mise >/dev/null 2>&1; then
        _safe_eval "$(mise activate zsh)" 10 true
    fi

    # Initialize direnv if available.
    if command -v direnv >/dev/null 2>&1; then
        _safe_eval "$(direnv hook zsh)" 10 true
    fi

    # Source autojump if it exists on macOS.
    if ((IS_MACOS)); then
        local -a autojump_scripts=(
            '/opt/homebrew/etc/profile.d/autojump.sh'
            '/usr/local/etc/profile.d/autojump.sh'
        )
        for script in "${autojump_scripts[@]}"; do
            if _safe_source "$script"; then
                _log_debug "autojump loaded from: $script"
                break
            fi
        done
    fi
}

###
# Creates stub functions for optional plugins to prevent errors if they are not loaded.
###
_create_stub_functions() {
    # Stub for a common Git prompt function.
    if ! _function_exists _git_prompt_info; then
        _git_prompt_info() { return 0; }
    fi

    # Stubs for Zconvey, a testing tool that might not be present.
    local -a zconvey_functions=(
        __zconvey_on_period_passed26
        __zconvey_on_period_passed30
        __zconvey_on_period_passed
    )
    for func in "${zconvey_functions[@]}"; do
        if ! _function_exists "$func"; then
            eval "$func() { return 0; }"
        fi
    done
}

###
# Detects the current operating system and sets global boolean flags.
# This function is guarded to only run once for efficiency.
###
_detect_platform() {
    if [[ -n "${_PLATFORM_DETECTED:-}" ]]; then
        return 0
    fi

    # Set platform variables based on the built-in $OSTYPE variable.
    case "$OSTYPE" in
    darwin*)
        typeset -gri IS_MACOS=1 IS_LINUX=0 IS_BSD=0 IS_CYGWIN=0
        ;;
    linux*)
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

    # Check for Windows Subsystem for Linux (WSL).
    typeset -gri IS_WSL=0
    if ((IS_LINUX)); then
        if [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSLENV:-}" || -f "/proc/sys/fs/binfmt_misc/WSLInterop" ]]; then
            typeset -gri IS_WSL=1
        elif [[ -r "/proc/version" ]]; then
            local proc_version
            if proc_version=$(head -c 1024 "/proc/version" 2>/dev/null); then
                if [[ "$proc_version" == *[Mm]icrosoft* || "$proc_version" == *[Ww][Ss][Ll]* ]]; then
                    typeset -gri IS_WSL=1
                fi
            fi
        fi
    fi

    # Check for Termux on Android.
    if ((IS_LINUX)) && [[ -d "/data/data/com.termux" ]]; then
        typeset -gri IS_TERMUX=1
    else
        typeset -gri IS_TERMUX=0
    fi

    # Set a flag for unknown platforms.
    if ((IS_MACOS || IS_LINUX || IS_BSD || IS_CYGWIN)); then
        typeset -gri IS_UNKNOWN=0
    else
        typeset -gri IS_UNKNOWN=1
    fi

    # Mark platform detection as complete.
    typeset -gr _PLATFORM_DETECTED=1

    if ((IS_UNKNOWN)); then
        _log_warn "Unknown platform: $OSTYPE"
    fi

    _log_debug "Platform: macOS=$IS_MACOS Linux=$IS_LINUX BSD=$IS_BSD WSL=$IS_WSL Cygwin=$IS_CYGWIN Termux=$IS_TERMUX"
}
###
# The main entry point for the Zsh initialization process.
###
_main() {
    zmodload zsh/datetime
    zmodload zsh/mathfunc 2>/dev/null
    typeset -F start_time
    start_time=$EPOCHREALTIME

    _detect_platform
    _create_stub_functions

    # Load core configuration files first.
    _load_config_files || return $?

    # Sequentially run setup functions defined in the loaded config files.
    local -a init_functions=(
        _initialize_environment
        _build_path
        _setup_environment
        _configure_shell
        _define_aliases
        setup_platform_aliases
    )
    local -i total_functions=${#init_functions[@]} current_function=0
    for func in "${init_functions[@]}"; do
        ((current_function++))
        _check_interrupted || return $?
        _show_progress $current_function $total_functions "init"
        _safe_call "$func"
    done

    # Load plugin manager and plugins.
    if _safe_call _install_zi; then
        _safe_call _load_plugins
    else
        _log_warn "ZI plugin manager not available."
    fi

    # Setup remaining components.
    _safe_call _setup_completions
    _safe_call _setup_keybindings
    _setup_external_tools
    _setup_gcloud_sdk
    _safe_call _setup_prompt

    # Final timing log.
    typeset -F end_time init_duration
    end_time=$EPOCHREALTIME
    init_duration=$((end_time - start_time))
    _log_info "Zsh initialized in $(printf "%.4f" $init_duration)s"
}

###
# Removes temporary initialization functions to keep the shell environment clean.
###
_cleanup_init_functions() {
    local -a cleanup_list=(
        _main
        _load_config_files
        _setup_gcloud_sdk
        _setup_external_tools
        _create_stub_functions
        _cleanup_init_functions
        _initialize_environment
        _build_path
        _setup_environment
        _configure_shell
        _define_aliases
        setup_platform_aliases
        _install_zi
        _load_plugins
        _setup_completions
        _setup_keybindings
        _setup_prompt
    )

    for func in "${cleanup_list[@]}"; do
        _safe_unset "$func" "func"
    done
    source "/Users/mkh/.wasmedge/env"
    export PATH="/Users/mkh/gaianet/bin:$PATH"

}

# --- Main Execution and Cleanup ---

# Run the main initialization function and store its exit code.
_main
_safe_eval "starship init zsh"
local main_exit_code=$?

# After initialization, clean up temporary functions to keep the environment lean.
# The core utility library functions (e.g., _log, _safe_call) will remain.
_cleanup_init_functions
# Return the exit code from the main function.
return $main_exit_code
