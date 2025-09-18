#!/usr/bin/env zsh
#
# Clipboard Tools Module
# Provides user-facing functions for clipboard interaction.
#

# ==============================================================================
# USER-FACING FUNCTIONS
# ==============================================================================

###
# Copies the contents of a file to the system clipboard.
# Intelligently detects the best available clipboard utility.
###
cpfile()
{
  emulate -L zsh
  # This function is user-facing, so it uses `print` for output, not z::log.

  local -i max_size=${CPFILE_MAX_SIZE:-5242880} # 5MB
  if (($# == 0)); then
    print -r -- "Usage: cpfile <filename>" >&2
    return 1
  fi
  local file="$1"

  if [[ ! -f "$file" ]]; then
    print -r -- "Error: File not found: '$file'" >&2
    return 1
  fi
  if [[ ! -r "$file" ]]; then
    print -r -- "Error: File not readable: '$file'" >&2
    return 1
  fi

  # Check file size
  local -i file_size
  file_size=$(
    zstat +size -- "$file" 2> /dev/null \
      || stat -c %s -- "$file" 2> /dev/null \
      || stat -f %z -- "$file" 2> /dev/null \
      || wc -c < "$file" 2> /dev/null
  )
  if ((file_size > max_size)); then
    printf "Error: File '%s' is too large to copy.\n" "$file" >&2
    return 1
  fi

  # Find the best clipboard tool
  local clipboard_cmd
  if ((IS_MACOS)); then
    clipboard_cmd="pbcopy"
  elif z::cmd::exists "clip.exe"; then # WSL
    clipboard_cmd="clip.exe"
  elif [[ -n "${WAYLAND_DISPLAY:-}" ]] \
    && z::cmd::exists "wl-copy"; then
    clipboard_cmd="wl-copy"
  elif [[ -n "${DISPLAY:-}" ]] \
    && z::cmd::exists "xclip"; then
    clipboard_cmd="xclip -selection clipboard -in"
  elif z::cmd::exists "tmux"; then
    clipboard_cmd="tmux load-buffer -w -"
  fi

  if [[ -z "$clipboard_cmd" ]]; then
    print -r -- "Error: No clipboard utility found." >&2
    return 1
  fi

  if < "$file" $clipboard_cmd; then
    print -r -- "✓ Copied contents of '$file' to clipboard."
  else
    print -r -- "Error: Failed to copy to clipboard using '$clipboard_cmd'." >&2
    return 1
  fi
}

###
# Backwards-compatibility alias for cpfile.
###
cbf()
{
  cpfile "$@"
}

# ==============================================================================
# MAIN INITIALIZATION
# ==============================================================================
z::mod::clipboard::init()
{
  emulate -L zsh
  z::log::info "Clipboard tools (cpfile) are now available."
}

if z::func::exists "z::mod::clipboard::init"; then
  z::mod::clipboard::init
fi
