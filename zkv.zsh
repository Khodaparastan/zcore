
################################################################################
# KV STORE - Depends ONLY on zsh-log
################################################################################

# Main key-value storage
typeset -gA _zcore_kv_store

# Metadata storage (TTL, types, etc.)
typeset -gA _zcore_kv_meta

# TTL expiration times (key -> epoch timestamp)
typeset -gA _zcore_kv_ttl

# Watch patterns and handlers
typeset -gA _zcore_kv_watchers

# Transaction state
typeset -gA _zcore_kv_transaction
typeset -gi _zcore_kv_in_transaction=0
# List storage: key -> pipe-separated values
typeset -gA _zcore_kv_lists

# Set storage: key -> pipe-separated unique values
typeset -gA _zcore_kv_sets

# Sorted set storage: key -> pipe-separated "score:value" pairs
typeset -gA _zcore_kv_zsets

# Hash storage: key.field -> value
typeset -gA _zcore_kv_hashes

# Pub/Sub channels: channel -> subscriber_list
typeset -gA _zcore_kv_pubsub

# Locks: lock_name -> owner_id|expire_time
typeset -gA _zcore_kv_locks

# Snapshot storage
typeset -gA _zcore_kv_snapshots
typeset -gi _zcore_kv_snapshot_id=0
# Statistics
typeset -gA _zcore_kv_stats=(
  [reads]=0
  [writes]=0
  [deletes]=0
  [hits]=0
  [misses]=0
)

# Configuration
typeset -gA _zcore_kv_config=(
  [auto_persist]=false
  [persist_file]=""
  [enable_events]=true
  [enable_ttl]=true
  [max_key_length]=256
  [max_value_length]=65536
)

################################################################################
# INTERNAL HELPERS
################################################################################

###
# Validate key format
# @param 1: string - Key name
# @private
# @return 0 if valid, 1 if invalid
###
__z::kv::validate_key() {
  emulate -L zsh
  local key="$1"

  if [[ -z $key ]]; then
    z::log::error "KV: Key cannot be empty"
    return 1
  fi

  if (( ${#key} > ${_zcore_kv_config[max_key_length]} )); then
    z::log::error "KV: Key too long: ${#key} > ${_zcore_kv_config[max_key_length]}"
    return 1
  fi

  # Allow alphanumeric, dots, underscores, hyphens, AND colons
  if [[ ! $key =~ '^[a-zA-Z0-9._:-]+$' ]]; then
    z::log::error "KV: Invalid key format: $key"
    return 1
  fi

  return 0
}

###
# Check and expire TTL keys
# @param 1: string - Key name
# @private
# @return 0 if valid, 1 if expired
###
__z::kv::check_ttl() {
  emulate -L zsh
  local key="$1"

  if [[ ${_zcore_kv_config[enable_ttl]} != true ]]; then
    return 0
  fi

  if (( ! ${+_zcore_kv_ttl[$key]} )); then
    return 0  # No TTL set
  fi

  typeset -i expire_time current_time
  (( expire_time = ${_zcore_kv_ttl[$key]} ))
  (( current_time = ${EPOCHSECONDS:-$(date +%s)} ))

  if (( current_time >= expire_time )); then
    # Key expired
    z::log::debug "KV: Key expired: $key"
    unset "_zcore_kv_store[$key]"
    unset "_zcore_kv_meta[$key]"
    unset "_zcore_kv_ttl[$key]"
    return 1
  fi

  return 0
}

###
# Trigger watch handlers for key pattern
# @param 1: string - Key that changed
# @param 2: string - New value
# @param 3: string - Operation (set|del)
# @private
# @return 0 always
###
__z::kv::trigger_watchers() {
  emulate -L zsh
  local key="$1"
  local value="$2"
  local operation="${3:-set}"

  if ((_zcore_subsys[bus]==1)); then
    return 0
  fi
  # Emit generic KV event
  z::event::emit "kv:${operation}" "$key" "$value" 2>/dev/null || true

  # Check watch patterns
  local pattern handler_list
  for pattern in "${(@k)_zcore_kv_watchers}"; do
    # Match pattern (support wildcards)
    if [[ $key == ${~pattern} ]]; then
      handler_list="${_zcore_kv_watchers[$pattern]}"

      # Call each handler
      local -a handlers
      handlers=(${(s:|:)handler_list})

      local handler
      for handler in "${handlers[@]}"; do
        if z::probe::func "$handler" 2>/dev/null; then
          "$handler" "$key" "$value" "$operation" 2>/dev/null || true
        fi
      done
    fi
  done

  return 0
}

###
# Auto-persist if enabled
# @private
# @return 0 always
###
__z::kv::auto_persist() {
  emulate -L zsh

  if [[ ${_zcore_kv_config[auto_persist]} == true ]] && \
     [[ -n ${_zcore_kv_config[persist_file]} ]]; then
    z::kv::save "${_zcore_kv_config[persist_file]}" 2>/dev/null || true
  fi

  return 0
}

################################################################################
# CORE OPERATIONS
################################################################################

###
# Set a key-value pair
#
# Usage:
#   z::kv::set "app.name" "MyApp"
#   z::kv::set "counter" "42" --ttl 3600
#   z::kv::set "debug" "true" --type bool
#
# @param 1: string - Key name
# @param 2: string - Value
# @param 3: string - --ttl N (optional, seconds until expiration)
# @param 4: string - --type TYPE (optional, for metadata)
# @return 0 on success, 1 on failure
###
z::kv::set() {
  emulate -L zsh
  setopt localoptions no_unset

  local key="$1"
  local value="$2"
  shift 2

  # Validate key
  __z::kv::validate_key "$key" || return 1

  # Validate value length
  if (( ${#value} > ${_zcore_kv_config[max_value_length]} )); then
    z::log::error "KV: Value too long for key '$key': ${#value} > ${_zcore_kv_config[max_value_length]}"
    return 1
  fi

  # Parse options
  typeset -i ttl=0
  local value_type="string"

  while (( $# > 0 )); do
    case "$1" in
      --ttl)
        if [[ ${2:-} == <-> ]]; then
          (( ttl = 10#${2} ))
          shift 2
        else
          z::log::error "KV: Invalid TTL value: ${2:-}"
          return 1
        fi
        ;;
      --type)
        value_type="${2:-string}"
        shift 2
        ;;
      *)
        z::log::warn "KV: Unknown option: $1"
        shift
        ;;
    esac
  done

  # Store value
  _zcore_kv_store[$key]="$value"
  _zcore_kv_meta[$key]="$value_type"

  # Set TTL if specified
  if (( ttl > 0 )); then
    typeset -i expire_time
    (( expire_time = ${EPOCHSECONDS:-$(date +%s)} + ttl ))
    _zcore_kv_ttl[$key]=$expire_time
    z::log::debug "KV: Set TTL for '$key': ${ttl}s (expires at $expire_time)"
  else
    unset "_zcore_kv_ttl[$key]"
  fi

  # Update stats
  (( _zcore_kv_stats[writes] += 1 ))

  # Trigger watchers and events
  __z::kv::trigger_watchers "$key" "$value" "set"

  # Auto-persist
  __z::kv::auto_persist

  z::log::debug "KV: Set '$key' = '$value' (type: $value_type)"

  return 0
}

###
# Get a value by key
#
# Usage:
#   value=$(z::kv::get "app.name")
#   z::kv::get "counter" || echo "Key not found"
#
# @param 1: string - Key name
# @stdout Value if exists
# @return 0 if found, 1 if not found or expired
###
z::kv::get() {
  emulate -L zsh
  setopt localoptions no_unset

  local key="$1"

  # Validate key
  __z::kv::validate_key "$key" || return 1

  # Check TTL
  if ! __z::kv::check_ttl "$key"; then
    (( _zcore_kv_stats[misses] += 1 ))
    return 1
  fi

  # Check existence
  if (( ! ${+_zcore_kv_store[$key]} )); then
    (( _zcore_kv_stats[misses] += 1 ))
    z::log::debug "KV: Key not found: $key"
    return 1
  fi

  # Update stats
  (( _zcore_kv_stats[reads] += 1 ))
  (( _zcore_kv_stats[hits] += 1 ))

  # Return value
  print -r -- "${_zcore_kv_store[$key]}"
  return 0
}

###
# Delete a key
#
# Usage:
#   z::kv::del "app.name"
#
# @param 1: string - Key name
# @return 0 on success, 1 if key doesn't exist
###
z::kv::del() {
  emulate -L zsh
  setopt localoptions no_unset

  local key="$1"

  # Validate key
  __z::kv::validate_key "$key" || return 1

  # Check existence
  if (( ! ${+_zcore_kv_store[$key]} )); then
    z::log::debug "KV: Key not found for deletion: $key"
    return 1
  fi

  local old_value="${_zcore_kv_store[$key]}"

  # Delete
  unset "_zcore_kv_store[$key]"
  unset "_zcore_kv_meta[$key]"
  unset "_zcore_kv_ttl[$key]"

  # Update stats
  (( _zcore_kv_stats[deletes] += 1 ))

  # Trigger watchers
  __z::kv::trigger_watchers "$key" "$old_value" "del"

  # Auto-persist
  __z::kv::auto_persist

  z::log::debug "KV: Deleted '$key'"

  return 0
}

###
# Check if key exists
#
# Usage:
#   if z::probe::kv "app.name"; then
#     echo "Key exists"
#   fi
#
# @param 1: string - Key name
# @return 0 if exists and not expired, 1 otherwise
###
z::probe::kv() {
  emulate -L zsh
  setopt localoptions no_unset

  local key="$1"

  __z::kv::validate_key "$key" || return 1
  __z::kv::check_ttl "$key" || return 1

  (( ${+_zcore_kv_store[$key]} ))
}

###
# List all keys matching pattern
#
# Usage:
#   z::kv::keys              # All keys
#   z::kv::keys "app.*"      # Keys starting with "app."
#   z::kv::keys "*.config"   # Keys ending with ".config"
#
# @param 1: string - Pattern (optional, default: "*")
# @stdout List of matching keys (one per line)
# @return 0 always
###
z::kv::keys() {
  emulate -L zsh
  setopt localoptions no_unset extended_glob

  local pattern="${1:-*}"

  local key
  for key in "${(@k)_zcore_kv_store}"; do
    # Check TTL
    __z::kv::check_ttl "$key" || continue

    # Match pattern
    if [[ $key == ${~pattern} ]]; then
      print -r -- "$key"
    fi
  done

  return 0
}

################################################################################
# TYPE-SAFE OPERATIONS
################################################################################

###
# Set integer value
# @param 1: string - Key
# @param 2: integer - Value
# @return 0 on success, 1 on failure
###
z::kv::set_int() {
  emulate -L zsh
  local key="$1"
  local value="$2"

  if [[ $value != <-> && $value != -<-> ]]; then
    z::log::error "KV: Not an integer: $value"
    return 1
  fi

  z::kv::set "$key" "$value" --type int
}

###
# Get integer value
# @param 1: string - Key
# @stdout Integer value
# @return 0 on success, 1 on failure
###
z::kv::get_int() {
  emulate -L zsh
  local value
  value=$(z::kv::get "$1") || return 1

  if [[ $value != <-> && $value != -<-> ]]; then
    z::log::error "KV: Not an integer: $value"
    return 1
  fi

  print -r -- "$value"
  return 0
}

###
# Set boolean value
# @param 1: string - Key
# @param 2: bool - Value (true/false, 1/0, yes/no)
# @return 0 on success, 1 on failure
###
z::kv::set_bool() {
  emulate -L zsh
  local key="$1"
  local value="$2"

  # Normalize boolean
  case "${value:l}" in
    true|1|yes|y|on) value="true" ;;
    false|0|no|n|off) value="false" ;;
    *)
      z::log::error "KV: Invalid boolean: $value"
      return 1
      ;;
  esac

  z::kv::set "$key" "$value" --type bool
}

###
# Get boolean value
# @param 1: string - Key
# @stdout "true" or "false"
# @return 0 if true, 1 if false or not found
###
z::kv::get_bool() {
  emulate -L zsh
  local value
  value=$(z::kv::get "$1") || return 1

  case "${value:l}" in
    true|1|yes|y|on)
      print "true"
      return 0
      ;;
    false|0|no|n|off)
      print "false"
      return 1
      ;;
    *)
      z::log::error "KV: Not a boolean: $value"
      return 1
      ;;
  esac
}

###
# Set array value (pipe-separated internally)
# @param 1: string - Key
# @param ...: string - Array elements
# @return 0 on success
###
z::kv::set_array() {
  emulate -L zsh
  local key="$1"
  shift

  local value="${(j:|:)@}"
  z::kv::set "$key" "$value" --type array
}

###
# Get array value
# @param 1: string - Key
# @param 2: string - Output array variable name
# @return 0 on success, 1 on failure
###
z::kv::get_array() {
  emulate -L zsh
  local key="$1"
  local output_var="$2"

  local value
  value=$(z::kv::get "$key") || return 1

  # Split by pipe and assign to array
  eval "${output_var}=(\"\${(@s:|:)value}\")"
  return 0
}

################################################################################
# ATOMIC OPERATIONS
################################################################################

###
# Increment integer value
# @param 1: string - Key
# @param 2: integer - Amount (optional, default: 1)
# @return 0 on success, 1 on failure
###
z::kv::incr() {
  emulate -L zsh
  local key="$1"
  typeset -i amount
  (( amount = ${2:-1} ))

  typeset -i current
  if z::probe::kv "$key"; then
    current=$(z::kv::get_int "$key") || current=0
  else
    current=0
  fi

  (( current += amount ))
  z::kv::set_int "$key" "$current"
}

###
# Decrement integer value
# @param 1: string - Key
# @param 2: integer - Amount (optional, default: 1)
# @return 0 on success, 1 on failure
###
z::kv::decr() {
  emulate -L zsh
  local key="$1"
  typeset -i amount
  (( amount = ${2:-1} ))

  z::kv::incr "$key" $(( -amount ))
}

###
# Append to string value
# @param 1: string - Key
# @param 2: string - Value to append
# @return 0 on success
###
z::kv::append() {
  emulate -L zsh
  local key="$1"
  local append_value="$2"

  local current=""
  if z::probe::kv "$key"; then
    current=$(z::kv::get "$key")
  fi

  z::kv::set "$key" "${current}${append_value}"
}

################################################################################
# TTL OPERATIONS
################################################################################

###
# Get remaining TTL for key
# @param 1: string - Key
# @stdout Remaining seconds (-1 if no TTL, -2 if not found)
# @return 0 always
###
z::kv::ttl() {
  emulate -L zsh
  local key="$1"

  if ! z::probe::kv "$key"; then
    print -- "-2"
    return 0
  fi

  if (( ! ${+_zcore_kv_ttl[$key]} )); then
    print -- "-1"  # No TTL
    return 0
  fi

  typeset -i expire_time current_time remaining
  (( expire_time = ${_zcore_kv_ttl[$key]} ))
  (( current_time = ${EPOCHSECONDS:-$(date +%s)} ))
  (( remaining = expire_time - current_time ))

  if (( remaining < 0 )); then
    remaining=0
  fi

  print -- "$remaining"
  return 0
}

###
# Set TTL for existing key
# @param 1: string - Key
# @param 2: integer - TTL in seconds
# @return 0 on success, 1 if key doesn't exist
###
z::kv::expire() {
  emulate -L zsh
  local key="$1"
  typeset -i ttl
  (( ttl = ${2:-0} ))

  if ! z::probe::kv "$key"; then
    z::log::error "KV: Cannot set TTL on non-existent key: $key"
    return 1
  fi

  if (( ttl <= 0 )); then
    unset "_zcore_kv_ttl[$key]"
    z::log::debug "KV: Removed TTL from '$key'"
  else
    typeset -i expire_time
    (( expire_time = ${EPOCHSECONDS:-$(date +%s)} + ttl ))
    _zcore_kv_ttl[$key]=$expire_time
    z::log::debug "KV: Set TTL for '$key': ${ttl}s"
  fi

  return 0
}

###
# Remove TTL from key (make it persistent)
# @param 1: string - Key
# @return 0 on success
###
z::kv::persist() {
  emulate -L zsh
  local key="$1"

  unset "_zcore_kv_ttl[$key]"
  z::log::debug "KV: Made key persistent: $key"
  return 0
}

################################################################################
# PERSISTENCE
################################################################################

###
# Save KV store to file
#
# Usage:
#   z::kv::save "/tmp/app.db"
#
# @param 1: string - File path
# @return 0 on success, 1 on failure
###
z::kv::save() {
  emulate -L zsh
  setopt localoptions no_unset

  local file="$1"

  if [[ -z $file ]]; then
    z::log::error "KV: No file specified for save"
    return 1
  fi

  z::log::info "KV: Saving to $file"

  {
    print "# ZCORE KV Store Dump"
    print "# Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    print "# Version: 1.0"
    print ""

    local key value value_type
    typeset -i ttl_remaining

    for key in "${(@k)_zcore_kv_store}"; do
      # Skip expired keys
      __z::kv::check_ttl "$key" || continue

      value="${_zcore_kv_store[$key]}"
      value_type="${_zcore_kv_meta[$key]:-string}"

      # Escape special characters
      value="${value//\\/\\\\}"
      value="${value//$'\n'/\\n}"
      value="${value//|/\\|}"

      # Get TTL
      ttl_remaining=$(z::kv::ttl "$key")

      # Format: key|type|ttl|value
      print "${key}|${value_type}|${ttl_remaining}|${value}"
    done
  } > "$file"

  z::log::info "KV: Saved ${#_zcore_kv_store} keys to $file"
  return 0
}

###
# Load KV store from file
#
# Usage:
#   z::kv::load "/tmp/app.db"
#
# @param 1: string - File path
# @return 0 on success, 1 on failure
###
z::kv::load() {
  emulate -L zsh
  setopt localoptions no_unset

  local file="$1"

  if [[ -z $file ]]; then
    z::log::error "KV: No file specified for load"
    return 1
  fi

  if [[ ! -f $file || ! -r $file ]]; then
    z::log::error "KV: Cannot read file: $file"
    return 1
  fi

  z::log::info "KV: Loading from $file"

  typeset -i loaded=0
  local line key value_type ttl_val value

  while IFS= read -r line; do
    # Skip comments and empty lines
    [[ $line =~ '^[[:space:]]*(#.*)?$' ]] && continue

    # Parse: key|type|ttl|value
    key="${line%%|*}"
    local rest="${line#*|}"
    value_type="${rest%%|*}"
    rest="${rest#*|}"
    ttl_val="${rest%%|*}"
    value="${rest#*|}"

    # Unescape special characters
    value="${value//\\n/$'\n'}"
    value="${value//\\\\/\\}"
    value="${value//\\|/|}"

    # Set value
    if [[ $ttl_val == <-> ]] && (( ttl_val > 0 )); then
      z::kv::set "$key" "$value" --type "$value_type" --ttl "$ttl_val"
    else
      z::kv::set "$key" "$value" --type "$value_type"
    fi

    (( loaded += 1 ))
  done < "$file"

  z::log::info "KV: Loaded $loaded keys from $file"
  return 0
}

################################################################################
# WATCH PATTERNS
################################################################################

###
# Watch keys matching pattern
#
# Usage:
#   z::kv::watch "config.*" my_handler
#   my_handler() {
#     local key="$1" value="$2" operation="$3"
#     echo "Changed: $key = $value ($operation)"
#   }
#
# @param 1: string - Key pattern (supports wildcards)
# @param 2: string - Handler function name
# @return 0 on success
###
z::kv::watch() {
  emulate -L zsh
  local pattern="$1"
  local handler="$2"

  if [[ -z $pattern || -z $handler ]]; then
    z::log::error "KV: watch requires pattern and handler"
    return 1
  fi

  if ! z::probe::func "$handler"; then
    z::log::error "KV: Handler function not found: $handler"
    return 1
  fi

  # Add handler to pattern
  local existing="${_zcore_kv_watchers[$pattern]:-}"
  if [[ -n $existing ]]; then
    _zcore_kv_watchers[$pattern]="${existing}|${handler}"
  else
    _zcore_kv_watchers[$pattern]="$handler"
  fi

  z::log::debug "KV: Watching pattern '$pattern' with handler '$handler'"
  return 0
}

###
# Stop watching pattern
# @param 1: string - Key pattern
# @param 2: string - Handler function name (optional, removes all if omitted)
# @return 0 on success
###
z::kv::unwatch() {
  emulate -L zsh
  local pattern="$1"
  local handler="${2:-}"

  if [[ -z $pattern ]]; then
    z::log::error "KV: unwatch requires pattern"
    return 1
  fi

  if [[ -z $handler ]]; then
    # Remove all handlers for pattern
    unset "_zcore_kv_watchers[$pattern]"
    z::log::debug "KV: Removed all watchers for pattern '$pattern'"
  else
    # Remove specific handler
    local existing="${_zcore_kv_watchers[$pattern]:-}"
    if [[ -n $existing ]]; then
      local -a handlers
      handlers=(${(s:|:)existing})
      handlers=(${(@)handlers:#$handler})

      if (( ${#handlers} > 0 )); then
        _zcore_kv_watchers[$pattern]="${(j:|:)handlers}"
      else
        unset "_zcore_kv_watchers[$pattern]"
      fi

      z::log::debug "KV: Removed watcher '$handler' from pattern '$pattern'"
    fi
  fi

  return 0
}

################################################################################
# BULK OPERATIONS
################################################################################

###
# Set multiple key-value pairs
# @param ...: string - Alternating keys and values
# @return 0 on success
###
z::kv::mset() {
  emulate -L zsh

  if (( $# % 2 != 0 )); then
    z::log::error "KV: mset requires even number of arguments (key value pairs)"
    return 1
  fi

  while (( $# >= 2 )); do
    z::kv::set "$1" "$2" || return 1
    shift 2
  done

  return 0
}

###
# Get multiple values
# @param ...: string - Keys
# @stdout Values (one per line, empty line if not found)
# @return 0 always
###
z::kv::mget() {
  emulate -L zsh

  local key value
  for key in "$@"; do
    if value=$(z::kv::get "$key" 2>/dev/null); then
      print -r -- "$value"
    else
      print ""
    fi
  done

  return 0
}

###
# Clear all keys matching pattern
# @param 1: string - Pattern (optional, default: "*" = all keys)
# @return 0 always
###
z::kv::clear() {
  emulate -L zsh
  local pattern="${1:-*}"

  local -a keys_to_delete
  keys_to_delete=($(z::kv::keys "$pattern"))

  typeset -i deleted=0
  local key
  for key in "${keys_to_delete[@]}"; do
    z::kv::del "$key" && (( deleted += 1 ))
  done

  z::log::debug "KV: Cleared $deleted keys matching '$pattern'"
  return 0
}

################################################################################
# TRANSACTIONS
################################################################################

###
# Begin transaction
# @return 0 on success, 1 if already in transaction
###
z::kv::begin() {
  emulate -L zsh

  if (( _zcore_kv_in_transaction )); then
    z::log::error "KV: Already in transaction"
    return 1
  fi

  # Backup current state using a better format
  local -a store_backup meta_backup ttl_backup

  local key value
  for key value in "${(@kv)_zcore_kv_store}"; do
    store_backup+=("$key")
    store_backup+=("$value")
  done

  for key value in "${(@kv)_zcore_kv_meta}"; do
    meta_backup+=("$key")
    meta_backup+=("$value")
  done

  for key value in "${(@kv)_zcore_kv_ttl}"; do
    ttl_backup+=("$key")
    ttl_backup+=("$value")
  done

  _zcore_kv_transaction[store]="${(F)store_backup}"
  _zcore_kv_transaction[meta]="${(F)meta_backup}"
  _zcore_kv_transaction[ttl]="${(F)ttl_backup}"

  (( _zcore_kv_in_transaction = 1 ))
  z::log::debug "KV: Transaction started"
  return 0
}

###
# Commit transaction
# @return 0 on success
###
z::kv::commit() {
  emulate -L zsh

  if (( ! _zcore_kv_in_transaction )); then
    z::log::warn "KV: Not in transaction"
    return 0
  fi

  # Clear backup
  _zcore_kv_transaction=()
  (( _zcore_kv_in_transaction = 0 ))

  z::log::debug "KV: Transaction committed"
  return 0
}

###
# Rollback transaction
# @return 0 on success
###
z::kv::rollback() {
  emulate -L zsh

  if (( ! _zcore_kv_in_transaction )); then
    z::log::warn "KV: Not in transaction"
    return 0
  fi

  # Parse and restore backup
  local backup_store="${_zcore_kv_transaction[store]}"
  local backup_meta="${_zcore_kv_transaction[meta]}"
  local backup_ttl="${_zcore_kv_transaction[ttl]}"

  # Clear current state
  _zcore_kv_store=()
  _zcore_kv_meta=()
  _zcore_kv_ttl=()

  # Restore store
  if [[ -n $backup_store ]]; then
    local -a lines
    lines=("${(@f)backup_store}")

    typeset -i i
    for (( i = 1; i <= ${#lines}; i += 2 )); do
      local key="${lines[i]}"
      local value="${lines[i+1]}"
      [[ -n $key ]] && _zcore_kv_store[$key]="$value"
    done
  fi

  # Restore meta
  if [[ -n $backup_meta ]]; then
    local -a lines
    lines=("${(@f)backup_meta}")

    typeset -i i
    for (( i = 1; i <= ${#lines}; i += 2 )); do
      local key="${lines[i]}"
      local value="${lines[i+1]}"
      [[ -n $key ]] && _zcore_kv_meta[$key]="$value"
    done
  fi

  # Restore TTL
  if [[ -n $backup_ttl ]]; then
    local -a lines
    lines=("${(@f)backup_ttl}")

    typeset -i i
    for (( i = 1; i <= ${#lines}; i += 2 )); do
      local key="${lines[i]}"
      local value="${lines[i+1]}"
      [[ -n $key ]] && _zcore_kv_ttl[$key]="$value"
    done
  fi

  _zcore_kv_transaction=()
  (( _zcore_kv_in_transaction = 0 ))

  z::log::debug "KV: Transaction rolled back"
  return 0
}
################################################################################
# INTROSPECTION & STATISTICS
################################################################################

###
# Get KV store statistics
# @return 0 always
###
z::kv::stats() {
  emulate -L zsh

  print "\nKV Store Statistics:"
  print "===================="

  typeset -i total_keys active_keys expired_keys
  (( total_keys = ${#_zcore_kv_store} ))

  # Count active keys (non-expired)
  active_keys=0
  expired_keys=0
  local key
  for key in "${(@k)_zcore_kv_store}"; do
    if __z::kv::check_ttl "$key"; then
      (( active_keys += 1 ))
    else
      (( expired_keys += 1 ))
    fi
  done

  print "Total Keys:     $total_keys"
  print "Active Keys:    $active_keys"
  print "Expired Keys:   $expired_keys"
  print ""
  print "Operations:"
  print "  Reads:        ${_zcore_kv_stats[reads]}"
  print "  Writes:       ${_zcore_kv_stats[writes]}"
  print "  Deletes:      ${_zcore_kv_stats[deletes]}"
  print "  Cache Hits:   ${_zcore_kv_stats[hits]}"
  print "  Cache Misses: ${_zcore_kv_stats[misses]}"

  if (( _zcore_kv_stats[reads] > 0 )); then
    typeset -F hit_rate
    (( hit_rate = (_zcore_kv_stats[hits] * 100.0) / _zcore_kv_stats[reads] ))
    print "  Hit Rate:     ${hit_rate}%"
  fi

  print ""
  print "Watchers:       ${#_zcore_kv_watchers}"
  print "Auto-persist:   ${_zcore_kv_config[auto_persist]}"

  if [[ -n ${_zcore_kv_config[persist_file]} ]]; then
    print "Persist File:   ${_zcore_kv_config[persist_file]}"
  fi

  print ""
  return 0
}

###
# Get total number of keys
# @stdout Number of keys
# @return 0 always
###
z::kv::size() {
  emulate -L zsh
  print -- "${#_zcore_kv_store}"
  return 0
}

###
# Export all data in human-readable format
# @stdout All key-value pairs
# @return 0 always
###
z::kv::export() {
  emulate -L zsh

  print "# ZCORE KV Store Export"
  print "# $(date '+%Y-%m-%d %H:%M:%S')"
  print ""

  local key value value_type
  for key in "${(@k)_zcore_kv_store}"; do
    __z::kv::check_ttl "$key" || continue

    value="${_zcore_kv_store[$key]}"
    value_type="${_zcore_kv_meta[$key]:-string}"

    print "${key} (${value_type}) = ${value}"
  done

  return 0
}

###
# Configure KV store
# @param 1: string - Config key
# @param 2: string - Config value
# @return 0 on success
###
z::kv::config() {
  emulate -L zsh
  local key="$1"
  local value="$2"

  if (( ! ${+_zcore_kv_config[$key]} )); then
    z::log::error "KV: Unknown config key: $key"
    return 1
  fi

  _zcore_kv_config[$key]="$value"
  z::log::debug "KV: Config updated: $key = $value"
  return 0
}

###
# Enable auto-persistence
# @param 1: string - File path
# @return 0 on success
###
z::kv::enable_persist() {
  emulate -L zsh
  local file="$1"

  if [[ -z $file ]]; then
    z::log::error "KV: Persist file path required"
    return 1
  fi

  _zcore_kv_config[auto_persist]=true
  _zcore_kv_config[persist_file]="$file"

  z::log::info "KV: Auto-persistence enabled: $file"
  return 0
}

###
# Disable auto-persistence
# @return 0 always
###
z::kv::disable_persist() {
  emulate -L zsh

  _zcore_kv_config[auto_persist]=false
  z::log::info "KV: Auto-persistence disabled"
  return 0
}


################################################################################
# LIST OPERATIONS (Like Redis Lists)
################################################################################

###
# Push value to left (head) of list
#
# Usage:
#   z::kv::lpush "mylist" "item1"
#   z::kv::lpush "mylist" "item2"  # List is now: item2, item1
#
# @param 1: string - List key
# @param 2: string - Value to push
# @return 0 on success
###
z::kv::lpush() {
  emulate -L zsh
  local key="$1"
  local value="$2"

  __z::kv::validate_key "$key" || return 1

  local existing="${_zcore_kv_lists[$key]:-}"

  if [[ -n $existing ]]; then
    _zcore_kv_lists[$key]="${value}|${existing}"
  else
    _zcore_kv_lists[$key]="$value"
  fi

  z::log::debug "KV: LPUSH '$key' <- '$value'"
  __z::kv::trigger_watchers "$key" "$value" "lpush"

  return 0
}

###
# Push value to right (tail) of list
#
# Usage:
#   z::kv::rpush "mylist" "item1"
#   z::kv::rpush "mylist" "item2"  # List is now: item1, item2
#
# @param 1: string - List key
# @param 2: string - Value to push
# @return 0 on success
###
z::kv::rpush() {
  emulate -L zsh
  local key="$1"
  local value="$2"

  __z::kv::validate_key "$key" || return 1

  local existing="${_zcore_kv_lists[$key]:-}"

  if [[ -n $existing ]]; then
    _zcore_kv_lists[$key]="${existing}|${value}"
  else
    _zcore_kv_lists[$key]="$value"
  fi

  z::log::debug "KV: RPUSH '$key' <- '$value'"
  __z::kv::trigger_watchers "$key" "$value" "rpush"

  return 0
}

###
# Pop value from left (head) of list
#
# Usage:
#   value=$(z::kv::lpop "mylist")
#
# @param 1: string - List key
# @stdout Popped value
# @return 0 on success, 1 if list empty or not found
###
z::kv::lpop() {
  emulate -L zsh
  setopt localoptions no_unset

  local key="$1"

  __z::kv::validate_key "$key" || return 1

  local existing="${_zcore_kv_lists[$key]:-}"

  if [[ -z $existing ]]; then
    z::log::debug "KV: LPOP '$key' - list empty or not found"
    return 1
  fi

  # Split into array
  local -a items
  items=("${(@s:|:)existing}")

  if (( ${#items} == 0 )); then
    z::log::debug "KV: LPOP '$key' - list empty"
    return 1
  fi

  # Get first item
  local popped="${items[1]}"

  # Remove first item and rebuild list
  if (( ${#items} > 1 )); then
    items=("${(@)items[2,-1]}")
    _zcore_kv_lists[$key]="${(j:|:)items}"
  else
    # List is now empty
    unset "_zcore_kv_lists[$key]"
  fi

  z::log::debug "KV: LPOP '$key' -> '$popped' (${#items} remaining)"
  print -r -- "$popped"

  return 0
}
###
# Pop value from right (tail) of list
#
# Usage:
#   value=$(z::kv::rpop "mylist")
#
# @param 1: string - List key
# @stdout Popped value
# @return 0 on success, 1 if list empty or not found
###
z::kv::rpop() {
  emulate -L zsh
  setopt localoptions no_unset

  local key="$1"

  __z::kv::validate_key "$key" || return 1

  local existing="${_zcore_kv_lists[$key]:-}"

  if [[ -z $existing ]]; then
    z::log::debug "KV: RPOP '$key' - list empty or not found"
    return 1
  fi

  # Split into array
  local -a items
  items=("${(@s:|:)existing}")

  if (( ${#items} == 0 )); then
    z::log::debug "KV: RPOP '$key' - list empty"
    return 1
  fi

  # Get last item
  local popped="${items[-1]}"

  # Remove last item and rebuild list
  if (( ${#items} > 1 )); then
    items=("${(@)items[1,-2]}")
    _zcore_kv_lists[$key]="${(j:|:)items}"
  else
    # List is now empty
    unset "_zcore_kv_lists[$key]"
  fi

  z::log::debug "KV: RPOP '$key' -> '$popped' (${#items} remaining)"
  print -r -- "$popped"

  return 0
}
###
# Get range of list elements
#
# Usage:
#   z::kv::lrange "mylist" 0 -1     # All elements
#   z::kv::lrange "mylist" 0 2      # First 3 elements
#   z::kv::lrange "mylist" -3 -1    # Last 3 elements
#
# @param 1: string - List key
# @param 2: integer - Start index (0-based, negative from end)
# @param 3: integer - Stop index (inclusive)
# @stdout List elements (one per line)
# @return 0 on success
###
z::kv::lrange() {
  emulate -L zsh
  local key="$1"
  typeset -i start stop
  (( start = ${2:-0} ))
  (( stop = ${3:--1} ))

  __z::kv::validate_key "$key" || return 1

  local existing="${_zcore_kv_lists[$key]:-}"

  if [[ -z $existing ]]; then
    return 0
  fi

  local -a items
  items=("${(@s:|:)existing}")

  # Handle negative indices
  if (( start < 0 )); then
    (( start = ${#items} + start + 1 ))
  else
    (( start += 1 ))  # Convert to 1-based
  fi

  if (( stop < 0 )); then
    (( stop = ${#items} + stop + 1 ))
  else
    (( stop += 1 ))  # Convert to 1-based
  fi

  # Bounds checking
  (( start < 1 )) && (( start = 1 ))
  (( stop > ${#items} )) && (( stop = ${#items} ))

  if (( start <= stop )); then
    print -l -- "${(@)items[start,stop]}"
  fi

  return 0
}

###
# Get list length
#
# Usage:
#   length=$(z::kv::llen "mylist")
#
# @param 1: string - List key
# @stdout List length
# @return 0 always
###
z::kv::llen() {
  emulate -L zsh
  local key="$1"

  local existing="${_zcore_kv_lists[$key]:-}"

  if [[ -z $existing ]]; then
    print "0"
    return 0
  fi

  local -a items
  items=("${(@s:|:)existing}")

  print "${#items}"
  return 0
}

################################################################################
# SET OPERATIONS (Unique Values)
################################################################################

###
# Add member to set
#
# Usage:
#   z::kv::sadd "myset" "value1"
#   z::kv::sadd "myset" "value2"
#   z::kv::sadd "myset" "value1"  # Ignored (already exists)
#
# @param 1: string - Set key
# @param 2: string - Value to add
# @return 0 if added, 1 if already exists
###
z::kv::sadd() {
  emulate -L zsh
  local key="$1"
  local value="$2"

  __z::kv::validate_key "$key" || return 1

  local existing="${_zcore_kv_sets[$key]:-}"

  # Check if already exists
  if [[ -n $existing ]]; then
    local -a members
    members=("${(@s:|:)existing}")

    if (( ${members[(Ie)$value]} )); then
      z::log::debug "KV: SADD '$key' - '$value' already exists"
      return 1
    fi

    _zcore_kv_sets[$key]="${existing}|${value}"
  else
    _zcore_kv_sets[$key]="$value"
  fi

  z::log::debug "KV: SADD '$key' <- '$value'"
  __z::kv::trigger_watchers "$key" "$value" "sadd"

  return 0
}

###
# Remove member from set
#
# Usage:
#   z::kv::srem "myset" "value1"
#
# @param 1: string - Set key
# @param 2: string - Value to remove
# @return 0 if removed, 1 if not found
###
z::kv::srem() {
  emulate -L zsh
  local key="$1"
  local value="$2"

  __z::kv::validate_key "$key" || return 1

  local existing="${_zcore_kv_sets[$key]:-}"

  if [[ -z $existing ]]; then
    return 1
  fi

  local -a members
  members=("${(@s:|:)existing}")

  # Remove value
  members=("${(@)members:#$value}")

  if (( ${#members} > 0 )); then
    _zcore_kv_sets[$key]="${(j:|:)members}"
  else
    unset "_zcore_kv_sets[$key]"
  fi

  z::log::debug "KV: SREM '$key' <- '$value'"

  return 0
}

###
# Check if member exists in set
#
# Usage:
#   if z::kv::sismember "myset" "value1"; then
#     echo "Value exists"
#   fi
#
# @param 1: string - Set key
# @param 2: string - Value to check
# @return 0 if exists, 1 if not
###
z::kv::sismember() {
  emulate -L zsh
  local key="$1"
  local value="$2"

  local existing="${_zcore_kv_sets[$key]:-}"

  if [[ -z $existing ]]; then
    return 1
  fi

  local -a members
  members=("${(@s:|:)existing}")

  (( ${members[(Ie)$value]} ))
}

###
# Get all set members
#
# Usage:
#   z::kv::smembers "myset"
#
# @param 1: string - Set key
# @stdout Set members (one per line)
# @return 0 always
###
z::kv::smembers() {
  emulate -L zsh
  local key="$1"

  local existing="${_zcore_kv_sets[$key]:-}"

  if [[ -z $existing ]]; then
    return 0
  fi

  local -a members
  members=("${(@s:|:)existing}")

  print -l -- "${members[@]}"
  return 0
}

###
# Get set cardinality (size)
#
# Usage:
#   size=$(z::kv::scard "myset")
#
# @param 1: string - Set key
# @stdout Set size
# @return 0 always
###
z::kv::scard() {
  emulate -L zsh
  local key="$1"

  local existing="${_zcore_kv_sets[$key]:-}"

  if [[ -z $existing ]]; then
    print "0"
    return 0
  fi

  local -a members
  members=("${(@s:|:)existing}")

  print "${#members}"
  return 0
}

################################################################################
# SORTED SET OPERATIONS (Score-based ordering)
################################################################################

###
# Add member to sorted set with score
#
# Usage:
#   z::kv::zadd "leaderboard" 100 "player1"
#   z::kv::zadd "leaderboard" 200 "player2"
#
# @param 1: string - Sorted set key
# @param 2: number - Score
# @param 3: string - Member
# @return 0 on success
###
z::kv::zadd() {
  emulate -L zsh
  local key="$1"
  typeset -F score
  (( score = ${2} ))
  local member="$3"

  __z::kv::validate_key "$key" || return 1

  local existing="${_zcore_kv_zsets[$key]:-}"
  local -a items

  if [[ -n $existing ]]; then
    items=("${(@s:|:)existing}")

    # Remove existing member if present
    local -a filtered
    local item
    for item in "${items[@]}"; do
      local item_member="${item#*:}"
      if [[ $item_member != $member ]]; then
        filtered+=("$item")
      fi
    done
    items=("${filtered[@]}")
  fi

  # Add new scored member
  items+=("${score}:${member}")

  _zcore_kv_zsets[$key]="${(j:|:)items}"

  z::log::debug "KV: ZADD '$key' <- $score:$member"
  __z::kv::trigger_watchers "$key" "$member" "zadd"

  return 0
}

###
# Get score of member in sorted set
#
# Usage:
#   score=$(z::kv::zscore "leaderboard" "player1")
#
# @param 1: string - Sorted set key
# @param 2: string - Member
# @stdout Score
# @return 0 if found, 1 if not found
###
z::kv::zscore() {
  emulate -L zsh
  local key="$1"
  local member="$2"

  local existing="${_zcore_kv_zsets[$key]:-}"

  if [[ -z $existing ]]; then
    return 1
  fi

  local -a items
  items=("${(@s:|:)existing}")

  local item
  for item in "${items[@]}"; do
    local item_score="${item%%:*}"
    local item_member="${item#*:}"

    if [[ $item_member == $member ]]; then
      print -r -- "$item_score"
      return 0
    fi
  done

  return 1
}

###
# Get range of sorted set members by rank
#
# Usage:
#   z::kv::zrange "leaderboard" 0 9           # Top 10
#   z::kv::zrange "leaderboard" 0 -1          # All members
#   z::kv::zrange "leaderboard" 0 2 --rev     # Top 3 (highest scores)
#
# @param 1: string - Sorted set key
# @param 2: integer - Start rank
# @param 3: integer - Stop rank
# @param 4: string - --rev (reverse order, highest first)
# @stdout Members (one per line)
# @return 0 always
###
z::kv::zrange() {
  emulate -L zsh
  local key="$1"
  typeset -i start stop
  (( start = ${2:-0} ))
  (( stop = ${3:--1} ))
  local reverse=false

  [[ ${4:-} == --rev ]] && reverse=true

  local existing="${_zcore_kv_zsets[$key]:-}"

  if [[ -z $existing ]]; then
    return 0
  fi

  local -a items
  items=("${(@s:|:)existing}")

  # Sort by score
  local -a sorted_items
  sorted_items=("${(@n)items}")  # Numeric sort

  # Reverse if requested
  if [[ $reverse == true ]]; then
    sorted_items=("${(@Oa)sorted_items}")
  fi

  # Handle negative indices
  typeset -i actual_start actual_stop
  if (( start < 0 )); then
    (( actual_start = ${#sorted_items} + start + 1 ))
  else
    (( actual_start = start + 1 ))
  fi

  if (( stop < 0 )); then
    (( actual_stop = ${#sorted_items} + stop + 1 ))
  else
    (( actual_stop = stop + 1 ))
  fi

  # Bounds checking
  (( actual_start < 1 )) && (( actual_start = 1 ))
  (( actual_stop > ${#sorted_items} )) && (( actual_stop = ${#sorted_items} ))

  # Output members (without scores)
  if (( actual_start <= actual_stop )); then
    local item
    for item in "${(@)sorted_items[actual_start,actual_stop]}"; do
      print -r -- "${item#*:}"
    done
  fi

  return 0
}

###
# Get range with scores
#
# Usage:
#   z::kv::zrange_withscores "leaderboard" 0 9
#
# @param 1: string - Sorted set key
# @param 2: integer - Start rank
# @param 3: integer - Stop rank
# @stdout "member score" pairs (one per line)
# @return 0 always
###
z::kv::zrange_withscores() {
  emulate -L zsh
  local key="$1"
  typeset -i start stop
  (( start = ${2:-0} ))
  (( stop = ${3:--1} ))

  local existing="${_zcore_kv_zsets[$key]:-}"

  if [[ -z $existing ]]; then
    return 0
  fi

  local -a items
  items=("${(@s:|:)existing}")

  # Sort by score (descending)
  local -a sorted_items
  sorted_items=("${(@On)items}")

  # Handle indices
  typeset -i actual_start actual_stop
  if (( start < 0 )); then
    (( actual_start = ${#sorted_items} + start + 1 ))
  else
    (( actual_start = start + 1 ))
  fi

  if (( stop < 0 )); then
    (( actual_stop = ${#sorted_items} + stop + 1 ))
  else
    (( actual_stop = stop + 1 ))
  fi

  (( actual_start < 1 )) && (( actual_start = 1 ))
  (( actual_stop > ${#sorted_items} )) && (( actual_stop = ${#sorted_items} ))

  if (( actual_start <= actual_stop )); then
    local item
    for item in "${(@)sorted_items[actual_start,actual_stop]}"; do
      local item_score="${item%%:*}"
      local item_member="${item#*:}"
      print "${item_member} ${item_score}"
    done
  fi

  return 0
}

###
# Remove member from sorted set
#
# Usage:
#   z::kv::zrem "leaderboard" "player1"
#
# @param 1: string - Sorted set key
# @param 2: string - Member to remove
# @return 0 if removed, 1 if not found
###
z::kv::zrem() {
  emulate -L zsh
  local key="$1"
  local member="$2"

  __z::kv::validate_key "$key" || return 1

  local existing="${_zcore_kv_zsets[$key]:-}"

  if [[ -z $existing ]]; then
    return 1
  fi

  local -a items filtered
  items=("${(@s:|:)existing}")

  local item
  for item in "${items[@]}"; do
    local item_member="${item#*:}"
    if [[ $item_member != $member ]]; then
      filtered+=("$item")
    fi
  done

  if (( ${#filtered} > 0 )); then
    _zcore_kv_zsets[$key]="${(j:|:)filtered}"
  else
    unset "_zcore_kv_zsets[$key]"
  fi

  z::log::debug "KV: ZREM '$key' <- '$member'"

  return 0
}

################################################################################
# HASH OPERATIONS (Field-Value pairs)
################################################################################

###
# Set hash field
#
# Usage:
#   z::kv::hset "user:1000" "name" "John"
#   z::kv::hset "user:1000" "email" "john@example.com"
#
# @param 1: string - Hash key
# @param 2: string - Field name
# @param 3: string - Value
# @return 0 on success
###
z::kv::hset() {
  emulate -L zsh
  local key="$1"
  local field="$2"
  local value="$3"

  __z::kv::validate_key "$key" || return 1

  local hash_key="${key}.${field}"
  _zcore_kv_hashes[$hash_key]="$value"

  z::log::debug "KV: HSET '$key' '$field' = '$value'"
  __z::kv::trigger_watchers "$key" "$field:$value" "hset"

  return 0
}

###
# Get hash field value
#
# Usage:
#   name=$(z::kv::hget "user:1000" "name")
#
# @param 1: string - Hash key
# @param 2: string - Field name
# @stdout Field value
# @return 0 if found, 1 if not found
###
z::kv::hget() {
  emulate -L zsh
  local key="$1"
  local field="$2"

  local hash_key="${key}.${field}"

  if (( ! ${+_zcore_kv_hashes[$hash_key]} )); then
    return 1
  fi

  print -r -- "${_zcore_kv_hashes[$hash_key]}"
  return 0
}

###
# Get all hash fields and values
#
# Usage:
#   z::kv::hgetall "user:1000"
#
# @param 1: string - Hash key
# @stdout "field value" pairs (one per line)
# @return 0 always
###
z::kv::hgetall() {
  emulate -L zsh
  local key="$1"

  local hash_key field value
  for hash_key in "${(@k)_zcore_kv_hashes}"; do
    if [[ $hash_key == ${key}.* ]]; then
      field="${hash_key#${key}.}"
      value="${_zcore_kv_hashes[$hash_key]}"
      print "${field} ${value}"
    fi
  done

  return 0
}

###
# Delete hash field
#
# Usage:
#   z::kv::hdel "user:1000" "email"
#
# @param 1: string - Hash key
# @param 2: string - Field name
# @return 0 if deleted, 1 if not found
###
z::kv::hdel() {
  emulate -L zsh
  local key="$1"
  local field="$2"

  local hash_key="${key}.${field}"

  if (( ! ${+_zcore_kv_hashes[$hash_key]} )); then
    return 1
  fi

  unset "_zcore_kv_hashes[$hash_key]"
  z::log::debug "KV: HDEL '$key' '$field'"

  return 0
}

###
# Check if hash field exists
#
# Usage:
#   if z::kv::hexists "user:1000" "email"; then
#     echo "Field exists"
#   fi
#
# @param 1: string - Hash key
# @param 2: string - Field name
# @return 0 if exists, 1 if not
###
z::kv::hexists() {
  emulate -L zsh
  local key="$1"
  local field="$2"

  local hash_key="${key}.${field}"
  (( ${+_zcore_kv_hashes[$hash_key]} ))
}

###
# Get all hash field names
#
# Usage:
#   z::kv::hkeys "user:1000"
#
# @param 1: string - Hash key
# @stdout Field names (one per line)
# @return 0 always
###
z::kv::hkeys() {
  emulate -L zsh
  local key="$1"

  local hash_key field
  for hash_key in "${(@k)_zcore_kv_hashes}"; do
    if [[ $hash_key == ${key}.* ]]; then
      field="${hash_key#${key}.}"
      print -r -- "$field"
    fi
  done

  return 0
}

###
# Get all hash values
#
# Usage:
#   z::kv::hvals "user:1000"
#
# @param 1: string - Hash key
# @stdout Values (one per line)
# @return 0 always
###
z::kv::hvals() {
  emulate -L zsh
  local key="$1"

  local hash_key
  for hash_key in "${(@k)_zcore_kv_hashes}"; do
    if [[ $hash_key == ${key}.* ]]; then
      print -r -- "${_zcore_kv_hashes[$hash_key]}"
    fi
  done

  return 0
}

################################################################################
# ATOMIC OPERATIONS
################################################################################

###
# Set value and return old value (atomic)
#
# Usage:
#   old_value=$(z::kv::getset "counter" "10")
#
# @param 1: string - Key
# @param 2: string - New value
# @stdout Old value (empty if key didn't exist)
# @return 0 always
###
z::kv::getset() {
  emulate -L zsh
  local key="$1"
  local new_value="$2"

  local old_value=""
  if z::probe::kv "$key"; then
    old_value=$(z::kv::get "$key")
  fi

  z::kv::set "$key" "$new_value"

  print -r -- "$old_value"
  return 0
}

###
# Set value only if key doesn't exist (SET if Not eXists)
#
# Usage:
#   if z::kv::setnx "lock" "owner_id"; then
#     echo "Lock acquired"
#   fi
#
# @param 1: string - Key
# @param 2: string - Value
# @return 0 if set, 1 if key already exists
###
z::kv::setnx() {
  emulate -L zsh
  local key="$1"
  local value="$2"

  if z::probe::kv "$key"; then
    z::log::debug "KV: SETNX '$key' - already exists"
    return 1
  fi

  z::kv::set "$key" "$value"
  return 0
}

###
# Set value only if key exists
#
# Usage:
#   if z::kv::setxx "existing_key" "new_value"; then
#     echo "Value updated"
#   fi
#
# @param 1: string - Key
# @param 2: string - Value
# @return 0 if set, 1 if key doesn't exist
###
z::kv::setxx() {
  emulate -L zsh
  local key="$1"
  local value="$2"

  if ! z::probe::kv "$key"; then
    z::log::debug "KV: SETXX '$key' - key doesn't exist"
    return 1
  fi

  z::kv::set "$key" "$value"
  return 0
}

################################################################################
# DISTRIBUTED LOCKING
################################################################################

###
# Acquire distributed lock
#
# Usage:
#   if z::kv::lock "resource_name" 30; then
#     # Critical section
#     z::kv::unlock "resource_name"
#   fi
#
# @param 1: string - Lock name
# @param 2: integer - TTL in seconds (optional, default: 10)
# @param 3: string - Owner ID (optional, default: $$)
# @return 0 if acquired, 1 if already locked
###
z::kv::lock() {
  emulate -L zsh
  local lock_name="$1"
  typeset -i ttl
  (( ttl = ${2:-10} ))
  local owner="${3:-$$}"

  __z::kv::validate_key "$lock_name" || return 1

  # Check if lock exists and is still valid
  if (( ${+_zcore_kv_locks[$lock_name]} )); then
    local lock_data="${_zcore_kv_locks[$lock_name]}"
    local lock_owner="${lock_data%%|*}"
    typeset -i lock_expire
    (( lock_expire = ${lock_data#*|} ))

    typeset -i current_time
    (( current_time = ${EPOCHSECONDS:-$(date +%s)} ))

    if (( current_time < lock_expire )); then
      z::log::debug "KV: Lock '$lock_name' already held by $lock_owner"
      return 1
    fi
  fi

  # Acquire lock
  typeset -i expire_time
  (( expire_time = ${EPOCHSECONDS:-$(date +%s)} + ttl ))

  _zcore_kv_locks[$lock_name]="${owner}|${expire_time}"

  z::log::debug "KV: Lock acquired: '$lock_name' by $owner (TTL: ${ttl}s)"
  z::event::emit "kv:lock:acquired" "$lock_name" "$owner" 2>/dev/null || true

  return 0
}

###
# Release distributed lock
#
# Usage:
#   z::kv::unlock "resource_name"
#
# @param 1: string - Lock name
# @param 2: string - Owner ID (optional, default: $$, must match acquirer)
# @return 0 if released, 1 if not held or wrong owner
###
z::kv::unlock() {
  emulate -L zsh
  local lock_name="$1"
  local owner="${2:-$$}"

  if (( ! ${+_zcore_kv_locks[$lock_name]} )); then
    z::log::debug "KV: Lock '$lock_name' not held"
    return 1
  fi

  local lock_data="${_zcore_kv_locks[$lock_name]}"
  local lock_owner="${lock_data%%|*}"

  if [[ $lock_owner != $owner ]]; then
    z::log::error "KV: Cannot unlock '$lock_name' - owned by $lock_owner, not $owner"
    return 1
  fi

  unset "_zcore_kv_locks[$lock_name]"

  z::log::debug "KV: Lock released: '$lock_name' by $owner"
  z::event::emit "kv:lock:released" "$lock_name" "$owner" 2>/dev/null || true

  return 0
}

###
# Try to acquire lock with retry
#
# Usage:
#   z::kv::lock_wait "resource" 30 5 0.5  # 30s TTL, 5 retries, 0.5s interval
#
# @param 1: string - Lock name
# @param 2: integer - TTL in seconds
# @param 3: integer - Max retries (default: 3)
# @param 4: float - Retry interval in seconds (default: 1)
# @return 0 if acquired, 1 if failed after retries
###
z::kv::lock_wait() {
  emulate -L zsh
  local lock_name="$1"
  typeset -i ttl retries
  (( ttl = ${2:-10} ))
  (( retries = ${3:-3} ))
  typeset -F interval
  (( interval = ${4:-1} ))

  typeset -i attempt
  for (( attempt = 0; attempt <= retries; attempt++ )); do
    if z::kv::lock "$lock_name" "$ttl"; then
      return 0
    fi

    if (( attempt < retries )); then
      z::log::debug "KV: Lock attempt $((attempt + 1)) failed, retrying in ${interval}s..."
      sleep "$interval"
    fi
  done

  z::log::error "KV: Failed to acquire lock '$lock_name' after $retries retries"
  return 1
}

################################################################################
# PUB/SUB CHANNELS
################################################################################

###
# Subscribe to channel
#
# Usage:
#   z::kv::subscribe "notifications" my_handler
#   my_handler() {
#     local channel="$1" message="$2"
#     echo "Received on $channel: $message"
#   }
#
# @param 1: string - Channel name
# @param 2: string - Handler function
# @return 0 on success
###
z::kv::subscribe() {
  emulate -L zsh
  local channel="$1"
  local handler="$2"

  if [[ -z $channel || -z $handler ]]; then
    z::log::error "KV: subscribe requires channel and handler"
    return 1
  fi

  if ! z::probe::func "$handler"; then
    z::log::error "KV: Handler function not found: $handler"
    return 1
  fi

  local existing="${_zcore_kv_pubsub[$channel]:-}"

  if [[ -n $existing ]]; then
    _zcore_kv_pubsub[$channel]="${existing}|${handler}"
  else
    _zcore_kv_pubsub[$channel]="$handler"
  fi

  z::log::debug "KV: Subscribed '$handler' to channel '$channel'"
  return 0
}

###
# Unsubscribe from channel
#
# Usage:
#   z::kv::unsubscribe "notifications" my_handler
#   z::kv::unsubscribe "notifications"  # Remove all
#
# @param 1: string - Channel name
# @param 2: string - Handler function (optional)
# @return 0 on success
###
z::kv::unsubscribe() {
  emulate -L zsh
  local channel="$1"
  local handler="${2:-}"

  if [[ -z $handler ]]; then
    unset "_zcore_kv_pubsub[$channel]"
    z::log::debug "KV: Unsubscribed all from channel '$channel'"
  else
    local existing="${_zcore_kv_pubsub[$channel]:-}"
    if [[ -n $existing ]]; then
      local -a handlers
      handlers=("${(@s:|:)existing}")
      handlers=("${(@)handlers:#$handler}")

      if (( ${#handlers} > 0 )); then
        _zcore_kv_pubsub[$channel]="${(j:|:)handlers}"
      else
        unset "_zcore_kv_pubsub[$channel]"
      fi

      z::log::debug "KV: Unsubscribed '$handler' from channel '$channel'"
    fi
  fi

  return 0
}

###
# Publish message to channel
#
# Usage:
#   z::kv::publish "notifications" "New message arrived"
#
# @param 1: string - Channel name
# @param 2: string - Message
# @return 0 always
###
z::kv::publish() {
  emulate -L zsh
  local channel="$1"
  local message="$2"

  z::log::debug "KV: Publishing to channel '$channel': $message"

  local handler_list="${_zcore_kv_pubsub[$channel]:-}"

  if [[ -z $handler_list ]]; then
    z::log::debug "KV: No subscribers for channel '$channel'"
    return 0
  fi

  local -a handlers
  handlers=("${(@s:|:)handler_list}")

  local handler
  for handler in "${handlers[@]}"; do
    if z::probe::func "$handler"; then
      "$handler" "$channel" "$message" 2>/dev/null || true
    fi
  done

  return 0
}

################################################################################
# SNAPSHOTS
################################################################################

###
# Create snapshot of current KV state
#
# Usage:
#   snapshot_id=$(z::kv::snapshot_create "before_upgrade")
#
# @param 1: string - Snapshot name/label
# @stdout Snapshot ID
# @return 0 on success
###
z::kv::snapshot_create() {
  emulate -L zsh
  setopt localoptions no_unset

  local label="${1:-snapshot}"

  # Generate ID without using command substitution that might reset counter
  typeset -gi _zcore_kv_snapshot_id
  (( _zcore_kv_snapshot_id += 1 ))
  local snapshot_id="snap_${_zcore_kv_snapshot_id}"

  # Serialize all data structures using (F) for newline joining
  local -a store_data meta_data lists_data sets_data zsets_data hashes_data

  local k v
  for k v in "${(@kv)_zcore_kv_store}"; do
    store_data+=("$k")
    store_data+=("$v")
  done

  for k v in "${(@kv)_zcore_kv_meta}"; do
    meta_data+=("$k")
    meta_data+=("$v")
  done

  for k v in "${(@kv)_zcore_kv_lists}"; do
    lists_data+=("$k")
    lists_data+=("$v")
  done

  for k v in "${(@kv)_zcore_kv_sets}"; do
    sets_data+=("$k")
    sets_data+=("$v")
  done

  for k v in "${(@kv)_zcore_kv_zsets}"; do
    zsets_data+=("$k")
    zsets_data+=("$v")
  done

  for k v in "${(@kv)_zcore_kv_hashes}"; do
    hashes_data+=("$k")
    hashes_data+=("$v")
  done

  _zcore_kv_snapshots[${snapshot_id}.label]="$label"
  _zcore_kv_snapshots[${snapshot_id}.timestamp]="${EPOCHSECONDS:-$(date +%s)}"
  _zcore_kv_snapshots[${snapshot_id}.store]="${(F)store_data}"
  _zcore_kv_snapshots[${snapshot_id}.meta]="${(F)meta_data}"
  _zcore_kv_snapshots[${snapshot_id}.lists]="${(F)lists_data}"
  _zcore_kv_snapshots[${snapshot_id}.sets]="${(F)sets_data}"
  _zcore_kv_snapshots[${snapshot_id}.zsets]="${(F)zsets_data}"
  _zcore_kv_snapshots[${snapshot_id}.hashes]="${(F)hashes_data}"

  z::log::info "KV: Snapshot created: $snapshot_id ($label)"
  print -r -- "$snapshot_id"

  return 0
}
###
# Restore from snapshot
#
# Usage:
#   z::kv::snapshot_restore "snap_1"
#
# @param 1: string - Snapshot ID
# @return 0 on success, 1 if not found
###
z::kv::snapshot_restore() {
  emulate -L zsh
  local snapshot_id="$1"

  if [[ -z ${_zcore_kv_snapshots[${snapshot_id}.label]:-} ]]; then
    z::log::error "KV: Snapshot not found: $snapshot_id"
    return 1
  fi

  local label="${_zcore_kv_snapshots[${snapshot_id}.label]}"
  z::log::info "KV: Restoring snapshot: $snapshot_id ($label)"

  # Clear current state
  _zcore_kv_store=()
  _zcore_kv_meta=()
  _zcore_kv_lists=()
  _zcore_kv_sets=()
  _zcore_kv_zsets=()
  _zcore_kv_hashes=()

  # Restore each data structure
  local -a lines
  local key value
  typeset -i i

  # Restore store
  lines=("${(@f)_zcore_kv_snapshots[${snapshot_id}.store]}")
  for (( i = 1; i <= ${#lines}; i += 2 )); do
    key="${lines[i]}"
    value="${lines[i+1]}"
    [[ -n $key ]] && _zcore_kv_store[$key]="$value"
  done

  # Restore meta
  lines=("${(@f)_zcore_kv_snapshots[${snapshot_id}.meta]}")
  for (( i = 1; i <= ${#lines}; i += 2 )); do
    key="${lines[i]}"
    value="${lines[i+1]}"
    [[ -n $key ]] && _zcore_kv_meta[$key]="$value"
  done

  # Restore lists
  lines=("${(@f)_zcore_kv_snapshots[${snapshot_id}.lists]}")
  for (( i = 1; i <= ${#lines}; i += 2 )); do
    key="${lines[i]}"
    value="${lines[i+1]}"
    [[ -n $key ]] && _zcore_kv_lists[$key]="$value"
  done

  # Restore sets
  lines=("${(@f)_zcore_kv_snapshots[${snapshot_id}.sets]}")
  for (( i = 1; i <= ${#lines}; i += 2 )); do
    key="${lines[i]}"
    value="${lines[i+1]}"
    [[ -n $key ]] && _zcore_kv_sets[$key]="$value"
  done

  # Restore zsets
  lines=("${(@f)_zcore_kv_snapshots[${snapshot_id}.zsets]}")
  for (( i = 1; i <= ${#lines}; i += 2 )); do
    key="${lines[i]}"
    value="${lines[i+1]}"
    [[ -n $key ]] && _zcore_kv_zsets[$key]="$value"
  done

  # Restore hashes
  lines=("${(@f)_zcore_kv_snapshots[${snapshot_id}.hashes]}")
  for (( i = 1; i <= ${#lines}; i += 2 )); do
    key="${lines[i]}"
    value="${lines[i+1]}"
    [[ -n $key ]] && _zcore_kv_hashes[$key]="$value"
  done

  z::log::info "KV: Snapshot restored: $snapshot_id"
  z::event::emit "kv:snapshot:restored" "$snapshot_id" 2>/dev/null || true

  return 0
}

###
# List all snapshots
#
# Usage:
#   z::kv::snapshot_list
#
# @return 0 always
###
z::kv::snapshot_list() {
  emulate -L zsh

  print "\nKV Snapshots:"
  print "============="

  local -a snapshot_ids
  local key
  for key in "${(@k)_zcore_kv_snapshots}"; do
    if [[ $key == snap_*.label ]]; then
      snapshot_ids+=("${key%.label}")
    fi
  done

  if (( ${#snapshot_ids} == 0 )); then
    print "No snapshots available.\n"
    return 0
  fi

  # Sort by ID
  snapshot_ids=("${(@n)snapshot_ids}")

  local snap_id label timestamp time_str
  for snap_id in "${snapshot_ids[@]}"; do
    label="${_zcore_kv_snapshots[${snap_id}.label]}"
    timestamp="${_zcore_kv_snapshots[${snap_id}.timestamp]}"

    time_str=$(date -r "$timestamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$timestamp")

    print "  $snap_id: $label [$time_str]"
  done

  print ""
  return 0
}

###
# Delete snapshot
#
# Usage:
#   z::kv::snapshot_delete "snap_1"
#
# @param 1: string - Snapshot ID
# @return 0 on success
###
z::kv::snapshot_delete() {
  emulate -L zsh
  local snapshot_id="$1"

  local key
  for key in "${(@k)_zcore_kv_snapshots}"; do
    if [[ $key == ${snapshot_id}.* ]]; then
      unset "_zcore_kv_snapshots[$key]"
    fi
  done

  z::log::info "KV: Snapshot deleted: $snapshot_id"
  return 0
}

################################################################################
# CONDITIONAL OPERATIONS
################################################################################

###
# Set value if current value matches expected
#
# Usage:
#   if z::kv::cas "counter" "10" "11"; then
#     echo "Updated from 10 to 11"
#   fi
#
# @param 1: string - Key
# @param 2: string - Expected current value
# @param 3: string - New value
# @return 0 if updated, 1 if value doesn't match
###
z::kv::cas() {
  emulate -L zsh
  local key="$1"
  local expected="$2"
  local new_value="$3"

  local current=""
  if z::probe::kv "$key"; then
    current=$(z::kv::get "$key")
  fi

  if [[ $current != $expected ]]; then
    z::log::debug "KV: CAS failed for '$key' - expected '$expected', got '$current'"
    return 1
  fi

  z::kv::set "$key" "$new_value"
  z::log::debug "KV: CAS succeeded for '$key': '$expected' -> '$new_value'"

  return 0
}

################################################################################
# BATCH OPERATIONS
################################################################################

###
# Execute multiple operations atomically
#
# Usage:
#   z::kv::batch <<EOF
#     set key1 value1
#     set key2 value2
#     incr counter
#     del old_key
#   EOF
#
# @stdin Batch commands (one per line)
# @return 0 on success, 1 if any command failed
###
z::kv::batch() {
  emulate -L zsh

  z::kv::begin || return 1

  typeset -i failed=0
  local line cmd

  while IFS= read -r line; do
    # Skip empty lines and comments
    [[ $line =~ '^[[:space:]]*(#.*)?$' ]] && continue

    # Parse command
    local -a parts
    parts=("${(@s: :)line}")

    cmd="${parts[1]}"

    case "$cmd" in
      set)
        z::kv::set "${parts[2]}" "${parts[3]}" || (( failed += 1 ))
        ;;
      get)
        z::kv::get "${parts[2]}" || (( failed += 1 ))
        ;;
      del)
        z::kv::del "${parts[2]}" || (( failed += 1 ))
        ;;
      incr)
        z::kv::incr "${parts[2]}" || (( failed += 1 ))
        ;;
      decr)
        z::kv::decr "${parts[2]}" || (( failed += 1 ))
        ;;
      *)
        z::log::warn "KV: Unknown batch command: $cmd"
        (( failed += 1 ))
        ;;
    esac
  done

  if (( failed > 0 )); then
    z::log::error "KV: Batch operation failed ($failed errors), rolling back"
    z::kv::rollback
    return 1
  fi

  z::kv::commit
  z::log::debug "KV: Batch operation completed successfully"

  return 0
}

################################################################################
# UTILITY OPERATIONS
################################################################################

###
# Rename key
#
# Usage:
#   z::kv::rename "old_key" "new_key"
#
# @param 1: string - Old key
# @param 2: string - New key
# @return 0 on success, 1 if old key doesn't exist
###
z::kv::rename() {
  emulate -L zsh
  local old_key="$1"
  local new_key="$2"

  if ! z::probe::kv "$old_key"; then
    z::log::error "KV: Cannot rename - key not found: $old_key"
    return 1
  fi

  local value=$(z::kv::get "$old_key")
  local value_type="${_zcore_kv_meta[$old_key]:-string}"

  z::kv::set "$new_key" "$value" --type "$value_type"
  z::kv::del "$old_key"

  z::log::debug "KV: Renamed '$old_key' to '$new_key'"

  return 0
}

###
# Copy key
#
# Usage:
#   z::kv::copy "source_key" "dest_key"
#
# @param 1: string - Source key
# @param 2: string - Destination key
# @return 0 on success, 1 if source doesn't exist
###
z::kv::copy() {
  emulate -L zsh
  local source="$1"
  local dest="$2"

  if ! z::probe::kv "$source"; then
    z::log::error "KV: Cannot copy - key not found: $source"
    return 1
  fi

  local value=$(z::kv::get "$source")
  local value_type="${_zcore_kv_meta[$source]:-string}"

  z::kv::set "$dest" "$value" --type "$value_type"

  z::log::debug "KV: Copied '$source' to '$dest'"

  return 0
}

###
# Get random key
#
# Usage:
#   random_key=$(z::kv::randomkey)
#
# @stdout Random key name
# @return 0 if keys exist, 1 if store empty
###
z::kv::randomkey() {
  emulate -L zsh

  local -a all_keys
  all_keys=("${(@k)_zcore_kv_store}")

  if (( ${#all_keys} == 0 )); then
    return 1
  fi

  # Get random index
  typeset -i random_idx
  (( random_idx = (RANDOM % ${#all_keys}) + 1 ))

  print -r -- "${all_keys[random_idx]}"
  return 0
}

###
# Scan keys with cursor (for large datasets)
#
# Usage:
#   z::kv::scan 0 "user:*" 10  # Get first 10 matching keys
#
# @param 1: integer - Cursor (0 to start)
# @param 2: string - Pattern (optional)
# @param 3: integer - Count (optional, default: 10)
# @stdout "cursor key1 key2 ..." (cursor 0 means done)
# @return 0 always
###
z::kv::scan() {
  emulate -L zsh
  typeset -i cursor count
  (( cursor = ${1:-0} ))
  local pattern="${2:-*}"
  (( count = ${3:-10} ))

  local -a all_keys matching_keys
  all_keys=("${(@k)_zcore_kv_store}")

  # Filter by pattern
  local key
  for key in "${all_keys[@]}"; do
    if [[ $key == ${~pattern} ]]; then
      matching_keys+=("$key")
    fi
  done

  typeset -i total start end next_cursor
  (( total = ${#matching_keys} ))
  (( start = cursor + 1 ))
  (( end = start + count - 1 ))
  (( end > total )) && (( end = total ))

  if (( start > total )); then
    print "0"
    return 0
  fi

  if (( end >= total )); then
    (( next_cursor = 0 ))
  else
    (( next_cursor = end ))
  fi

  # Output: cursor followed by keys
  print -n "$next_cursor"

  if (( start <= end )); then
    local -a result_keys
    result_keys=("${(@)matching_keys[start,end]}")
    print -n " ${(j: :)result_keys}"
  fi

  print ""
  return 0
}

################################################################################
# ADVANCED STATISTICS
################################################################################

###
# Get memory usage estimate
#
# Usage:
#   z::kv::memory
#
# @stdout Memory usage info
# @return 0 always
###
z::kv::memory() {
  emulate -L zsh

  print "\nKV Memory Usage:"
  print "================"

  typeset -i total_bytes=0

  # Calculate store size
  typeset -i store_bytes=0
  local key value
  for key value in "${(@kv)_zcore_kv_store}"; do
    (( store_bytes += ${#key} + ${#value} ))
  done

  # Calculate lists size
  typeset -i lists_bytes=0
  for key value in "${(@kv)_zcore_kv_lists}"; do
    (( lists_bytes += ${#key} + ${#value} ))
  done

  # Calculate sets size
  typeset -i sets_bytes=0
  for key value in "${(@kv)_zcore_kv_sets}"; do
    (( sets_bytes += ${#key} + ${#value} ))
  done

  # Calculate zsets size
  typeset -i zsets_bytes=0
  for key value in "${(@kv)_zcore_kv_zsets}"; do
    (( zsets_bytes += ${#key} + ${#value} ))
  done

  # Calculate hashes size
  typeset -i hashes_bytes=0
  for key value in "${(@kv)_zcore_kv_hashes}"; do
    (( hashes_bytes += ${#key} + ${#value} ))
  done

  (( total_bytes = store_bytes + lists_bytes + sets_bytes + zsets_bytes + hashes_bytes ))

  print "Store:        ${store_bytes} bytes (${#_zcore_kv_store} keys)"
  print "Lists:        ${lists_bytes} bytes (${#_zcore_kv_lists} lists)"
  print "Sets:         ${sets_bytes} bytes (${#_zcore_kv_sets} sets)"
  print "Sorted Sets:  ${zsets_bytes} bytes (${#_zcore_kv_zsets} zsets)"
  print "Hashes:       ${hashes_bytes} bytes (${#_zcore_kv_hashes} hashes)"
  print "Total:        ${total_bytes} bytes"

  # Human readable
  typeset -F kb mb
  (( kb = total_bytes / 1024.0 ))
  (( mb = kb / 1024.0 ))

  if (( mb >= 1 )); then
    printf "              %.2f MB\n" "$mb"
  elif (( kb >= 1 )); then
    printf "              %.2f KB\n" "$kb"
  fi

  print ""
  return 0
}

###
# Get detailed info about a key
#
# Usage:
#   z::kv::info "mykey"
#
# @param 1: string - Key name
# @return 0 if found, 1 if not found
###
z::kv::info() {
  emulate -L zsh
  local key="$1"

  print "\nKey Information: $key"
  print "===================="

  # Check in store
  if (( ${+_zcore_kv_store[$key]} )); then
    local value="${_zcore_kv_store[$key]}"
    local value_type="${_zcore_kv_meta[$key]:-string}"

    print "Type:       string/value"
    print "Data Type:  $value_type"
    print "Value:      $value"
    print "Size:       ${#value} bytes"

    local ttl_val=$(z::kv::ttl "$key")
    if [[ $ttl_val == -1 ]]; then
      print "TTL:        No expiration"
    elif [[ $ttl_val == -2 ]]; then
      print "TTL:        Key not found"
    else
      print "TTL:        ${ttl_val}s remaining"
    fi

    print ""
    return 0
  fi

  # Check in lists
  if (( ${+_zcore_kv_lists[$key]} )); then
    local list_data="${_zcore_kv_lists[$key]}"
    local -a items
    items=("${(@s:|:)list_data}")

    print "Type:       list"
    print "Length:     ${#items}"
    print "Size:       ${#list_data} bytes"
    print ""
    return 0
  fi

  # Check in sets
  if (( ${+_zcore_kv_sets[$key]} )); then
    local set_data="${_zcore_kv_sets[$key]}"
    local -a members
    members=("${(@s:|:)set_data}")

    print "Type:       set"
    print "Cardinality: ${#members}"
    print "Size:       ${#set_data} bytes"
    print ""
    return 0
  fi

  # Check in zsets
  if (( ${+_zcore_kv_zsets[$key]} )); then
    local zset_data="${_zcore_kv_zsets[$key]}"
    local -a items
    items=("${(@s:|:)zset_data}")

    print "Type:       sorted set"
    print "Members:    ${#items}"
    print "Size:       ${#zset_data} bytes"
    print ""
    return 0
  fi

  # Check in hashes
  typeset -i hash_fields=0
  local hash_key
  for hash_key in "${(@k)_zcore_kv_hashes}"; do
    if [[ $hash_key == ${key}.* ]]; then
      (( hash_fields += 1 ))
    fi
  done

  if (( hash_fields > 0 )); then
    print "Type:       hash"
    print "Fields:     $hash_fields"
    print ""
    return 0
  fi

  print "Key not found in any data structure.\n"
  return 1
}
