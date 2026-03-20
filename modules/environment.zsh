#!/usr/bin/env zsh

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# Internal: Gets stat value in a cross-platform way
# Usage: __z::mod::env::get_stat_value <format> <file>
# Formats: "mtime", "uid", "perms"
__z::mod::env::get_stat_value() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent
	local format="$1" file="$2"
	local result

	case "$format" in
		mtime)
			if (( ${+commands[zstat]} )); then
				result=$(zstat +mtime -- "$file" 2>/dev/null)
			elif [[ "$OSTYPE" == darwin* ]]; then
				result=$(command stat -f %m -- "$file" 2>/dev/null)
			else
				result=$(command stat -c %Y -- "$file" 2>/dev/null)
			fi
			;;
		uid)
			if [[ "$OSTYPE" == darwin* ]]; then
				result=$(command stat -f %u -- "$file" 2>/dev/null)
			else
				result=$(command stat -c %u -- "$file" 2>/dev/null)
			fi
			;;
		perms)
			if [[ "$OSTYPE" == darwin* ]]; then
				result=$(command stat -f %Lp -- "$file" 2>/dev/null)
			else
				result=$(command stat -c %a -- "$file" 2>/dev/null)
			fi
			;;
		*)
			return 1
			;;
	esac

	if [[ -z "$result" ]]; then
		print -r -- "unknown"
		return 1
	fi
	print -r -- "$result"
	return 0
}

# Internal: Gets CPU core count
__z::mod::env::get_cpu_count() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent
	local cores

	if [[ "$OSTYPE" == darwin* ]]; then
		cores=$(sysctl -n hw.ncpu 2>/dev/null)
	else
		cores=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null)
	fi

	# Validate and provide fallback
	if [[ -z "$cores" ]] || ! [[ "$cores" =~ '^[0-9]+$' ]]; then
		cores=2
	fi
	print -r -- "$cores"
}

# ==============================================================================
# PACKAGE MANAGER SETUP
# ==============================================================================

__z::mod::env::setup_package_managers() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent no_unset



	if (( IS_MACOS )) && z::probe::cmd "brew"; then
    z::exec::from_hook brew shellenv
		typeset -gx HOMEBREW_NO_ANALYTICS=1
		typeset -gx HOMEBREW_NO_AUTO_UPDATE=1
		typeset -gx HOMEBREW_NO_INSTALL_CLEANUP=1
		typeset -gx HOMEBREW_BUNDLE_NO_LOCK=1
		typeset -gx HOMEBREW_NO_EMOJI=1
    typeset -gx HOMEBREW_NO_ENV_HINTS=1

		z::log::debug "Homebrew environment variables configured"
	fi

	if z::probe::cmd "apt"; then
		typeset -gx DEBIAN_FRONTEND=noninteractive
		z::log::debug "APT environment configured"
	fi

	if z::probe::cmd "pacman"; then
		typeset -gx PACMAN_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pacman/pkg"
		if [[ ! -d $PACMAN_CACHE_DIR ]]; then
			if mkdir -p -- "$PACMAN_CACHE_DIR" 2>/dev/null; then
				z::log::debug "Created pacman cache directory: $PACMAN_CACHE_DIR"
			else
				z::log::warn "Failed to create pacman cache directory: $PACMAN_CACHE_DIR"
			fi
		fi
		z::log::debug "Pacman environment configured"
	fi
	return 0
}

# ==============================================================================
# XDG DIRECTORY VALIDATION HELPERS
# ==============================================================================

__z::mod::env::xdg_can_modify_dir() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent
	local dir="$1"
	[[ -O "$dir" ]] 2>/dev/null
}

__z::mod::env::xdg_is_system_managed() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent
	local dir="$1"
	local owner_uid

	owner_uid=$(__z::mod::env::get_stat_value uid "$dir")
	[[ "$owner_uid" == "0" || "$owner_uid" == "unknown" ]]
}

__z::mod::env::xdg_has_immutable_attrs() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent
	local dir="$1"

	if [[ "$OSTYPE" == darwin* ]]; then
		local flags
		flags=$(ls -ldO "$dir" 2>/dev/null | awk '{print $5}')
		[[ "$flags" == *"uchg"* || "$flags" == *"schg"* ]]
	else
		local attrs
		attrs=$(lsattr -d "$dir" 2>/dev/null | awk '{print $1}')
		[[ "$attrs" == *"i"* || "$attrs" == *"a"* ]]
	fi
}

__z::mod::env::xdg_is_symlink() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent
	local path="$1"
	[[ -L "$path" ]]
}

__z::mod::env::xdg_is_readonly_fs() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent
	local path="$1"
	local test_file="${path}/.z_test_$$"

	if touch -- "$test_file" 2>/dev/null; then
		rm -f -- "$test_file" 2>/dev/null
		return 1  # not read-only
	fi
	return 0      # read-only
}

# ==============================================================================
# XDG DIRECTORY CREATION
# ==============================================================================

__z::mod::env::create_xdg_dirs() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent no_unset


	if [[ -z ${XDG_CONFIG_HOME:-} || -z ${XDG_DATA_HOME:-} || -z ${XDG_CACHE_HOME:-} || -z ${XDG_STATE_HOME:-} ]]; then
		__z::mod::env::setup_xdg || return 1
	fi

	# Skip permissions modifications as root
	if (( EUID == 0 )); then
		z::log::warn "Running as root, skipping XDG directory permission modifications"
		return 0
	fi

	local -a dirs=(
		# XDG base dirs (readable by others)
		"$XDG_CONFIG_HOME:755"
		"$XDG_DATA_HOME:755"
		"$XDG_CACHE_HOME:755"
		"$XDG_STATE_HOME:755"
		# Zsh-specific (group-readable)
		"$XDG_CONFIG_HOME/zsh:750"
		"$XDG_CACHE_HOME/zsh:750"
		"$XDG_STATE_HOME/zsh:750"
		# SSH config (owner-only)
		"$XDG_CONFIG_HOME/ssh:700"
	)

	local entry dir perm current_perm
	for entry in "${dirs[@]}"; do


		dir="${entry%:*}"
		perm="${entry#*:}"

		if [[ ! -d $dir ]]; then
			if mkdir -p -- "$dir" 2>/dev/null; then
				z::log::debug "Created XDG directory: $dir"
				if chmod "$perm" -- "$dir" 2>/dev/null; then
					z::log::debug "Set permissions $perm on: $dir"
				else
					z::log::debug "Using default permissions on: $dir"
				fi
			else
				z::log::warn "Failed to create XDG directory: $dir"
				continue
			fi
		else
			current_perm=$(__z::mod::env::get_stat_value perms "$dir")

			if [[ "$current_perm" != "unknown" ]] \
			  && __z::mod::env::xdg_can_modify_dir "$dir" \
			  && ! __z::mod::env::xdg_is_system_managed "$dir" \
			  && ! __z::mod::env::xdg_has_immutable_attrs "$dir" \
			  && ! __z::mod::env::xdg_is_symlink "$dir" \
			  && ! __z::mod::env::xdg_is_readonly_fs "$dir"
			then
				# Extract first digit (owner permissions) using zsh syntax
				local current_owner_perm="${current_perm[1]}"
				local target_owner_perm="${perm[1]}"

				# Validate numeric before comparison
				if [[ "$current_owner_perm" =~ '^[0-7]$' ]] && [[ "$target_owner_perm" =~ '^[0-7]$' ]]; then
					if (( current_owner_perm > target_owner_perm )); then
						if chmod "$perm" -- "$dir" 2>/dev/null; then
							z::log::debug "Updated permissions from $current_perm to $perm on: $dir"
						else
							z::log::debug "Using existing permissions $current_perm on: $dir"
						fi
					else
						z::log::debug "Permissions already appropriate ($current_perm) on: $dir"
					fi
				else
					z::log::debug "Using existing permissions $current_perm on: $dir (non-standard format)"
				fi
			elif __z::mod::env::xdg_is_system_managed "$dir"; then
				z::log::debug "Using existing permissions $current_perm on: $dir (system-managed)"
			elif __z::mod::env::xdg_has_immutable_attrs "$dir"; then
				z::log::debug "Using existing permissions $current_perm on: $dir (immutable attributes)"
			elif __z::mod::env::xdg_is_symlink "$dir"; then
				z::log::debug "Using existing permissions $current_perm on: $dir (symlink)"
			elif __z::mod::env::xdg_is_readonly_fs "$dir"; then
				z::log::debug "Using existing permissions $current_perm on: $dir (read-only filesystem)"
			elif [[ "$current_perm" != "unknown" ]]; then
				z::log::debug "Using existing permissions $current_perm on: $dir (not owned by current user)"
			else
				z::log::debug "Using existing permissions on: $dir"
			fi
		fi
	done

	z::log::debug "XDG directory setup completed"

	if [[ ${Z_DEBUG:-0} == 1 ]]; then
		z::log::info "XDG directories configured:"
		z::log::info "  Config: $XDG_CONFIG_HOME"
		z::log::info "  Data:   $XDG_DATA_HOME"
		z::log::info "  Cache:  $XDG_CACHE_HOME"
		z::log::info "  State:  $XDG_STATE_HOME"
	fi
	return 0
}

__z::mod::env::setup_xdg() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent no_unset

	if [[ -z ${HOME:-} ]]; then
		z::log::error "HOME environment variable is not set"
		return 1
	fi

	typeset -gx XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
	typeset -gx XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
	typeset -gx XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
	typeset -gx XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

	z::log::debug "XDG directories configured:"
	z::log::debug "  Config: $XDG_CONFIG_HOME"
	z::log::debug "  Data:   $XDG_DATA_HOME"
	z::log::debug "  Cache:  $XDG_CACHE_HOME"
	z::log::debug "  State:  $XDG_STATE_HOME"
	return 0
}

__z::mod::env::initialize_environment() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent no_unset


	# __z::mod::env::setup_xdg || return 1
	# __z::mod::env::create_xdg_dirs || return 1
	__z::mod::env::setup_package_managers || return 1

		z::log::info "Core environment initialized:"
		z::log::info "  XDG Config: $XDG_CONFIG_HOME"
		z::log::info "  XDG Data:   $XDG_DATA_HOME"
		z::log::info "  XDG Cache:  $XDG_CACHE_HOME"
		z::log::info "  XDG State:  $XDG_STATE_HOME"
		z::log::info "  Homebrew Prefix: ${HOMEBREW_PREFIX:-Not Found}"
		z::log::debug "Core environment initialized successfully"
	return 0
}

# ==============================================================================
# EDITOR SETUP
# ==============================================================================

__z::mod::env::setup_editor() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent no_unset


	local editor_preference

	if z::probe::cmd "nvim"; then
		editor_preference="nvim"
	elif z::probe::cmd "vim"; then
		editor_preference="vim"
	else
		editor_preference="vi"
	fi

	typeset -gx EDITOR="$editor_preference"
	typeset -gx VISUAL="$EDITOR"
	typeset -gx SUDO_EDITOR="$EDITOR"
	typeset -gx GIT_EDITOR="$EDITOR"
	z::log::debug "Editor environment configured: $EDITOR"
	return 0
}
# ==============================================================================
# DEVELOPMENT ENVIRONMENT SETUP
# ==============================================================================

__z::mod::env::setup_development() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent no_unset

	# Go
	if z::probe::cmd "go"; then
		typeset -gx GOPATH="${GOPATH:-$HOME/go}"
		typeset -gx GOBIN="$GOPATH/bin"
		local -a go_dirs=("$GOPATH" "$GOPATH/src" "$GOPATH/bin" "$GOPATH/pkg")
		local d
		for d in "${go_dirs[@]}"; do

			if [[ ! -d $d ]]; then
				if mkdir -p -- "$d" 2>/dev/null; then
					z::log::debug "Created Go directory: $d"
				else
					z::log::warn "Failed to create Go directory: $d"
				fi
			fi
		done
		z::log::debug "Go environment configured: GOPATH=$GOPATH"
	fi

	# Rust
	if z::probe::cmd "cargo" || [[ -d $HOME/.cargo ]]; then
		typeset -gx CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
		typeset -gx RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
		typeset -gx CARGO_INCREMENTAL=1
		typeset -gx RUST_BACKTRACE=1
		z::log::debug "Rust environment configured: CARGO_HOME=$CARGO_HOME"
	fi

	# Node
	if z::probe::cmd "node"; then
		typeset -gx NPM_CONFIG_PREFIX="${NPM_CONFIG_PREFIX:-$HOME/.npm-global}"
		if [[ ! -d $NPM_CONFIG_PREFIX ]]; then
			if mkdir -p -- "$NPM_CONFIG_PREFIX" 2>/dev/null; then
				z::log::debug "Created npm directory: $NPM_CONFIG_PREFIX"
			else
				z::log::warn "Failed to create npm directory: $NPM_CONFIG_PREFIX"
			fi
		fi
		z::log::debug "Node.js environment configured: NPM_CONFIG_PREFIX=$NPM_CONFIG_PREFIX"
	fi

	# Python
	if z::probe::cmd "python3" || z::probe::cmd "python"; then
		typeset -gx PYTHONDONTWRITEBYTECODE=1
		typeset -gx PYTHONUNBUFFERED=1
		typeset -gx PIP_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pip"
		typeset -gx PIPENV_VENV_IN_PROJECT=1
		if [[ ! -d $PIP_CACHE_DIR ]]; then
			if mkdir -p -- "$PIP_CACHE_DIR" 2>/dev/null; then
				z::log::debug "Created pip cache directory: $PIP_CACHE_DIR"
			else
				z::log::warn "Failed to create pip cache directory: $PIP_CACHE_DIR"
			fi
		fi
		z::log::debug "Python environment configured: PIP_CACHE_DIR=$PIP_CACHE_DIR"
	fi

	# Java / Maven
	if z::probe::cmd "java"; then
		# Detect JAVA_HOME if not set
		if [[ -z ${JAVA_HOME:-} ]]; then
			if [[ "$OSTYPE" == darwin* ]] && [[ -x /usr/libexec/java_home ]]; then
				typeset -gx JAVA_HOME="$(/usr/libexec/java_home 2>/dev/null)"
			else
				# Linux: try common paths
				local -a java_paths=(
					"/usr/lib/jvm/default-java"
					"/usr/lib/jvm/java-17-openjdk-amd64"
					"/usr/lib/jvm/java-11-openjdk-amd64"
					"/usr/lib/jvm/java-8-openjdk-amd64"
				)
				local jpath
				for jpath in "${java_paths[@]}"; do

					if [[ -d $jpath ]]; then
						typeset -gx JAVA_HOME="$jpath"
						break
					fi
				done
			fi
		fi

		# Set MAVEN_OPTS with explicit default
		if [[ -z ${MAVEN_OPTS:-} ]]; then
			typeset -gx MAVEN_OPTS="-Xmx1024m -XX:MaxMetaspaceSize=256m"
		fi

		typeset -gx M2_HOME="${M2_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/maven}"
		if [[ ! -d $M2_HOME ]]; then
			if mkdir -p -- "$M2_HOME" 2>/dev/null; then
				z::log::debug "Created Maven directory: $M2_HOME"
			else
				z::log::warn "Failed to create Maven directory: $M2_HOME"
			fi
		fi
		z::log::debug "Java environment configured: JAVA_HOME=${JAVA_HOME:-Not Found}"
	fi

	# Docker
	if z::probe::cmd "docker"; then
		typeset -gx DOCKER_BUILDKIT=1
		typeset -gx COMPOSE_DOCKER_CLI_BUILD=1
		z::log::debug "Docker environment configured"
	fi

	return 0
}

# ==============================================================================
# XDG COMPLIANCE SETUP
# ==============================================================================

__z::mod::env::setup_xdg_compliance() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent no_unset


	local state_dir="$XDG_STATE_HOME"
	local cache_dir="$XDG_CACHE_HOME"
	local config_dir="$XDG_CONFIG_HOME"

	local -a xdg_app_dirs=(
		"$state_dir/zsh" "$cache_dir/zsh" "$config_dir/zsh"
		"$config_dir/git"
		"$config_dir/wget" "$config_dir/curl"
		"$config_dir/less" "$state_dir/less"
		"$cache_dir/pip"
		"$config_dir/maven"
		"$config_dir/readline"
	)

	local d
	for d in "${xdg_app_dirs[@]}"; do

		if [[ -n $d && ! -d $d ]]; then
			if mkdir -p -- "$d" 2>/dev/null; then
				z::log::debug "Created XDG app directory: $d"
			else
				z::log::warn "Failed to create XDG app directory: $d"
			fi
		fi
	done

	# History file with robust fallback and smart permission handling
	local hist_dir="${XDG_STATE_HOME}/zsh"
	local hist_file="${hist_dir}/history"
	local -i hist_dir_created=0

	if [[ ! -d $hist_dir ]]; then
		if mkdir -p -- "$hist_dir" 2>/dev/null; then
			z::log::debug "Created history directory: $hist_dir"
			hist_dir_created=1
		else
			z::log::warn "Failed to create history directory: $hist_dir"
			hist_dir="$HOME"
			hist_file="$hist_dir/.zsh_history"
			z::log::info "Using fallback history location: $hist_file"
		fi
	fi

	# Only attempt chmod if we created the directory or permissions are wrong
	if [[ -d $hist_dir && $hist_dir != "$HOME" ]]; then
		local current_perms
		current_perms=$(__z::mod::env::get_stat_value perms "$hist_dir" 2>/dev/null)

		if [[ "$current_perms" == "700" ]]; then
			z::log::debug "History directory permissions already correct (700): $hist_dir"
		elif (( hist_dir_created )) || [[ "$current_perms" != "700" && "$current_perms" != "unknown" ]]; then
			# Only try to chmod if we just created it or permissions are known but wrong
			if chmod 700 -- "$hist_dir" 2>/dev/null; then
				z::log::debug "Set permissions 700 on history directory: $hist_dir"
			else
				# Check if we own the directory
				if [[ -O "$hist_dir" ]]; then
					z::log::debug "Could not modify permissions on history directory: $hist_dir (possibly restricted filesystem)"
				else
					z::log::debug "History directory not owned by current user, skipping permission change: $hist_dir"
				fi
			fi
		elif [[ "$current_perms" == "unknown" ]]; then
			# Can't determine current permissions, try anyway
			if chmod 700 -- "$hist_dir" 2>/dev/null; then
				z::log::debug "Set permissions 700 on history directory: $hist_dir"
			else
				z::log::debug "Could not determine or modify permissions on history directory: $hist_dir"
			fi
		fi
	fi

	typeset -gx HISTFILE="$hist_file"

	# Other history/state files
	typeset -gx NODE_REPL_HISTORY="$XDG_STATE_HOME/zsh/node_repl_history"
	typeset -gx PYTHON_HISTORY="$XDG_STATE_HOME/zsh/python_history"
	typeset -gx PYTHONHISTFILE="$PYTHON_HISTORY"
	typeset -gx SQLITE_HISTORY="$XDG_STATE_HOME/zsh/sqlite_history"
	typeset -gx MYSQL_HISTFILE="$XDG_STATE_HOME/zsh/mysql_history"
	typeset -gx PSQL_HISTORY="$XDG_STATE_HOME/zsh/psql_history"
	typeset -gx REDISCLI_HISTFILE="$XDG_STATE_HOME/zsh/redis_history"

	typeset -gx LESSHISTFILE="$XDG_STATE_HOME/less/history"
	typeset -gx WGETRC="$XDG_CONFIG_HOME/wget/wgetrc"
	typeset -gx CURL_HOME="$XDG_CONFIG_HOME/curl"
	typeset -gx INPUTRC="$XDG_CONFIG_HOME/readline/inputrc"

	typeset -gx GIT_CONFIG_GLOBAL="$XDG_CONFIG_HOME/git/config"
	z::log::debug "XDG compliance configured"
	return 0
}

# ==============================================================================
# SECURITY SETUP
# ==============================================================================


__z::mod::env::setup_security() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent no_unset

	if z::probe::cmd "gpg" || z::probe::cmd "gpg2"; then
		typeset -gx GNUPGHOME="${XDG_DATA_HOME:-$HOME/.local/share}/gnupg"
		local -i gnupg_created=0

		if [[ ! -d $GNUPGHOME ]]; then
			if mkdir -p -m 700 -- "$GNUPGHOME" 2>/dev/null; then
				z::log::debug "Created GPG directory: $GNUPGHOME"
				gnupg_created=1
			else
				z::log::warn "Failed to create GPG directory: $GNUPGHOME"
			fi
		fi

		# Only attempt chmod if we just created it or permissions are wrong
		if [[ -d $GNUPGHOME ]]; then
			local current_perms
			current_perms=$(__z::mod::env::get_stat_value perms "$GNUPGHOME" 2>/dev/null)

			if [[ "$current_perms" == "700" ]]; then
				z::log::debug "GPG directory permissions already correct (700): $GNUPGHOME"
			elif (( gnupg_created )) || [[ "$current_perms" != "700" && "$current_perms" != "unknown" ]]; then
				# Only try to chmod if we just created it or permissions are known but wrong
				if chmod 700 -- "$GNUPGHOME" 2>/dev/null; then
					z::log::debug "Set permissions 700 on GPG directory: $GNUPGHOME"
				else
					# Check if we own the directory
					if [[ -O "$GNUPGHOME" ]]; then
						z::log::debug "Could not modify permissions on GPG directory: $GNUPGHOME (possibly restricted filesystem)"
					else
						z::log::debug "GPG directory not owned by current user, skipping permission change: $GNUPGHOME"
					fi
				fi
			elif [[ "$current_perms" == "unknown" ]]; then
				# Can't determine current permissions, try anyway
				if chmod 700 -- "$GNUPGHOME" 2>/dev/null; then
					z::log::debug "Set permissions 700 on GPG directory: $GNUPGHOME"
				else
					z::log::debug "Could not determine or modify permissions on GPG directory: $GNUPGHOME"
				fi
			fi
		fi

		# Set GPG_TTY if interactive
		if [[ -t 0 ]]; then
			typeset -gx GPG_TTY="$(tty 2>/dev/null || print '/dev/tty')"
		fi

		z::log::debug "GPG environment configured: GNUPGHOME=$GNUPGHOME"
	fi
	return 0
}

# ==============================================================================
# PERFORMANCE SETUP
# ==============================================================================

__z::mod::env::setup_performance() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent no_unset

	if z::probe::cmd "make"; then
		local cores
		cores=$(__z::mod::env::get_cpu_count)
		typeset -gx MAKEFLAGS="-j${cores}"
		z::log::debug "Performance environment configured: MAKEFLAGS=$MAKEFLAGS"
	fi
	return 0
}

# ==============================================================================
# TERMINAL SETUP
# ==============================================================================

__z::mod::env::setup_terminal() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent no_unset

	typeset -gx LANG="${LANG:-en_US.UTF-8}"
	typeset -gx LC_ALL="${LC_ALL:-$LANG}"
	typeset -gx TERM="${TERM:-xterm-256color}"
	typeset -gx COLORTERM="${COLORTERM:-truecolor}"

	if z::probe::cmd "less"; then
		typeset -gx PAGER="less"
		typeset -gx LESS="-R -Si -M -j.5"

		if z::probe::cmd "lesspipe.sh"; then
			typeset -gx LESSOPEN="|lesspipe.sh %s"
		elif z::probe::cmd "src-hilite-lesspipe.sh"; then
			typeset -gx LESSOPEN="|src-hilite-lesspipe.sh %s"
			typeset -gx LESSCOLOR=always
		elif z::probe::cmd "pygmentize"; then
			typeset -gx LESSCOLORIZER=pygmentize
		fi
	fi

	typeset -gx LESS_TERMCAP_mb=$'\e[1;32m'
	typeset -gx LESS_TERMCAP_md=$'\e[1;36m'
	typeset -gx LESS_TERMCAP_me=$'\e[0m'
	typeset -gx LESS_TERMCAP_so=$'\e[01;44;33m'
	typeset -gx LESS_TERMCAP_se=$'\e[0m'
	typeset -gx LESS_TERMCAP_us=$'\e[1;4;31m'
	typeset -gx LESS_TERMCAP_ue=$'\e[0m'

	z::log::debug "Terminal environment configured: LANG=$LANG, TERM=$TERM"
	return 0
}

# ==============================================================================
# CLOUD ENVIRONMENT SETUP
# ==============================================================================

__z::mod::env::setup_cloud() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent no_unset



	if z::probe::cmd "aws"; then
		typeset -gx AWS_CLI_AUTO_PROMPT=on-partial
		typeset -gx AWS_PAGER=""
		z::log::debug "AWS environment configured"
	fi

	if z::probe::cmd "terraform"; then
		local cores
		cores=$(__z::mod::env::get_cpu_count)
		typeset -gx TF_CLI_ARGS_plan="-parallelism=${cores}"
		typeset -gx TF_CLI_ARGS_apply="-parallelism=${cores}"
		z::log::debug "Terraform environment configured: parallelism=$cores"
	fi

	if z::probe::cmd "kubectl" && z::probe::cmd "delta"; then
		typeset -gx KUBECTL_EXTERNAL_DIFF="delta --syntax-highlight --paging=never"
		z::log::debug "Kubernetes environment configured"
	fi
	return 0
}

# ==============================================================================
# MODULE INITIALIZATION
# ==============================================================================

__z::mod::env::init() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent no_unset


	z::log::info "Initializing core environment..."
	__z::mod::env::setup_editor        || return $?
	# __z::mod::env::initialize_environment || return $?
	__z::mod::env::setup_development   || return $?
	__z::mod::env::setup_xdg_compliance            || return $?
	__z::mod::env::setup_security      || return $?
	__z::mod::env::setup_performance   || return $?
	__z::mod::env::setup_terminal      || return $?
	__z::mod::env::setup_cloud         || return $?
	z::log::info "Core environment initialized successfully."
	return 0
}

if z::probe::func "__z::mod::env::init"; then
	__z::mod::env::init
fi
