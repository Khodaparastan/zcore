#!/usr/bin/env zsh
# =============================================================================
# z/cache.zsh — Process-scoped cache with optional TTL
# =============================================================================
# Description:  In-memory key/value cache with absolute-expiry TTLs,
#               namespace-scoped counters, a silent probe, and a memoization
#               helper that caches a function's stdout.
#
# Part of:      z — assembled by bin/zbundle; see lib/z/parts
#
# Requires:     zlog; emits cache:* through z::event::* when the bus
#               subsystem is active
# =============================================================================

# Depends on logging alone, so it is usable before the KV and bus subsystems
# come up. Keys follow a `namespace:field` convention: the segment before the
# first colon groups the hit/miss/write/expiry counters.

typeset -gA _zcore_cache_store   # key -> value
typeset -gA _zcore_cache_ttl     # key -> absolute expiry epoch
typeset -gA _zcore_cache_stats   # "<namespace>.<metric>" -> count

# __z::cache::check_ttl <key>
# Evict <key> when its TTL has elapsed and bump the namespace `expired`
# counter. Returns 0 while the entry is live or has no TTL, 1 once evicted.
__z::cache::check_ttl() {
  emulate -L zsh
  local key="$1"

  # No TTL recorded means the entry never expires.
  if (( ! ${+_zcore_cache_ttl[$key]} )); then
    return 0
  fi

  typeset -i expire_time current_time
  (( expire_time = ${_zcore_cache_ttl[$key]} ))
  (( current_time = ${EPOCHSECONDS:-$(date +%s)} ))

  if (( current_time >= expire_time )); then
    zlog::debug "Cache expired: $key"
    unset "_zcore_cache_store[$key]"
    unset "_zcore_cache_ttl[$key]"

    # Namespace is the segment before the first ':' in the key.
    local namespace="${key%%:*}"
    typeset -i expired
    (( expired = ${_zcore_cache_stats[${namespace}.expired]:-0} + 1 ))
    _zcore_cache_stats[${namespace}.expired]=$expired

    return 1
  fi

  return 0
}

# z::cache::set <key> <value> [--ttl <seconds>]
# Store a value, replacing any existing entry. A TTL of 0 (the default) never
# expires. Bumps the namespace `writes` counter and emits `cache:set` when the
# bus is active. Returns Z_ERR_INPUT on an empty key or non-integer TTL.
z::cache::set() {
  emulate -L zsh
  local key="${1:-}"
  local value="${2:-}"
  # A bare `shift 2` on a shorter argv is a fatal builtin error, which would
  # abort the function before the argument checks below could report it.
  shift $(( $# > 2 ? 2 : $# ))

  if [[ -z $key ]]; then
    zlog::error "Cache key required"
    return $Z_ERR_INPUT
  fi

  typeset -i ttl=0
  while (( $# > 0 )); do
    case "$1" in
      --ttl)
        # `<->` matches an integer; 10# forces base-10 interpretation.
        if [[ ${2:-} == <-> ]]; then
          (( ttl = 10#${2} ))
          shift 2
        else
          zlog::error "Invalid TTL: ${2:-}"
          return $Z_ERR_INPUT
        fi
        ;;
      *)
        shift
        ;;
    esac
  done

  _zcore_cache_store[$key]="$value"

  if (( ttl > 0 )); then
    # Absolute expiry, so a later read needs no knowledge of when we wrote.
    typeset -i expire_time
    (( expire_time = ${EPOCHSECONDS:-$(date +%s)} + ttl ))
    _zcore_cache_ttl[$key]=$expire_time
  else
    unset "_zcore_cache_ttl[$key]"
  fi

  local namespace="${key%%:*}"
  typeset -i writes
  (( writes = ${_zcore_cache_stats[${namespace}.writes]:-0} + 1 ))
  _zcore_cache_stats[${namespace}.writes]=$writes

  zlog::debug "Cache set: $key (ttl: ${ttl}s)"

  if (( _zcore_subsys[bus] == 1 )); then
    z::event::emit "cache:set" "$key" "$value" || true
  fi
  return 0
}

# z::cache::get <key>
# Print the cached value to stdout — note this is the one z:: accessor that
# does not use REPLY; capture it with `value=$(z::cache::get key)`. Bumps the
# namespace hit/miss counters and emits `cache:hit` / `cache:miss` when the bus
# is active. Returns Z_ERR_NOTFOUND on a miss or an expired entry,
# Z_ERR_INPUT on an empty key.
z::cache::get() {
  emulate -L zsh
  local key="${1:-}"

  if [[ -z $key ]]; then
    zlog::error "Cache key required"
    return $Z_ERR_INPUT
  fi

  # A failed TTL check means the entry expired and was just evicted.
  if ! __z::cache::check_ttl "$key"; then
    local namespace="${key%%:*}"
    typeset -i misses
    (( misses = ${_zcore_cache_stats[${namespace}.misses]:-0} + 1 ))
    _zcore_cache_stats[${namespace}.misses]=$misses
    if (( _zcore_subsys[bus] == 1 )); then
      z::event::emit "cache:miss" "$key" "expired" || true
    fi
    return $Z_ERR_NOTFOUND
  fi

  if (( ! ${+_zcore_cache_store[$key]} )); then
    local namespace="${key%%:*}"
    typeset -i misses
    (( misses = ${_zcore_cache_stats[${namespace}.misses]:-0} + 1 ))
    _zcore_cache_stats[${namespace}.misses]=$misses

    if (( _zcore_subsys[bus] == 1 )); then
      z::event::emit "cache:miss" "$key" "not_found" || true
    fi
    return $Z_ERR_NOTFOUND
  fi

  local namespace="${key%%:*}"
  typeset -i hits
  (( hits = ${_zcore_cache_stats[${namespace}.hits]:-0} + 1 ))
  _zcore_cache_stats[${namespace}.hits]=$hits
  if (( _zcore_subsys[bus] == 1 )); then
    z::event::emit "cache:hit" "$key" || true
  fi
  print -r -- "${_zcore_cache_store[$key]}"
  return 0
}

# z::cache::del <key>
# Drop a cache entry and its TTL. Deleting a key that was never set is not an
# error. Emits `cache:delete` when the bus is active; returns Z_ERR_INPUT on
# an empty key.
z::cache::del() {
  emulate -L zsh
  local key="${1:-}"

  if [[ -z $key ]]; then
    return $Z_ERR_INPUT
  fi

  unset "_zcore_cache_store[$key]"
  unset "_zcore_cache_ttl[$key]"

  zlog::debug "Cache deleted: $key"
  if (( _zcore_subsys[bus] == 1 )); then
    z::event::emit "cache:delete" "$key" || true
  fi
  return 0
}

# z::probe::cache <key>
# Silent predicate: succeed when <key> is present and unexpired. Never sets
# REPLY and never logs, but does evict the entry as a side effect when its TTL
# has elapsed.
z::probe::cache() {
  emulate -L zsh
  local key="${1:-}"
  __z::cache::check_ttl "$key" || return 1
  (( ${+_zcore_cache_store[$key]} ))
}

# z::cache::clear [<pattern>]
# Delete every entry whose key matches the glob <pattern> (default `*`, i.e.
# the whole cache). Emits `cache:cleared` with the number removed when the bus
# is active. Always returns 0.
z::cache::clear() {
  emulate -L zsh
  local pattern="${1:-*}"

  typeset -i cleared=0
  local key

  for key in "${(@k)_zcore_cache_store}"; do
    # `${~pattern}` forces glob expansion of the caller-supplied pattern.
    if [[ $key == ${~pattern} ]]; then
      z::cache::del "$key"
      (( cleared += 1 ))
    fi
  done

  zlog::debug "Cache cleared: $cleared entries"
  if (( _zcore_subsys[bus] == 1 )); then
    z::event::emit "cache:cleared" "$pattern" "$cleared" || true
  fi
  return 0
}

# z::cache::stats [<namespace>]
# Print hit/miss/write/expiry counters to stdout for one namespace, or for
# every namespace seen so far when called without an argument. Always
# returns 0.
z::cache::stats() {
  emulate -L zsh
  local namespace="${1:-}"

  print "\nCache Statistics:"
  print "================="

  if [[ -n $namespace ]]; then
    print "Namespace: $namespace"
    print "  Hits:    ${_zcore_cache_stats[${namespace}.hits]:-0}"
    print "  Misses:  ${_zcore_cache_stats[${namespace}.misses]:-0}"
    print "  Writes:  ${_zcore_cache_stats[${namespace}.writes]:-0}"
    print "  Expired: ${_zcore_cache_stats[${namespace}.expired]:-0}"

    typeset -i total
    (( total = ${_zcore_cache_stats[${namespace}.hits]:-0} + ${_zcore_cache_stats[${namespace}.misses]:-0} ))
    if (( total > 0 )); then
      typeset -F hit_rate
      # 100.0 rather than 100: integer division would floor the rate to 0.
      (( hit_rate = (${_zcore_cache_stats[${namespace}.hits]:-0} * 100.0) / total ))
      print "  Hit Rate: ${hit_rate}%"
    fi
  else
    # Derive the unique namespace set from the "<ns>.<metric>" stat keys.
    typeset -A namespaces
    local key ns
    for key in "${(@k)_zcore_cache_stats}"; do
      ns="${key%.*}"
      namespaces[$ns]=1
    done

    for ns in "${(@k)namespaces}"; do
      print "\n$ns:"
      print "  Hits:    ${_zcore_cache_stats[${ns}.hits]:-0}"
      print "  Misses:  ${_zcore_cache_stats[${ns}.misses]:-0}"
      print "  Writes:  ${_zcore_cache_stats[${ns}.writes]:-0}"
      print "  Expired: ${_zcore_cache_stats[${ns}.expired]:-0}"
    done
  fi

  print "\nTotal Entries: ${#_zcore_cache_store}"
  print ""
  return 0
}

# z::cache::memoize <cache-key> <ttl-seconds> <function> [<args> ...]
# Print the cached result for <cache-key>, calling <function> with the trailing
# arguments only on a miss and caching what it prints. A failing function is
# never cached and its status is propagated. Returns Z_ERR_INPUT on a missing
# key/function or non-integer TTL, Z_ERR_NOTFOUND when <function> is undefined.
z::cache::memoize() {
  emulate -L zsh
  local cache_key="${1:-}"
  local raw_ttl="${2:-0}"
  local func="${3:-}"
  # See z::cache::set — `shift 3` on a shorter argv is fatal to the function.
  shift $(( $# > 3 ? 3 : $# ))

  if [[ -z $cache_key || -z $func ]]; then
    zlog::error "Cache key and function required"
    return $Z_ERR_INPUT
  fi

  if [[ $raw_ttl != <-> ]]; then
    zlog::error "Invalid TTL: $raw_ttl"
    return $Z_ERR_INPUT
  fi
  typeset -i ttl=$(( 10#$raw_ttl ))

  local cached
  if cached=$(z::cache::get "$cache_key"); then
    print -r -- "$cached"
    return 0
  fi

  if (( ! ${+functions[$func]} )); then
    zlog::error "Function not found: $func"
    return $Z_ERR_NOTFOUND
  fi

  # A failed call must not be memoised; propagate its own status verbatim.
  local result
  result=$("$func" "$@") || return $?

  if (( ttl > 0 )); then
    z::cache::set "$cache_key" "$result" --ttl "$ttl"
  else
    z::cache::set "$cache_key" "$result"
  fi

  print -r -- "$result"
  return 0
}


