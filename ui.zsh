# =============================================================================
# z::ui / z::progress / z::util — Terminal UI Primitives
# =============================================================================
# Description: Provides terminal dimension queries, line/screen clearing,
#              progress bar rendering, spinner animation, comma-formatting
#              for integers, and progress visibility throttling logic.
#
# Usage:       Sourced as part of the z-framework; functions are not intended
#              to be called directly from the command line.
#
# Requires:    z::cache, z::config, z::log (internal framework modules)
#              tput (optional, fallback for terminal dimension detection)
# =============================================================================

# ---------------------------------------------------------------------------
# TERMINAL DIMENSIONS
# ---------------------------------------------------------------------------

z::ui::width() {
  emulate -L zsh

  # Return cached width if available (TTL: 1 second)
  local cached
  if cached=$(z::cache::get "ui:term_width"); then
    print -r -- "$cached"
    return 0
  fi

  typeset -i width=80
  local columns_current=${COLUMNS:-}

  # Prefer $COLUMNS if it is a valid integer
  if [[ $columns_current == <-> ]]; then
    ((width = 10#$columns_current))
  elif (($+commands[tput])); then
    # Fall back to tput when $COLUMNS is unset or non-numeric
    local tput_width
    if tput_width=$(tput cols 2>/dev/null) && [[ $tput_width == <-> ]]; then
      ((width = 10#$tput_width))
    fi
  fi

  z::cache::set "ui:term_width" "$width" --ttl 1
  print -r -- "$width"
  return 0
}

z::ui::height() {
  emulate -L zsh

  typeset -i rows=24
  local lines_current=${LINES:-}

  # Prefer $LINES if it is a valid integer
  if [[ $lines_current == <-> ]]; then
    ((rows = 10#$lines_current))
  elif (($+commands[tput])); then
    # Fall back to tput when $LINES is unset or non-numeric
    local tput_height
    if tput_height=$(tput lines 2>/dev/null) && [[ $tput_height == <-> ]]; then
      ((rows = 10#$tput_height))
    fi
  fi

  print -r -- "$rows"
  return 0
}

# ---------------------------------------------------------------------------
# TERMINAL CLEARING
# ---------------------------------------------------------------------------

z::ui::clear_line() {
  emulate -L zsh

  local arg
  typeset -i force=0 newline=1

  for arg in "$@"; do
    case $arg in
    -f | --force)
      force=1
      ;;
    -n | --no-newline)
      newline=0
      ;;
    --)
      break
      ;;
    *)
      return 1
      ;;
    esac
  done

  # Skip output when stderr is not a terminal, unless --force is passed
  ((force == 0)) && [[ ! -t 2 ]] && return 0

  printf '\r\e[K' >&2 # CR + erase to end of line
  ((newline)) && printf '\n' >&2
  return 0
}

z::ui::clear() {
  emulate -L zsh

  # Only clear when stdout is an interactive terminal
  if [[ -t 1 ]]; then
    clear
  fi

  return 0
}

# ---------------------------------------------------------------------------
# PROGRESS VISIBILITY THROTTLE
# ---------------------------------------------------------------------------

# Determines whether a progress update should be rendered for the given
# current/total pair, based on configurable interval and total-size tiers.
__z::progress::should_show() {
  emulate -L zsh

  # Both arguments must be valid integers
  [[ ${1-} == <-> && ${2-} == <-> ]] || return 1

  typeset -i current total interval=10
  local interval_raw

  ((current = 10#$1))
  ((total = 10#$2))

  # Allow the update interval to be overridden via framework config
  interval_raw=$(z::config::get progress_update_interval 2>/dev/null)
  if [[ $interval_raw == <-> ]]; then
    ((interval = 10#$interval_raw))
  fi
  ((interval < 1)) && interval=1

  # Always show the first and last item
  if ((current == 1 || current == total)); then
    return 0
  fi

  # Show every item when the total is very small
  if ((total <= 5)); then
    return 0
  fi

  # Show every other item for small totals
  if ((total <= 10)); then
    ((current % 2 == 0)) && return 0
    return 1
  fi

  # Show every 5th item for medium totals
  if ((total <= 50)); then
    ((current % 5 == 0)) && return 0
    return 1
  fi

  # For large totals: show on interval boundaries, or when nearing the end
  if ((current % interval == 0)) || ((total - current < interval)); then
    return 0
  fi

  return 1
}

# ---------------------------------------------------------------------------
# NUMBER FORMATTING
# ---------------------------------------------------------------------------

z::util::comma() {
  emulate -L zsh
  setopt localoptions typeset_silent

  local n="${1:-0}"
  local sign=''

  # Strip and preserve a leading minus sign
  if [[ $n == -* ]]; then
    sign='-'
    n="${n#-}"
  fi

  # Pass through non-integer values unchanged
  if [[ $n != <-> ]]; then
    print -r -- "${sign}${n}"
    return 0
  fi

  typeset -i len
  ((len = ${#n}))

  # No comma needed for numbers with 3 or fewer digits
  if ((len <= 3)); then
    print -r -- "${sign}${n}"
    return 0
  fi

  local result="" chunk
  typeset -i pos remainder

  # Handle the leading chunk that is shorter than 3 digits
  ((remainder = len % 3))
  if ((remainder > 0)); then
    result="${n[1,remainder]}"
    ((pos = remainder + 1))
  else
    ((pos = 1))
  fi

  # Walk through remaining digits in groups of 3
  while ((pos <= len)); do
    chunk="${n[pos,pos+2]}"
    if [[ -n $result ]]; then
      result="${result},${chunk}"
    else
      result="$chunk"
    fi
    ((pos += 3))
  done

  print -r -- "${sign}${result}"
  return 0
}

# ---------------------------------------------------------------------------
# PROGRESS BAR
# ---------------------------------------------------------------------------

z::progress::show() {
  emulate -L zsh

  if [[ ${1-} != <-> || ${2-} != <-> ]]; then
    z::log::debug "Invalid progress params: must be integers."
    return 1
  fi

  typeset -i current total term_width=80 percent_int filled bar_width empty_len
  local label="${3:-items}"
  local show_progress term_width_raw
  local bar_fill="" bar_empty="" progress_bar
  local current_fmt total_fmt

  ((current = 10#$1))
  ((total = 10#$2))

  if ((total <= 0 || current < 0 || current > total)); then
    z::log::debug "Invalid progress range: $current/$total."
    return 1
  fi

  # Skip rendering when log level is below INFO or stderr is not a terminal
  if ((${_zlog_config[level]:-0} < _ZLOG_LEVEL_INFO)) || [[ ! -t 2 ]]; then
    return 0
  fi

  show_progress=$(z::config::get show_progress 2>/dev/null)
  [[ -z $show_progress ]] && show_progress=true
  [[ $show_progress == false ]] && return 0

  # Apply throttle logic before doing any rendering work
  __z::progress::should_show "$current" "$total" || return 0

  term_width_raw=$(z::ui::width)
  if [[ $term_width_raw == <-> ]]; then
    ((term_width = 10#$term_width_raw))
  fi

  ((percent_int = (current * 100) / total))

  # Use a narrower bar on small terminals
  if ((term_width > 40)); then
    ((bar_width = 20))
  else
    ((bar_width = 10))
  fi

  ((filled = (current * bar_width) / total))
  ((filled < 0)) && filled=0
  ((filled > bar_width)) && filled=bar_width
  ((empty_len = bar_width - filled))

  # Build filled and empty segments by padding a string then substituting chars
  if ((filled > 0)); then
    printf -v bar_fill '%*s' "$filled" ''
    bar_fill=${bar_fill// /█}
  fi

  if ((empty_len > 0)); then
    printf -v bar_empty '%*s' "$empty_len" ''
    bar_empty=${bar_empty// /░}
  fi

  progress_bar="${bar_fill}${bar_empty}"
  current_fmt=$(z::util::comma "$current")
  total_fmt=$(z::util::comma "$total")

  # Wide terminals get a labelled format; narrow terminals get a compact one
  if ((term_width > 70)); then
    printf '\r\e[K[%s] %3d%% | %s: %s / %s\n' \
      "$progress_bar" "$percent_int" "$label" "$current_fmt" "$total_fmt" >&2
  else
    printf '\r\e[K[%s] %3d%% (%s/%s)\n' \
      "$progress_bar" "$percent_int" "$current_fmt" "$total_fmt" >&2
  fi
  return 0
}

# ---------------------------------------------------------------------------
# PROGRESS CONTROL
# ---------------------------------------------------------------------------

z::progress::clear() {
  emulate -L zsh
  z::ui::clear_line --no-newline
}

z::progress::enable() {
  emulate -L zsh
  z::config::set show_progress true
}

z::progress::disable() {
  emulate -L zsh
  z::config::set show_progress false
}

# ---------------------------------------------------------------------------
# SPINNER
# ---------------------------------------------------------------------------

z::progress::spinner() {
  emulate -L zsh

  local message="${1:-Working...}"
  local show_progress
  local -a frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

  show_progress=$(z::config::get show_progress 2>/dev/null)
  [[ -z $show_progress ]] && show_progress=true

  # Skip animation when stderr is not a terminal or progress is disabled
  if [[ ! -t 2 || $show_progress == false ]]; then
    return 0
  fi

  # Advance the global frame index, wrapping around the frames array
  typeset -gi _z_progress_spinner_idx
  ((_z_progress_spinner_idx = (_z_progress_spinner_idx % ${#frames[@]}) + 1))

  printf '\r\e[K%s %s' "${frames[_z_progress_spinner_idx]}" "$message" >&2
  return 0
}
