#!/usr/bin/env zsh
# ZSH Config orchestrator using zcore library

if [[ -n "${_zcore_init_loaded:-}" ]]; then
	return 0
fi
typeset -gr _zcore_init_loaded=1
setopt PROMPT_SUBST PROMPT_PERCENT
umask 022

typeset -gx ZDOTDIR="${ZDOTDIR:-$XDG_CONFIG_HOME/zsh}"
typeset -g ZCORE_LIBDIR="${ZDOTDIR}/lib"
typeset -g ZCORE_MODDIR="${ZDOTDIR}/modules"
typeset -gx zcore_config_verbose="${zcore_config_verbose:-3}"
if ! source "${ZCORE_LIBDIR}/core.zsh"; then
	print -u2 -- "FATAL: zcore library not found at '${ZCORE_LIBDIR}/core.zsh'"
	return 1
fi
z::init::_load_modules() {
	emulate -L zsh
	z::runtime::check_interrupted || return $?
	# The order of this list determines the loading sequence.
	local -ar modules=(
		"environment"
		"path-setup"
		"zi-plugins"
                "completions"
                "ls-enhancements"
		"python"
		"utils"
                "clipboard-tools"
                "options"
                "keybindings"
                "aliases"
		"integrations"
		"prompt"
	)

	local -i loaded_count=0
	local -i total_modules=${#modules[@]}
	local module full_path

	z::log::info "Loading ${total_modules} configuration modules..."
	for module in "${modules[@]}"; do
		full_path="${ZCORE_MODDIR}/${module}.zsh"
		if z::path::source "$full_path"; then
			((loaded_count++))
			z::log::debug "Module loaded: ${module}.zsh"
		else
			z::log::debug "Module not found or failed to load: ${module}.zsh"
		fi
	done

	z::log::info "Successfully loaded ${loaded_count}/${total_modules} modules."
	return 0
}

# Main orchestrator for the entire Zsh initialization process.
z::init::main() {
	emulate -L zsh
	zmodload zsh/datetime 2>/dev/null
	zmodload zsh/mathfunc 2>/dev/null
        zmodload zsh/parameter 2>/dev/null

	typeset -F start_time end_time init_duration
	start_time=${EPOCHREALTIME:-$EPOCHSECONDS}
	z::path::source "${ZCORE_LIBDIR}/platform.zsh"
	z::detect::platform
	z::init::_load_modules
        eval $(starship init zsh)
	end_time=${EPOCHREALTIME:-$EPOCHSECONDS}
	init_duration=$(( end_time - start_time + 0.0 ))
	z::log::info "Zsh initialized in $(printf '%.4f' "$init_duration")s"
}

# Unsets the initialization functions to keep the shell environment clean.
z::init::_cleanup() {
	emulate -L zsh
	unset -f -- z::init::main z::init::_load_modules z::init::_cleanup
}

# --- Main Execution Block ---
if [[ -o interactive ]]; then
	z::init::main
	z::init::_cleanup
fi

# Always succeed when sourced
return 0
