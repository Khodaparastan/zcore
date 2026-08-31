#!/usr/bin/env zsh
# =============================================================================
# z/sys.zsh — Platform detection, interrupts, and fatal exits
# =============================================================================
# Description:  Classifies the host into the IS_* flags, handles INT/TERM
#               once and then hard, and terminates on a fatal error without
#               ever closing an interactive session.
#
# Part of:      z — assembled by bin/zbundle; see lib/z/parts
#
# Requires:     zlog, zbase (z::is::int), z::cache::set for the sys:* keys;
#               ui is optional and its absence is tolerated
# =============================================================================


typeset -gi _zcore_interrupted=0
typeset -gi _zcore_platform_detected=0
typeset -gi IS_MACOS=0 IS_LINUX=0 IS_BSD=0 IS_CYGWIN=0 IS_WSL=0 IS_TERMUX=0 IS_UNKNOWN=1

# __z::sys::clear_progress
# Tear down any active progress bar, tolerating the absence of the optional
# `ui` module. SAFETY: both callers are failure paths — dying with "command
# not found" while already handling a fatal error or an interrupt would mask
# the real problem. Always returns 0.
__z::sys::clear_progress() {
  (( ${+functions[z::progress::clear]} )) && z::progress::clear
  return 0
}

# __z::sys::handle_interrupt
# INT/TERM trap handler: clear the progress bar, warn once, and emit
# `sys:interrupted` when the bus is active. Returns 130 so the interrupted
# command reports the conventional status; a second interrupt exits
# immediately, and inside ZLE the keystroke is handed back to the editor.
__z::sys::handle_interrupt() {
  emulate -L zsh
  setopt extendedglob warncreateglobal typesetsilent noshortloops nopromptsubst
  if [[ -n ${ZLE_STATE:-} ]]; then
    # A trap returning 0 during ZLE swallows the interrupt entirely, leaving
    # the line editor wedged; hand the break back to ZLE instead.
    zle send-break
    return $?
  fi

  # A second interrupt means the graceful path is not working — leave now.
  if (( _zcore_interrupted )); then
    exit 130
  fi

  (( _zcore_interrupted = 1 ))
  __z::sys::clear_progress
  zlog::warn "Interrupt received. Gracefully shutting down..."

  if (( _zcore_subsys[bus] == 1 )); then
    z::event::emit "sys:interrupted"
  fi
  return 130
}

# z::sys::interrupted
# Report whether the interrupt trap has fired: returns ZCORE_ERROR_INTERRUPTED
# (130) once the user has pressed Ctrl+C, 0 otherwise. Poll this inside
# long-running loops to unwind at a safe point.
z::sys::interrupted() {
  emulate -L zsh
  setopt extendedglob warncreateglobal typesetsilent noshortloops nopromptsubst
  if (( _zcore_interrupted )); then
    zlog::info "Operation cancelled by user."
    return $ZCORE_ERROR_INTERRUPTED
  fi
  return 0
}

# z::sys::die <message> [<exit-code>]
# Log a fatal error and terminate. <exit-code> must be an integer in 1..255;
# anything else is rejected with a warning and Z_ERR_GENERAL is used instead.
# In an interactive shell the code is *returned* so a fatal error never closes
# the user's session; in a script it calls `exit`.
z::sys::die() {
  emulate -L zsh
  setopt extendedglob warncreateglobal typesetsilent noshortloops nopromptsubst
  local message="${1-}"
  # SAFETY: never feed argv straight into `(( ))` here — a non-numeric code
  # raises a math error inside the fatal path, and 0 would report success
  # from a fatal error.
  typeset -i exit_code=$Z_ERR_GENERAL
  if [[ -n ${2-} ]]; then
    if z::is::int "${2}" && (( ${2} > 0 && ${2} < 256 )); then
      exit_code=${2}
    else
      zlog::warn "z::sys::die: invalid exit code; using default" \
        given "${2}" using "$Z_ERR_GENERAL"
    fi
  fi

  __z::sys::clear_progress
  zlog::error "FATAL (exit $exit_code): $message"

  # SAFETY: `-o interactive` is the only reliable discriminator here.
  # $ZSH_EVAL_CONTEXT cannot be used: a genuine `source` yields
  # "toplevel:file", and by the time a function of this module runs the
  # context is "toplevel:shfunc" with no `file` component at all — so any
  # `*:file:*` test silently degrades into "always exit" and would kill the
  # interactive shell that sourced the framework.
  if [[ -o interactive ]]; then
    return $exit_code
  fi
  exit $exit_code
}

# z::sys::platform
# Classify the host and publish the result in the IS_* globals and the `sys:*`
# cache keys. Detection runs once per process; subsequent calls are free.
# Emits `sys:platform_detected` when the bus is active. Always returns 0.
z::sys::platform() {
  emulate -L zsh
  setopt extendedglob warncreateglobal typesetsilent noshortloops nopromptsubst

  # PERF: memoise in-process. Detection is idempotent and the IS_* flags are
  # globals already, so reading them back out of the cache would cost seven
  # forks per call (~7 ms) on a path that z::sys::is_* hits every time — and
  # would break outright once a single sys:is_* key had been evicted.
  if (( _zcore_platform_detected )); then
    return 0
  fi

  # $OSTYPE is a zsh builtin parameter, but stays overridable; fall back to
  # `uname -s` when something has unset it.
  local ostype_value="${OSTYPE:-}"
  if [[ -z $ostype_value ]]; then
    case "$(uname -s 2>/dev/null)" in
      Darwin)  ostype_value="darwin" ;;
      Linux)   ostype_value="linux" ;;
      *BSD*)   ostype_value="bsd" ;;
      CYGWIN*) ostype_value="cygwin" ;;
      *)       ostype_value="unknown" ;;
    esac
  fi

  local platform_name="unknown"
  case $ostype_value in
    darwin*)
      (( IS_MACOS = 1, IS_LINUX = 0, IS_BSD = 0, IS_CYGWIN = 0 ))
      platform_name="macos"
      ;;
    linux*)
      (( IS_MACOS = 0, IS_LINUX = 1, IS_BSD = 0, IS_CYGWIN = 0 ))
      platform_name="linux"
      ;;
    *bsd*|dragonfly*|netbsd*|openbsd*|freebsd*)
      (( IS_MACOS = 0, IS_LINUX = 0, IS_BSD = 1, IS_CYGWIN = 0 ))
      platform_name="bsd"
      ;;
    cygwin*|msys*|mingw*)
      (( IS_MACOS = 0, IS_LINUX = 0, IS_BSD = 0, IS_CYGWIN = 1 ))
      platform_name="cygwin"
      ;;
    *)
      (( IS_MACOS = 0, IS_LINUX = 0, IS_BSD = 0, IS_CYGWIN = 0 ))
      ;;
  esac

  # WSL exposes itself three ways and not all of them are present in every
  # release: environment hints, the binfmt interop file, or /proc/version.
  local -i is_wsl=0 is_termux=0
  if (( IS_LINUX )); then
    if [[ -n ${WSL_DISTRO_NAME:-} || -n ${WSLENV:-} || -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
      (( is_wsl = 1 ))
    elif [[ -r /proc/version ]]; then
      local proc_version=""
      if IFS= read -r proc_version < /proc/version 2>/dev/null; then
        if [[ $proc_version == *[Mm]icrosoft* || $proc_version == *[Ww][Ss][Ll]* ]]; then
          (( is_wsl = 1 ))
        fi
      fi
    fi
  fi
  (( IS_WSL = is_wsl ))

  # Termux always installs its prefix under this fixed Android data path.
  if (( IS_LINUX )) && [[ -d /data/data/com.termux/files/usr ]]; then
    (( is_termux = 1 ))
  fi
  (( IS_TERMUX = is_termux ))

  if (( IS_MACOS || IS_LINUX || IS_BSD || IS_CYGWIN )); then
    (( IS_UNKNOWN = 0 ))
  else
    (( IS_UNKNOWN = 1 ))
  fi

  # Published for consumers that read the sys:* keys directly. Detection
  # itself never reads them back — see the memoisation note above.
  z::cache::set "sys:platform" "$platform_name"
  z::cache::set "sys:is_macos" "$IS_MACOS"
  z::cache::set "sys:is_linux" "$IS_LINUX"
  z::cache::set "sys:is_bsd" "$IS_BSD"
  z::cache::set "sys:is_cygwin" "$IS_CYGWIN"
  z::cache::set "sys:is_wsl" "$IS_WSL"
  z::cache::set "sys:is_termux" "$IS_TERMUX"
  z::cache::set "sys:is_unknown" "$IS_UNKNOWN"

  (( _zcore_platform_detected = 1 ))
  zlog::debug "Platform: $platform_name"

  if (( _zcore_subsys[bus] == 1 )); then
    z::event::emit "sys:platform_detected" "$platform_name" 2>/dev/null || true
  fi

  return 0
}

# z::sys::is_macos / is_linux / is_bsd / is_wsl
# Silent predicates over the platform flags, forcing detection on first use.
# Each inverts its flag so that a set flag (1) becomes exit status 0.
z::sys::is_macos() { z::sys::platform; return $(( ! IS_MACOS )); }
z::sys::is_linux() { z::sys::platform; return $(( ! IS_LINUX )); }
z::sys::is_bsd()   { z::sys::platform; return $(( ! IS_BSD )); }
z::sys::is_wsl()   { z::sys::platform; return $(( ! IS_WSL )); }


