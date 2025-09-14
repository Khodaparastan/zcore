#!/usr/bin/env zsh
#
# Custom Integrations Module
# Handles user-specific aliases, tool integrations, and compatibility stubs.
#

# ==============================================================================
# PRIVATE HELPERS
# ==============================================================================

###
# Sets up general and platform-specific aliases.
###
z::custom::_setup_aliases() {
	emulate -L zsh
	z::runtime::check_interrupted || return $?

	# --- General Aliases ---
	z::alias::define y 'yazi'
	z::alias::define dev 'cd ~/dev'
	z::alias::define zss 'cd ~/.ssh'
	z::alias::define zdd 'cd "${XDG_CONFIG_HOME:-$HOME/.config}"'
	# The alias 'z' is commented out as it conflicts with zoxide's main function.
	# z::alias::define z 'j'
	z::alias::define skr 'ssh-keygen -R'
	z::alias::define sci 'ssh-copy-id -i'
	z::alias::define ssi 'ssh -i'

	# --- Platform-Specific Aliases ---
	local platform_name="unknown"
	if (( IS_MACOS )); then
		platform_name="macOS"
		z::alias::define o 'open'
		z::alias::define clip 'pbcopy'
		if z::cmd::exists "yabai"; then
			z::alias::define ybr 'yabai --restart-service'
		fi
		local surge_cli='/Applications/Surge.app/Contents/Resources/surge-cli'
		if [[ -x "$surge_cli" ]]; then
			z::alias::define surge "$surge_cli"
		fi
	elif (( IS_LINUX )); then
		platform_name="Linux"
		z::alias::define o 'xdg-open'
		if z::cmd::exists "xclip"; then
			z::alias::define clip 'xclip -selection clipboard'
		elif z::cmd::exists "xsel"; then
			z::alias::define clip 'xsel --clipboard --input'
		fi
	elif (( IS_BSD )); then
		platform_name="BSD"
		z::alias::define o 'xdg-open'
		z::cmd::exists "xclip" && z::alias::define clip 'xclip -selection clipboard'
	elif (( IS_CYGWIN )); then
		platform_name="Cygwin"
		z::alias::define o 'cygstart'
		z::alias::define clip 'cat > /dev/clipboard'
	fi

	z::log::debug "Platform-specific aliases configured for: $platform_name"
	return 0
}

###
# Detects and configures the Google Cloud SDK.
###
z::custom::_setup_gcloud() {
	emulate -L zsh
	z::runtime::check_interrupted || return $?

	local gcloud_base
	local -a possible_bases=("$HOME/google-cloud-sdk" "/usr/lib/google-cloud-sdk")
	for base in "${possible_bases[@]}"; do
		[[ -d "$base/bin" ]] && gcloud_base="$base" && break
	done

	if [[ -z "$gcloud_base" ]] && z::cmd::exists "gcloud"; then
		gcloud_base="$(dirname "$(dirname "$(command -v gcloud)")")"
	fi

	if [[ -z "$gcloud_base" || ! -d "$gcloud_base" ]]; then
		z::log::debug "Google Cloud SDK not found."
		return 1
	fi

	z::path::source "$gcloud_base/path.zsh.inc"
	z::path::source "$gcloud_base/completion.zsh.inc"

	if [[ -x "$gcloud_base/gcp-venv/bin/python" ]]; then
		export CLOUDSDK_PYTHON="$gcloud_base/gcp-venv/bin/python"
	elif z::cmd::exists "python3"; then
		export CLOUDSDK_PYTHON="$(command -v python3)"
	fi
	[[ -n "$CLOUDSDK_PYTHON" ]] && z::log::debug "Set CLOUDSDK_PYTHON to: $CLOUDSDK_PYTHON"

	z::log::debug "Google Cloud SDK initialized from: $gcloud_base"
	return 0
}

###
# Sets up core external shell tools like mise and direnv.
###
z::custom::_setup_tools() {
	emulate -L zsh
	z::runtime::check_interrupted || return $?

	if z::cmd::exists "mise"; then
		z::exec::eval "$(mise activate zsh)" 10 true || z::log::warn "Failed to activate mise"
	fi

	if z::cmd::exists "direnv"; then
		z::exec::eval "$(direnv hook zsh)" 10 true || z::log::warn "Failed to install direnv hook"
	fi

	z::log::debug "Core external tools setup completed"
	return 0
}

###
# Creates empty stub functions for optional plugins to prevent errors.
###
z::custom::_create_stubs() {
	emulate -L zsh
	z::runtime::check_interrupted || return $?

	# Stub for a common Git prompt function
	if ! z::func::exists "_git_prompt_info"; then
		_git_prompt_info() { return 0; }
		z::log::debug "Created stub for _git_prompt_info"
	fi

	# Stubs for zconvey scheduler hooks
	local -a zconvey_stubs=("__zconvey_on_period_passed" "__zconvey_on_period_passed"*)
	for func_pattern in "${zconvey_stubs[@]}"; do
		# Check for functions matching the pattern
		if ! z::func::exists "$func_pattern"; then
			# Define a no-op function using a safe, direct method
			"$func_pattern"() { return 0; }
			z::log::debug "Created stub for pattern: $func_pattern"
		fi
	done

	z::log::debug "Stub functions created successfully"
	return 0
}

# ==============================================================================
# MAIN INITIALIZATION ORCHESTRATOR
# ==============================================================================

###
# Public entry point to configure all custom integrations.
###
z::custom::init() {
	emulate -L zsh
	z::runtime::check_interrupted || return $?
	z::log::info "Initializing custom integrations module..."

	z::custom::_setup_aliases
	z::custom::_setup_gcloud
	z::custom::_setup_tools
	# z::custom::_create_stubs

	z::log::info "Custom integrations module initialized successfully."
	return 0
}

# ==============================================================================
# MODULE EXECUTION
# ==============================================================================

# Auto-initialize the module when it is sourced.
if z::func::exists "z::custom::init"; then
	z::custom::init
fi
