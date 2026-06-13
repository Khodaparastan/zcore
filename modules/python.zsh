#!/usr/bin/env zsh
#
# Python Development Module
# Provides intelligent environment detection and management for Python projects
# with full support for uv, poetry, and venv.
#

# ==============================================================================
# PRIVATE HELPERS - Project Type Detection
# ==============================================================================

###
# Detects the Python project type in a directory.
# Returns: "uv", "poetry", "venv", or "none"
###
__z::mod::python::detect_project_type()
{
  emulate -L zsh
  local project_dir="${1:-$PWD}"

  if [[ ! -d "$project_dir" ]]; then
    print "none"
    return 1
  fi

  # Priority 1: uv project (uv.lock or .venv with uv signature)
  if [[ -f "$project_dir/uv.lock" ]]; then
    print "uv"
    return 0
  fi

  # Check for uv-created venv
  if [[ -d "$project_dir/.venv" && -f "$project_dir/.venv/pyvenv.cfg" ]]; then
    local pyvenv_content
    if pyvenv_content=$(<"$project_dir/.venv/pyvenv.cfg" 2>/dev/null); then
      if [[ "$pyvenv_content" == *uv* ]]; then
        print "uv"
        return 0
      fi
    fi
  fi

  # Priority 2: poetry project
  if [[ -f "$project_dir/poetry.lock" ]]; then
    print "poetry"
    return 0
  fi

  if [[ -f "$project_dir/pyproject.toml" ]]; then
    local pyproject_content
    if pyproject_content=$(<"$project_dir/pyproject.toml" 2>/dev/null); then
      if [[ "$pyproject_content" == *'[tool.poetry]'* ]]; then
        print "poetry"
        return 0
      fi
    fi
  fi

  # Priority 3: plain venv
  if [[ -d "$project_dir/.venv" && -f "$project_dir/.venv/pyvenv.cfg" ]]; then
    print "venv"
    return 0
  fi

  print "none"
  return 1
}

###
# Gets the best Python command available, with optional version.
###
__z::mod::python::get_python_cmd()
{
  emulate -L zsh
  local version="${1:-}"

  if [[ -n "$version" ]]; then
    local cmd="python${version}"
    if z::probe::cmd "$cmd"; then
      print "$cmd"
      return 0
    fi
    z::log::error "Python ${version} not found"
    return 1
  fi

  # Try in order of preference
  local -a candidates=(python3 python py)
  local cmd version_output
  for cmd in "${candidates[@]}"; do
    if z::probe::cmd "$cmd"; then
      # Validate it's Python 3 - cache result
      if version_output=$("$cmd" --version 2>&1); then
        if [[ "$version_output" =~ 'Python[[:space:]]+3\.' ]]; then
          print "$cmd"
          return 0
        fi
      fi
    fi
  done

  z::log::error "No Python 3 interpreter found"
  return 1
}

###
# Finds activation script for a venv path.
###
__z::mod::python::find_activation_script()
{
  emulate -L zsh
  local venv_path="$1"

  if [[ -z "$venv_path" || ! -d "$venv_path" ]]; then
    return 1
  fi

  local -a candidates=(
    "$venv_path/bin/activate"
    "$venv_path/Scripts/activate"
  )

  local script
  for script in "${candidates[@]}"; do
    if [[ -f "$script" && -r "$script" ]]; then
      print "$script"
      return 0
    fi
  done

  return 1
}

###
# Validates if a path is a valid venv.
###
__z::mod::python::is_valid_venv()
{
  emulate -L zsh
  local path="$1"
  [[ -d "$path" && -f "$path/pyvenv.cfg" && -r "$path/pyvenv.cfg" ]]
}

###
# Finds all venv candidates in current directory.
###
__z::mod::python::find_venv_candidates()
{
  emulate -L zsh
  setopt local_options null_glob

  local -a candidates=()
  local -A seen=()

  # Priority order
  local -a patterns=(.venv venv .env env 'venv*' 'env*' '.env*')

  local pattern dir
  for pattern in "${patterns[@]}"; do
    for dir in ${~pattern}(N/); do
      if [[ -n "${seen[$dir]}" ]]; then
        continue
      fi
      if __z::mod::python::is_valid_venv "$dir"; then
        if __z::mod::python::find_activation_script "$dir" >/dev/null 2>&1; then
          candidates+=("$dir")
          seen[$dir]=1
        fi
      fi
    done
  done

  if ((${#candidates[@]} > 0)); then
    printf '%s\n' "${candidates[@]}"
  fi
}

###
# Gets poetry environment path.
###
__z::mod::python::get_poetry_env_path()
{
  emulate -L zsh
  local project_dir="${1:-$PWD}"

  # Check if already in poetry venv
  if [[ -n "$VIRTUAL_ENV" && "$VIRTUAL_ENV" == *"pypoetry"* ]]; then
    print "$VIRTUAL_ENV"
    return 0
  fi

  z::probe::cmd poetry || return 1

  local env_path
  if env_path=$(cd "$project_dir" && poetry env info --path 2>/dev/null); then
    if [[ -n "$env_path" && -d "$env_path" ]]; then
      print "$env_path"
      return 0
    fi
  fi

  return 1
}

###
# Common helper to source and activate a venv script.
# Returns 0 on success, 1 on failure.
###
__z::mod::python::activate_venv_script()
{
  emulate -L zsh
  local venv_path="$1"
  local label="${2:-virtual environment}"

  local activate_script
  if ! activate_script=$(__z::mod::python::find_activation_script "$venv_path"); then
    z::log::error "Activation script not found in: $venv_path"
    return 1
  fi

  if z::file::source "$activate_script" 2>/dev/null; then
    z::log::info "✓ Activated: $label"
    return 0
  else
    z::log::error "Failed to source activation script: $activate_script"
    return 1
  fi
}

# ==============================================================================
# PRIVATE HELPERS - Environment Setup
# ==============================================================================

###
# Sets up Python-related aliases and environment.
###
__z::mod::python::setup_aliases()
{
  emulate -L zsh

  local -i error_count=0

  # Python shortcuts
  if z::probe::cmd python; then
    z::env::alias_set 'py' 'python' || integer -i error_count=$((error_count + 1))
  fi
  if z::probe::cmd python3; then
    z::env::alias_set 'py3' 'python3' || integer -i error_count=$((error_count + 1))
  fi

  # Pip aliases
  if z::probe::cmd pip; then
    z::env::alias_set 'pipu' 'pip install --upgrade'
    z::env::alias_set 'pipr' 'pip install -r requirements.txt'
    z::env::alias_set 'pipf' 'pip freeze'
    z::env::alias_set 'pipl' 'pip list'
    z::env::alias_set 'pips' 'pip show'
  fi

  # Poetry aliases
  if z::probe::cmd poetry; then
    # Project
    z::env::alias_set 'poinit' 'poetry init'
    z::env::alias_set 'ponew' 'poetry new'

    # Dependencies
    z::env::alias_set 'poadd' 'poetry add'
    z::env::alias_set 'porm' 'poetry remove'
    z::env::alias_set 'poshow' 'poetry show'

    # Install
    z::env::alias_set 'poi' 'poetry install'
    z::env::alias_set 'pou' 'poetry update'
    z::env::alias_set 'polock' 'poetry lock'

    # Environment
    z::env::alias_set 'poenv' 'poetry env info'
    z::env::alias_set 'porun' 'poetry run'
    z::env::alias_set 'poshell' 'poetry shell'

    # Export
    z::env::alias_set 'poexport' 'poetry export -f requirements.txt -o requirements.txt'
  fi

  # uv aliases
  if z::probe::cmd uv; then
    # Project
    z::env::alias_set 'uvinit' 'uv init'
    z::env::alias_set 'uvbuild' 'uv build'

    # Dependencies
    z::env::alias_set 'uvadd' 'uv add'
    z::env::alias_set 'uvrm' 'uv remove'
    z::env::alias_set 'uvlock' 'uv lock'
    z::env::alias_set 'uvsync' 'uv sync'

    # Execution
    z::env::alias_set 'uvrun' 'uv run'
    z::env::alias_set 'uvtool' 'uv tool'

    # Pip interface
    z::env::alias_set 'uvpip' 'uv pip'
    z::env::alias_set 'uvpi' 'uv pip install'
    z::env::alias_set 'uvpl' 'uv pip list'
    z::env::alias_set 'uvpf' 'uv pip freeze'
  fi

  if ((error_count > 0)); then
    z::log::debug "Python aliases setup completed with $error_count warnings"
  fi
  return 0
}

# ==============================================================================
# PUBLIC API - Virtual Environment Management
# ==============================================================================

###
# Creates a new virtual environment.
# Usage: z::mod::pyenv::create [name] [python_version]
###
z::mod::pyenv::create()
{
  emulate -L zsh
  local venv_name="${1:-.venv}"
  local python_version="${2:-}"

  # Detect project type
  local project_type
  project_type=$(__z::mod::python::detect_project_type)

  case "$project_type" in
    uv)
      z::log::info "uv project detected"
      if z::probe::cmd uv; then
        z::log::info "Creating uv virtual environment..."
        local -a uv_args=("$venv_name")
        if [[ -n "$python_version" ]]; then
          uv_args+=(--python "$python_version")
        fi
        uv venv "${uv_args[@]}"
        return $?
      fi
      ;;
    poetry)
      z::log::info "Poetry project detected. Use 'poetry install' or 'poetry env use <python>'"
      return 1
      ;;
  esac

  # Validate venv name
  if [[ "$venv_name" =~ [[:space:]] ]]; then
    z::log::error "Virtual environment name cannot contain spaces"
    return 1
  fi

  if [[ -e "$venv_name" ]]; then
    z::log::error "Path '$venv_name' already exists"
    return 1
  fi

  # Get Python command
  local python_cmd
  python_cmd=$(__z::mod::python::get_python_cmd "$python_version") || return 1

  # Verify venv module with detailed error
  local venv_help_output
  if ! venv_help_output=$("$python_cmd" -m venv --help 2>&1); then
    z::log::error "venv module not available for $python_cmd"
    z::log::error "Install the python3-venv package (Debian/Ubuntu) or equivalent"
    z::log::debug "Error output: $venv_help_output"
    return 1
  fi

  # Get and display Python version
  local python_version_str
  python_version_str=$("$python_cmd" --version 2>&1)

  z::log::info "Creating virtual environment: $venv_name"
  z::log::info "Using: $python_cmd ($python_version_str)"

  local venv_error
  if ! venv_error=$("$python_cmd" -m venv "$venv_name" 2>&1); then
    z::log::error "Failed to create virtual environment"
    z::log::debug "Error: $venv_error"
    return 1
  fi

  # Auto-activate using common helper
  if __z::mod::python::activate_venv_script "$venv_name" "$venv_name"; then
    z::log::info "Upgrading pip..."
    python -m pip install --quiet --upgrade pip setuptools wheel 2>/dev/null || true
    z::log::info "✓ Virtual environment '$venv_name' created and activated"
    return 0
  fi

  z::log::warn "Created but failed to activate. Run: source $venv_name/bin/activate"
  return 0
}

###
# Activates a virtual environment (auto-detects project type).
# Usage: z::mod::pyenv::activate [path]
###
z::mod::pyenv::activate()
{
  emulate -L zsh
  local venv_path="${1:-}"

  if [[ -n "$VIRTUAL_ENV" ]]; then
    z::log::info "Already in virtual environment: $(basename "$VIRTUAL_ENV")"
    return 0
  fi

  # Explicit path provided
  if [[ -n "$venv_path" ]]; then
    if [[ ! -d "$venv_path" ]]; then
      z::log::error "Directory not found: $venv_path"
      return 1
    fi

    if ! __z::mod::python::is_valid_venv "$venv_path"; then
      z::log::error "Not a valid virtual environment: $venv_path"
      return 1
    fi

    __z::mod::python::activate_venv_script "$venv_path" "$venv_path"
    return $?
  fi

  # Auto-detect project type
  local project_type
  project_type=$(__z::mod::python::detect_project_type)

  case "$project_type" in
    uv|venv)
      local -a candidates
      candidates=(${(f)"$(__z::mod::python::find_venv_candidates)"})

      if ((${#candidates[@]} == 0)); then
        z::log::error "No virtual environment found. Run 'mkvenv' to create one"
        return 1
      fi

      local candidate="${candidates[1]}"
      z::log::debug "Found venv candidate: $candidate"
      __z::mod::python::activate_venv_script "$candidate" "$candidate"
      return $?
      ;;

    poetry)
      if ! z::probe::cmd poetry; then
        z::log::error "Poetry project detected but poetry not installed"
        return 1
      fi

      local poetry_env
      if poetry_env=$(__z::mod::python::get_poetry_env_path); then
        if __z::mod::python::activate_venv_script "$poetry_env" "Poetry environment"; then
          export POETRY_ACTIVE=1
          return 0
        fi
        return 1
      else
        z::log::info "Poetry project detected but no environment exists"
        z::log::info "Run 'poetry install' to create it"
        return 1
      fi
      ;;

    none)
      z::log::error "No Python project detected in current directory"
      return 1
      ;;
  esac

  z::log::error "Failed to activate virtual environment"
  return 1
}

###
# Deactivates the current virtual environment.
###
z::mod::pyenv::deactivate()
{
  emulate -L zsh

  if [[ -z "$VIRTUAL_ENV" ]]; then
    if [[ -n "${POETRY_ACTIVE:-}" ]]; then
      unset POETRY_ACTIVE
      z::log::info "Poetry environment markers cleared"
      return 0
    fi
    z::log::error "No virtual environment is active"
    return 1
  fi

  local venv_name="${VIRTUAL_ENV:t}"

  if z::probe::func deactivate; then
    deactivate
    if [[ -n "${POETRY_ACTIVE:-}" ]]; then
      unset POETRY_ACTIVE
    fi
    z::log::info "✓ Deactivated: $venv_name"
  else
    z::log::warn "No deactivate function available"
    unset VIRTUAL_ENV VIRTUAL_ENV_PROMPT
    if [[ -n "${POETRY_ACTIVE:-}" ]]; then
      unset POETRY_ACTIVE
    fi
    z::log::info "✓ Environment variables cleared"
  fi

  return 0
}

###
# Removes a virtual environment.
# Usage: z::mod::pyenv::remove [name]
###
z::mod::pyenv::remove()
{
  emulate -L zsh
  local venv_name="${1:-.venv}"

  

  if [[ ! -e "$venv_name" ]]; then
    z::log::error "Path does not exist: $venv_name"
    return 1
  fi

  if [[ ! -d "$venv_name" ]]; then
    z::log::error "Not a directory: $venv_name"
    return 1
  fi

  # Safety check
  if ! __z::mod::python::is_valid_venv "$venv_name"; then
    z::log::error "Not a valid virtual environment: $venv_name"
    z::log::error "Refusing to remove for safety (missing pyvenv.cfg)"
    return 1
  fi

  # Deactivate if active
  if [[ -n "$VIRTUAL_ENV" ]]; then
    local current_real="${VIRTUAL_ENV:A}"
    local target_real="${venv_name:A}"

    if [[ "$current_real" == "$target_real" ]]; then
      z::log::info "Deactivating active environment..."
      z::log::debug "Current: $current_real, Target: $target_real"
      z::mod::pyenv::deactivate || {
        z::log::error "Failed to deactivate"
        return 1
      }
    fi
  fi

  # Check for interactive terminal before prompting
  if [[ ! -t 0 ]]; then
    z::log::error "Non-interactive mode: refusing to remove without explicit confirmation"
    z::log::info "Use 'rm -rf \"$venv_name\"' manually if you're sure"
    return 1
  fi

  print -n "Remove '$venv_name'? [y/N] "
  local response
  read -r response </dev/tty || {
    print
    z::log::info "Cancelled"
    return 1
  }

  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    z::log::info "Cancelled"
    return 1
  fi

  z::log::info "Removing: $venv_name"
  if rm -rf "$venv_name" 2>/dev/null; then
    z::log::info "✓ Removed successfully"
  else
    z::log::error "Failed to remove. Check permissions"
    return 1
  fi
}

###
# Lists all virtual environments in current directory.
###
z::mod::pyenv::list()
{
  emulate -L zsh

  z::log::info "Python environments in $PWD:"
  local -i env_count=0

  # Show active
  if [[ -n "$VIRTUAL_ENV" ]]; then
    z::log::info "  Active:"
    local env_type="venv"
    if [[ "$VIRTUAL_ENV" == *"pypoetry"* ]]; then
      env_type="poetry"
    fi
    if [[ -n "${POETRY_ACTIVE:-}" ]]; then
      env_type="poetry"
    fi
    printf "    %-30s %-10s %s\n" "${VIRTUAL_ENV:t}" "($env_type)" "[active]"
    integer -i env_count=$((env_count + 1))
  fi

  # Show project type
  local project_type
  project_type=$(__z::mod::python::detect_project_type)

  case "$project_type" in
    uv)
      z::log::info "  Project: uv"
      integer -i env_count=$((env_count + 1))
      ;;
    poetry)
      z::log::info "  Project: Poetry"
      if z::probe::cmd poetry; then
        local envs
        if envs=$(poetry env list --full-path 2>/dev/null); then
          while IFS= read -r line; do
            if [[ -z "$line" ]]; then
              continue
            fi
            local path="${line%% *}"
            local env_state="[inactive]"
            if [[ "$line" == *"(Activated)"* ]]; then
              env_state="[active]"
            fi
            printf "    %-30s %-10s %s\n" "${path:t}" "(poetry)" "$env_state"
          done <<<"$envs"
        fi
      fi
      integer -i env_count=$((env_count + 1))
      ;;
  esac

  # Show local venvs
  local -a venvs
  venvs=(${(f)"$(__z::mod::python::find_venv_candidates)"})

  if ((${#venvs[@]} > 0)); then
    z::log::info "  Local:"
    local venv py_ver env_state
    for venv in "${venvs[@]}"; do
      py_ver="unknown"
      if [[ -f "$venv/pyvenv.cfg" ]]; then
        local pyvenv_line
        while IFS= read -r pyvenv_line; do
          if [[ "$pyvenv_line" =~ ^version[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            py_ver="${match[1]}"
            break
          fi
        done <"$venv/pyvenv.cfg" 2>/dev/null
      fi

      env_state="[inactive]"
      if [[ -n "$VIRTUAL_ENV" && "${VIRTUAL_ENV:A}" == "${venv:A}" ]]; then
        env_state="[active]"
      fi

      printf "    %-30s %-10s %s\n" "$venv" "($py_ver)" "$env_state"
      integer -i env_count=$((env_count + 1))
    done
  fi

  if ((env_count == 0)); then
    z::log::info "  None found"
  fi
}

###
# Shows detailed information about current environment.
###
z::mod::pyenv::info()
{
  emulate -L zsh

  local project_type
  project_type=$(__z::mod::python::detect_project_type)

  z::log::info "Python Environment Information:"
  z::log::info "  Project Type: $project_type"

  # Project-specific info
  case "$project_type" in
    uv)
      if z::probe::cmd uv; then
        local uv_ver
        uv_ver=$(uv --version 2>/dev/null)
        z::log::info "  uv version: $uv_ver"
        if [[ -f "uv.lock" ]]; then
          z::log::info "  Lock file: uv.lock (present)"
        fi
      fi
      ;;
    poetry)
      if z::probe::cmd poetry; then
        local ver
        ver=$(poetry version 2>/dev/null)
        if [[ -n "$ver" ]]; then
          z::log::info "  Poetry project: $ver"
        fi
        local poetry_info
        if poetry_info=$(poetry env info 2>/dev/null); then
          print "$poetry_info" | sed 's/^/    /'
        fi
      fi
      ;;
  esac

  # Active venv info
  if [[ -n "$VIRTUAL_ENV" ]]; then
    z::log::info "  Active venv: $VIRTUAL_ENV"
    if z::probe::cmd python; then
      local py_ver
      py_ver=$(python --version 2>&1)
      z::log::info "  Python: $py_ver"
    fi
    if z::probe::cmd pip; then
      local count
      count=$(pip list --format=freeze 2>/dev/null | wc -l)
      # Trim whitespace from wc output
      count="${count##*[[:space:]]}"
      z::log::info "  Packages: $count installed"
    fi
  else
    z::log::info "  No virtual environment active"
  fi
}

# ==============================================================================
# MODULE INITIALIZATION
# ==============================================================================

__z::mod::python::init()
{
  emulate -L zsh
  

  z::log::info "Initializing Python module..."

  # Setup aliases
  __z::mod::python::setup_aliases

  # User-facing command aliases
  z::env::alias_set 'mkvenv' 'z::mod::pyenv::create'
  z::env::alias_set 'avenv' 'z::mod::pyenv::activate'
  z::env::alias_set 'dvenv' 'z::mod::pyenv::deactivate'
  z::env::alias_set 'rmvenv' 'z::mod::pyenv::remove'
  z::env::alias_set 'lsvenv' 'z::mod::pyenv::list'
  z::env::alias_set 'venvinfo' 'z::mod::pyenv::info'

  # Shorter aliases
  z::env::alias_set 'mkenv' 'z::mod::pyenv::create'
  z::env::alias_set 'aenv' 'z::mod::pyenv::activate'
  z::env::alias_set 'denv' 'z::mod::pyenv::deactivate'
  z::env::alias_set 'lsenv' 'z::mod::pyenv::list'
  z::env::alias_set 'vinfo' 'z::mod::pyenv::info'

  z::log::info "Python module initialized successfully"
}

# Auto-initialize if function exists
if z::probe::func "__z::mod::python::init"; then
  __z::mod::python::init
fi
