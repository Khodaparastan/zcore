#!/usr/bin/env zsh
# vim: set ft=zsh ts=2 sw=2 et:

# ============================================
# Cross-Platform Network Info Aliases (net.*)
# ============================================
# Compatible with: Linux, macOS, FreeBSD, OpenBSD, NetBSD
# Requires: zsh 5+
# Version: 2.3 (Refactored with cache validation)
# ============================================

# Global configuration
typeset -gr NET_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/net-tools"
typeset -gr NET_CACHE_FILE="$NET_CONFIG_DIR/cache"
typeset -gr NET_DEBUG="${NET_DEBUG:-0}"
typeset -gr NET_COLOR="${NET_COLOR:-auto}"
typeset -gr NET_TIMEOUT="${NET_TIMEOUT:-30}"

# Ensure config directory exists with proper permissions
[[ ! -d "$NET_CONFIG_DIR" ]] && {
  mkdir -p "$NET_CONFIG_DIR" || { echo "[ERROR] Failed to create $NET_CONFIG_DIR" >&2; return 1; }
  chmod 700 "$NET_CONFIG_DIR" || { echo "[ERROR] Failed to set permissions on $NET_CONFIG_DIR" >&2; return 1; }
}
# ============================================
# Core Utility Functions
# ============================================

# --- Logging and output functions ---
_net_log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp="$(TZ=America/New_York date '+%Y-%m-%d %H:%M:%S')"

  case "$level" in
  DEBUG) [[ $NET_DEBUG -ge 2 ]] && print -r -- "[DEBUG $timestamp] $message" >&2 ;;
  INFO) [[ $NET_DEBUG -ge 1 ]] && print -r -- "[INFO  $timestamp] $message" >&2 ;;
  WARN) print -r -- "[WARN  $timestamp] $message" >&2 ;;
  ERROR) print -r -- "[ERROR $timestamp] $message" >&2 ;;
  esac
}

# --- Color output support ---
_net_color() {
  local color="$1"
  shift
  local text="$*"  # Escape potential % in text to avoid prompt issues
  text="${text//\%/%%}"

  if [[ "$NET_COLOR" == "never" ]] || [[ "$NET_COLOR" == "auto" && ! -t 1 ]]; then
    print -r -- "$text"
    return
  fi

  case "$color" in
  red) print -P "%F{red}$text%f" ;;
  green) print -P "%F{green}$text%f" ;;
  yellow) print -P "%F{yellow}$text%f" ;;
  blue) print -P "%F{blue}$text%f" ;;
  bold) print -P "%B$text%b" ;;
  *) print -r -- "$text" ;;
  esac
}

# --- Input validation and sanitization ---
_net_validate_input() {
  local input="$1"
  local type="${2:-hostname}"
  local sanitized=""

  case "$type" in
  hostname)
    sanitized="${input//[^a-zA-Z0-9.-]/}"  # Remove : and other unsafe chars
    if [[ ! "$sanitized" =~ ^[a-zA-Z0-9.-]+$ ]] || [[ ${#sanitized} -gt 253 ]]; then
      _net_log ERROR "Invalid hostname: $input"
      return 1
    fi
    ;;
  ip)
    sanitized="${input//[^0-9a-fA-F.:]/}"  # Tailored for IP (IPv4/IPv6)
    if [[ "$sanitized" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      # Validate IPv4 octets
      local octets=("${(@s/./)sanitized}")
      for o in "${octets[@]}"; do
        (( o >= 0 && o <= 255 )) || {
          _net_log ERROR "Invalid IPv4 address: $input"
          return 1
        }
      done
    elif [[ "$sanitized" =~ ^[0-9a-fA-F:]+$ ]]; then
      # Improved IPv6: Check length, normalize, validate groups
      local normalized="${sanitized//::/:0:}"  # Rough expansion for counting
      local groups=("${(@s/:/)normalized}")
      if (( ${#sanitized} > 39 || ${#sanitized} < 2 || ${#groups} != 8 )); then
        _net_log ERROR "Invalid IPv6 address: $input"
        return 1
      fi
      for g in "${groups[@]}"; do
        [[ "$g" =~ ^[0-9a-fA-F]{1,4}$ ]] || {
          _net_log ERROR "Invalid IPv6 address: $input"
          return 1
        }
      done
    else
      _net_log ERROR "Invalid IP address: $input"
      return 1
    fi
    ;;
  port)
    sanitized="${input//[^0-9]/}"  # Only digits
    if [[ ! "$sanitized" =~ ^[0-9]+$ ]] || (( sanitized < 1 || sanitized > 65535 )); then
      _net_log ERROR "Invalid port number: $input"
      return 1
    fi
    ;;
  esac
  print -r -- "$sanitized"  # Output sanitized input if valid
  return 0
}
# --- Safe command execution with timeout ---
_net_exec() {
  local timeout_duration="$NET_TIMEOUT"
  local cmd=("$@")
  local log_cmd="${cmd[1]} ${(@)cmd[2,-1]/%/\*}*"  # Mask args for logging to prevent leaks

  _net_log DEBUG "Executing: $log_cmd"

  local exit_status
  if command -v timeout >/dev/null 2>&1; then
    command timeout "$timeout_duration" "${cmd[@]}" ; exit_status=$?
  elif command -v gtimeout >/dev/null 2>&1; then
    command gtimeout "$timeout_duration" "${cmd[@]}" ; exit_status=$?
  else
    _net_log WARN "No timeout tool available; running without timeout"
    "${cmd[@]}" ; exit_status=$?
  fi
  return $exit_status
}

# --- OS detection with caching ---
_net_get_os() {
  local cache_file="$NET_CACHE_FILE"
  local cache_key="os_type"
  local current_date="2025-07-16"  # User current date
  local expire_date="$(TZ=America/New_York date -d "$current_date -1 day" '+%s')"  # Epoch seconds for yesterday

  # Ensure cache file exists and has proper permissions
  if [[ ! -f "$cache_file" ]]; then
    touch "$cache_file" || { _net_log ERROR "Failed to create $cache_file"; return 1; }
  fi
  chmod 600 "$cache_file" || { _net_log ERROR "Failed to set permissions on $cache_file"; return 1; }

  # Check for staleness (if mtime older than 1 day)
  local mtime="$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null)"  # Linux/macOS compatible
  if [[ -n "$mtime" ]] && (( mtime < expire_date )); then
    _net_log DEBUG "Cache stale; recomputing OS"
    : > "$cache_file"  # Truncate to clear stale cache
  fi

  # Read cache into associative array
  typeset -A cache
  local line
  while IFS='=' read -r key value; do
    cache[$key]="${value##[[:space:]]}"  # Trim leading/trailing space
    cache[$key]="${cache[$key]%%[[:space:]]}"
  done < "$cache_file" 2>/dev/null

  # Validate cached value
  if [[ -n "${cache[$cache_key]}" ]] && [[ "${cache[$cache_key]}" =~ ^(Linux|macOS|FreeBSD|OpenBSD|NetBSD|Unknown)$ ]]; then
    _net_log DEBUG "Valid cached OS: ${cache[$cache_key]}"
    print -r -- "${cache[$cache_key]}"
    return 0
  elif [[ -n "${cache[$cache_key]}" ]]; then
    _net_log WARN "Invalid cached OS value: ${cache[$cache_key]} - recomputing and recaching"
  fi

  local os_type
  case "$(uname -s)" in
  Linux*) os_type="Linux" ;;
  Darwin*) os_type="macOS" ;;
  FreeBSD*) os_type="FreeBSD" ;;
  OpenBSD*) os_type="OpenBSD" ;;
  NetBSD*) os_type="NetBSD" ;;
  SunOS*) os_type="Solaris" ;;  # Added common variant
  *) os_type="Unknown" ;;
  esac

  # Cache if valid
  if [[ "$os_type" != "Unknown" ]]; then
    cache[$cache_key]="$os_type"
    local tmpfile="$(mktemp "${cache_file}.XXXXXX")" || { _net_log ERROR "Failed to create temp file"; return 1; }
    for k in "${(@k)cache}"; do
      print -r -- "$k=${cache[$k]}" >> "$tmpfile"
    done
    mv "$tmpfile" "$cache_file" || { _net_log ERROR "Failed to update $cache_file"; rm -f "$tmpfile"; return 1; }
    _net_log DEBUG "Cached OS type: $os_type"
  fi

  print -r -- "$os_type"
}

# --- Tool availability detection with caching ---
_net_has_tool() {
  local tool="$1"
  local cache_file="$NET_CACHE_FILE"
  local cache_key="tool_$tool"
  local current_date="2025-07-16"  # User current date
  local expire_date="$(TZ=America/New_York date -d "$current_date -1 day" '+%s')"  # Epoch seconds for yesterday

  # Ensure cache file exists and has proper permissions
  if [[ ! -f "$cache_file" ]]; then
    touch "$cache_file" || { _net_log ERROR "Failed to create $cache_file"; return 1; }
  fi
  chmod 600 "$cache_file" || { _net_log ERROR "Failed to set permissions on $cache_file"; return 1; }

  # Check for staleness (if mtime older than 1 day)
  local mtime="$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null)"  # Linux/macOS compatible
  if [[ -n "$mtime" ]] && (( mtime < expire_date )); then
    _net_log DEBUG "Cache stale; recomputing tool availability"
    : > "$cache_file"  # Truncate to clear stale cache
  fi

  # Read cache into associative array
  typeset -A cache
  local line
  while IFS='=' read -r key value; do
    cache[$key]="${value##[[:space:]]}"  # Trim leading/trailing space
    cache[$key]="${cache[$key]%%[[:space:]]}"
  done < "$cache_file" 2>/dev/null

  # Validate cached value
  if [[ -n "${cache[$cache_key]}" ]] && [[ "${cache[$cache_key]}" =~ ^[01]$ ]]; then
    _net_log DEBUG "Valid cached tool: $tool=${cache[$cache_key]}"
    [[ "${cache[$cache_key]}" == "1" ]]
    return $?
  elif [[ -n "${cache[$cache_key]}" ]]; then
    _net_log WARN "Invalid cached tool value for $tool: ${cache[$cache_key]} - recomputing and recaching"
  fi

  local result=0
  if command -v "$tool" >/dev/null 2>&1; then
    result=1
  fi

  # Cache
  cache[$cache_key]="$result"
  local tmpfile="$(mktemp "${cache_file}.XXXXXX")" || { _net_log ERROR "Failed to create temp file"; return 1; }
  for k in "${(@k)cache}"; do
    print -r -- "$k=${cache[$k]}" >> "$tmpfile"
  done
  mv "$tmpfile" "$cache_file" || { _net_log ERROR "Failed to update $cache_file"; rm -f "$tmpfile"; return 1; }
  _net_log DEBUG "Cached tool availability: $tool=$result"

  [[ $result -eq 1 ]]
  return $?
}

_net_need_sudo() {
  local operation="$1"
  local uid="$(id -u)"
  if [[ $uid -eq 0 ]]; then
    return 1 # Already root, no need for sudo
  fi

  local os="$(_net_get_os)"
  case "$os" in
  Linux)
    case "$operation" in
    ss | netstat | ufw | firewall-cmd | resolvectl | systemd-resolve | systemctl) return 0 ;;
    *) return 1 ;;
    esac
    ;;
  macOS)
    case "$operation" in
    lsof | netstat | pfctl | dscacheutil | killall) return 0 ;;
    *) return 1 ;;
    esac
    ;;
  FreeBSD|OpenBSD|NetBSD)
    case "$operation" in
    lsof | netstat | pfctl | rcctl | ipfw) return 0 ;;
    *) return 1 ;;
    esac
    ;;
  *)
    case "$operation" in
    lsof | ss | netstat | pfctl) return 0 ;;  # Fallback for unknown OS
    *) return 1 ;;
    esac
    ;;
  esac
}

# --- Execute command with appropriate privileges ---
_net_exec_priv() {
  local operation="$1"
  shift
  local cmd=("$@")

  if _net_need_sudo "$operation"; then
    if ! command -v sudo >/dev/null 2>&1; then
      _net_log ERROR "sudo is required but not available for operation: $operation"
      return 1
    fi
    if command sudo -n true 2>/dev/null; then
      # Non-interactive sudo possible; proceed
      _net_exec sudo "${cmd[@]}"
      return $?
    else
      if [[ ! -t 0 ]]; then
        _net_log ERROR "Non-interactive shell; cannot prompt for sudo on operation: $operation"
        return 1
      fi
      _net_color yellow "This operation requires administrator privileges."
      _net_color yellow "Command will be executed with sudo (password may be prompted)."
      print -r -n -- "$(_net_color bold "Proceed? [y/N]: ")"
      local response
      if ! read -t "$NET_TIMEOUT" -r response; then
        _net_log INFO "Prompt timed out for operation: $operation"
        return 1
      fi
      response="${response//[[:space:]]/}"  # Trim whitespace
      if [[ "$response" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        _net_exec sudo "${cmd[@]}"
        local status=$?
        if [[ $status -ne 0 ]]; then
          _net_log ERROR "sudo execution failed for operation: $operation (status $status)"
        fi
        return $status
      else
        _net_log INFO "Operation cancelled by user: $operation"
        return 1
      fi
    fi
  else
    _net_exec "${cmd[@]}"
    return $?
  fi
}

# ============================================
# Network Information Functions
# ============================================

# --- Function to show IP addresses with formatting ---
_net_show_ip() {
  local os="$(_net_get_os)"
  local show_ipv6="${1:-true}"

  _net_color bold "Network Interface IP Addresses"
  echo "================================"

  case "$os" in
  macOS)
    if _net_has_tool ifconfig; then
      command ifconfig | awk '
        /^[a-z]/ { iface=$1; gsub(/:$/, "", iface) }
        /inet / && !/127\.0\.0\.1/ { printf "%-12s IPv4: %s\n", iface, $2 }
        /inet6 / && !/::1/ && !/fe80:/ { if ("'"$show_ipv6"'" == "true") printf "%-12s IPv6: %s\n", iface, $2 }
        /status: active/ { printf "%-12s Status: %s\n", iface, "UP" }
        /status: inactive/ { printf "%-12s Status: %s\n", iface, "DOWN" }
      '
    else
      _net_log ERROR "ifconfig not available"
      return 1
    fi
    ;;
  Linux)
    if _net_has_tool ip; then
      command ip -br addr show | awk '
        {
          iface = $1
          status = $2
          ips = ""
          for (i=3; i<=NF; i++) {
            if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/) {
              ips = ips (ips ? " " : "") $i " (IPv4)"
            } else if ($i ~ /:/ && "'"$show_ipv6"'" == "true") {
              ips = ips (ips ? " " : "") $i " (IPv6)"
            }
          }
          if (ips) printf "%-12s %s (Status: %s)\n", iface, ips, status
        }
      '
    elif _net_has_tool ifconfig; then
      command ifconfig | awk '
        /^[a-z]/ { iface=$1; gsub(/:$/, "", iface) }
        /inet / && !/127\.0\.0\.1/ { printf "%-12s IPv4: %s\n", iface, $2 }
        /inet6 / && !/::1/ && !/fe80:/ { if ("'"$show_ipv6"'" == "true") printf "%-12s IPv6: %s\n", iface, $2 }
      '
    else
      _net_log ERROR "Neither ip nor ifconfig available"
      return 1
    fi
    ;;
  FreeBSD | OpenBSD | NetBSD)
    if _net_has_tool ifconfig; then
      command ifconfig | awk '
        /^[a-z]/ { iface=$1; gsub(/:$/, "", iface) }
        /inet / && !/127\.0\.0\.1/ { printf "%-12s IPv4: %s\n", iface, $2 }
        /inet6 / && !/::1/ && !/fe80:/ { if ("'"$show_ipv6"'" == "true") printf "%-12s IPv6: %s\n", iface, $2 }
      '
    else
      _net_log ERROR "ifconfig not available"
      return 1
    fi
    ;;
  *)
    _net_log ERROR "Unsupported OS: $os"
    return 1
    ;;
  esac
}

# --- Function to show interface statistics ---
_net_show_stats() {
  local os="$(_net_get_os)"
  local interface="${1:-}"

  _net_color bold "Network Interface Statistics"
  echo "============================="

  case "$os" in
  macOS)
    if [[ -n "$interface" ]]; then
      command netstat -I "$interface" -b
    else
      command netstat -i -b
    fi
    ;;
  Linux)
    if [[ -n "$interface" ]]; then
      if [[ -f "/sys/class/net/$interface/statistics/rx_bytes" ]]; then
        local rx_bytes="$(cat "/sys/class/net/$interface/statistics/rx_bytes")"
        local tx_bytes="$(cat "/sys/class/net/$interface/statistics/tx_bytes")"
        local rx_packets="$(cat "/sys/class/net/$interface/statistics/rx_packets")"
        local tx_packets="$(cat "/sys/class/net/$interface/statistics/tx_packets")"

        printf "Interface: %s\n" "$interface"
        printf "RX Bytes:  %d\n" "$rx_bytes"
        printf "TX Bytes:  %d\n" "$tx_bytes"
        printf "RX Packets: %d\n" "$rx_packets"
        printf "TX Packets: %d\n" "$tx_packets"
      else
        _net_log ERROR "Interface $interface not found"
        return 1
      fi
    else
      cat /proc/net/dev | awk '
        NR>2 {
          gsub(/:/, "", $1)
          printf "%-12s RX: %d bytes %d packets  TX: %d bytes %d packets\n",
                 $1, $2, $3, $10, $11
        }
      '
    fi
    ;;
  FreeBSD | OpenBSD | NetBSD)
    if [[ -n "$interface" ]]; then
      command netstat -I "$interface" -b
    else
      command netstat -i -b
    fi
    ;;
  *)
    _net_log ERROR "Unsupported OS: $os"
    return 1
    ;;
  esac
}

# --- function to show interface link status ---
_net_show_links() {
  local os="$(_net_get_os)"
  local show_details="${1:-false}"

  _net_color bold "Network Interface Link Status"
  echo "=============================="

  case "$os" in
  macOS)
    if [[ "$show_details" == "true" ]]; then
      command networksetup -listallhardwareports
    else
      command ifconfig -a | awk '
        BEGIN { iface = ""; status = "DOWN" }
        /^[a-z]/ {
          if (iface != "") { printf "%-12s %s\n", iface, status }  # Print previous
          iface = $1; gsub(/:$/, "", iface)
          status = "DOWN"
        }
        /status: active/ { status = "UP" }
        /status: inactive/ { status = "DOWN" }
        /flags=/ && /UP/ { if (status == "DOWN") status = "UP" }
        END { if (iface != "") printf "%-12s %s\n", iface, status }
      '
    fi
    ;;
  Linux)
    if _net_has_tool ip; then
      if [[ "$show_details" == "true" ]]; then
        command ip -details link show
      else
        command ip link show | awk '
          /^[0-9]+:/ {
            gsub(/:$/, "", $2)
            iface = $2
          }
          /state / { status = $9 }
          /link\// { if (iface) printf "%-12s %s\n", iface, (status ? status : "UNKNOWN") }
        '
      fi
    elif _net_has_tool ifconfig; then
      command ifconfig -a | awk '
        BEGIN { iface = ""; status = "DOWN" }
        /^[a-z]/ {
          if (iface != "") { printf "%-12s %s\n", iface, status }  # Print previous
          iface = $1; gsub(/:$/, "", iface)
          status = "DOWN"
        }
        /UP/ && /RUNNING/ { status = "UP" }
        END { if (iface != "") printf "%-12s %s\n", iface, status }
      '
    else
      _net_log ERROR "Neither ip nor ifconfig available"
      return 1
    fi
    ;;
  FreeBSD | OpenBSD | NetBSD)
    command ifconfig -a | awk '
      BEGIN { iface = ""; status = "DOWN" }
      /^[a-z]/ {
        if (iface != "") { printf "%-12s %s\n", iface, status }  # Print previous
        iface = $1; gsub(/:$/, "", iface)
        status = "DOWN"
      }
      /flags=/ && /UP/ { status = "UP" }
      END { if (iface != "") printf "%-12s %s\n", iface, status }
    '
    ;;
  *)
    _net_log ERROR "Unsupported OS: $os"
    return 1
    ;;
  esac
}

# --- routing table display ---
_net_show_routes() {
  local os="$(_net_get_os)"
  local family="${1:-all}" # all, ipv4, ipv6

  _net_color bold "Routing Table"
  echo "============="

  case "$os" in
  macOS)
    case "$family" in
    ipv4) command netstat -rn -f inet ;;
    ipv6) command netstat -rn -f inet6 ;;
    *) command netstat -rn ;;
    esac
    ;;
  Linux)
    if _net_has_tool ip; then
      case "$family" in
      ipv4) command ip -4 route show ;;
      ipv6) command ip -6 route show ;;
      *)
        command ip route show
        echo
        command ip -6 route show
        ;;
      esac
    elif _net_has_tool route; then
      command route -n
    else
      _net_log ERROR "Neither ip nor route available"
      return 1
    fi
    ;;
  FreeBSD | OpenBSD | NetBSD)
    case "$family" in
    ipv4) command netstat -rn -f inet ;;
    ipv6) command netstat -rn -f inet6 ;;
    *) command netstat -rn ;;
    esac
    ;;
  *)
    _net_log ERROR "Unsupported OS: $os"
    return 1
    ;;
  esac
}

# --- default gateway display ---
_net_show_gw() {
  local os="$(_net_get_os)"
  local family="${1:-ipv4}" # ipv4, ipv6, all

  _net_color bold "Default Gateway Information"
  echo "==========================="

  case "$os" in
  macOS)
    case "$family" in
    ipv4) command netstat -rn -f inet | grep '^default' ;;
    ipv6) command netstat -rn -f inet6 | grep '^default' ;;
    *) command netstat -rn | grep '^default' ;;
    esac
    ;;
  Linux)
    if _net_has_tool ip; then
      case "$family" in
      ipv4) command ip -4 route show default ;;
      ipv6) command ip -6 route show default ;;
      *)
        echo "IPv4 Default Routes:"
        command ip -4 route show default
        echo -e "\nIPv6 Default Routes:"
        command ip -6 route show default
        ;;
      esac
    elif _net_has_tool route; then
      command route -n | grep '^0\.0\.0\.0'
    else
      _net_log ERROR "Neither ip nor route available"
      return 1
    fi
    ;;
  FreeBSD | OpenBSD | NetBSD)
    case "$family" in
    ipv4) command netstat -rn -f inet | grep '^default' ;;
    ipv6) command netstat -rn -f inet6 | grep '^default' ;;
    *) command netstat -rn | grep '^default' ;;
    esac
    ;;
  *)
    _net_log ERROR "Unsupported OS: $os"
    return 1
    ;;
  esac
}

# --- DNS configuration display ---
_net_show_dns() {
  local os="$(_net_get_os)"
  local detailed="${1:-false}"

  _net_color bold "DNS Configuration"
  echo "================="

  case "$os" in
  macOS)
    if [[ "$detailed" == "true" ]]; then
      echo "DNS Servers (via scutil):"
      command scutil --dns | grep -E 'nameserver|domain|search'
      echo -e "\nDNS Servers (per network service):"
      command networksetup -listallnetworkservices | grep -v '^\*' | while IFS= read -r service; do
        printf "\n%s:\n" "$service"
        command networksetup -getdnsservers "$service" 2>/dev/null || echo "  No DNS servers configured"
        local search_domains="$(command networksetup -getsearchdomains "$service" 2>/dev/null)"
        [[ -n "$search_domains" && ! "$search_domains" =~ "There aren't any" ]] && echo "  Search domains: $search_domains"
      done
    else
      command scutil --dns | grep 'nameserver\[' | awk '{print $3}' | sort -u
    fi
    ;;
  Linux)
    if _net_has_tool resolvectl; then
      if [[ "$detailed" == "true" ]]; then
        command resolvectl status
      else
        command resolvectl dns | grep -v '^Link' | awk '{for(i=2;i<=NF;i++) print $i}' | sort -u
      fi
    elif [[ -f /etc/resolv.conf ]]; then
      if [[ "$detailed" == "true" ]]; then
        echo "DNS Configuration (/etc/resolv.conf):"
        cat /etc/resolv.conf
      else
        grep '^nameserver' /etc/resolv.conf | awk '{print $2}'
      fi
    else
      _net_log ERROR "No DNS resolution method found"
      return 1
    fi
    ;;
  FreeBSD | OpenBSD | NetBSD)
    if [[ -f /etc/resolv.conf ]]; then
      if [[ "$detailed" == "true" ]]; then
        echo "DNS Configuration (/etc/resolv.conf):"
        cat /etc/resolv.conf
      else
        grep '^nameserver' /etc/resolv.conf | awk '{print $2}'
      fi
    else
      _net_log ERROR "/etc/resolv.conf not found"
      return 1
    fi
    ;;
  *)
    _net_log ERROR "Unsupported OS: $os"
    return 1
    ;;
  esac
}

# --- DNS cache flushing with better error handling ---
_net_flush_dns() {
  local os="$(_net_get_os)"

  _net_color yellow "Attempting to flush DNS cache..."

  case "$os" in
  macOS)
    if _net_exec_priv dscacheutil command dscacheutil -flushcache; then
      if _net_exec_priv killall command sudo killall -HUP mDNSResponder 2>/dev/null; then
        _net_color green "macOS DNS cache flushed successfully"
      else
        _net_color yellow "DNS cache flushed, but couldn't restart mDNSResponder"
      fi
    else
      _net_log ERROR "Failed to flush DNS cache"
      return 1
    fi
    ;;
  Linux)
    local success=false

    if _net_has_tool resolvectl; then
      if _net_exec_priv resolvectl command sudo resolvectl flush-caches; then
        _net_color green "systemd-resolved cache flushed"
        success=true
      fi
    fi

    if ! $success && _net_has_tool nscd; then
      if _net_exec_priv systemctl command sudo systemctl restart nscd; then
        _net_color green "nscd service restarted (cache flushed)"
        success=true
      fi
    fi

    if ! $success && _net_has_tool dnsmasq; then
      if _net_exec_priv systemctl command sudo systemctl restart dnsmasq; then
        _net_color green "dnsmasq service restarted (cache flushed)"
        success=true
      fi
    fi

    if ! $success; then
      _net_log ERROR "No suitable DNS cache flushing method found"
      return 1
    fi
    ;;
  FreeBSD | OpenBSD | NetBSD)
    _net_color yellow "BSD systems typically don't cache DNS by default"
    _net_color blue "If using a local DNS cache (like unbound), restart the service manually"
    return 0  # Not an error
    ;;
  *)
    _net_log ERROR "Unsupported OS: $os"
    return 1
    ;;
  esac
}

# --- port listening display ---
_net_show_listeners() {
  local os="$(_net_get_os)"
  local protocol="${1:-all}" # all, tcp, udp
  local show_processes="${2:-true}"

  _net_color bold "Listening Ports"
  echo "==============="

  case "$os" in
  macOS)
    if [[ "$show_processes" == "true" ]]; then
      case "$protocol" in
      tcp) _net_exec_priv lsof command sudo lsof -i TCP -P -n | grep LISTEN ;;
      udp) _net_exec_priv lsof command sudo lsof -i UDP -P -n ;;
      *) _net_exec_priv lsof command sudo lsof -i -P -n | grep -E "LISTEN|UDP" ;;
      esac
    else
      case "$protocol" in
      tcp) command netstat -an -p tcp | grep LISTEN ;;
      udp) command netstat -an -p udp ;;
      *) command netstat -an | grep -E "LISTEN|UDP" ;;
      esac
    fi
    ;;
  Linux)
    if _net_has_tool ss; then
      local ss_opts="-ln"
      [[ "$show_processes" == "true" ]] && ss_opts="${ss_opts}p"

      case "$protocol" in
      tcp) _net_exec_priv ss command sudo ss -t $ss_opts ;;
      udp) _net_exec_priv ss command sudo ss -u $ss_opts ;;
      *) _net_exec_priv ss command sudo ss -tu $ss_opts ;;
      esac
    elif _net_has_tool netstat; then
      local netstat_opts="-ln"
      [[ "$show_processes" == "true" ]] && netstat_opts="${netstat_opts}p"

      case "$protocol" in
      tcp) _net_exec_priv netstat command sudo netstat -t $netstat_opts ;;
      udp) _net_exec_priv netstat command sudo netstat -u $netstat_opts ;;
      *) _net_exec_priv netstat command sudo netstat -tu $netstat_opts ;;
      esac
    else
      _net_log ERROR "Neither ss nor netstat available"
      return 1
    fi
    ;;
  FreeBSD | OpenBSD | NetBSD)
    if [[ "$show_processes" == "true" ]]; then
      case "$protocol" in
      tcp) _net_exec_priv lsof command sudo lsof -i TCP -P -n | grep LISTEN ;;
      udp) _net_exec_priv lsof command sudo lsof -i UDP -P -n ;;
      *) _net_exec_priv lsof command sudo lsof -i -P -n | grep -E "LISTEN|UDP" ;;
      esac
    else
      case "$protocol" in
      tcp) command netstat -an -p tcp | grep LISTEN ;;
      udp) command netstat -an -p udp ;;
      *) command netstat -an | grep -E "LISTEN|UDP" ;;
      esac
    fi
    ;;
  *)
    _net_log ERROR "Unsupported OS: $os"
    return 1
    ;;
  esac
}

# --- wireless information display ---
_net_show_wireless() {
  local os="$(_net_get_os)"
  local interface="${1:-}"

  _net_color bold "Wireless Network Information"
  echo "============================="

  case "$os" in
  macOS)
    local airport="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"
    if [[ -n "$interface" ]]; then
      "$airport" -I "$interface"
    else
      "$airport" -I
    fi
    ;;
  Linux)
    if _net_has_tool iwconfig; then
      if [[ -n "$interface" ]]; then
        command iwconfig "$interface"
      else
        command iwconfig 2>/dev/null | grep -v "no wireless extensions"
      fi
    elif _net_has_tool iw; then
      if [[ -n "$interface" ]]; then
        command iw dev "$interface" info
        echo
        command iw dev "$interface" link
      else
        local found=false
        for dev in /sys/class/net/*/wireless; do
          if [[ -d "$dev" ]]; then
            local iface="$(basename "$(dirname "$dev")")"
            echo "=== $iface ==="
            command iw dev "$iface" info
            echo
            command iw dev "$iface" link
            echo
            found=true
          fi
        done
        [[ $found == false ]] && _net_log WARN "No wireless interfaces found"
      fi
    else
      _net_log ERROR "Neither iwconfig nor iw available"
      return 1
    fi
    ;;
  FreeBSD)
    if [[ -n "$interface" ]]; then
      command ifconfig "$interface"
    else
      command ifconfig | awk '/^[a-z0-9]+:/ { iface=$1; gsub(/:$/, "", iface) } /ieee80211/ { print "=== " iface " ==="; print }'
    fi
    ;;
  OpenBSD | NetBSD)
    _net_color yellow "Wireless information display not yet implemented for $os"
    return 0  # Not an error
    ;;
  *)
    _net_log ERROR "Unsupported OS: $os"
    return 1
    ;;
  esac
}

# ============================================
# Network Diagnostic Functions
# ============================================

# --- ping with better defaults ---
_net_ping() {
  local target="$1"
  local count="${2:-4}"
  local interval="${3:-1}"

  if ! _net_validate_input "$target" "hostname"; then
    return 1
  fi

  _net_color bold "Pinging $target ($count packets, ${interval}s interval)"
  echo "=================================================="

  local os="$(_net_get_os)"
  case "$os" in
  macOS | FreeBSD | OpenBSD | NetBSD | Linux)
    _net_exec ping -c "$count" -i "$interval" "$target"
    ;;
  *)
    _net_log ERROR "Unsupported OS: $os"
    return 1
    ;;
  esac
}

# --- traceroute ---
_net_traceroute() {
  local target="$1"
  local max_hops="${2:-30}"

  if ! _net_validate_input "$target" "hostname"; then
    return 1
  fi

  _net_color bold "Tracing route to $target (max $max_hops hops)"
  echo "============================================"

  if _net_has_tool traceroute; then
    _net_exec traceroute -m "$max_hops" "$target"
  elif _net_has_tool tracepath; then
    _net_exec tracepath "$target"
  else
    _net_log ERROR "Neither traceroute nor tracepath available"
    return 1
  fi
}

# --- public IP detection with multiple sources ---
_net_show_public_ip() {
  local protocol="${1:-4}" # 4 for IPv4, 6 for IPv6

  _net_color bold "Public IP Address (IPv$protocol)"
  echo "==============================="

  local sources
  if [[ "$protocol" == "6" ]]; then
    sources=(
      "https://ipv6.icanhazip.com"
      "https://v6.ident.me"
      "https://ipv6.jsonip.com"
    )
  else
    sources=(
      "https://ipv4.icanhazip.com"
      "https://v4.ident.me"
      "https://ifconfig.me/ip"
      "https://api.ipify.org"
    )
  fi

  for source in "${sources[@]}"; do
    _net_log DEBUG "Trying source: $source"
    local result
    result="$(_net_exec curl -s --max-time 10 "$source" 2>/dev/null)"
    if [[ -n "$result" ]]; then
      # Handle JSON if needed
      if [[ "$source" =~ jsonip ]]; then
        result="$(echo "$result" | awk -F'"' '/ip/ {print $4}')"
      fi
      # Validate
      if [[ "$protocol" == "6" && "$result" =~ : ]] || [[ "$protocol" != "6" && "$result" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$result"
        return 0
      fi
    fi
  done

  _net_log ERROR "Could not determine public IP address"
  return 1
}

# --- HTTP timing analysis ---
_net_http_timing() {
  local url="$1"
  local method="${2:-GET}"

  if [[ -z "$url" ]]; then
    _net_log ERROR "URL required"
    return 1
  fi

  _net_color bold "HTTP Timing Analysis: $url"
  echo "=========================="

  if ! _net_has_tool curl; then
    _net_log ERROR "curl not available"
    return 1
  fi

  local timing_format='
DNS Lookup:        %{time_namelookup}s
TCP Connect:       %{time_connect}s
TLS Handshake:     %{time_appconnect}s
Server Processing: %{time_starttransfer}s
Total Time:        %{time_total}s

HTTP Status:       %{http_code}
Size Downloaded:   %{size_download} bytes
Speed:             %{speed_download} bytes/sec
'

  _net_exec curl -X "$method" -w "$timing_format" -o /dev/null -s "$url" || _net_log ERROR "HTTP request failed"
}

# ============================================
# System Service and Firewall Functions
# ============================================

# --- service status check ---
_net_service_status() {
  local service="$1"
  local os="$(_net_get_os)"

  _net_color bold "Service Status: $service"
  echo "======================="

  case "$os" in
  macOS)
    if _net_has_tool launchctl; then
      command launchctl print "system/$service" 2>/dev/null ||
        command launchctl print "user/$(id -u)/$service" 2>/dev/null ||
        _net_log ERROR "Service $service not found"
    else
      _net_log ERROR "launchctl not available"
      return 1
    fi
    ;;
  Linux)
    if _net_has_tool systemctl; then
      command systemctl status "$service" --no-pager
    elif _net_has_tool service; then
      command service "$service" status
    else
      _net_log ERROR "Neither systemctl nor service available"
      return 1
    fi
    ;;
  FreeBSD)
    if _net_has_tool service; then
      command service "$service" status
    else
      _net_log ERROR "service command not available"
      return 1
    fi
    ;;
  OpenBSD | NetBSD)
    if _net_has_tool rcctl; then
      command rcctl check "$service"
    else
      _net_log ERROR "rcctl not available"
      return 1
    fi
    ;;
  *)
    _net_log ERROR "Unsupported OS: $os"
    return 1
    ;;
  esac
}

# --- firewall status ---
_net_firewall_status() {
  local os="$(_net_get_os)"

  _net_color bold "Firewall Status"
  echo "==============="

  case "$os" in
  macOS)
    if _net_has_tool pfctl; then
      echo "PF Firewall Status:"
      _net_exec_priv pfctl command sudo pfctl -s info
      echo -e "\nApplication Firewall Status:"
      command sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
    else
      _net_log ERROR "pfctl not available"
      return 1
    fi
    ;;
  Linux)
    local found_firewall=false

    if _net_has_tool ufw; then
      echo "UFW Status:"
      _net_exec_priv ufw command sudo ufw status verbose
      found_firewall=true
    fi

    if _net_has_tool firewall-cmd; then
      echo -e "\nfirewalld Status:"
      if _net_exec_priv firewall-cmd command sudo firewall-cmd --state >/dev/null 2>&1; then
        _net_exec_priv firewall-cmd command sudo firewall-cmd --list-all
      else
        echo "firewalld is not running"
      fi
      found_firewall=true
    fi

    if _net_has_tool iptables; then
      echo -e "\niptables Rules (filter table):"
      _net_exec_priv iptables command sudo iptables -L -n -v --line-numbers
      found_firewall=true
    fi

    if ! $found_firewall; then
      _net_log ERROR "No firewall tools found (ufw, firewalld, iptables)"
      return 1
    fi
    ;;
  FreeBSD)
    if _net_has_tool pfctl; then
      echo "PF Firewall Status:"
      _net_exec_priv pfctl command sudo pfctl -s info
      echo -e "\nPF Rules:"
      _net_exec_priv pfctl command sudo pfctl -s rules
    elif _net_has_tool ipfw; then
      echo "IPFW Status:"
      _net_exec_priv ipfw command sudo ipfw list
    else
      _net_log ERROR "Neither pfctl nor ipfw available"
      return 1
    fi
    ;;
  OpenBSD | NetBSD)
    if _net_has_tool pfctl; then
      echo "PF Firewall Status:"
      _net_exec_priv pfctl command sudo pfctl -s info
      echo -e "\nPF Rules:"
      _net_exec_priv pfctl command sudo pfctl -s rules
    else
      _net_log ERROR "pfctl not available"
      return 1
    fi
    ;;
  *)
    _net_log ERROR "Unsupported OS: $os"
    return 1
    ;;
  esac
}

# ============================================
# Aliases with Functionality
# ============================================

# --- Core Network Information ---
alias net.ip='_net_show_ip'
alias net.ip4='_net_show_ip false' # IPv4 only
alias net.ip6='_net_show_ip true'  # Include IPv6
alias net.links='_net_show_links'
alias net.links.detailed='_net_show_links true'
alias net.stats='_net_show_stats'
alias net.wireless='_net_show_wireless'

# --- Routing Information ---
alias net.routes='_net_show_routes'
alias net.routes.ipv4='_net_show_routes ipv4'
alias net.routes.ipv6='_net_show_routes ipv6'
alias net.gw='_net_show_gw'
alias net.gw.ipv4='_net_show_gw ipv4'
alias net.gw.ipv6='_net_show_gw ipv6'

# --- DNS Information ---
alias net.dns='_net_show_dns'
alias net.dns.detailed='_net_show_dns true'
alias net.dns.flush='_net_flush_dns'

# --- Port and Socket Information ---
alias net.ports='_net_show_listeners'
alias net.ports.tcp='_net_show_listeners tcp'
alias net.ports.udp='_net_show_listeners udp'
alias net.ports.simple='_net_show_listeners all false'

# --- Network Diagnostics ---
alias net.ping='_net_ping'
alias net.trace='_net_traceroute'
alias net.myip='_net_show_public_ip'
alias net.myip6='_net_show_public_ip 6'
alias net.http='_net_http_timing'

# --- Service Management ---
alias net.svc.nm='_net_service_status NetworkManager'
alias net.svc.networkd='_net_service_status systemd-networkd'
alias net.svc.resolved='_net_service_status systemd-resolved'

# --- Firewall Status ---
alias net.firewall='_net_firewall_status'

# --- Advanced Diagnostics (if tools available) ---
if _net_has_tool mtr; then
  alias net.mtr='command sudo mtr -b -z -w -n'
fi

if _net_has_tool iperf3; then
  alias net.iperf.server='iperf3 -s'
  alias net.iperf.client='iperf3 -c'
fi

if _net_has_tool nmap; then
  alias net.scan.local='if [[ "$(_net_get_os)" == "Linux" ]]; then nmap -sn $(ip route | grep "scope link" | head -1 | awk "{print \$1}"); else echo "Local scan only supported on Linux"; fi'
  net.scan.port() {
    local host="$1"
    local ports="${2:-1-1000}"
    if _net_validate_input "$host" "hostname"; then
      nmap -p "$ports" "$host"
    fi
  }
fi

# --- Network Configuration (if tools available) ---
if _net_has_tool nmcli; then
  alias net.conf.wifi='nmcli dev wifi'
  alias net.conf.conn='nmcli conn show'
  alias net.conf.devices='nmcli dev status'
fi

if _net_has_tool networkctl; then
  alias net.conf.networkctl='networkctl status'
fi

# --- Container Network Diagnostics ---
if _net_has_tool docker; then
  alias net.docker.networks='docker network ls'
  alias net.docker.inspect='docker network inspect'
fi

# ============================================
# Help System
# ============================================

net.help() {
  _net_color bold "Network Information Commands (net.*)"
  echo "=============================================="
  echo
  _net_color blue "BASIC INFORMATION:"
  echo "  net.ip                Show all IP addresses"
  echo "  net.ip4               Show IPv4 addresses only"
  echo "  net.ip6               Show IPv4 and IPv6 addresses"
  echo "  net.links             Show network interface status"
  echo "  net.links.detailed    Show detailed interface information"
  echo "  net.stats [interface] Show network interface statistics"
  echo "  net.wireless [iface]  Show wireless network information"
  echo
  _net_color blue "ROUTING INFORMATION:"
  echo "  net.routes            Show routing table (all)"
  echo "  net.routes.ipv4       Show IPv4 routing table"
  echo "  net.routes.ipv6       Show IPv6 routing table"
  echo "  net.gw                Show default gateway"
  echo "  net.gw.ipv4           Show IPv4 default gateway"
  echo "  net.gw.ipv6           Show IPv6 default gateway"
  echo
  _net_color blue "DNS INFORMATION:"
  echo "  net.dns               Show DNS servers"
  echo "  net.dns.detailed      Show detailed DNS configuration"
  echo "  net.dns.flush         Flush DNS cache (requires admin)"
  echo
  _net_color blue "PORT AND SOCKET INFORMATION:"
  echo "  net.ports             Show all listening ports with processes"
  echo "  net.ports.tcp         Show TCP listening ports only"
  echo "  net.ports.udp         Show UDP listening ports only"
  echo "  net.ports.simple      Show listening ports without process info"
  echo
  _net_color blue "NETWORK DIAGNOSTICS:"
  echo "  net.ping <host> [count] [interval]  Ping host"
  echo "  net.trace <host> [max_hops]         Traceroute to host"
  echo "  net.myip              Show public IPv4 address"
  echo "  net.myip6             Show public IPv6 address"
  echo "  net.http <url> [method]             HTTP timing analysis"
  echo
  _net_color blue "SYSTEM SERVICES:"
  echo "  net.svc.nm            NetworkManager status"
  echo "  net.svc.networkd      systemd-networkd status"
  echo "  net.svc.resolved      systemd-resolved status"
  echo
  _net_color blue "FIREWALL STATUS:"
  echo "  net.firewall          Show firewall status and rules"
  echo
  _net_color blue "ADVANCED TOOLS (if available):"
  echo "  net.mtr <host>        MTR network diagnostic"
  echo "  net.iperf.server      Start iperf3 server"
  echo "  net.iperf.client <host> Connect to iperf3 server"
  echo "  net.scan.local        Scan local network (Linux only)"
  echo "  net.scan.port <host> [ports] Port scan"
  echo
  _net_color blue "CONFIGURATION (if available):"
  echo "  net.conf.wifi         WiFi networks (NetworkManager)"
  echo "  net.conf.conn         Network connections"
  echo "  net.conf.devices      Network devices status"
  echo
  _net_color blue "CONTAINER NETWORKS (if available):"
  echo "  net.docker.networks   List Docker networks"
  echo "  net.docker.inspect <network> Inspect Docker network"
  echo
  _net_color blue "ENVIRONMENT VARIABLES:"
  echo "  NET_DEBUG=1           Enable debug output"
  echo "  NET_COLOR=never       Disable colored output"
  echo "  NET_TIMEOUT=30        Set command timeout (seconds)"
  echo
  _net_color blue "EXAMPLES:"
  echo "  net.ping google.com 10 2           # Ping 10 times, 2s interval"
  echo "  net.trace github.com 20            # Traceroute with max 20 hops"
  echo "  net.http https://example.com POST  # POST request timing"
  echo "  net.stats eth0                     # Statistics for eth0"
  echo
  _net_color green "Supported OS: Linux, macOS, FreeBSD, OpenBSD, NetBSD"
}

# --- Configuration management ---
net.config() {
  echo "Network Tools Configuration"
  echo "=========================="
  echo "Config Directory: $NET_CONFIG_DIR"
  echo "Cache File: $NET_CACHE_FILE"
  echo "Debug Level: $NET_DEBUG"
  echo "Color Output: $NET_COLOR"
  echo "Command Timeout: ${NET_TIMEOUT}s"
  echo "Detected OS: $(_net_get_os)"
  echo
  echo "Available Tools:"
  local tools=(ip ifconfig ss netstat curl dig host nmap mtr iperf3 nmcli networkctl)
  for tool in "${tools[@]}"; do
    if _net_has_tool "$tool"; then
      _net_color green "  ✓ $tool"
    else
      _net_color red "  ✗ $tool"
    fi
  done
}

# --- Cache management ---
net.cache.clear() {
  if [[ -f "$NET_CACHE_FILE" ]]; then
    rm "$NET_CACHE_FILE"
    _net_color green "Cache cleared"
  else
    _net_color yellow "No cache file found"
  fi
}

net.cache.show() {
  if [[ -f "$NET_CACHE_FILE" ]]; then
    echo "Cache Contents:"
    echo "==============="
    cat "$NET_CACHE_FILE"
  else
    _net_color yellow "No cache file found"
  fi
}

# Initialize on first load
_net_log DEBUG "Network tools initialized for $(_net_get_os)"
