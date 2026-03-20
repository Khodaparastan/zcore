#!/usr/bin/env zsh
#
# External Tools Configuration Module
# Handles initialization of external tools and development utilities
# Fully integrated with the zcore library.
#
# ==============================================================================
# INDIVIDUAL TOOL SETUP FUNCTIONS
# ==============================================================================

###
# Initialize direnv using the generic hook helper.
###
__z::ext::setup_direnv() {
  z::exec::from_hook "direnv" "hook" "zsh"
}

###
# Initialize mise using the generic hook helper.
###
__z::ext::setup_mise() {
  z::exec::from_hook "mise" "activate"
}

###
# Initialize zoxide using the generic hook helper.
###
__z::ext::setup_zoxide() {
  z::exec::from_hook "zoxide"
}

###
# Initialize atuin using the generic hook helper.
###
__z::ext::setup_atuin() {
  z::exec::from_hook "atuin"
}

###
# Initialize mcfly using the generic hook helper.
###
__z::ext::setup_mcfly() {
  z::exec::from_hook "mcfly"
}

###
# Initialize fzf (fuzzy finder) by sourcing its integration files.
###
__z::ext::setup_fzf() {
  emulate -L zsh -o no_aliases

  if ! z::probe::cmd "fzf"; then
    z::log::debug "fzf not found, skipping"
    return 0
  fi

  local -a key_paths=()
  local -a comp_paths=()
  local brew_prefix
  if z::probe::cmd "brew"; then
    brew_prefix="$(brew --prefix 2>/dev/null)"
    if [[ -n "$brew_prefix" ]]; then
      key_paths+=("${brew_prefix}/opt/fzf/shell/key-bindings.zsh")
      comp_paths+=("${brew_prefix}/opt/fzf/shell/completion.zsh")
    fi
  fi
  key_paths+=("/usr/share/fzf/key-bindings.zsh" "${HOME}/.fzf/shell/key-bindings.zsh")
  comp_paths+=("/usr/share/fzf/completion.zsh" "${HOME}/.fzf/shell/completion.zsh")

  local fzf_file found_keys=0 found_comp=0
  for fzf_file in "${key_paths[@]}"; do
    [[ -f "$fzf_file" ]] ||
      continue
    if z::file::source "$fzf_file"; then
      z::log::debug "Loaded fzf key-bindings: $fzf_file"
      found_keys=1
      break
    fi
  done
  ((!found_keys)) &&
    z::log::debug "fzf key-bindings script not found or failed to load."

  for fzf_file in "${comp_paths[@]}"; do
    [[ -f "$fzf_file" ]] ||
      continue
    if z::file::source "$fzf_file"; then
      z::log::debug "Loaded fzf completion: $fzf_file"
      found_comp=1
      break
    fi
  done
  ((!found_comp)) &&
    z::log::debug "fzf completion script not found or failed to load."

  local base_opts="--height 40% --layout=reverse --border --info=inline"
  if [[ -n ${FZF_DEFAULT_OPTS:-} ]]; then
    export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS} ${base_opts}"
  else
    export FZF_DEFAULT_OPTS="${base_opts}"
  fi

  if [[ -z ${FZF_DEFAULT_COMMAND:-} ]]; then
    if z::probe::cmd "fd"; then
      export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    elif z::probe::cmd "rg"; then
      export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*"'
    fi
    [[ -n "$FZF_DEFAULT_COMMAND" ]] &&
      export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  fi

  z::log::debug "fzf setup completed"
  return 0
}

###
# Initialize Google Cloud SDK if found in common locations.
###
__z::ext::setup_gcloud_sdk() {
  emulate -L zsh -o no_aliases

  local -a sdk_paths=(
    # "${HOME}/google-cloud-sdk"
    "${HOME}/.local/google-cloud-sdk"
    # "/opt/google-cloud-sdk"
    # "/usr/lib/google-cloud-sdk"
  )
  # local brew_prefix
  # if z::probe::cmd "brew"; then
  #   brew_prefix="$(brew --prefix 2>/dev/null)"
  #   [[ -n "$brew_prefix" ]] &&
  #     sdk_paths+=("${brew_prefix}/share/google-cloud-sdk")
  # fi

  local sdk_path
  for sdk_path in "${sdk_paths[@]}"; do
    [[ -d "$sdk_path" ]] ||
      continue

    z::log::debug "Found Google Cloud SDK at: $sdk_path"
    local path_script="${sdk_path}/path.zsh.inc"
    local comp_script="${sdk_path}/completion.zsh.inc"
    z::log::debug "comp_script is at $comp_script"
    [[ -f "$path_script" ]] &&
      z::file::source --global "$path_script"
    [[ -f "$comp_script" ]] &&
      z::file::source --global "$comp_script" && z::log::debug "gcloud completions sourced."

    z::log::info "Google Cloud SDK initialized from: $sdk_path"
    return 0
  done

  if z::probe::cmd "gcloud"; then
    z::log::info "gcloud command found in PATH but SDK directory not located in standard paths."
  else
    z::log::debug "Google Cloud SDK not found."
  fi

  return 0
}

# ==============================================================================
# MAIN INITIALIZATION ORCHESTRATOR
# ==============================================================================

###
# Public entry point to set up all external tools.
###
__z::ext::init() {
  emulate -L zsh -o no_aliases
  z::log::debug "Initializing external tools module..."

  local -a setup_functions=(
    "__z::ext::setup_direnv"
    "__z::ext::setup_mise"
    # "__z::ext::setup_zoxide"
    "__z::ext::setup_atuin"
    # "__z::ext::setup_mcfly"
    "__z::ext::setup_fzf"
    "__z::ext::setup_gcloud_sdk"
  )
  local -a simple_check_tools=(
    "docker"
    "kubectl"
  )

  local setup_func
  for setup_func in "${setup_functions[@]}"; do
    z::func::call "$setup_func"
  done

  local tool
  for tool in "${simple_check_tools[@]}"; do
    if z::probe::cmd "$tool"; then
      z::log::debug "$tool is available in PATH."
    fi
  done

  z::log::debug "External tools module initialization complete."
  return 0
}

# ==============================================================================
# MODULE EXECUTION
# ==============================================================================

# Auto-initialize all tools when this module is sourced.
if z::probe::func "__z::ext::init"; then
  __z::ext::init
fi
