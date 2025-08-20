# --- Platform-Specific Aliases ---
setup_platform_aliases() {
  _detect_platform
  # --- General Aliases ---
  _safe_alias y 'yazi'
  _safe_alias dev 'cd ~/dev'
  _safe_alias zss 'cd ~/.ssh'
  _safe_alias zdd 'cd ${XDG_CONFIG_HOME:-$HOME/.config}'
  _safe_alias z 'j'
  _safe_alias skr 'ssh-keygen -R'
  _safe_alias sci 'ssh-copy-id -i'
  _safe_alias ssi 'ssh -i'

  if ((IS_MACOS)); then
    _safe_alias o 'open'
    _safe_alias clip 'pbcopy'
    if command -v yabai >/dev/null 2>&1; then
      _safe_alias ybr 'yabai --restart-service'
    fi
    local surge_cli='/Applications/Surge.app/Contents/Resources/surge-cli'
    [[ -x "$surge_cli" ]] && _safe_alias surge "$surge_cli"

  elif ((IS_LINUX)); then
    _safe_alias o 'xdg-open'
    if command -v xclip >/dev/null 2>&1; then
      _safe_alias clip 'xclip -selection clipboard'
    elif command -v xsel >/dev/null 2>&1; then
      _safe_alias clip 'xsel --clipboard --input'
    else
      _log_warn "No clipboard tool found (xclip or xsel) for Linux"
    fi

  elif ((IS_BSD)); then
    _safe_alias o 'xdg-open'
    if command -v xclip >/dev/null 2>&1; then
      _safe_alias clip 'xclip -selection clipboard'
    else
      _log_warn "No clipboard tool found (xclip) for BSD"
    fi

  elif ((IS_CYGWIN)); then
    _safe_alias o 'cygstart'
    _safe_alias clip 'cat > /dev/clipboard'
  fi

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
