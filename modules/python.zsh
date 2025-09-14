#!/usr/bin/env zsh

# ==============================================================================
# Python and Poetry Management Module
# Fully compliant with zcore library principles
# ==============================================================================

# Global cache for Python commands with size limits
typeset -gA __PYTHON_CMD_CACHE
typeset -gi __PYTHON_CACHE_SIZE=0
typeset -ga __PYTHON_CACHE_ORDER=()

# Recursion guards for critical functions
typeset -gi __PYTHON_SETUP_RUNNING=0
typeset -gi __PYTHON_VENV_OPERATION=0

# Performance mode detection
typeset -gi __PYTHON_PERFORMANCE_MODE=0
if [[ "${_zcore_config[performance_mode]:-}" == "true" ]]; then
	__PYTHON_PERFORMANCE_MODE=1
fi

# Cache management functions
_cleanup_python_cache() {
	emulate -L zsh
	setopt typeset_silent

	if (( __PYTHON_CACHE_SIZE > 50 )); then
		local -i to_remove=$(( __PYTHON_CACHE_SIZE / 2 ))
		local -i removed=0
		local key

		while (( removed < to_remove && ${#__PYTHON_CACHE_ORDER[@]} > 0 )); do
			key="${__PYTHON_CACHE_ORDER[1]}"
			if [[ -n "$key" && -n "${__PYTHON_CMD_CACHE[$key]:-}" ]]; then
				unset "__PYTHON_CMD_CACHE[$key]"
				(( removed++ ))
			fi
			shift __PYTHON_CACHE_ORDER
		done

		__PYTHON_CACHE_SIZE=${#__PYTHON_CMD_CACHE[@]}
		z::log::debug "Cleaned Python command cache: removed $removed entries"
	fi
}

# Utility function to repeat a string with validation
function repeat {
	emulate -L zsh
	setopt no_unset warn_create_global typeset_silent

	local string="${1:-}"
	local num="${2:-100}"

	if [[ -z "$string" ]]; then
		z::log::error "Usage: repeat <string> [count]"
		return 1
	fi

	if [[ ! "$num" =~ ^[0-9]+$ ]] || (( num <= 0 )); then
		z::log::error "count must be a positive integer (got: '$num')"
		return 1
	fi

	if (( num > 10000 )); then
		z::log::error "count too large (maximum: 10000)"
		return 1
	fi

	local -i i
	for (( i = 0; i < num; i++ )); do
		printf '%s' "$string"
	done
}

# Setup Python and Poetry aliases with comprehensive error handling
_setup_python_poetry_aliases() {
	emulate -L zsh -o no_aliases
	setopt typeset_silent no_unset warn_create_global

	# Recursion guard
	if (( __PYTHON_SETUP_RUNNING )); then
		z::log::warn "Python setup already running, skipping"
		return 0
	fi
	__PYTHON_SETUP_RUNNING=1

	z::runtime::check_interrupted || {
		__PYTHON_SETUP_RUNNING=0
		return ${_zcore_config[exit_interrupted]:-130}
	}

	# Predeclare loop/temporary variables to prevent global leakage
	local cmd python_cmd alias_def build_alias
	local alias_name alias_value

	local -A available_commands=()
	local -i setup_errors=0

	# Fallback alias helper
	local -i _use_helper=0
	if typeset -f z::alias::define >/dev/null 2>&1; then
		_use_helper=1
	fi
	_define_alias() {
		# Usage: _define_alias name value
		if (( _use_helper )); then
			z::alias::define "$1" "$2"
		else
			builtin alias -- "${1}=${2}"
		fi
	}

	# Check and cache available commands
	for cmd in python python3 pip pip3 poetry; do
		if command -v "$cmd" >/dev/null 2>&1; then
			available_commands[$cmd]=1
			z::log::debug "Found command: $cmd"
		else
			z::log::debug "Command not found: $cmd"
		fi
	done

	# Python aliases with error handling
	if (( ${+available_commands[python]} )); then
		if ! _define_alias 'py' 'python'; then
			(( setup_errors++ ))
		fi
	fi
	if (( ${+available_commands[python3]} )); then
		if ! _define_alias 'py3' 'python3'; then
			(( setup_errors++ ))
		fi
	fi

	# Pip aliases with error handling
	if (( ${+available_commands[pip]} )); then
		local -a pip_aliases=(
			'piprm:pip uninstall -y'
			'pipl:pip list'
			'pipf:pip freeze'
			'pipu:pip install --upgrade'
			'pipr:pip install -r requirements.txt'
			'piprt:pip install -r requirements-test.txt'
			'piprd:pip install -r requirements-dev.txt'
			'pips:pip show'
			'pipc:pip check'
		)

		for alias_def in "${pip_aliases[@]}"; do
			alias_name="${alias_def%%:*}"
			alias_value="${alias_def##*:}"
			if ! _define_alias "$alias_name" "$alias_value"; then
				(( setup_errors++ ))
			fi
		done
	fi

	# Poetry aliases with comprehensive error handling
	if (( ${+available_commands[poetry]} )); then
		local -a poetry_aliases=(
			# Project management
			'poinit:poetry init'
			'ponew:poetry new'
			'pocheck:poetry check'

			# Dependency management
			'poadd:poetry add'
			'poadd-dev:poetry add --group dev'
			'poadd-test:poetry add --group test'
			'porm:poetry remove'
			'porm-dev:poetry remove --group dev'
			'porm-test:poetry remove --group test'
			'poshow:poetry show'
			'poshow-tree:poetry show --tree'
			'poshow-outdated:poetry show --outdated'

			# Installation
			'poi:poetry install'
			'poin:poetry install --no-root'
			'poi-dev:poetry install --with dev'
			'poi-test:poetry install --with test'
			'poi-all:poetry install --with dev,test'
			'poi-sync:poetry install --sync'
			'pou:poetry update'
			'por:poetry lock --no-update && poetry install'

			# Lock file management
			'polock:poetry lock'
			'polock-check:poetry lock --check'
			'polock-no-update:poetry lock --no-update'

			# Environment management
			'poenv:poetry env'
			'poenv-info:poetry env info'
			'poenv-list:poetry env list'
			'poenv-remove:poetry env remove'
			'poenv-use:poetry env use'
			'poshell:poetry shell'
			'porun:poetry run'

			# Export and build
			'poexport:poetry export'
			'poexport-dev:poetry export --with dev'
			'poexport-req:poetry export --format requirements.txt --output requirements.txt'
			'pobuild:poetry build'
			'popublish:poetry publish'

			# Configuration and cache
			'poconfig:poetry config'
			'poconfig-list:poetry config --list'
			'pocache:poetry cache'
			'pocache-clear:poetry cache clear --all pypi'

			# Version management
			'poversion:poetry version'
			'poversion-patch:poetry version patch'
			'poversion-minor:poetry version minor'
			'poversion-major:poetry version major'
		)

		for alias_def in "${poetry_aliases[@]}"; do
			alias_name="${alias_def%%:*}"
			alias_value="${alias_def##*:}"
			if ! _define_alias "$alias_name" "$alias_value"; then
				(( setup_errors++ ))
			fi
		done
	fi

	# Python build aliases with fallback detection
	for python_cmd in python python3; do
		if (( ${+available_commands[$python_cmd]} )); then
			if "$python_cmd" -m build --help >/dev/null 2>&1; then
				local -a build_aliases=(
					"pybuild:$python_cmd -m build"
					"pysdist:$python_cmd -m build --sdist"
					"pywheel:$python_cmd -m build --wheel"
				)

				for build_alias in "${build_aliases[@]}"; do
					alias_name="${build_alias%%:*}"
					alias_value="${build_alias##*:}"
					if ! _define_alias "$alias_name" "$alias_value"; then
						(( setup_errors++ ))
					fi
				done
				break
			fi
		fi
	done

	if (( setup_errors > 0 )); then
		z::log::warn "Python setup completed with $setup_errors errors"
	else
		z::log::debug "Python and Poetry aliases configured successfully"
	fi

	__PYTHON_SETUP_RUNNING=0
	return $(( setup_errors > 0 ? 1 : 0 ))
}

# Get Python command with caching, validation, and error handling
function _get_python_cmd {
	emulate -L zsh
	setopt no_unset warn_create_global typeset_silent

	local cache_key="${1:-default}"
	local python_cmd

	# Check cache first
	if [[ -n "${__PYTHON_CMD_CACHE[$cache_key]:-}" ]]; then
		python_cmd="${__PYTHON_CMD_CACHE[$cache_key]}"
		if command -v "$python_cmd" >/dev/null 2>&1; then
			print "$python_cmd"
			return 0
		else
			# Command no longer available, clear cache
			unset "__PYTHON_CMD_CACHE[$cache_key]"
			__PYTHON_CACHE_SIZE=${#__PYTHON_CMD_CACHE[@]}
		fi
	fi

	local -a candidates=()

	# Build candidate list
	if [[ "$cache_key" != "default" ]]; then
		candidates+="python${cache_key}"
	fi
	candidates+=(python3 python py)

	# Find first available candidate
	local cmd
	for cmd in "${candidates[@]}"; do
		if command -v "$cmd" >/dev/null 2>&1; then
			python_cmd="$cmd"
			break
		fi
	done

	if [[ -z "$python_cmd" ]]; then
		z::log::error "No Python interpreter found. Please install Python 3."
		return 1
	fi

	# Validate Python version with error handling
	local version_output major minor patch
	if ! version_output=$("$python_cmd" --version 2>&1); then
		z::log::error "Cannot determine Python version for '$python_cmd'"
		return 1
	fi

	if [[ "$version_output" =~ 'Python[[:space:]]+([0-9]+)\.([0-9]+)\.?([0-9]+)?' ]]; then
		major="${match[1]}"
		minor="${match[2]}"
		patch="${match[3]:-0}"
	else
		z::log::error "Unable to parse Python version from: $version_output"
		return 1
	fi

	if (( major < 3 )); then
		z::log::error "Python 3 is required (found: $version_output)"
		return 1
	fi

	# Cache the result with size management
	__PYTHON_CMD_CACHE[$cache_key]="$python_cmd"
	__PYTHON_CACHE_ORDER+=("$cache_key")
	(( __PYTHON_CACHE_SIZE++ ))

	# Clean cache if needed (skip in performance mode)
	if (( ! __PYTHON_PERFORMANCE_MODE )); then
		_cleanup_python_cache
	fi

	print "$python_cmd"
}

# Check if directory is a Poetry project with validation
function _is_poetry_project {
	emulate -L zsh
	setopt no_unset warn_create_global typeset_silent

	local project_dir="${1:-$PWD}"

	if [[ ! -d "$project_dir" ]]; then
		z::log::debug "Directory does not exist: $project_dir"
		return 1
	fi

	if [[ ! -f "$project_dir/pyproject.toml" ]]; then
		return 1
	fi

	if ! grep -q '\[tool\.poetry\]' "$project_dir/pyproject.toml" 2>/dev/null; then
		if [[ ! -f "$project_dir/poetry.lock" ]]; then
			return 1
		fi
	fi

	return 0
}

# Get Poetry environment information with error handling
function _get_poetry_env_info {
	emulate -L zsh
	setopt no_unset warn_create_global typeset_silent

	local project_dir="${1:-$PWD}"

	# Check if already in a Poetry environment
	if [[ -n "$VIRTUAL_ENV" && "$VIRTUAL_ENV" == *"pypoetry"* ]]; then
		print "$VIRTUAL_ENV"
		return 0
	fi

	if ! _is_poetry_project "$project_dir"; then
		return 1
	fi

	if ! command -v poetry >/dev/null 2>&1; then
		return 1
	fi

	local poetry_env_path
	if poetry_env_path=$(cd "$project_dir" && poetry env info --path 2>/dev/null); then
		if [[ -n "$poetry_env_path" && -d "$poetry_env_path" ]]; then
			print "$poetry_env_path"
			return 0
		fi
	fi

	return 1
}

# Check if Poetry shell is active
function _is_poetry_shell_active {
	emulate -L zsh
	setopt no_unset warn_create_global typeset_silent

	[[ -n "$POETRY_ACTIVE" ]] || [[ -n "$VIRTUAL_ENV" && "$VIRTUAL_ENV" == *"poetry"* ]]
}

# Find activation script for virtual environment with validation
function _find_activation_script {
	emulate -L zsh
	setopt no_unset warn_create_global typeset_silent

	local venv_path="$1"

	if [[ -z "$venv_path" || ! -d "$venv_path" ]]; then
		return 1
	fi

	local -a script_paths=(
		"$venv_path/bin/activate"
		"$venv_path/Scripts/activate"
	)

	local script_path
	for script_path in "${script_paths[@]}"; do
		if [[ -f "$script_path" && -r "$script_path" ]]; then
			print "$script_path"
			return 0
		fi
	done

	return 1
}

# Validate if path is a valid virtual environment
function _is_valid_venv {
	emulate -L zsh
	setopt no_unset warn_create_global typeset_silent

	local path="$1"

	if [[ -z "$path" ]]; then
		return 1
	fi

	[[ -d "$path" && -f "$path/pyvenv.cfg" && -r "$path/pyvenv.cfg" ]]
}

# Validate virtual environment path for security
function _validate_venv_path {
	emulate -L zsh
	setopt no_unset warn_create_global typeset_silent

	local path="$1"

	if [[ -z "$path" ]]; then
		z::log::error "Virtual environment name cannot be empty"
		return 1
	fi

	if [[ "$path" =~ [[:space:]] ]]; then
		z::log::error "Virtual environment name cannot contain spaces"
		return 1
	fi

	if [[ "$path" == /* ]] || [[ "$path" =~ '\.\.' ]]; then
		z::log::error "Invalid path specified for security reasons"
		return 1
	fi

	# Allow leading dots for hidden directories like .venv
	if [[ ! "$path" =~ ^[a-zA-Z0-9.]([a-zA-Z0-9._-]*[a-zA-Z0-9.])?$ ]]; then
		z::log::error "Virtual environment name contains invalid characters"
		z::log::error "       Must start/end with alphanumeric or dot, contain only letters, numbers, dots, hyphens, underscores"
		return 1
	fi

	local -a reserved_names=(
		"." ".." "bin" "lib" "include" "share" "Scripts"
		"python" "python3" "pip" "poetry" "conda"
	)

	if (( ${#${(M)reserved_names:#$path}} )); then
		z::log::error "'$path' is a reserved name"
		return 1
	fi

	return 0
}

# Create a virtual environment with comprehensive error handling
function mkvenv {
	# Recursion guard
	if (( __PYTHON_VENV_OPERATION )); then
		z::log::error "Virtual environment operation already in progress"
		return 1
	fi
	__PYTHON_VENV_OPERATION=1

	emulate -L zsh
	setopt no_unset warn_create_global typeset_silent

	local venv_name="${1:-.venv}"
	local python_version="${2:-}"
	local force_regular=0

	if [[ "$venv_name" == "--force" ]]; then
		force_regular=1
		venv_name="${2:-.venv}"
		python_version="${3:-}"
	fi

	z::runtime::check_interrupted || {
		__PYTHON_VENV_OPERATION=0
		return ${_zcore_config[exit_interrupted]:-130}
	}

	if (( ! force_regular )) && _is_poetry_project; then
		z::log::info "Poetry project detected. Use 'poetry install' or 'poetry env use <python>' instead."
		z::log::info "Or use 'mkvenv --force' to create a regular venv anyway."
		__PYTHON_VENV_OPERATION=0
		return 1
	fi

	if ! _validate_venv_path "$venv_name"; then
		__PYTHON_VENV_OPERATION=0
		return 1
	fi

	if [[ -e "$venv_name" ]]; then
		z::log::error "Path '$venv_name' already exists"
		__PYTHON_VENV_OPERATION=0
		return 1
	fi

	local python_cmd
	if [[ -n "$python_version" ]]; then
		python_cmd="python$python_version"
		if ! command -v "$python_cmd" >/dev/null 2>&1; then
			z::log::error "Python version '$python_version' not found"
			__PYTHON_VENV_OPERATION=0
			return 1
		fi
	else
		python_cmd=$(_get_python_cmd) || {
			__PYTHON_VENV_OPERATION=0
			return 1
		}
	fi

	if ! "$python_cmd" -c "import venv" 2>/dev/null; then
		z::log::error "venv module not available. Install python3-venv package."
		__PYTHON_VENV_OPERATION=0
		return 1
	fi

	z::log::info "Creating virtual environment: $venv_name"
	z::log::info "Using Python: $python_cmd ($("$python_cmd" --version 2>&1))"

	if ! "$python_cmd" -m venv "$venv_name" 2>/dev/null; then
		z::log::error "Failed to create virtual environment. Check permissions."
		__PYTHON_VENV_OPERATION=0
		return 1
	fi

	local activate_script
	if ! activate_script=$(_find_activation_script "$venv_name"); then
		z::log::error "Virtual environment created but activation script not found"
		__PYTHON_VENV_OPERATION=0
		return 1
	fi

	if ! z::path::source "$activate_script" 2>/dev/null; then
		z::log::error "Failed to activate virtual environment"
		__PYTHON_VENV_OPERATION=0
		return 1
	fi

	z::log::info "Upgrading pip..."
	if ! python -m pip install --upgrade pip setuptools wheel >/dev/null 2>&1; then
		z::log::warn "Failed to upgrade pip/setuptools/wheel"
	fi

	z::log::info "✓ Virtual environment '$venv_name' created and activated"
	__PYTHON_VENV_OPERATION=0
}

# Find virtual environment candidates with optimized search
function _find_venv_candidates {
	emulate -L zsh
	setopt no_unset warn_create_global local_options null_glob typeset_silent

	local -a candidates=()
	local -A seen_dirs=()
	local dir

	# Priority patterns first
	local pattern
	for pattern in .venv; do
		for dir in ${~pattern}(N/); do
			if [[ -z "${seen_dirs[$dir]:-}" ]] && _is_valid_venv "$dir"; then
				if _find_activation_script "$dir" >/dev/null 2>&1; then
					candidates+=("$dir")
					seen_dirs[$dir]=1
				fi
			fi
		done
	done

	# Common patterns
	for pattern in venv* env* .env*; do
		for dir in ${~pattern}(N/); do
			if [[ -z "${seen_dirs[$dir]:-}" ]] && _is_valid_venv "$dir"; then
				if _find_activation_script "$dir" >/dev/null 2>&1; then
					candidates+=("$dir")
					seen_dirs[$dir]=1
				fi
			fi
		done
	done

	# Check remaining directories with inline exclusion check
	for dir in *(N/); do
		[[ -n "${seen_dirs[$dir]:-}" ]] && continue

		# Skip common non-venv directories
		case "$dir" in
			.* | node_modules | __pycache__ | .git | .pytest_cache | \
			*.egg-info | build | dist | target | bin | lib | include | share | \
			*.app | *.bundle)
				continue
				;;
		esac

		if _is_valid_venv "$dir"; then
			if _find_activation_script "$dir" >/dev/null 2>&1; then
				candidates+=("$dir")
				seen_dirs[$dir]=1
			fi
		fi
	done

	printf '%s\n' "${candidates[@]}"
}

# Activate virtual environment with comprehensive error handling
function avenv {
	# Recursion guard
	if (( __PYTHON_VENV_OPERATION )); then
		z::log::error "Virtual environment operation already in progress"
		return 1
	fi
	__PYTHON_VENV_OPERATION=1

	emulate -L zsh
	setopt no_unset warn_create_global typeset_silent

	local venv_name="${1:-}"

	z::runtime::check_interrupted || {
		__PYTHON_VENV_OPERATION=0
		return ${_zcore_config[exit_interrupted]:-130}
	}

	if [[ -n "$VIRTUAL_ENV" ]]; then
		z::log::info "Virtual environment already active: $(basename "$VIRTUAL_ENV")"
		__PYTHON_VENV_OPERATION=0
		return 0
	fi

	if [[ -z "$venv_name" ]]; then
		# Try Poetry first
		if _is_poetry_project; then
			local poetry_env
			if poetry_env=$(_get_poetry_env_info); then
				local activate_script
				if activate_script=$(_find_activation_script "$poetry_env"); then
					if z::path::source "$activate_script" 2>/dev/null; then
						export POETRY_ACTIVE=1
						z::log::info "✓ Activated Poetry environment: $(basename "$poetry_env")"
						__PYTHON_VENV_OPERATION=0
						return 0
					fi
				fi
			else
				z::log::info "Poetry project detected but no environment found."
				z::log::info "Run 'poetry install' to create the environment first."
				__PYTHON_VENV_OPERATION=0
				return 1
			fi
		fi

		# Find local venv
		local -a candidates=()
		candidates=("${(f)$(_find_venv_candidates)}")

		if (( ${#candidates[@]} > 0 )); then
			local candidate="${candidates[1]}"
			local activate_script
			if activate_script=$(_find_activation_script "$candidate"); then
				if z::path::source "$activate_script" 2>/dev/null; then
					z::log::info "✓ Activated virtual environment: ${candidate}"
					__PYTHON_VENV_OPERATION=0
					return 0
				fi
			fi
			z::log::error "Failed to activate virtual environment: ${candidate}"
			__PYTHON_VENV_OPERATION=0
			return 1
		fi

		z::log::error "No virtual environment found in current directory"
		z::log::error "       Run 'mkvenv' to create one, or specify a path explicitly"
		__PYTHON_VENV_OPERATION=0
		return 1
	else
		if [[ ! -d "$venv_name" ]]; then
			z::log::error "Directory '$venv_name' does not exist"
			__PYTHON_VENV_OPERATION=0
			return 1
		fi

		if ! _is_valid_venv "$venv_name"; then
			z::log::error "'$venv_name' is not a valid virtual environment"
			__PYTHON_VENV_OPERATION=0
			return 1
		fi

		local activate_script
		if ! activate_script=$(_find_activation_script "$venv_name"); then
			z::log::error "'$venv_name' missing activation script"
			__PYTHON_VENV_OPERATION=0
			return 1
		fi

		if z::path::source "$activate_script" 2>/dev/null; then
			z::log::info "✓ Activated virtual environment: $venv_name"
		else
			z::log::error "Failed to activate virtual environment: $venv_name"
			__PYTHON_VENV_OPERATION=0
			return 1
		fi
	fi

	__PYTHON_VENV_OPERATION=0
}

# Clean up PATH from old venv with validation
function _cleanup_venv_path {
	emulate -L zsh
	setopt no_unset warn_create_global typeset_silent

	local old_venv_path="$1"

	if [[ -z "$old_venv_path" ]]; then
		return 1
	fi

	local -a path_elements=("${(@s/:/)PATH}")
	local -a clean_path=()
	local path_element

	for path_element in "${path_elements[@]}"; do
		if [[ "$path_element" != "$old_venv_path"/* ]]; then
			clean_path+=("$path_element")
		fi
	done

	export PATH="${(j.:.)clean_path}"
}

# Deactivate virtual environment with error handling
function dvenv {
	# Recursion guard
	if (( __PYTHON_VENV_OPERATION )); then
		z::log::error "Virtual environment operation already in progress"
		return 1
	fi
	__PYTHON_VENV_OPERATION=1

	emulate -L zsh
	setopt no_unset warn_create_global typeset_silent

	local was_poetry_active=0

	if [[ -n "$POETRY_ACTIVE" ]]; then
		was_poetry_active=1
		unset POETRY_ACTIVE
	fi

	if [[ -z "$VIRTUAL_ENV" ]]; then
		if (( was_poetry_active )); then
			z::log::info "Poetry environment variables cleared"
			__PYTHON_VENV_OPERATION=0
			return 0
		else
			z::log::error "No virtual environment is currently active"
			__PYTHON_VENV_OPERATION=0
			return 1
		fi
	fi

	local current_venv="$(basename "$VIRTUAL_ENV")"

	if typeset -f deactivate >/dev/null 2>&1; then
		deactivate
		if (( was_poetry_active )); then
			z::log::info "✓ Deactivated Poetry environment: $current_venv"
		else
			z::log::info "✓ Deactivated virtual environment: $current_venv"
		fi
	else
		z::log::warn "No deactivate function found, performing manual cleanup"

		local old_virtual_env="$VIRTUAL_ENV"
		_cleanup_venv_path "$old_virtual_env"

		unset VIRTUAL_ENV VIRTUAL_ENV_PROMPT

		if [[ -n "$_OLD_VIRTUAL_PS1" ]]; then
			PS1="$_OLD_VIRTUAL_PS1"
			unset _OLD_VIRTUAL_PS1
		fi

		if (( was_poetry_active )); then
			z::log::info "✓ Manually deactivated Poetry environment: $current_venv"
		else
			z::log::info "✓ Manually deactivated virtual environment: $current_venv"
		fi
	fi

	__PYTHON_VENV_OPERATION=0
}

# Remove virtual environment with safety checks
function rmvenv {
	# Recursion guard
	if (( __PYTHON_VENV_OPERATION )); then
		z::log::error "Virtual environment operation already in progress"
		return 1
	fi
	__PYTHON_VENV_OPERATION=1

	emulate -L zsh
	setopt no_unset warn_create_global typeset_silent

	local venv_name="${1:-.venv}"

	z::runtime::check_interrupted || {
		__PYTHON_VENV_OPERATION=0
		return ${_zcore_config[exit_interrupted]:-130}
	}

	if [[ "$venv_name" == ".venv" ]] && _is_poetry_project; then
		z::log::info "Poetry project detected. Use 'poetry env remove <python>' instead."
		z::log::info "Available Poetry environments:"
		if command -v poetry >/dev/null 2>&1; then
			poetry env list 2>/dev/null || z::log::info "  No Poetry environments found"
		fi
		__PYTHON_VENV_OPERATION=0
		return 1
	fi

	if [[ ! -e "$venv_name" ]]; then
		z::log::error "Path '$venv_name' does not exist"
		__PYTHON_VENV_OPERATION=0
		return 1
	fi

	if [[ ! -d "$venv_name" ]]; then
		z::log::error "'$venv_name' is not a directory"
		__PYTHON_VENV_OPERATION=0
		return 1
	fi

	if ! _is_valid_venv "$venv_name"; then
		z::log::error "'$venv_name' does not appear to be a virtual environment"
		z::log::error "       Missing pyvenv.cfg file. Refusing to remove directory for safety."
		__PYTHON_VENV_OPERATION=0
		return 1
	fi

	# Check if this is the active environment
	if [[ -n "$VIRTUAL_ENV" ]]; then
		local current_venv_real="${VIRTUAL_ENV:A}"
		local target_venv_real="${venv_name:A}"

		if [[ "$current_venv_real" == "$target_venv_real" ]]; then
			z::log::info "Deactivating currently active virtual environment..."
			dvenv || {
				z::log::error "Failed to deactivate virtual environment"
				__PYTHON_VENV_OPERATION=0
				return 1
			}
		fi
	fi

	print -n "Are you sure you want to remove '$venv_name'? [y/N] "
	local response
	if ! read -r response </dev/tty; then
		print
		z::log::info "Cancelled (EOF received)."
		__PYTHON_VENV_OPERATION=0
		return 1
	fi

	if [[ ! "$response" =~ ^[Yy]$ ]]; then
		z::log::info "Cancelled."
		__PYTHON_VENV_OPERATION=0
		return 1
	fi

	z::log::info "Removing virtual environment: $venv_name"
	if ! rm -rf "$venv_name" 2>/dev/null; then
		z::log::error "Failed to remove virtual environment. Check permissions."
		__PYTHON_VENV_OPERATION=0
		return 1
	fi

	z::log::info "✓ Virtual environment '$venv_name' removed"
	__PYTHON_VENV_OPERATION=0
}

# List virtual environments with comprehensive information
function lsvenv {
	emulate -L zsh
	setopt no_unset warn_create_global typeset_silent

	local current_dir="$PWD"
	local found_any=0

	z::log::info "Virtual environments in $current_dir:"

	# Show currently active environment
	if [[ -n "$VIRTUAL_ENV" ]]; then
		z::log::info "  Currently Active:"
		local env_type="standard"
		if [[ "$VIRTUAL_ENV" == *"pypoetry"* ]]; then
			env_type="poetry"
		fi
		printf "    %-30s %-15s %s\n" "$(basename "$VIRTUAL_ENV")" "($env_type)" "[active]"
		found_any=1
	fi

	# Show Poetry environments
	if _is_poetry_project; then
		z::log::info "  Poetry Project:"

		if command -v poetry >/dev/null 2>&1; then
			local poetry_envs
			if poetry_envs=$(poetry env list --full-path 2>/dev/null) && [[ -n "$poetry_envs" ]]; then
				local env_path env_status line
				while IFS= read -r line; do
					if [[ -n "$line" ]]; then
						env_path="${line%% *}"
						env_status="[inactive]"

						if [[ "$line" == *"(Activated)"* ]] || [[ -n "$VIRTUAL_ENV" && "$VIRTUAL_ENV" == "$env_path" ]]; then
							env_status="[active]"
						fi

						printf "    %-30s %-15s %s\n" "$(basename "$env_path")" "(poetry)" "$env_status"
					fi
				done <<< "$poetry_envs"
				found_any=1
			else
				z::log::info "    No Poetry environments found (run 'poetry install')"
			fi
		else
			z::log::info "    Poetry not available"
		fi
	fi

	# Show local environments
	local -a venv_dirs=()
	venv_dirs=("${(f)$(_find_venv_candidates)}")

	if (( ${#venv_dirs[@]} > 0 )); then
		z::log::info "  Local environments:"
		local dir python_version venv_status
		for dir in ${(o)venv_dirs}; do
			python_version=""
			if [[ -f "$dir/pyvenv.cfg" ]]; then
				python_version=$(grep -E '^version[[:space:]]*=' "$dir/pyvenv.cfg" 2>/dev/null | sed 's/.*=[[:space:]]*//')
			fi

			venv_status="inactive"
			if [[ -n "$VIRTUAL_ENV" && "${VIRTUAL_ENV:A}" == "${dir:A}" ]]; then
				venv_status="active"
			fi

			printf "    %-30s %-15s %s\n" "$dir" "(${python_version:-unknown})" "[$venv_status]"
			found_any=1
		done
	fi

	if (( ! found_any )); then
		z::log::info "  No virtual environments found"
	fi
}

# Show virtual environment information with comprehensive details
function venvinfo {
	emulate -L zsh
	setopt no_unset warn_create_global typeset_silent

	local show_poetry=0

	if _is_poetry_shell_active || _is_poetry_project; then
		show_poetry=1
	fi

	if [[ -z "$VIRTUAL_ENV" ]] && (( ! show_poetry )); then
		z::log::error "No virtual environment is currently active"
		return 1
	fi

	# Poetry project information
	if (( show_poetry )) && _is_poetry_project; then
		z::log::info "Poetry Project Information:"
		if command -v poetry >/dev/null 2>&1; then
			local project_info
			if project_info=$(poetry version 2>/dev/null); then
				z::log::info "  Project: $project_info"
			fi

			local poetry_env_info
			if poetry_env_info=$(poetry env info 2>/dev/null); then
				z::log::info "  Environment Info:"
				print "$poetry_env_info" | sed 's/^/    /'
			fi

			z::log::info "  Configuration:"
			poetry config --list 2>/dev/null | grep -E '^virtualenvs\.' | sed 's/^/    /'
		fi
		print ""
	fi

	# Active virtual environment information
	if [[ -n "$VIRTUAL_ENV" ]]; then
		z::log::info "Active virtual environment:"
		z::log::info "  Path: $VIRTUAL_ENV"
		z::log::info "  Name: $(basename "$VIRTUAL_ENV")"

		if [[ -n "$POETRY_ACTIVE" ]]; then
			z::log::info "  Type: Poetry managed"
		else
			z::log::info "  Type: Standard venv"
		fi

		if command -v python >/dev/null 2>&1; then
			z::log::info "  Python: $(python --version 2>&1)"
			z::log::info "  Python Path: $(command -v python)"
		else
			z::log::info "  Python: Not found in PATH"
		fi

		if command -v pip >/dev/null 2>&1; then
			z::log::info "  Pip: $(pip --version 2>&1 | head -1)"

			local pkg_count
			if pkg_count=$(pip list --format=freeze 2>/dev/null | wc -l); then
				z::log::info "  Packages: $pkg_count installed"
			else
				z::log::info "  Packages: Unable to count (pip error)"
			fi
		else
			z::log::info "  Pip: Not available"
		fi

		if [[ -f "$VIRTUAL_ENV/pyvenv.cfg" ]]; then
			z::log::info "  Configuration:"
			sed 's/^/    /' "$VIRTUAL_ENV/pyvenv.cfg"
		fi
	fi
}

# Utility functions with zcore compliance
function _clear_python_cache {
	emulate -L zsh
	setopt no_unset warn_create_global typeset_silent

	__PYTHON_CMD_CACHE=()
	__PYTHON_CACHE_SIZE=0
	__PYTHON_CACHE_ORDER=()
	z::log::info "Python command cache cleared"
}

function _poetry_shell_activate {
	emulate -L zsh
	setopt no_unset warn_create_global typeset_silent

	if ! _is_poetry_project; then
		z::log::error "Not in a Poetry project directory"
		return 1
	fi

	z::log::info "Activating Poetry shell..."
	# Do not 'exec' to avoid replacing the current interactive shell
	poetry shell
}

function _poetry_env_create {
	emulate -L zsh
	setopt no_unset warn_create_global typeset_silent

	local python_version="${1:-}"

	if ! _is_poetry_project; then
		z::log::error "Not in a Poetry project directory"
		return 1
	fi

	if [[ -n "$python_version" ]]; then
		poetry env use "$python_version"
	else
		poetry install
	fi
}

# Convenient aliases using zcore safe_alias (fallback handled in setup)
z::alias::define 'aenv' 'avenv'
z::alias::define 'denv' 'dvenv'
z::alias::define 'rmenv' 'rmvenv'
z::alias::define 'mkenv' 'mkvenv'
z::alias::define 'lsenv' 'lsvenv'
z::alias::define 'vinfo' 'venvinfo'

z::alias::define 'poshell' '_poetry_shell_activate'
z::alias::define 'poenv-create' '_poetry_env_create'
z::alias::define 'poclear' '_clear_python_cache'

# Initialize the module
_setup_python_poetry_aliases

# Module initialization complete
z::log::debug "Python module initialized with zcore compliance"
