#!/usr/bin/env zsh

# Package managers and environment initialization helpers

_setup_package_managers() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent no_unset

	z::runtime::check_interrupted || return $?

	if (( IS_MACOS )) && command -v brew >/dev/null 2>&1; then
		typeset -gx HOMEBREW_NO_ANALYTICS=1
		typeset -gx HOMEBREW_NO_AUTO_UPDATE=1
		typeset -gx HOMEBREW_NO_INSTALL_CLEANUP=1
		typeset -gx HOMEBREW_BUNDLE_NO_LOCK=1
		typeset -gx HOMEBREW_NO_EMOJI=1
		z::log::debug "Homebrew environment variables configured"
	fi

	if command -v apt >/dev/null 2>&1; then
		typeset -gx DEBIAN_FRONTEND=noninteractive
		z::log::debug "APT environment configured"
	fi

	if command -v pacman >/dev/null 2>&1; then
		typeset -gx PACMAN_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pacman/pkg"
		if [[ ! -d $PACMAN_CACHE_DIR ]]; then
			if mkdir -p "$PACMAN_CACHE_DIR" 2>/dev/null; then
				z::log::debug "Created pacman cache directory: $PACMAN_CACHE_DIR"
			else
				z::log::warn "Failed to create pacman cache directory: $PACMAN_CACHE_DIR"
			fi
		fi
		z::log::debug "Pacman environment configured"
	fi
	return 0
}

# ----- XDG helper functions (moved out of _create_xdg_dirs) -----

_xdg_can_modify_dir() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent
	local dir="$1"
	[[ -O "$dir" ]] 2>/dev/null
}

_xdg_is_system_managed() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent
	local dir="$1"
	# macOS: stat -f; Linux: stat -c; fallback: unknown
	local owner_uid
	owner_uid=$(stat -f "%u" "$dir" 2>/dev/null || stat -c "%u" "$dir" 2>/dev/null || print -r -- "unknown")
	[[ "$owner_uid" == "0" || "$owner_uid" == "unknown" ]]
}

_xdg_has_immutable_attrs() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent
	local dir="$1"
	if [[ "$OSTYPE" == darwin* ]]; then
		local flags
		flags=$(ls -ldO "$dir" 2>/dev/null | awk '{print $5}' || print -r -- "")
		[[ "$flags" == *"uchg"* || "$flags" == *"schg"* ]]
	else
		local attrs
		attrs=$(lsattr -d "$dir" 2>/dev/null | awk '{print $1}' || print -r -- "")
		[[ "$attrs" == *"i"* || "$attrs" == *"a"* ]]
	fi
}

_xdg_is_symlink() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent
	local path="$1"
	[[ -L "$path" ]]
}

_xdg_is_readonly_fs() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent
	local path="$1"
	local test_file="${path}/.zcore_test_$$"
	if touch "$test_file" 2>/dev/null; then
		rm -f "$test_file" 2>/dev/null
		return 1  # not read-only
	fi
	return 0      # read-only
}

# ----- Create XDG directories with permissions -----

_create_xdg_dirs() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent no_unset

	z::runtime::check_interrupted || return $?

	# Ensure XDG variables are set
	if [[ -z $XDG_CONFIG_HOME || -z $XDG_DATA_HOME || -z $XDG_CACHE_HOME || -z $XDG_STATE_HOME ]]; then
		_setup_xdg || return 1
	fi

	# Skip permissions modifications as root
	if [[ $EUID -eq 0 ]]; then
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
		z::runtime::check_interrupted || return $?

		dir="${entry%:*}"
		perm="${entry#*:}"

		if [[ ! -d $dir ]]; then
			if mkdir -p "$dir" 2>/dev/null; then
				z::log::debug "Created XDG directory: $dir"
				if chmod "$perm" "$dir" 2>/dev/null; then
					z::log::debug "Set permissions $perm on: $dir"
				else
					z::log::debug "Using default permissions on: $dir"
				fi
			else
				z::log::warn "Failed to create XDG directory: $dir"
				continue
			fi
		else
			current_perm=$(stat -f "%Lp" "$dir" 2>/dev/null || stat -c "%a" "$dir" 2>/dev/null || print -r -- "unknown")

			if [[ "$current_perm" != "unknown" ]] \
			  && _xdg_can_modify_dir "$dir" \
			  && ! _xdg_is_system_managed "$dir" \
			  && ! _xdg_has_immutable_attrs "$dir" \
			  && ! _xdg_is_symlink "$dir" \
			  && ! _xdg_is_readonly_fs "$dir"
			then
				local current_owner_perm="${current_perm:0:1}"
				local target_owner_perm="${perm:0:1}"
				if (( current_owner_perm > target_owner_perm )); then
					if chmod "$perm" "$dir" 2>/dev/null; then
						z::log::debug "Updated permissions from $current_perm to $perm on: $dir"
					else
						z::log::debug "Using existing permissions $current_perm on: $dir"
					fi
				else
					z::log::debug "Permissions already appropriate ($current_perm) on: $dir"
				fi
			elif _xdg_is_system_managed "$dir"; then
				z::log::debug "Using existing permissions $current_perm on: $dir (system-managed)"
			elif _xdg_has_immutable_attrs "$dir"; then
				z::log::debug "Using existing permissions $current_perm on: $dir (immutable attributes)"
			elif _xdg_is_symlink "$dir"; then
				z::log::debug "Using existing permissions $current_perm on: $dir (symlink)"
			elif _xdg_is_readonly_fs "$dir"; then
				z::log::debug "Using existing permissions $current_perm on: $dir (read-only filesystem)"
			elif [[ "$current_perm" != "unknown" ]]; then
				z::log::debug "Using existing permissions $current_perm on: $dir (not owned by current user)"
			else
				z::log::debug "Using existing permissions on: $dir"
			fi
		fi
	done

	z::log::debug "XDG directory setup completed"

	if [[ ${ZCORE_DEBUG:-0} == 1 ]]; then
		z::log::info "XDG directories configured:"
		z::log::info "  Config: $XDG_CONFIG_HOME"
		z::log::info "  Data:   $XDG_DATA_HOME"
		z::log::info "  Cache:  $XDG_CACHE_HOME"
		z::log::info "  State:  $XDG_STATE_HOME"
	fi
	return 0
}

_setup_xdg() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent no_unset

	z::runtime::check_interrupted || return $?

	if [[ -z $HOME ]]; then
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

_initialize_environment() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent no_unset

	z::runtime::check_interrupted || return $?

	_setup_xdg || return 1
	# _create_xdg_dirs
	_setup_package_managers || return 1

	if [[ ${ZCORE_DEBUG:-0} == 1 ]]; then
		z::log::info "Core environment initialized:"
		z::log::info "  XDG Config: $XDG_CONFIG_HOME"
		z::log::info "  XDG Data:   $XDG_DATA_HOME"
		z::log::info "  XDG Cache:  $XDG_CACHE_HOME"
		z::log::info "  XDG State:  $XDG_STATE_HOME"
		z::log::info "  Homebrew Prefix: ${HOMEBREW_PREFIX:-Not Found}"
	else
		z::log::debug "Core environment initialized successfully"
	fi
	return 0
}

zcore_safe_exec() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent

	local cmd="$1"
	[[ $# -eq 0 ]] && return 1
	shift

	if command -v "$cmd" >/dev/null 2>&1; then
		command "$cmd" "$@"
		return $?
	fi

	z::log::debug "Command not found: $cmd"
	return 127
}

_check_network() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent no_unset

	z::runtime::check_interrupted || return $?

	local timeout="${1:-2}"
	local -a endpoints=(
		"https://1.1.1.1"
		"https://api.github.com/zen"
		"https://httpbin.org/status/200"
	)

	if ! command -v curl >/dev/null 2>&1; then
		z::log::debug "curl not available for network check"
		return 1
	fi

	local endpoint
	for endpoint in "${endpoints[@]}"; do
		z::runtime::check_interrupted || return $?
		if command curl -fsSL --connect-timeout "$timeout" --max-time $((timeout + 1)) \
		  --retry 1 --retry-delay 0 "$endpoint" >/dev/null 2>&1
		then
			z::log::debug "Network check successful via: $endpoint"
			return 0
		fi
	done

	z::log::debug "Network check failed for all endpoints"
	return 1
}

# ----- Environment setup helpers (moved out of _setup_environment) -----

_setup_editor_environment() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent no_unset

	z::runtime::check_interrupted || return $?

	local editor_preference

	if (( ${+SSH_CONNECTION} )); then
		if command -v vim >/dev/null 2>&1; then
			editor_preference="vim"
		elif command -v vi >/dev/null 2>&1; then
			editor_preference="vi"
		else
			editor_preference="vi"
		fi
	else
		if command -v nvim >/dev/null 2>&1; then
			editor_preference="nvim"
		elif command -v vim >/dev/null 2>&1; then
			editor_preference="vim"
		elif command -v vi >/dev/null 2>&1; then
			editor_preference="vi"
		else
			editor_preference="vi"
		fi
	fi

	typeset -gx EDITOR="$editor_preference"
	typeset -gx VISUAL="$EDITOR"
	typeset -gx SUDO_EDITOR="$EDITOR"
	typeset -gx GIT_EDITOR="$EDITOR"
	z::log::debug "Editor environment configured: $EDITOR"
	return 0
}


_setup_development_environment() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent no_unset

	z::runtime::check_interrupted || return $?

	# Go
	if command -v go >/dev/null 2>&1; then
		typeset -gx GOPATH="${GOPATH:-$HOME/go}"
		typeset -gx GOBIN="$GOPATH/bin"
		local -a go_dirs=("$GOPATH" "$GOPATH/src" "$GOPATH/bin" "$GOPATH/pkg")
		local d
		for d in "${go_dirs[@]}"; do
			z::runtime::check_interrupted || return $?
			if [[ ! -d $d ]]; then
				if mkdir -p "$d" 2>/dev/null; then
					z::log::debug "Created Go directory: $d"
				else
					z::log::warn "Failed to create Go directory: $d"
				fi
			fi
		done
		z::log::debug "Go environment configured: GOPATH=$GOPATH"
	fi

	# Rust
	if command -v cargo >/dev/null 2>&1 || [[ -d $HOME/.cargo ]]; then
		typeset -gx CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
		typeset -gx RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
		typeset -gx CARGO_INCREMENTAL=1
		typeset -gx RUST_BACKTRACE=1
		z::log::debug "Rust environment configured: CARGO_HOME=$CARGO_HOME"
	fi

	# Node
	if command -v node >/dev/null 2>&1; then
		typeset -gx NPM_CONFIG_PREFIX="${NPM_CONFIG_PREFIX:-$HOME/.npm-global}"
		if [[ ! -d $NPM_CONFIG_PREFIX ]]; then
			if mkdir -p "$NPM_CONFIG_PREFIX" 2>/dev/null; then
				z::log::debug "Created npm directory: $NPM_CONFIG_PREFIX"
			else
				z::log::warn "Failed to create npm directory: $NPM_CONFIG_PREFIX"
			fi
		fi
		z::log::debug "Node.js environment configured: NPM_CONFIG_PREFIX=$NPM_CONFIG_PREFIX"
	fi

	# Python
	if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
		typeset -gx PYTHONDONTWRITEBYTECODE=1
		typeset -gx PYTHONUNBUFFERED=1
		typeset -gx PIP_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pip"
		typeset -gx PIPENV_VENV_IN_PROJECT=1
		if [[ ! -d $PIP_CACHE_DIR ]]; then
			if mkdir -p "$PIP_CACHE_DIR" 2>/dev/null; then
				z::log::debug "Created pip cache directory: $PIP_CACHE_DIR"
			else
				z::log::warn "Failed to create pip cache directory: $PIP_CACHE_DIR"
			fi
		fi
		z::log::debug "Python environment configured: PIP_CACHE_DIR=$PIP_CACHE_DIR"
	fi

	# Java / Maven
	if command -v java >/dev/null 2>&1; then
		# Guard JAVA_HOME under no_unset
		if [[ -z ${JAVA_HOME:-} ]]; then
			if (( IS_MACOS )) && [[ -x /usr/libexec/java_home ]]; then
				typeset -gx JAVA_HOME="$(/usr/libexec/java_home 2>/dev/null)"
			elif (( IS_LINUX )); then
				local -a java_paths=(
					"/usr/lib/jvm/default-java"
					"/usr/lib/jvm/java-17-openjdk-amd64"
					"/usr/lib/jvm/java-11-openjdk-amd64"
					"/usr/lib/jvm/java-8-openjdk-amd64"
				)
				local jpath
				for jpath in "${java_paths[@]}"; do
					z::runtime::check_interrupted || return $?
					if [[ -d $jpath ]]; then
						typeset -gx JAVA_HOME="$jpath"
						break
					fi
				done
			fi
		fi

		typeset -gx MAVEN_OPTS="${MAVEN_OPTS:--Xmx1024m -XX:MaxMetaspaceSize=256m}"
		typeset -gx M2_HOME="${M2_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/maven}"
		if [[ ! -d $M2_HOME ]]; then
			if mkdir -p "$M2_HOME" 2>/dev/null; then
				z::log::debug "Created Maven directory: $M2_HOME"
			else
				z::log::warn "Failed to create Maven directory: $M2_HOME"
			fi
		fi
		z::log::debug "Java environment configured: JAVA_HOME=${JAVA_HOME:-Not Found}"
	fi

	# Docker
	if command -v docker >/dev/null 2>&1; then
		typeset -gx DOCKER_BUILDKIT=1
		typeset -gx COMPOSE_DOCKER_CLI_BUILD=1
		z::log::debug "Docker environment configured"
	fi

	return 0
}
_setup_xdg_compliance() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent no_unset

	z::runtime::check_interrupted || return $?

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
		z::runtime::check_interrupted || return $?
		if [[ -n $d && ! -d $d ]]; then
			if mkdir -p "$d" 2>/dev/null; then
				z::log::debug "Created XDG app directory: $d"
			else
				z::log::warn "Failed to create XDG app directory: $d"
			fi
		fi
	done

	# History file with robust fallback
	local hist_dir="${XDG_STATE_HOME}/zsh"
	local hist_file="${hist_dir}/history"

	if [[ ! -d "$hist_dir" ]]; then
		if mkdir -p "$hist_dir" 2>/dev/null; then
			z::log::debug "Created history directory: $hist_dir"
			if chmod 700 "$hist_dir" 2>/dev/null; then
				z::log::debug "Set permissions on history directory: $hist_dir"
			else
				z::log::debug "Could not set permissions on history directory: $hist_dir (continuing)"
			fi
		else
			z::log::warn "Failed to create history directory: $hist_dir"
			hist_dir="$HOME"
			hist_file="$hist_dir/.zsh_history"
			z::log::info "Using fallback history location: $hist_file"
		fi
	else
		if chmod 700 "$hist_dir" 2>/dev/null; then
			z::log::debug "Set permissions on history directory: $hist_dir"
		else
			z::log::debug "Could not set permissions on history directory: $hist_dir (continuing)"
		fi
	fi

	typeset -gx HISTFILE="$hist_file"

	# Other history/state files
	typeset -gx NODE_REPL_HISTORY="$XDG_STATE_HOME/node_repl_history"
	typeset -gx PYTHON_HISTORY="$XDG_STATE_HOME/python_history"
	typeset -gx PYTHONHISTFILE="$PYTHON_HISTORY"
	typeset -gx SQLITE_HISTORY="$XDG_STATE_HOME/sqlite_history"
	typeset -gx MYSQL_HISTFILE="$XDG_STATE_HOME/mysql_history"
	typeset -gx PSQL_HISTORY="$XDG_STATE_HOME/psql_history"
	typeset -gx REDISCLI_HISTFILE="$XDG_STATE_HOME/redis_history"

	typeset -gx LESSHISTFILE="$XDG_STATE_HOME/less/history"
	typeset -gx WGETRC="$XDG_CONFIG_HOME/wget/wgetrc"
	typeset -gx CURL_HOME="$XDG_CONFIG_HOME/curl"
	typeset -gx INPUTRC="$XDG_CONFIG_HOME/readline/inputrc"

	typeset -gx GIT_CONFIG_GLOBAL="$XDG_CONFIG_HOME/git/config"
	z::log::debug "XDG compliance configured"
	return 0
}

_setup_security_environment() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent no_unset

	z::runtime::check_interrupted || return $?

	if command -v gpg >/dev/null 2>&1 || command -v gpg2 >/dev/null 2>&1; then
		typeset -gx GNUPGHOME="${XDG_DATA_HOME:-$HOME/.local/share}/gnupg"
		if [[ ! -d $GNUPGHOME ]]; then
			if mkdir -p -m 700 "$GNUPGHOME" 2>/dev/null; then
				z::log::debug "Created GPG directory: $GNUPGHOME"
			else
				z::log::warn "Failed to create GPG directory: $GNUPGHOME"
			fi
		else
			if chmod 700 "$GNUPGHOME" 2>/dev/null; then
				z::log::debug "Set permissions on GPG directory: $GNUPGHOME"
			else
				z::log::warn "Failed to set permissions on GPG directory: $GNUPGHOME"
			fi
		fi
		if [[ -t 0 ]]; then
			typeset -gx GPG_TTY="$(tty 2>/dev/null || print -r -- '/dev/tty')"
		fi
		z::log::debug "GPG environment configured: GNUPGHOME=$GNUPGHOME"
	fi
	return 0
}

_setup_performance_environment() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent no_unset

	z::runtime::check_interrupted || return $?

	if command -v make >/dev/null 2>&1; then
		local cores
		if (( IS_MACOS )); then
			cores=$(sysctl -n hw.ncpu 2>/dev/null || print -r -- 2)
		else
			cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || print -r -- 2)
		fi
		typeset -gx MAKEFLAGS="-j${cores}"
		z::log::debug "Performance environment configured: MAKEFLAGS=$MAKEFLAGS"
	fi
	return 0
}

_setup_terminal_environment() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent no_unset

	z::runtime::check_interrupted || return $?

	typeset -gx LANG="${LANG:-en_US.UTF-8}"
	typeset -gx LC_ALL="${LC_ALL:-$LANG}"
	typeset -gx TERM="${TERM:-xterm-256color}"
	typeset -gx COLORTERM="${COLORTERM:-truecolor}"

	if command -v less >/dev/null 2>&1; then
		typeset -gx PAGER="less"
		# Widely-supported set of options
		typeset -gx LESS="-R -Si -M -j.5"

		if command -v lesspipe.sh >/dev/null 2>&1; then
			typeset -gx LESSOPEN="|lesspipe.sh %s"
		elif command -v src-hilite-lesspipe.sh >/dev/null 2>&1; then
			typeset -gx LESSOPEN="|src-hilite-lesspipe.sh %s"
			typeset -gx LESSCOLOR=always
			command -v pygmentize >/dev/null 2>&1 && typeset -gx LESSCOLORIZER=pygmentize
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

_setup_cloud_environment() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent no_unset

	z::runtime::check_interrupted || return $?

	if command -v aws >/dev/null 2>&1; then
		typeset -gx AWS_CLI_AUTO_PROMPT=on-partial
		typeset -gx AWS_PAGER=""
		z::log::debug "AWS environment configured"
	fi

	if command -v terraform >/dev/null 2>&1; then
		local cores
		if (( IS_MACOS )); then
			cores=$(sysctl -n hw.ncpu 2>/dev/null || print -r -- 10)
		else
			cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || print -r -- 10)
		fi
		typeset -gx TF_CLI_ARGS_plan="-parallelism=${cores}"
		typeset -gx TF_CLI_ARGS_apply="-parallelism=${cores}"
		z::log::debug "Terraform environment configured: parallelism=$cores"
	fi

	if command -v kubectl >/dev/null 2>&1 && command -v delta >/dev/null 2>&1; then
		typeset -gx KUBECTL_EXTERNAL_DIFF="delta --syntax-highlight --paging=never"
		z::log::debug "Kubernetes environment configured"
	fi
	return 0
}

_setup_environment() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent no_unset

	z::runtime::check_interrupted || return $?

	_setup_editor_environment        || return $?
	_setup_development_environment   || return $?
	_setup_xdg_compliance            || return $?
	_setup_security_environment      || return $?
	_setup_performance_environment   || return $?
	_setup_terminal_environment      || return $?
	_setup_cloud_environment         || return $?

	z::log::debug "Environment setup completed successfully"
	return 0
}
