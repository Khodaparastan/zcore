#!/usr/bin/env zsh
###
# Detects the current operating system and sets global boolean flags.
# This function is guarded to only run once for efficiency.
###

z::detect::platform()
{
  emulate -L zsh
  setopt no_unset typeset_silent

  # Allow running regardless of sourcing order; gracefully skip if interrupted checker is unavailable
  if typeset -f z::runtime::check_interrupted > /dev/null 2>&1; then
    z::runtime::check_interrupted \
      || return $?
  fi

  if [[ -n "${_PLATFORM_DETECTED:-}" ]]; then
    return 0
  fi

  # Defensive fallback if OSTYPE is empty
  local ostype_value="${OSTYPE:-}"
  if [[ -z "$ostype_value" ]]; then
    case "$(uname -s 2> /dev/null)" in
      Darwin) ostype_value="darwin" ;;
      Linux) ostype_value="linux" ;;
      FreeBSD | OpenBSD | NetBSD | DragonFly) ostype_value="bsd" ;;
      CYGWIN* | MSYS* | MINGW*) ostype_value="cygwin" ;;
      *) ostype_value="unknown" ;;
    esac
  fi

  # Set platform variables based on $ostype_value
  case "$ostype_value" in
    darwin*)
      typeset -gri IS_MACOS=1 IS_LINUX=0 IS_BSD=0 IS_CYGWIN=0
      ;;
    linux* | linux-gnu*)
      typeset -gri IS_MACOS=0 IS_LINUX=1 IS_BSD=0 IS_CYGWIN=0
      ;;
    *bsd* | dragonfly* | netbsd* | openbsd* | freebsd*)
      typeset -gri IS_MACOS=0 IS_LINUX=0 IS_BSD=1 IS_CYGWIN=0
      ;;
    cygwin* | msys* | mingw*)
      typeset -gri IS_MACOS=0 IS_LINUX=0 IS_BSD=0 IS_CYGWIN=1
      ;;
    *)
      typeset -gri IS_MACOS=0 IS_LINUX=0 IS_BSD=0 IS_CYGWIN=0
      ;;
  esac

  # Check for Windows Subsystem for Linux (WSL)
  local is_wsl=0
  if ((IS_LINUX)); then
    if [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSLENV:-}" || -f "/proc/sys/fs/binfmt_misc/WSLInterop" ]]; then
      is_wsl=1
    elif [[ -r "/proc/version" ]]; then
      local proc_version=""
      # Avoid subshell: read directly
      if IFS= read -r proc_version < /proc/version 2> /dev/null; then
        if [[ "$proc_version" == *[Mm]icrosoft* || "$proc_version" == *[Ww][Ss][Ll]* ]]; then
          is_wsl=1
        fi
      fi
    fi
  fi
  typeset -gri IS_WSL=$is_wsl

  # Check for Termux on Android
  local is_termux=0
  if ((IS_LINUX)) \
    && [[ -d "/data/data/com.termux/files/usr" ]]; then
    is_termux=1
  fi
  typeset -gri IS_TERMUX=$is_termux

  # Unknown flag
  if ((IS_MACOS || IS_LINUX || IS_BSD || IS_CYGWIN)); then
    typeset -gri IS_UNKNOWN=0
  else
    typeset -gri IS_UNKNOWN=1
  fi

  # Mark complete
  typeset -gr _PLATFORM_DETECTED=1

  # Logging (guard if zcore loggers are not yet available)
  if ((IS_UNKNOWN)); then
    if typeset -f z::log::warn > /dev/null 2>&1; then
      z::log::warn "Unknown platform: ${ostype_value}"
    else
      print -r -- "Unknown platform: ${ostype_value}" >&2
    fi
  fi

  if typeset -f z::log::debug > /dev/null 2>&1; then
    z::log::debug "Platform: macOS=$IS_MACOS Linux=$IS_LINUX BSD=$IS_BSD WSL=$IS_WSL Cygwin=$IS_CYGWIN Termux=$IS_TERMUX"
  fi

  return 0
}
