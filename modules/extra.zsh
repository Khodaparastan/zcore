# --- Platform-Specific Aliases ---
setup_platform_aliases() {
  z::runtime::check_interrupted || return $?

  # --- General Aliases ---
  z::alias::define y 'yazi'
  z::alias::define dev 'cd ~/dev'
  z::alias::define zss 'cd ~/.ssh'
  z::alias::define zdd 'cd ${XDG_CONFIG_HOME:-$HOME/.config}'
#  z::alias::define z 'j'
  z::alias::define skr 'ssh-keygen -R'
  z::alias::define sci 'ssh-copy-id -i'
  z::alias::define ssi 'ssh -i'

  if ((IS_MACOS)); then
    z::alias::define o 'open'
    z::alias::define clip 'pbcopy'
    if command -v yabai >/dev/null 2>&1; then
      z::alias::define ybr 'yabai --restart-service'
    fi
    local surge_cli='/Applications/Surge.app/Contents/Resources/surge-cli'
    if [[ -x "$surge_cli" ]]; then
      z::alias::define surge "$surge_cli"
    fi

  elif ((IS_LINUX)); then
    z::alias::define o 'xdg-open'
    if command -v xclip >/dev/null 2>&1; then
      z::alias::define clip 'xclip -selection clipboard'
    elif command -v xsel >/dev/null 2>&1; then
      z::alias::define clip 'xsel --clipboard --input'
    else
      z::log::warn "No clipboard tool found (xclip or xsel) for Linux"
    fi

  elif ((IS_BSD)); then
    z::alias::define o 'xdg-open'
    if command -v xclip >/dev/null 2>&1; then
      z::alias::define clip 'xclip -selection clipboard'
    else
      z::log::warn "No clipboard tool found (xclip) for BSD"
    fi

  elif ((IS_CYGWIN)); then
    z::alias::define o 'cygstart'
    z::alias::define clip 'cat > /dev/clipboard'
  fi

  z::log::debug "Platform-specific aliases configured for: $PLATFORM"
  return 0
}

###
# Detects the Google Cloud SDK installation, sets the Python interpreter,
# and sources the necessary shell integration files.
###
_setup_gcloud_sdk() {
  _detect_platform

  # --- Find GCloud SDK Base Path ---
  local gcloud_base="${GCLOUD_SDK_PATH:-}" # 1. Check environment variable first.
  if [[ -z "$gcloud_base" ]]; then
    # 2. Check common installation locations.
    local -a possible_bases=("$HOME/.local/google-cloud-sdk" "$HOME/google-cloud-sdk" "/usr/lib/google-cloud-sdk")
    for base in "${possible_bases[@]}"; do
      if [[ -d "$base/bin" ]]; then
        gcloud_base="$base"
        break
      fi
    done
  fi
  if [[ -z "$gcloud_base" ]] && command -v gcloud >/dev/null 2>&1; then
    # 3. As a last resort, derive from the command path.
    gcloud_base="$(dirname "$(dirname "$(command -v gcloud)")")"
  fi

  if [[ -z "$gcloud_base" || ! -d "$gcloud_base" ]]; then
    _log_debug "Google Cloud SDK not found."
    return 1
  fi

  local -a gcloud_files=(
    "$gcloud_base/path.zsh.inc"
    "$gcloud_base/completion.zsh.inc"
  )
  local -i success_count=0
  for file in "${gcloud_files[@]}"; do
    if _safe_source "$file"; then
      ((success_count++))
    fi
  done

  # --- Set Python Interpreter ---
  local gcloud_python="${GCLOUD_PYTHON_PATH:-}"
  if [[ -z "$gcloud_python" ]]; then
    # Prefer the SDK's bundled Python if it exists.
    if [[ -x "$gcloud_base/gcp-venv/bin/python" ]]; then
      gcloud_python="$gcloud_base/gcp-venv/bin/python"
    else
      # Fallback to system python3.
      gcloud_python="$(command -v python3 2>/dev/null)"
    fi
  fi

  if [[ -n "$gcloud_python" && -x "$gcloud_python" ]]; then
    export CLOUDSDK_PYTHON="$gcloud_python"
    _log_debug "Set CLOUDSDK_PYTHON to: $gcloud_python"
  fi

  if ((success_count > 0)); then
    _log_debug "Google Cloud SDK initialized ($success_count files loaded)"
    return 0
  fi
  return 1
}

###
# Sets up external shell tools if available.
###
_setup_external_tools() {
  if command -v mise >/dev/null 2>&1; then
    _safe_eval "$(mise activate zsh)" 10 true
  fi

  if command -v direnv >/dev/null 2>&1; then
    _safe_eval "$(direnv hook zsh)" 10 true
  fi

  if ((IS_MACOS)); then
    local -a autojump_scripts=(
      '/opt/homebrew/etc/profile.d/autojump.sh'
      '/usr/local/etc/profile.d/autojump.sh'
    )
    for script in "${autojump_scripts[@]}"; do
      if _safe_source "$script"; then
        _log_debug "autojump loaded from: $script"
        break
      fi
    done
  fi
}

###
# Creates stub functions for optional plugins to prevent errors if they are not loaded.
###
_create_stub_functions() {
  # Stub for a common Git prompt function.
  if ! _function_exists _git_prompt_info; then
    _git_prompt_info() { return 0; }
  fi

  # Stubs for Zconvey, a testing tool that might not be present.
  local -a zconvey_functions=(
    __zconvey_on_period_passed26
    __zconvey_on_period_passed30
    __zconvey_on_period_passed
  )
  for func in "${zconvey_functions[@]}"; do
    if ! _function_exists "$func"; then
      eval "$func() { return 0; }"
    fi
  done
}
