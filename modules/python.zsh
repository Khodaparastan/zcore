#!/usr/bin/env zsh

# Global cache for Python commands
typeset -gA __PYTHON_CMD_CACHE

# Utility function to repeat a string
function repeat {
    local string="${1:-}"
    local num="${2:-100}"

    if [[ -z "$string" ]]; then
        print -u2 "Usage: repeat <string> [count]"
        return 1
    fi

    # Fix: Remove quotes from regex pattern
    if [[ ! "$num" =~ ^[0-9]+$ ]] || (( num <= 0 )); then
        print -u2 "Error: count must be a positive integer (got: '$num')"
        return 1
    fi

    if (( num > 10000 )); then
        print -u2 "Error: count too large (maximum: 10000)"
        return 1
    fi

    printf '%s' "${(pl:num::$string:)}"
}
# Setup Python and Poetry aliases
_setup_python_poetry_aliases() {
	local cmd
	local -A available_commands=()

	# Check and cache available commands
	for cmd in python python3 pip poetry; do
		if command -v "$cmd" >/dev/null 2>&1; then
			available_commands[$cmd]=1
		fi
	done

	# Python aliases
	if command -v python >/dev/null 2>&1; then
		alias 'py'='python'
	fi
	if command -v python3 >/dev/null 2>&1; then
		alias 'py3'='python3'
	fi

	# Pip aliases
	if command -v pip >/dev/null 2>&1; then
		alias 'piprm'='pip uninstall -y'
		alias 'pipl'='pip list'
		alias 'pipf'='pip freeze'
		alias 'pipu'='pip install --upgrade'
		alias 'pipr'='pip install -r requirements.txt'
		alias 'piprt'='pip install -r requirements-test.txt'
		alias 'piprd'='pip install -r requirements-dev.txt'
		alias 'pips'='pip show'
		alias 'pipc'='pip check'
	fi

	# Poetry aliases
	if command -v poetry >/dev/null 2>&1; then
		# Project management
		alias 'poinit'='poetry init'
		alias 'ponew'='poetry new'
		alias 'pocheck'='poetry check'

		# Dependency management
		alias 'poadd'='poetry add'
		alias 'poadd-dev'='poetry add --group dev'
		alias 'poadd-test'='poetry add --group test'
		alias 'porm'='poetry remove'
		alias 'porm-dev'='poetry remove --group dev'
		alias 'porm-test'='poetry remove --group test'
		alias 'poshow'='poetry show'
		alias 'poshow-tree'='poetry show --tree'
		alias 'poshow-outdated'='poetry show --outdated'

		# Installation
		alias 'poi'='poetry install'
		alias 'poin'='poetry install --no-root'
		alias 'poi-dev'='poetry install --with dev'
		alias 'poi-test'='poetry install --with test'
		alias 'poi-all'='poetry install --with dev,test'
		alias 'poi-sync'='poetry install --sync'
		alias 'pou'='poetry update'
		alias 'por'='poetry lock --no-update && poetry install'

		# Lock file management
		alias 'polock'='poetry lock'
		alias 'polock-check'='poetry lock --check'
		alias 'polock-no-update'='poetry lock --no-update'

		# Environment management
		alias 'poenv'='poetry env'
		alias 'poenv-info'='poetry env info'
		alias 'poenv-list'='poetry env list'
		alias 'poenv-remove'='poetry env remove'
		alias 'poenv-use'='poetry env use'
		alias 'poshell'='poetry shell'
		alias 'porun'='poetry run'

		# Export and build
		alias 'poexport'='poetry export'
		alias 'poexport-dev'='poetry export --with dev'
		alias 'poexport-req'='poetry export --format requirements.txt --output requirements.txt'
		alias 'pobuild'='poetry build'
		alias 'popublish'='poetry publish'

		# Configuration and cache
		alias 'poconfig'='poetry config'
		alias 'poconfig-list'='poetry config --list'
		alias 'pocache'='poetry cache'
		alias 'pocache-clear'='poetry cache clear --all pypi'

		# Version management
		alias 'poversion'='poetry version'
		alias 'poversion-patch'='poetry version patch'
		alias 'poversion-minor'='poetry version minor'
		alias 'poversion-major'='poetry version major'
	fi

	# Python build aliases
	local python_cmd
	for python_cmd in python python3; do
		if command -v "$python_cmd" >/dev/null 2>&1; then
			if "$python_cmd" -m build --help >/dev/null 2>&1; then
				alias 'pybuild'="$python_cmd -m build"
				alias 'pysdist'="$python_cmd -m build --sdist"
				alias 'pywheel'="$python_cmd -m build --wheel"
				break
			fi
		fi
	done
}

# Call the function to set up aliases
_setup_python_poetry_aliases
# Get Python command with caching and validation
function _get_python_cmd {
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
        print -u2 "Error: No Python interpreter found. Please install Python 3."
        return 1
    fi

    # Validate Python version
    local version_output major minor patch
    if ! version_output=$("$python_cmd" --version 2>&1); then
        print -u2 "Error: Cannot determine Python version for '$python_cmd'"
        return 1
    fi

    if [[ "$version_output" =~ 'Python[[:space:]]+([0-9]+)\.([0-9]+)\.?([0-9]+)?' ]]; then
        major="${match[1]}"
        minor="${match[2]}"
        patch="${match[3]:-0}"
    else
        print -u2 "Error: Unable to parse Python version from: $version_output"
        return 1
    fi

    if (( major < 3 )); then
        print -u2 "Error: Python 3 is required (found: $version_output)"
        return 1
    fi

    # Cache the result
    __PYTHON_CMD_CACHE[$cache_key]="$python_cmd"
    print "$python_cmd"
}

# Check if directory is a Poetry project
function _is_poetry_project {
    local project_dir="${1:-$PWD}"

    [[ -f "$project_dir/pyproject.toml" ]] || return 1

    if grep -q '\[tool\.poetry\]' "$project_dir/pyproject.toml" 2>/dev/null; then
        return 0
    fi

    [[ -f "$project_dir/poetry.lock" ]] && return 0

    return 1
}

# Get Poetry environment information
function _get_poetry_env_info {
    local project_dir="${1:-$PWD}"

    # Check if already in a Poetry environment
    if [[ -n "$VIRTUAL_ENV" && "$VIRTUAL_ENV" == *"pypoetry"* ]]; then
        print "$VIRTUAL_ENV"
        return 0
    fi

    _is_poetry_project "$project_dir" || return 1
    command -v poetry >/dev/null 2>&1 || return 1

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
    [[ -n "$POETRY_ACTIVE" ]] || [[ -n "$VIRTUAL_ENV" && "$VIRTUAL_ENV" == *"poetry"* ]]
}

# Find activation script for virtual environment
function _find_activation_script {
    local venv_path="$1"
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
    local path="$1"
    [[ -d "$path" && -f "$path/pyvenv.cfg" && -r "$path/pyvenv.cfg" ]]
}

# Validate virtual environment path for security
function _validate_venv_path {
    local path="$1"

    if [[ -z "$path" ]]; then
        print -u2 "Error: Virtual environment name cannot be empty"
        return 1
    fi

    if [[ "$path" =~ [[:space:]] ]]; then
        print -u2 "Error: Virtual environment name cannot contain spaces"
        return 1
    fi

    if [[ "$path" == /* ]] || [[ "$path" =~ '\.\.' ]]; then
        print -u2 "Error: Invalid path specified for security reasons"
        return 1
    fi

    # Allow leading dots for hidden directories like .venv
    if [[ ! "$path" =~ ^[a-zA-Z0-9.]([a-zA-Z0-9._-]*[a-zA-Z0-9.])?$ ]]; then
        print -u2 "Error: Virtual environment name contains invalid characters"
        print -u2 "       Must start/end with alphanumeric or dot, contain only letters, numbers, dots, hyphens, underscores"
        return 1
    fi

    local -a reserved_names=(
        "." ".." "bin" "lib" "include" "share" "Scripts"
        "python" "python3" "pip" "poetry" "conda"
    )

    # Check if path is in reserved names
    if (( ${reserved_names[(I)$path]} )); then
        print -u2 "Error: '$path' is a reserved name"
        return 1
    fi

    return 0
}

# Create a virtual environment
function mkvenv {
    local venv_name="${1:-.venv}"
    local python_version="${2:-}"
    local force_regular=0

    if [[ "$venv_name" == "--force" ]]; then
        force_regular=1
        venv_name="${2:-.venv}"
        python_version="${3:-}"
    fi

    if (( ! force_regular )) && _is_poetry_project; then
        print "Poetry project detected. Use 'poetry install' or 'poetry env use <python>' instead."
        print "Or use 'mkvenv --force' to create a regular venv anyway."
        return 1
    fi

    _validate_venv_path "$venv_name" || return 1

    if [[ -e "$venv_name" ]]; then
        print -u2 "Error: Path '$venv_name' already exists"
        return 1
    fi

    local python_cmd
    if [[ -n "$python_version" ]]; then
        python_cmd="python$python_version"
        if ! command -v "$python_cmd" >/dev/null 2>&1; then
            print -u2 "Error: Python version '$python_version' not found"
            return 1
        fi
    else
        python_cmd=$(_get_python_cmd) || return 1
    fi

    if ! "$python_cmd" -c "import venv" 2>/dev/null; then
        print -u2 "Error: venv module not available. Install python3-venv package."
        return 1
    fi

    print "Creating virtual environment: $venv_name"
    print "Using Python: $python_cmd ($("$python_cmd" --version 2>&1))"

    if ! "$python_cmd" -m venv "$venv_name" 2>/dev/null; then
        print -u2 "Error: Failed to create virtual environment. Check permissions."
        return 1
    fi

    local activate_script
    if ! activate_script=$(_find_activation_script "$venv_name"); then
        print -u2 "Error: Virtual environment created but activation script not found"
        return 1
    fi

    if ! source "$activate_script" 2>/dev/null; then
        print -u2 "Error: Failed to activate virtual environment"
        return 1
    fi

    print "Upgrading pip..."
    if ! python -m pip install --upgrade pip setuptools wheel >/dev/null 2>&1; then
        print -u2 "Warning: Failed to upgrade pip/setuptools/wheel"
    fi

    print "✓ Virtual environment '$venv_name' created and activated"
}
function _find_venv_candidates {
    local -a candidates=()
    local -A seen_dirs=()
    local dir

    setopt local_options null_glob

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

# Activate virtual environment
function avenv {
    local venv_name="${1:-}"

    if [[ -n "$VIRTUAL_ENV" ]]; then
        print "Virtual environment already active: $(basename "$VIRTUAL_ENV")"
        return 0
    fi

    if [[ -z "$venv_name" ]]; then
        # Try Poetry first
        if _is_poetry_project; then
            local poetry_env
            if poetry_env=$(_get_poetry_env_info); then
                local activate_script
                if activate_script=$(_find_activation_script "$poetry_env"); then
                    if source "$activate_script" 2>/dev/null; then
                        export POETRY_ACTIVE=1
                        print "✓ Activated Poetry environment: $(basename "$poetry_env")"
                        return 0
                    fi
                fi
            else
                print "Poetry project detected but no environment found."
                print "Run 'poetry install' to create the environment first."
                return 1
            fi
        fi

        # Find local venv
        local -a candidates=()
        candidates=($(_find_venv_candidates))

        if (( ${#candidates[@]} > 0 )); then
            local candidate="${candidates[1]}"
            local activate_script
            if activate_script=$(_find_activation_script "$candidate"); then
                if source "$activate_script" 2>/dev/null; then
                    print "✓ Activated virtual environment: ${candidate}"
                    return 0
                fi
            fi
            print -u2 "Error: Failed to activate virtual environment: ${candidate}"
            return 1
        fi

        print -u2 "Error: No virtual environment found in current directory"
        print -u2 "       Run 'mkvenv' to create one, or specify a path explicitly"
        return 1
    else
        if [[ ! -d "$venv_name" ]]; then
            print -u2 "Error: Directory '$venv_name' does not exist"
            return 1
        fi

        if ! _is_valid_venv "$venv_name"; then
            print -u2 "Error: '$venv_name' is not a valid virtual environment"
            return 1
        fi

        local activate_script
        if ! activate_script=$(_find_activation_script "$venv_name"); then
            print -u2 "Error: '$venv_name' missing activation script"
            return 1
        fi

        if source "$activate_script" 2>/dev/null; then
            print "✓ Activated virtual environment: $venv_name"
        else
            print -u2 "Error: Failed to activate virtual environment: $venv_name"
            return 1
        fi
    fi
}

# Clean up PATH from old venv
function _cleanup_venv_path {
    local old_venv_path="$1"
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

# Deactivate virtual environment
function dvenv {
    local was_poetry_active=0

    if [[ -n "$POETRY_ACTIVE" ]]; then
        was_poetry_active=1
        unset POETRY_ACTIVE
    fi

    if [[ -z "$VIRTUAL_ENV" ]]; then
        if (( was_poetry_active )); then
            print "Poetry environment variables cleared"
            return 0
        else
            print -u2 "Error: No virtual environment is currently active"
            return 1
        fi
    fi

    local current_venv="$(basename "$VIRTUAL_ENV")"

    if typeset -f deactivate >/dev/null 2>&1; then
        deactivate
        if (( was_poetry_active )); then
            print "✓ Deactivated Poetry environment: $current_venv"
        else
            print "✓ Deactivated virtual environment: $current_venv"
        fi
    else
        print -u2 "Warning: No deactivate function found, performing manual cleanup"

        local old_virtual_env="$VIRTUAL_ENV"
        _cleanup_venv_path "$old_virtual_env"

        unset VIRTUAL_ENV VIRTUAL_ENV_PROMPT

        if [[ -n "$_OLD_VIRTUAL_PS1" ]]; then
            PS1="$_OLD_VIRTUAL_PS1"
            unset _OLD_VIRTUAL_PS1
        fi

        if (( was_poetry_active )); then
            print "✓ Manually deactivated Poetry environment: $current_venv"
        else
            print "✓ Manually deactivated virtual environment: $current_venv"
        fi
    fi
}

# Remove virtual environment
function rmvenv {
    local venv_name="${1:-.venv}"

    if [[ "$venv_name" == ".venv" ]] && _is_poetry_project; then
        print "Poetry project detected. Use 'poetry env remove <python>' instead."
        print "Available Poetry environments:"
        if command -v poetry >/dev/null 2>&1; then
            poetry env list 2>/dev/null || print "  No Poetry environments found"
        fi
        return 1
    fi

    if [[ ! -e "$venv_name" ]]; then
        print -u2 "Error: Path '$venv_name' does not exist"
        return 1
    fi

    if [[ ! -d "$venv_name" ]]; then
        print -u2 "Error: '$venv_name' is not a directory"
        return 1
    fi

    if ! _is_valid_venv "$venv_name"; then
        print -u2 "Error: '$venv_name' does not appear to be a virtual environment"
        print -u2 "       Missing pyvenv.cfg file. Refusing to remove directory for safety."
        return 1
    fi

    # Check if this is the active environment
    if [[ -n "$VIRTUAL_ENV" ]]; then
        local current_venv_real="${VIRTUAL_ENV:A}"
        local target_venv_real="${venv_name:A}"

        if [[ "$current_venv_real" == "$target_venv_real" ]]; then
            print "Deactivating currently active virtual environment..."
            dvenv || {
                print -u2 "Error: Failed to deactivate virtual environment"
                return 1
            }
        fi
    fi

    print -n "Are you sure you want to remove '$venv_name'? [y/N] "
    local response
    if ! read -r response </dev/tty; then
        print
        print "Cancelled (EOF received)."
        return 1
    fi

    # Fix: Remove quotes from regex pattern
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        print "Cancelled."
        return 1
    fi

    print "Removing virtual environment: $venv_name"
    if ! rm -rf "$venv_name" 2>/dev/null; then
        print -u2 "Error: Failed to remove virtual environment. Check permissions."
        return 1
    fi

    print "✓ Virtual environment '$venv_name' removed"
}

# List virtual environments
function lsvenv {
    local current_dir="$PWD"
    local found_any=0

    print "Virtual environments in $current_dir:"

    # Show currently active environment
    if [[ -n "$VIRTUAL_ENV" ]]; then
        print "  Currently Active:"
        local env_type="standard"
        if [[ "$VIRTUAL_ENV" == *"pypoetry"* ]]; then
            env_type="poetry"
        fi
        printf "    %-30s %-15s %s\n" "$(basename "$VIRTUAL_ENV")" "($env_type)" "[active]"
        found_any=1
    fi

    # Show Poetry environments
    if _is_poetry_project; then
        print "  Poetry Project:"

        if command -v poetry >/dev/null 2>&1; then
            local poetry_envs
            if poetry_envs=$(poetry env list --full-path 2>/dev/null) && [[ -n "$poetry_envs" ]]; then
                local env_path env_status line
                while IFS= read -r line; do
                    if [[ -n "$line" ]]; then
                        env_path="${line%% *}"
                        env_status="[inactive]"

                        if [[ "$line" == *"(Activated)" ]] || [[ -n "$VIRTUAL_ENV" && "$VIRTUAL_ENV" == "$env_path" ]]; then
                            env_status="[active]"
                        fi

                        printf "    %-30s %-15s %s\n" "$(basename "$env_path")" "(poetry)" "$env_status"
                    fi
                done <<< "$poetry_envs"
                found_any=1
            else
                print "    No Poetry environments found (run 'poetry install')"
            fi
        else
            print "    Poetry not available"
        fi
    fi

    # Show local environments
    local -a venv_dirs=()
    venv_dirs=($(_find_venv_candidates))

    if (( ${#venv_dirs[@]} > 0 )); then
        print "  Local environments:"
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
        print "  No virtual environments found"
    fi
}

# Show virtual environment information
function venvinfo {
    local show_poetry=0

    if _is_poetry_shell_active || _is_poetry_project; then
        show_poetry=1
    fi

    if [[ -z "$VIRTUAL_ENV" ]] && (( ! show_poetry )); then
        print -u2 "Error: No virtual environment is currently active"
        return 1
    fi

    # Poetry project information
    if (( show_poetry )) && _is_poetry_project; then
        print "Poetry Project Information:"
        if command -v poetry >/dev/null 2>&1; then
            local project_info
            if project_info=$(poetry version 2>/dev/null); then
                print "  Project: $project_info"
            fi

            local poetry_env_info
            if poetry_env_info=$(poetry env info 2>/dev/null); then
                print "  Environment Info:"
                print "$poetry_env_info" | sed 's/^/    /'
            fi

            print "  Configuration:"
            poetry config --list 2>/dev/null | grep -E '^virtualenvs\.' | sed 's/^/    /'
        fi
        print ""
    fi

    # Active virtual environment information
    if [[ -n "$VIRTUAL_ENV" ]]; then
        print "Active virtual environment:"
        print "  Path: $VIRTUAL_ENV"
        print "  Name: $(basename "$VIRTUAL_ENV")"

        if [[ -n "$POETRY_ACTIVE" ]]; then
            print "  Type: Poetry managed"
        else
            print "  Type: Standard venv"
        fi

        if command -v python >/dev/null 2>&1; then
            print "  Python: $(python --version 2>&1)"
            print "  Python Path: $(command -v python)"
        else
            print "  Python: Not found in PATH"
        fi

        if command -v pip >/dev/null 2>&1; then
            print "  Pip: $(pip --version 2>&1 | head -1)"

            local pkg_count
            if pkg_count=$(pip list --format=freeze 2>/dev/null | wc -l); then
                print "  Packages: $pkg_count installed"
            else
                print "  Packages: Unable to count (pip error)"
            fi
        else
            print "  Pip: Not available"
        fi

        if [[ -f "$VIRTUAL_ENV/pyvenv.cfg" ]]; then
            print "  Configuration:"
            sed 's/^/    /' "$VIRTUAL_ENV/pyvenv.cfg"
        fi
    fi
}

# Utility functions
function _clear_python_cache {
    __PYTHON_CMD_CACHE=()
    print "Python command cache cleared"
}

function _poetry_shell_activate {
    if ! _is_poetry_project; then
        print -u2 "Error: Not in a Poetry project directory"
        return 1
    fi

    print "Activating Poetry shell..."
    exec poetry shell
}

function _poetry_env_create {
    local python_version="${1:-}"

    if ! _is_poetry_project; then
        print -u2 "Error: Not in a Poetry project directory"
        return 1
    fi

    if [[ -n "$python_version" ]]; then
        poetry env use "$python_version"
    else
        poetry install
    fi
}

# Convenient aliases
alias 'aenv'='avenv'
alias 'denv'='dvenv'
alias 'rmenv'='rmvenv'
alias 'mkenv'='mkvenv'
alias 'lsenv'='lsvenv'
alias 'vinfo'='venvinfo'

alias 'poshell'='_poetry_shell_activate'
alias 'poenv-create'='_poetry_env_create'
alias 'poclear'='_clear_python_cache'
