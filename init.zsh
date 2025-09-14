#!/usr/bin/env zsh
# Guard: prevent reloading
if [[ -n "${_zcore_config_loaded:-}" ]]; then
	return 0
fi
typeset -gr _zcore_config_loaded=1

# Intentionally global shell options for interactive init
setopt PROMPT_SUBST PROMPT_PERCENT
umask 022

# Require zsh 5+
typeset -i _zsh_major="${${ZSH_VERSION%%.*}:-0}"
if (( _zsh_major < 5 )); then
	print -u2 -- "error: zsh 5.0+ required (current: ${ZSH_VERSION})"
	print -u2 -- "please upgrade zsh or use bash compatibility mode."
	return 1
fi

typeset -gx XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
typeset -gx XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
typeset -gx XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
typeset -gx XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
typeset -gx ZDOTDIR="${ZDOTDIR:-$HOME/.config/zsh}"
typeset -g ZCORE_LIBDIR="${ZDOTDIR}/lib"
typeset -g ZCORE_MODDIR="${ZDOTDIR}/modules"

# Config knobs (env visible so the library can read them)
typeset -gx ZCORE_CONFIG_SHOW_PROGRESS=false
typeset -gx ZCORE_CONFIG_PERFORMANCE_MODE=false
# Honor desired verbosity in the library
#typeset -gx zcore_config_verbose="${zcore_config_verbose:-3}"

# Load core libraries
source "${ZCORE_LIBDIR}/core.zsh"
source "${ZCORE_LIBDIR}/platform.zsh"

###
# Loads all specified Zsh configuration files from the modules directory.
###
_load_config_files() {
	emulate -L zsh

	local config_base=$ZCORE_MODDIR
	local -ar config_files=(
		"environment"
		"path"
		"extra"
		"aliases"
		"load_zi"
		"completions"
		"keybindings"
		"utils"
		"python"
		"funcs"
		"external_tools"
		"prompt"
    "clipboard"
	)

	local -i loaded_files=0
	local -i total_files=${#config_files[@]}
	local -i current_file_num=0

	local config_file full_path
	for config_file in "${config_files[@]}"; do
		((current_file_num++))
		z::runtime::check_interrupted || return $?

		z::ui::progress::show $current_file_num $total_files "config"

		full_path="${config_base}/${config_file}.zsh"
		if z::path::source "$full_path"; then
			((loaded_files++))
		else
			z::log::debug "Failed to load config: $full_path"
		fi
	done

	z::log::info "Loaded $loaded_files/$total_files config files"
	return 0
}

_main() {
	emulate -L zsh

	# Optional modules; silence failures
	zmodload zsh/datetime 2>/dev/null
	zmodload zsh/mathfunc 2>/dev/null

	typeset -F start_time end_time init_duration
	# Fallback if EPOCHREALTIME is unavailable
	start_time=${EPOCHREALTIME:-$EPOCHSECONDS}

	z::detect::platform

	# Load core configuration files first.
	_load_config_files || return $?

	local -a init_functions=(
		_initialize_environment
		_build_path
		_setup_environment
		_define_aliases
		setup_platform_aliases
		_create_stub_functions
	)
	local -i total_functions=${#init_functions[@]} current_function=0
	local func
	for func in "${init_functions[@]}"; do
		((current_function++))
		z::runtime::check_interrupted || return $?
		z::ui::progress::show $current_function $total_functions "init"
		z::func::call "$func"
	done

	if z::func::call _install_zi; then
		z::func::call _load_plugins
	else
		z::log::warn "ZI plugin manager not available."
	fi

	z::func::call _setup_completions
	z::func::call _setup_keybindings
	z::func::call _setup_ls
	# Configure shell options after environment is set up (safe-source)
	if ! z::path::source "${ZCORE_MODDIR}/options.zsh"; then
		z::log::warn "Options module not found or unreadable: ${ZCORE_MODDIR}/options.zsh"
	fi
	_setup_prompt || return $?
	# External tools and prompt are now handled by their respective modules

	end_time=${EPOCHREALTIME:-$EPOCHSECONDS}
	init_duration=$(( end_time - start_time + 0.0 ))
	z::log::info "Zsh initialized in $(printf '%.4f' "$init_duration")s"
}

_cleanup_init_functions() {
	emulate -L zsh

	local -a cleanup_list=(
		_main
		_load_config_files
		_create_stub_functions
		_cleanup_init_functions
		_initialize_environment
		_build_path
		_setup_environment
		_define_aliases
		setup_platform_aliases
		_install_zi
		_load_plugins
		_setup_completions
		_setup_keybindings
		_setup_ls
	)

	local func
	for func in "${cleanup_list[@]}"; do
		z::state::unset "$func" "func"
	done

}


# Only run initialization in interactive shells; never exit the shell from here.
if [[ -o interactive ]]; then
	_main
	_configure_setopts || return $?
	_cleanup_init_functions
fi

# Always succeed when sourced during startup
return 0
