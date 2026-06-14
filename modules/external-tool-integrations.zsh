#!/usr/bin/env zsh
#
# External Tools Configuration Module
# Handles initialization of external tools and development utilities.
#

# ==============================================================================
# INDIVIDUAL TOOL SETUP FUNCTIONS
# ==============================================================================

__z::ext::setup_direnv()  { z::exec::from_hook "direnv" "hook" "zsh"; }
__z::ext::setup_mise()    { z::exec::from_hook "mise"   "activate"; }
__z::ext::setup_atuin()   { z::exec::from_hook "atuin"; }
__z::ext::setup_mcfly()   { z::exec::from_hook "mcfly"; }

###
# Initialize fzf (fuzzy finder).
###
__z::ext::setup_fzf() {
  emulate -L zsh -o no_aliases

  if ! z::probe::cmd "fzf"; then
    z::log::debug "fzf not found, skipping"
    return 0
  fi

  local -a key_paths comp_paths
  if [[ -n "${HOMEBREW_PREFIX:-}" ]]; then
    key_paths+=("${HOMEBREW_PREFIX}/opt/fzf/shell/key-bindings.zsh")
    comp_paths+=("${HOMEBREW_PREFIX}/opt/fzf/shell/completion.zsh")
  fi
  key_paths+=("/usr/share/fzf/key-bindings.zsh" "${HOME}/.fzf/shell/key-bindings.zsh")
  comp_paths+=("/usr/share/fzf/completion.zsh" "${HOME}/.fzf/shell/completion.zsh")

  local fzf_file
  local -i found_keys=0 found_comp=0
  for fzf_file in "${key_paths[@]}"; do
    [[ -f "$fzf_file" ]] || continue
    if builtin source "$fzf_file" 2>/dev/null; then
      z::log::debug "Loaded fzf key-bindings: $fzf_file"
      found_keys=1
      break
    fi
  done
  (( found_keys )) || z::log::debug "fzf key-bindings script not found or failed to load."

  for fzf_file in "${comp_paths[@]}"; do
    [[ -f "$fzf_file" ]] || continue
    if builtin source "$fzf_file" 2>/dev/null; then
      z::log::debug "Loaded fzf completion: $fzf_file"
      found_comp=1
      break
    fi
  done
  (( found_comp )) || z::log::debug "fzf completion script not found or failed to load."

  # Idempotent FZF_DEFAULT_OPTS append.
  local base_opts="--height 40% --layout=reverse --border --info=inline"
  if [[ "${FZF_DEFAULT_OPTS:-}" != *"--info=inline"* ]]; then
    export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:+${FZF_DEFAULT_OPTS} }${base_opts}"
  fi

  if [[ -z ${FZF_DEFAULT_COMMAND:-} ]]; then
    if z::probe::cmd "fd"; then
      export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    elif z::probe::cmd "rg"; then
      export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*"'
    fi
    [[ -n "${FZF_DEFAULT_COMMAND:-}" ]] && export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
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
    "${HOME}/.local/google-cloud-sdk"
  )

  local sdk_path path_script comp_script
  for sdk_path in "${sdk_paths[@]}"; do
    [[ -d "$sdk_path" ]] || continue

    z::log::debug "Found Google Cloud SDK at: $sdk_path"
    path_script="${sdk_path}/path.zsh.inc"
    comp_script="${sdk_path}/completion.zsh.inc"

    [[ -f "$path_script" ]] && builtin source "$path_script" 2>/dev/null
    [[ -f "$comp_script" ]] && builtin source "$comp_script" 2>/dev/null \
      && z::log::debug "gcloud completions sourced."

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

__z::ext::init() {
  emulate -L zsh -o no_aliases
  z::log::debug "Initializing external tools module..."

  local -a setup_functions=(
    __z::ext::setup_direnv
    __z::ext::setup_mise
    __z::ext::setup_atuin
    __z::ext::setup_fzf
    __z::ext::setup_gcloud_sdk
  )
  local -a simple_check_tools=(docker kubectl)

  local fn tool
  for fn in "${setup_functions[@]}"; do
    z::func::call "$fn"
  done
  for tool in "${simple_check_tools[@]}"; do
    z::probe::cmd "$tool" && z::log::debug "$tool is available in PATH."
  done

  z::log::debug "External tools module initialization complete."
  return 0
}

if z::probe::func "__z::ext::init"; then
  __z::ext::init
fi
