###
# Detects the current operating system and sets global boolean flags.
# This function is guarded to only run once for efficiency.
###
_detect_platform() {
  if [[ -n "${_PLATFORM_DETECTED:-}" ]]; then
    return 0
  fi

  # Set platform variables based on the built-in $OSTYPE variable.
  case "$OSTYPE" in
  darwin*)
    typeset -gri IS_MACOS=1 IS_LINUX=0 IS_BSD=0 IS_CYGWIN=0
    ;;
  linux*)
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

  # Check for Windows Subsystem for Linux (WSL).
  typeset -gri IS_WSL=0
  if ((IS_LINUX)); then
    if [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSLENV:-}" || -f "/proc/sys/fs/binfmt_misc/WSLInterop" ]]; then
      typeset -gri IS_WSL=1
    elif [[ -r "/proc/version" ]]; then
      local proc_version
      if proc_version=$(head -c 1024 "/proc/version" 2>/dev/null); then
        if [[ "$proc_version" == *[Mm]icrosoft* || "$proc_version" == *[Ww][Ss][Ll]* ]]; then
          typeset -gri IS_WSL=1
        fi
      fi
    fi
  fi

  # Check for Termux on Android.
  if ((IS_LINUX)) && [[ -d "/data/data/com.termux" ]]; then
    typeset -gri IS_TERMUX=1
  else
    typeset -gri IS_TERMUX=0
  fi

  # Set a flag for unknown platforms.
  if ((IS_MACOS || IS_LINUX || IS_BSD || IS_CYGWIN)); then
    typeset -gri IS_UNKNOWN=0
  else
    typeset -gri IS_UNKNOWN=1
  fi

  # Mark platform detection as complete.
  typeset -gr _PLATFORM_DETECTED=1

  if ((IS_UNKNOWN)); then
    _log_warn "Unknown platform: $OSTYPE"
  fi

  _log_debug "Platform: macOS=$IS_MACOS Linux=$IS_LINUX BSD=$IS_BSD WSL=$IS_WSL Cygwin=$IS_CYGWIN Termux=$IS_TERMUX"
}
