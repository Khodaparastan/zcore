#!/usr/bin/env zsh
#
# External Tools Configuration Module
# Handles initialization of external tools and development utilities
#

# ==============================================================================
# EXTERNAL TOOLS SETUP
# ==============================================================================

# Internal helper: command existence (prefers zcore cache if available)
_ext::_cmd_exists() {
	emulate -L zsh -o no_aliases
	if typeset -f z::cmd::exists >/dev/null 2>&1; then
		z::cmd::exists "$1"
		return $?
	fi
	command -v "$1" >/dev/null 2>&1
}

###
# Sets up various external development tools and their integrations
###
_setup_external_tools() {
	emulate -L zsh -o no_aliases

	z::runtime::check_interrupted || return $?
	z::log::debug "Setting up external tools..."

	# Tool initialization functions
	local -a tools=(
		"_setup_direnv"
		"_setup_mise"
		"_setup_zoxide"
		"_setup_atuin"
		"_setup_mcfly"
		"_setup_fzf"
	)

	local tool
	for tool in "${tools[@]}"; do
		z::runtime::check_interrupted || return $?
		if typeset -f "$tool" >/dev/null 2>&1; then
			z::func::call "$tool"
		else
			z::log::debug "Tool setup function '$tool' not defined, skipping"
		fi
	done

	z::log::debug "External tools setup completed"
	return 0
}

###
# Initialize direnv for automatic environment loading
###
_setup_direnv() {
	emulate -L zsh -o no_aliases
	z::runtime::check_interrupted || return $?

	if ! _ext::_cmd_exists direnv; then
		z::log::debug "direnv not found, skipping"
		return 0
	fi

	local direnv_init_code
	if direnv_init_code="$(direnv hook zsh 2>/dev/null)" && [[ -n "$direnv_init_code" ]]; then
		if z::exec::eval "$direnv_init_code" 30 true; then
			z::log::debug "direnv initialized successfully"
		else
			z::log::warn "Failed to initialize direnv"
			return 1
		fi
	else
		z::log::warn "Failed to get direnv hook"
		return 1
	fi

	return 0
}

###
# Initialize mise (formerly rtx) for runtime version management
###
_setup_mise() {
	emulate -L zsh -o no_aliases
	z::runtime::check_interrupted || return $?

	if ! _ext::_cmd_exists mise; then
		z::log::debug "mise not found, skipping"
		return 0
	fi

	local mise_init_code
	if mise_init_code="$(mise activate zsh 2>/dev/null)" && [[ -n "$mise_init_code" ]]; then
		if z::exec::eval "$mise_init_code" 30 true; then
			z::log::debug "mise initialized successfully"
		else
			z::log::warn "Failed to initialize mise"
			return 1
		fi
	else
		z::log::warn "Failed to get mise activation code"
		return 1
	fi

	return 0
}

###
# Initialize zoxide for smart directory jumping
###
_setup_zoxide() {
	emulate -L zsh -o no_aliases
	z::runtime::check_interrupted || return $?

	if ! _ext::_cmd_exists zoxide; then
		z::log::debug "zoxide not found, skipping"
		return 0
	fi

	local zoxide_init_code
	if zoxide_init_code="$(zoxide init zsh 2>/dev/null)" && [[ -n "$zoxide_init_code" ]]; then
		if z::exec::eval "$zoxide_init_code" 30 true; then
			z::log::debug "zoxide initialized successfully"
		else
			z::log::warn "Failed to initialize zoxide"
			return 1
		fi
	else
		z::log::warn "Failed to get zoxide init code"
		return 1
	fi

	return 0
}

###
# Initialize atuin for shell history sync and search
###
_setup_atuin() {
	emulate -L zsh -o no_aliases
	z::runtime::check_interrupted || return $?

	if ! _ext::_cmd_exists atuin; then
		z::log::debug "atuin not found, skipping"
		return 0
	fi

	local atuin_init_code
	if atuin_init_code="$(atuin init zsh 2>/dev/null)" && [[ -n "$atuin_init_code" ]]; then
		if z::exec::eval "$atuin_init_code" 30 true; then
			z::log::debug "atuin initialized successfully"
		else
			z::log::warn "Failed to initialize atuin"
			return 1
		fi
	else
		z::log::warn "Failed to get atuin init code"
		return 1
	fi

	return 0
}

###
# Initialize mcfly for shell history search
###
_setup_mcfly() {
	emulate -L zsh -o no_aliases
	z::runtime::check_interrupted || return $?

	if ! _ext::_cmd_exists mcfly; then
		z::log::debug "mcfly not found, skipping"
		return 0
	fi

	local mcfly_init_code
	if mcfly_init_code="$(mcfly init zsh 2>/dev/null)" && [[ -n "$mcfly_init_code" ]]; then
		if z::exec::eval "$mcfly_init_code" 30 true; then
			z::log::debug "mcfly initialized successfully"
		else
			z::log::warn "Failed to initialize mcfly"
			return 1
		fi
	else
		z::log::warn "Failed to get mcfly init code"
		return 1
	fi

	return 0
}

###
# Initialize fzf for fuzzy finding
###
_setup_fzf() {
	emulate -L zsh -o no_aliases
	z::runtime::check_interrupted || return $?

	if ! _ext::_cmd_exists fzf; then
		z::log::debug "fzf not found, skipping"
		return 0
	fi

	# Candidate paths for fzf zsh integration files (key-bindings and completion)
	local -a fzf_key_paths=(
		"/usr/share/fzf/key-bindings.zsh"
		"/opt/homebrew/share/fzf/shell/key-bindings.zsh"
		"/usr/local/opt/fzf/shell/key-bindings.zsh"
		"${HOME}/.fzf/shell/key-bindings.zsh"
	)
	local -a fzf_comp_paths=(
		"/usr/share/fzf/completion.zsh"
		"/opt/homebrew/share/fzf/shell/completion.zsh"
		"/usr/local/opt/fzf/shell/completion.zsh"
		"${HOME}/.fzf/shell/completion.zsh"
	)

	# Source at most one key-bindings file and one completion file
	local fzf_file
	for fzf_file in "${fzf_key_paths[@]}"; do
		[[ -f "$fzf_file" ]] || continue
		if z::path::source "$fzf_file"; then
			z::log::debug "Loaded fzf key-bindings: $fzf_file"
			break
		else
			z::log::warn "Failed to load fzf key-bindings: $fzf_file"
		fi
	done
	for fzf_file in "${fzf_comp_paths[@]}"; do
		[[ -f "$fzf_file" ]] || continue
		if z::path::source "$fzf_file"; then
			z::log::debug "Loaded fzf completion: $fzf_file"
			break
		else
			z::log::warn "Failed to load fzf completion: $fzf_file"
		fi
	done

	# Set up common fzf environment variables:
	# - Modernize --inline-info -> --info=inline
	# - Append to existing FZF_DEFAULT_OPTS instead of overwriting
	local base_opts="--height 40% --layout=reverse --border --info=inline"
	if [[ -n ${FZF_DEFAULT_OPTS:-} ]]; then
		export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS} ${base_opts}"
	else
		export FZF_DEFAULT_OPTS="${base_opts}"
	fi

	# Use fd or ripgrep if available; respect existing user settings
	if [[ -z ${FZF_DEFAULT_COMMAND:-} ]]; then
		if _ext::_cmd_exists fd; then
			export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
			export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
		elif _ext::_cmd_exists rg; then
			export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*"'
			export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
		fi
	fi

	z::log::debug "fzf setup completed"
	return 0
}

###
# Initialize Google Cloud SDK if installed
###
_setup_gcloud_sdk() {
	emulate -L zsh -o no_aliases
	z::runtime::check_interrupted || return $?

	z::log::debug "Setting up Google Cloud SDK..."

	# Common gcloud installation paths
	local -a gcloud_paths=(
		"${HOME}/google-cloud-sdk"
		"/opt/google-cloud-sdk"
		"/usr/lib/google-cloud-sdk"
		"/usr/local/share/google-cloud-sdk"
		"/opt/homebrew/share/google-cloud-sdk"
	)

	local gcloud_path gcloud_completion gcloud_path_script
	for gcloud_path in "${gcloud_paths[@]}"; do
		[[ -d "$gcloud_path" ]] || continue
		z::log::debug "Found Google Cloud SDK at: $gcloud_path"

		# Source the path script
		gcloud_path_script="${gcloud_path}/path.zsh.inc"
		if [[ -f "$gcloud_path_script" ]]; then
			if z::path::source "$gcloud_path_script"; then
				z::log::debug "Loaded gcloud path script"
			else
				z::log::warn "Failed to load gcloud path script"
			fi
		fi

		# Source the completion script
		gcloud_completion="${gcloud_path}/completion.zsh.inc"
		if [[ -f "$gcloud_completion" ]]; then
			if z::path::source "$gcloud_completion"; then
				z::log::debug "Loaded gcloud completion"
			else
				z::log::warn "Failed to load gcloud completion"
			fi
		fi

		z::log::info "Google Cloud SDK initialized from: $gcloud_path"
		return 0
	done

	# Check if gcloud is available in PATH but we couldn't find the SDK directory
	if _ext::_cmd_exists gcloud; then
		z::log::info "gcloud command found in PATH but SDK directory not located"
		return 0
	fi

	z::log::debug "Google Cloud SDK not found"
	return 0
}

###
# Setup Docker completion if available
###
_setup_docker() {
	emulate -L zsh -o no_aliases
	z::runtime::check_interrupted || return $?

	if ! _ext::_cmd_exists docker; then
		z::log::debug "docker not found, skipping"
		return 0
	fi

	# Docker completion is usually handled by the system package manager
	# or completions module, but we can add any Docker-specific setup here
	z::log::debug "docker found and available"
	return 0
}

###
# Setup kubectl completion
###
_setup_kubectl() {
	emulate -L zsh -o no_aliases
	z::runtime::check_interrupted || return $?

	if ! _ext::_cmd_exists kubectl; then
		z::log::debug "kubectl not found, skipping"
		return 0
	fi

	# kubectl completion is typically handled in completions module
	# but we can add kubectl-specific aliases or setup here
	z::log::debug "kubectl found and available"
	return 0
}

# Export functions that should be available after module load
typeset -f _setup_external_tools _setup_gcloud_sdk >/dev/null 2>&1 || {
	z::log::error "Failed to define external tools functions"
	return 1
}

# Auto-initialize external tools when module is loaded
_setup_external_tools
_setup_gcloud_sdk

z::log::debug "External tools module loaded"
