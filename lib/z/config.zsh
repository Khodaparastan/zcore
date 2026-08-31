#!/usr/bin/env zsh
# =============================================================================
# z/config.zsh — KV-backed configuration
# =============================================================================
# Description:  Seeds and validates configuration in the zkv `config` store,
#               typing each key by its name suffix, and saves or loads the
#               whole set as key=value text.
#
# Part of:      z — assembled by bin/zbundle; see lib/z/parts
#
# Requires:     zlog, zkv; emits config:changed through z::event::* when the
#               bus subsystem is active
# =============================================================================

# Values are typed by key suffix rather than by an explicit schema: `*_mode`,
# `show_*` and `enable_*` are booleans, `*_size`/`*_timeout`/`*_depth`/
# `*_threshold`/`*_interval`/`*_iterations`/`*_level` are integers, everything
# else is a string. Adding a key means picking a name that reads correctly.

# __z::config::set_default <key> <value> [int|bool|string]
# Seed a configuration default. Existing values are never overwritten, so this
# is safe to call on every load.
__z::config::set_default() {
  emulate -L zsh
  local key="$1" value="$2" kind="${3:-string}"

  if z::kv::exists config "$key" 2>/dev/null; then
    return 0
  fi

  case "$kind" in
    int)  z::kv::set_int  config "$key" "$value" ;;
    bool) z::kv::set_bool config "$key" "$value" ;;
    *)    z::kv::set      config "$key" "$value" ;;
  esac
}

# __z::config::init_defaults
# Open the `config` store and seed every built-in default, then apply the
# ZCORE_* environment overrides on top. Called once from INITIALIZATION;
# propagates the store's status if it cannot be opened.
__z::config::init_defaults() {
  emulate -L zsh

  z::kv::open config || return $?

  __z::config::set_default "log_level"                "$_ZLOG_LEVEL_INFO" int
  __z::config::set_default "cache_max_size"           "100"     int
  __z::config::set_default "timeout_default"          "30"      int
  __z::config::set_default "performance_mode"         "false"   bool
  __z::config::set_default "show_progress"            "true"    bool
  __z::config::set_default "symlink_max_iterations"   "40"      int
  __z::config::set_default "progress_update_interval" "10"      int
  __z::config::set_default "progress_style"           "classic"

  # Environment wins over the seeded defaults, but not over a value the user
  # has already stored — these are set unconditionally, the defaults are not.
  if [[ -n ${ZCORE_PERFORMANCE_MODE:-} ]]; then
    z::kv::set_bool config "performance_mode" "$ZCORE_PERFORMANCE_MODE"
  fi

  if [[ -n ${ZCORE_SHOW_PROGRESS:-} ]]; then
    z::kv::set_bool config "show_progress" "$ZCORE_SHOW_PROGRESS"
  fi

  if [[ -n ${ZCORE_PROGRESS_STYLE:-} ]]; then
    z::kv::set config "progress_style" "$ZCORE_PROGRESS_STYLE"
  fi

  zlog::debug "Configuration defaults initialized"
  return 0
}

# z::config::get <key>
# Read a configuration value into REPLY. Returns Z_ERR_INPUT on an empty key,
# otherwise the status of the underlying store (Z_ERR_NOTFOUND when the key is
# absent). Read REPLY immediately — any subsequent zlog call clobbers it.
z::config::get() {
  emulate -L zsh
  local key="${1:-}"

  if [[ -z $key ]]; then
    zlog::error "Config key required"
    return $Z_ERR_INPUT
  fi

  z::kv::get config "${key}"
  return $?
}

# z::config::set <key> <value>
# Validate <value> against the type implied by the key suffix and store it.
# Emits `config:changed` when the bus is active. Returns Z_ERR_INPUT on an
# empty key or a value of the wrong type.
z::config::set() {
  emulate -L zsh
  local key="${1:-}"
  local value="${2:-}"

  if [[ -z $key ]]; then
    zlog::error "Config key required"
    return $Z_ERR_INPUT
  fi

  local rc=0

  # The key suffix selects both the typed setter and the validation rule.
  case $key in
    *_mode|show_*|enable_*)
      if [[ $value != true && $value != false ]]; then
        zlog::error "Boolean required for $key"
        return $Z_ERR_INPUT
      fi
      z::kv::set_bool config "${key}" "$value" || rc=$?
      ;;
    *_size|*_timeout|*_depth|*_threshold|*_interval|*_iterations|*_level)
      if [[ $value != <-> ]]; then
        zlog::error "Integer required for $key"
        return $Z_ERR_INPUT
      fi
      z::kv::set_int config "${key}" "$value" || rc=$?
      ;;
    *)
      z::kv::set config "${key}" "$value" || rc=$?
      ;;
  esac

  if (( rc )); then
    return $rc
  fi

  zlog::debug "Config updated: $key = $value"

  if (( _zcore_subsys[bus] == 1 )); then
    z::event::emit "config:changed" "$key" "$value" || true
  fi

  return 0
}

# z::config::watch <pattern> <handler>
# Invoke <handler> whenever a configuration key matching the glob <pattern>
# changes; see z::kv::watch for the handler contract. Returns Z_ERR_INPUT when
# either argument is empty.
z::config::watch() {
  emulate -L zsh
  local pattern="${1:-}"
  local handler="${2:-}"

  if [[ -z $pattern || -z $handler ]]; then
    zlog::error "Pattern and handler required"
    return $Z_ERR_INPUT
  fi

  z::kv::watch config "${pattern}" "$handler"
}

# z::config::show
# Print every configuration key and value to stdout as an aligned table.
# Unreadable keys are shown as N/A. Always returns 0.
z::config::show() {
  emulate -L zsh

  print "\nConfiguration:"
  print "=============="

  local -a config_keys
  z::kv::keys config "*"
  config_keys=("${reply[@]}")

  local key value
  for key in "${config_keys[@]}"; do
    if z::kv::get config "$key"; then
      value="$REPLY"
    else
      value="N/A"
    fi
    printf "  %-30s = %s\n" "$key" "$value"
  done

  print ""
  return 0
}

# z::config::save <file>
# Write the whole configuration to <file> as `key=value` lines with a version
# banner, in a format z::config::load reads back. Returns Z_ERR_INPUT on an
# empty path, Z_ERR_GENERAL when the file cannot be written.
z::config::save() {
  emulate -L zsh
  local file="${1:-}"

  if [[ -z $file ]]; then
    zlog::error "File path required"
    return $Z_ERR_INPUT
  fi

  # The whole group is tested, not just the last `print`: an unwritable path
  # fails at redirection time and must not be reported as a successful save.
  if ! {
    print "# ZCORE Configuration v${ZCORE_VERSION}"
    print "# Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    print ""

    local -a config_keys
    z::kv::keys config "*"
    config_keys=("${reply[@]}")

    local key value
    for key in "${config_keys[@]}"; do
      if z::kv::get config "$key"; then
        value="$REPLY"
      else
        value=""
      fi
      print "${key}=${value}"
    done
  } > "$file"; then
    zlog::error "Failed to write configuration" file "$file"
    return $Z_ERR_GENERAL
  fi

  zlog::info "Configuration saved: $file"
  return 0
}

# z::config::load <file>
# Apply a file written by z::config::save. Blank lines and `#` comments are
# skipped; each remaining line is split on its first `=` and passed through
# z::config::set, so type validation still applies and a rejected key is
# warned about rather than aborting the load. Returns Z_ERR_INPUT on an empty
# path, Z_ERR_NOTFOUND when <file> is missing or unreadable.
z::config::load() {
  emulate -L zsh
  local file="${1:-}"

  if [[ -z $file ]]; then
    zlog::error "File path required"
    return $Z_ERR_INPUT
  fi

  if [[ ! -f $file || ! -r $file ]]; then
    zlog::error "Cannot read: $file"
    return $Z_ERR_NOTFOUND
  fi

  local line key value
  while IFS= read -r line; do
    # Skip comment-only and blank lines.
    [[ $line =~ ^[[:space:]]*# ]] && continue
    [[ $line =~ ^[[:space:]]*$ ]] && continue

    # $match holds the capture groups; [^=]+ is greedy-safe here because the
    # second group swallows any further `=` in the value.
    if [[ $line =~ ^([^=]+)=(.*)$ ]]; then
      key="${match[1]}"
      value="${match[2]}"
      z::config::set "$key" "$value" || zlog::warn "Failed: $key=$value"
    fi
  done < "$file"

  zlog::info "Configuration loaded: $file"
  return 0
}


