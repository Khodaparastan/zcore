#!/usr/bin/env bash

_NET_SHELL_TYPE=""
_net_detect_shell() {
  if [[ -n "$ZSH_VERSION" ]]; then
    _NET_SHELL_TYPE="zsh"
    # Enable bash-like word splitting in zsh if needed
    setopt SH_WORD_SPLIT 2>/dev/null || true
  elif [[ -n "$BASH_VERSION" ]] && [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
    _NET_SHELL_TYPE="bash"
  else
    echo "Error: This script requires bash 4+ or zsh 5+" >&2
    exit 1
  fi
}

# Initialize shell detection
_net_detect_shell

# Declare variables in a shell-compatible way
if [[ "$_NET_SHELL_TYPE" == "zsh" ]]; then
  typeset -g NET_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/net-tools"
  typeset -g NET_CACHE_FILE="$NET_CONFIG_DIR/cache"
  typeset -g NET_DEBUG="${NET_DEBUG:-0}"
  typeset -g NET_COLOR="${NET_COLOR:-auto}"
  typeset -g NET_TIMEOUT="${NET_TIMEOUT:-30}"
  typeset -g NET_CACHE_TTL="${NET_CACHE_TTL:-3600}"
  typeset -g NET_CACHE_MAX_SIZE="${NET_CACHE_MAX_SIZE:-10240}"
else
  declare -g NET_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/net-tools"
  declare -g NET_CACHE_FILE="$NET_CONFIG_DIR/cache"
  declare -g NET_DEBUG="${NET_DEBUG:-0}"
  declare -g NET_COLOR="${NET_COLOR:-auto}"
  declare -g NET_TIMEOUT="${NET_TIMEOUT:-30}"
  declare -g NET_CACHE_TTL="${NET_CACHE_TTL:-3600}"
  declare -g NET_CACHE_MAX_SIZE="${NET_CACHE_MAX_SIZE:-10240}"
fi

# Ensure config directory exists with proper permissions
if [[ ! -d "$NET_CONFIG_DIR" ]]; then
  mkdir -p "$NET_CONFIG_DIR"
  chmod 700 "$NET_CONFIG_DIR"
fi

# Initialize temporary directory with cleanup
_NET_TEMP_DIR=""
_net_init_temp() {
  if [[ -z "$_NET_TEMP_DIR" ]]; then
    _NET_TEMP_DIR=$(mktemp -d -t net-tools.XXXXXX) || {
      echo "Error: Failed to create temporary directory" >&2
      exit 1
    }
    # Set trap for cleanup
    trap '_net_cleanup_temp' EXIT INT TERM
  fi
}

_net_cleanup_temp() {
  if [[ -n "$_NET_TEMP_DIR" ]] && [[ -d "$_NET_TEMP_DIR" ]]; then
    rm -rf "$_NET_TEMP_DIR"
    _NET_TEMP_DIR=""
  fi
}

# ============================================
# Core Utility Functions
# ============================================

# --- logging with multiple output streams ---
_net_log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)

  case "$level" in
  DEBUG)
    [[ $NET_DEBUG -ge 2 ]] && echo "[DEBUG $timestamp] $message" >&2
    ;;
  INFO)
    [[ $NET_DEBUG -ge 1 ]] && echo "[INFO  $timestamp] $message" >&2
    ;;
  WARN)
    echo "[WARN  $timestamp] $message" >&2
    ;;
  ERROR)
    echo "[ERROR $timestamp] $message" >&2
    # Log to system log if available
    command -v logger >/dev/null 2>&1 && logger -t net-tools "ERROR: $message"
    ;;
  esac
}

# --- color output with terminal capability detection ---
_net_color() {
  local color="$1"
  shift
  local text="$*"

  # Check if we should use colors
  if [[ "$NET_COLOR" == "never" ]] || [[ "$NET_COLOR" == "auto" && ! -t 1 ]]; then
    printf '%s\n' "$text"
    return
  fi

  # color support with better terminal compatibility
  local color_code=""
  case "$color" in
  red) color_code="\033[31m" ;;
  green) color_code="\033[32m" ;;
  yellow) color_code="\033[33m" ;;
  blue) color_code="\033[34m" ;;
  magenta) color_code="\033[35m" ;;
  cyan) color_code="\033[36m" ;;
  bold) color_code="\033[1m" ;;
  dim) color_code="\033[2m" ;;
  underline) color_code="\033[4m" ;;
  reset) color_code="\033[0m" ;;
  *)
    printf '%s\n' "$text"
    return
    ;;
  esac

  printf '%b%s\033[0m\n' "$color_code" "$text"
}

# --- input validation with comprehensive patterns ---
_net_validate_input() {
  local input="$1"
  local type="${2:-hostname}"

  # Sanitize input - remove potentially dangerous characters
  input=$(printf '%s' "$input" | tr -d '\0\r\n')

  case "$type" in
  hostname)
    # RFC 1123 compliant hostname validation
    if ! [[ "$input" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
      if ! [[ ${#input} -le 253 ]]; then
        _net_log ERROR "Hostname too long: $input"
        return 1
      fi
      _net_log ERROR "Invalid hostname format: $input"
      return 1
    fi
    ;;
  ipv4)
    # Comprehensive IPv4 validation
    if [[ "$input" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      local IFS='.'
      local octets=($input)
      local i
      for i in "${octets[@]}"; do
        if [[ $i -gt 255 ]]; then
          _net_log ERROR "Invalid IPv4 address: $input"
          return 1
        fi
      done
    else
      _net_log ERROR "Invalid IPv4 format: $input"
      return 1
    fi
    ;;
  ipv6)
    # IPv6 validation (simplified but more comprehensive)
    if ! [[ "$input" =~ ^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$ ]] &&
      ! [[ "$input" =~ ^::([0-9a-fA-F]{0,4}:){0,6}[0-9a-fA-F]{0,4}$ ]] &&
      ! [[ "$input" =~ ^([0-9a-fA-F]{0,4}:){1,6}::$ ]] &&
      ! [[ "$input" =~ ^::1$ ]] &&
      ! [[ "$input" =~ ^::$ ]]; then
      _net_log ERROR "Invalid IPv6 address: $input"
      return 1
    fi
    ;;
  ip)
    # Validate both IPv4 and IPv6
    if ! _net_validate_input "$input" "ipv4" && ! _net_validate_input "$input" "ipv6"; then
      _net_log ERROR "Invalid IP address: $input"
      return 1
    fi
    ;;
  port)
    if ! [[ "$input" =~ ^[0-9]+$ ]] || [[ "$input" -lt 1 || "$input" -gt 65535 ]]; then
      _net_log ERROR "Invalid port number: $input (must be 1-65535)"
      return 1
    fi
    ;;
  url)
    # Basic URL validation
    if ! [[ "$input" =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]+)?(/.*)?$ ]]; then
      _net_log ERROR "Invalid URL format: $input"
      return 1
    fi
    ;;
  esac
  return 0
}

# --- command execution with better timeout and error handling ---
_net_exec() {
  local timeout_duration="${NET_TIMEOUT}"
  local cmd=("$@")
  local exit_code=0

  _net_log DEBUG "Executing: ${cmd[*]}"

  # Check if command exists
  if ! command -v "${cmd[0]}" >/dev/null 2>&1; then
    _net_log ERROR "Command not found: ${cmd[0]}"
    return 127
  fi

  # Use timeout if available, with fallback methods
  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_duration" "${cmd[@]}"
    exit_code=$?
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$timeout_duration" "${cmd[@]}"
    exit_code=$?
  else
    # Fallback: run without timeout but warn
    _net_log WARN "No timeout command available, running without timeout"
    "${cmd[@]}"
    exit_code=$?
  fi

  if [[ $exit_code -eq 124 ]] || [[ $exit_code -eq 142 ]]; then
    _net_log WARN "Command timed out after ${timeout_duration}s: ${cmd[*]}"
  elif [[ $exit_code -ne 0 ]]; then
    _net_log DEBUG "Command failed with exit code $exit_code: ${cmd[*]}"
  fi

  return $exit_code
}

# --- OS detection with better caching and validation ---
_net_get_os() {
  local cache_file="$NET_CACHE_FILE"
  local cache_key="os_type"
  local cached_os=""

  # Check cache with TTL validation
  if [[ -f "$cache_file" ]]; then
    local cache_entry
    cache_entry=$(grep "^$cache_key=" "$cache_file" 2>/dev/null | tail -1)
    if [[ -n "$cache_entry" ]]; then
      cached_os=$(echo "$cache_entry" | cut -d= -f2 | cut -d: -f1)
      local cache_time
      cache_time=$(echo "$cache_entry" | cut -d= -f2 | cut -d: -f2)
      local current_time
      current_time=$(date +%s 2>/dev/null || echo "0")

      if [[ -n "$cache_time" ]] && [[ $((current_time - cache_time)) -lt $NET_CACHE_TTL ]]; then
        echo "$cached_os"
        return 0
      fi
    fi
  fi

  # Detect OS
  local os_type=""
  local uname_s
  uname_s=$(uname -s 2>/dev/null || echo "Unknown")

  case "$uname_s" in
  Linux*) os_type="Linux" ;;
  Darwin*) os_type="macOS" ;;
  FreeBSD*) os_type="FreeBSD" ;;
  OpenBSD*) os_type="OpenBSD" ;;
  NetBSD*) os_type="NetBSD" ;;
  CYGWIN*) os_type="Cygwin" ;;
  MINGW*) os_type="MinGW" ;;
  *) os_type="Unknown" ;;
  esac

  # Cache the result with timestamp
  if [[ "$os_type" != "Unknown" ]]; then
    local current_time
    current_time=$(date +%s 2>/dev/null || echo "0")
    _net_cache_set "$cache_key" "$os_type:$current_time"
    _net_log DEBUG "Detected and cached OS type: $os_type"
  fi

  echo "$os_type"
}

# --- caching system with size limits and TTL ---
_net_cache_set() {
  local key="$1"
  local value="$2"
  local cache_file="$NET_CACHE_FILE"

  # Create cache file if it doesn't exist
  touch "$cache_file"

  # Remove existing entry for this key
  if command -v sed >/dev/null 2>&1; then
    sed -i.bak "/^$key=/d" "$cache_file" 2>/dev/null && rm -f "${cache_file}.bak"
  else
    grep -v "^$key=" "$cache_file" >"${cache_file}.tmp" 2>/dev/null && mv "${cache_file}.tmp" "$cache_file"
  fi

  # Add new entry
  echo "$key=$value" >>"$cache_file"

  # Manage cache size
  _net_cache_cleanup
}

_net_cache_get() {
  local key="$1"
  local cache_file="$NET_CACHE_FILE"

  if [[ -f "$cache_file" ]]; then
    grep "^$key=" "$cache_file" 2>/dev/null | tail -1 | cut -d= -f2
  fi
}

_net_cache_cleanup() {
  local cache_file="$NET_CACHE_FILE"

  if [[ ! -f "$cache_file" ]]; then
    return
  fi

  # Check cache size and trim if necessary
  local cache_size
  cache_size=$(wc -c <"$cache_file" 2>/dev/null || echo "0")

  if [[ $cache_size -gt $NET_CACHE_MAX_SIZE ]]; then
    _net_log DEBUG "Cache size ($cache_size) exceeds limit ($NET_CACHE_MAX_SIZE), cleaning up"
    # Keep only the last half of entries
    local line_count
    line_count=$(wc -l <"$cache_file" 2>/dev/null || echo "0")
    local keep_lines=$((line_count / 2))

    if [[ $keep_lines -gt 0 ]]; then
      tail -n "$keep_lines" "$cache_file" >"${cache_file}.tmp" && mv "${cache_file}.tmp" "$cache_file"
    fi
  fi
}

# --- tool availability detection ---
_net_has_tool() {
  local tool="$1"
  local cache_key="tool_$tool"
  local cached_result

  # Check cache first
  cached_result=$(_net_cache_get "$cache_key")
  if [[ -n "$cached_result" ]]; then
    local result_value
    result_value=$(echo "$cached_result" | cut -d: -f1)
    local cache_time
    cache_time=$(echo "$cached_result" | cut -d: -f2)
    local current_time
    current_time=$(date +%s 2>/dev/null || echo "0")

    if [[ -n "$cache_time" ]] && [[ $((current_time - cache_time)) -lt $NET_CACHE_TTL ]]; then
      [[ "$result_value" == "1" ]]
      return $?
    fi
  fi

  # Check tool availability
  local result=0
  if command -v "$tool" >/dev/null 2>&1; then
    result=1
  fi

  # Cache the result with timestamp
  local current_time
  current_time=$(date +%s 2>/dev/null || echo "0")
  _net_cache_set "$cache_key" "$result:$current_time"
  _net_log DEBUG "Tool availability cached: $tool=$result"

  [[ $result -eq 1 ]]
}

# --- privilege escalation with better security ---
_net_need_sudo() {
  local operation="$1"

  # Already root
  if [[ $EUID -eq 0 ]]; then
    return 1
  fi

  # Check if operation requires privileges
  case "$operation" in
  lsof | ss | netstat | pfctl | ufw | firewall-cmd | iptables | ipfw | tcpdump | wireshark)
    return 0 # Needs sudo
    ;;
  systemctl | service | launchctl)
    # Some systemctl/service commands need sudo, some don't
    return 0
    ;;
  *)
    return 1 # Doesn't need sudo
    ;;
  esac
}

_net_exec_priv() {
  local operation="$1"
  shift
  local cmd=("$@")

  if _net_need_sudo "$operation"; then
    # Check if we can run sudo without password
    if ! sudo -n true 2>/dev/null; then
      _net_color yellow "This operation requires administrator privileges."
      _net_color blue "Command: ${cmd[*]}"
      echo -n "Proceed? [y/N]: "
      read -r response
      if [[ ! "$response" =~ ^[Yy]$ ]]; then
        _net_log INFO "Operation cancelled by user"
        return 1
      fi
    fi
    _net_exec sudo "${cmd[@]}"
  else
    _net_exec "${cmd[@]}"
  fi
}

# ============================================
# Network Information Functions
# ============================================

# --- IP address display with better formatting ---
_net_show_ip() {
  local show_ipv6="${1:-true}"
  local interface="${2:-}"
  local os
  os=$(_net_get_os)

  _net_color bold "Network Interface IP Addresses"
  echo "================================"

  case "$os" in
  macOS)
    local ifconfig_cmd=(ifconfig)
    [[ -n "$interface" ]] && ifconfig_cmd+=("$interface")

    if _net_has_tool ifconfig; then
      "${ifconfig_cmd[@]}" | awk -v show_ipv6="$show_ipv6" '
                    /^[a-z]/ { 
                        iface=$1; gsub(/:$/, "", iface)
                        status = "DOWN"
                    }
                    /inet / && !/127\.0\.0\.1/ { 
                        printf "%-15s IPv4: %-15s", iface, $2
                        if ($4) printf " (netmask: %s)", $4
                        printf "\n"
                    }
                    /inet6 / && !/::1/ && !/fe80:/ && show_ipv6 == "true" { 
                        printf "%-15s IPv6: %s\n", iface, $2
                    }
                    /status: active/ { 
                        printf "%-15s Status: UP\n", iface
                        status = "UP"
                    }
                    /flags=.*UP/ && status == "DOWN" {
                        printf "%-15s Status: UP (no carrier)\n", iface
                    }
                '
    else
      _net_log ERROR "ifconfig not available"
      return 1
    fi
    ;;
  Linux)
    if _net_has_tool ip; then
      local ip_cmd=(ip -br addr show)
      [[ -n "$interface" ]] && ip_cmd+=("$interface")

      "${ip_cmd[@]}" | awk -v show_ipv6="$show_ipv6" '
                    {
                        iface = $1
                        status = $2
                        for (i=3; i<=NF; i++) {
                            if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\//) {
                                split($i, addr, "/")
                                printf "%-15s IPv4: %-15s (Status: %s, CIDR: /%s)\n", iface, addr[1], status, addr[2]
                            } else if ($i ~ /:/ && show_ipv6 == "true" && $i !~ /^fe80:/) {
                                printf "%-15s IPv6: %s (Status: %s)\n", iface, $i, status
                            }
                        }
                    }
                '
    elif _net_has_tool ifconfig; then
      local ifconfig_cmd=(ifconfig)
      [[ -n "$interface" ]] && ifconfig_cmd+=("$interface")

      "${ifconfig_cmd[@]}" | awk -v show_ipv6="$show_ipv6" '
                    /^[a-z]/ { iface=$1; gsub(/:$/, "", iface) }
                    /inet / && !/127\.0\.0\.1/ { 
                        printf "%-15s IPv4: %s", iface, $2
                        if ($4) printf " (netmask: %s)", $4
                        printf "\n"
                    }
                    /inet6 / && !/::1/ && !/fe80:/ && show_ipv6 == "true" { 
                        printf "%-15s IPv6: %s\n", iface, $2
                    }
                '
    else
      _net_log ERROR "Neither ip nor ifconfig available"
      return 1
    fi
    ;;
  FreeBSD | OpenBSD | NetBSD)
    local ifconfig_cmd=(ifconfig)
    [[ -n "$interface" ]] && ifconfig_cmd+=("$interface")

    if _net_has_tool ifconfig; then
      "${ifconfig_cmd[@]}" | awk -v show_ipv6="$show_ipv6" '
                    /^[a-z]/ { iface=$1; gsub(/:$/, "", iface) }
                    /inet / && !/127\.0\.0\.1/ { 
                        printf "%-15s IPv4: %s", iface, $2
                        if ($4) printf " (netmask: %s)", $4
                        printf "\n"
                    }
                    /inet6 / && !/::1/ && !/fe80:/ && show_ipv6 == "true" { 
                        printf "%-15s IPv6: %s\n", iface, $2
                    }
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

# --- interface statistics with performance metrics ---
_net_show_stats() {
  local interface="${1:-}"
  local detailed="${2:-false}"
  local os
  os=$(_net_get_os)

  _net_color bold "Network Interface Statistics"
  echo "============================="

  case "$os" in
  macOS)
    if [[ -n "$interface" ]]; then
      if _net_has_tool netstat; then
        netstat -I "$interface" -b
        if [[ "$detailed" == "true" ]]; then
          echo
          _net_color blue "Detailed Interface Information:"
          ifconfig "$interface" 2>/dev/null
        fi
      fi
    else
      netstat -i -b
    fi
    ;;
  Linux)
    if [[ -n "$interface" ]]; then
      if [[ -d "/sys/class/net/$interface/statistics" ]]; then
        local stats_dir="/sys/class/net/$interface/statistics"
        printf "Interface: %s\n" "$interface"
        printf "=========================================\n"
        printf "RX Bytes:      %'d\n" "$(cat "$stats_dir/rx_bytes" 2>/dev/null || echo 0)"
        printf "TX Bytes:      %'d\n" "$(cat "$stats_dir/tx_bytes" 2>/dev/null || echo 0)"
        printf "RX Packets:    %'d\n" "$(cat "$stats_dir/rx_packets" 2>/dev/null || echo 0)"
        printf "TX Packets:    %'d\n" "$(cat "$stats_dir/tx_packets" 2>/dev/null || echo 0)"
        printf "RX Errors:     %'d\n" "$(cat "$stats_dir/rx_errors" 2>/dev/null || echo 0)"
        printf "TX Errors:     %'d\n" "$(cat "$stats_dir/tx_errors" 2>/dev/null || echo 0)"
        printf "RX Dropped:    %'d\n" "$(cat "$stats_dir/rx_dropped" 2>/dev/null || echo 0)"
        printf "TX Dropped:    %'d\n" "$(cat "$stats_dir/tx_dropped" 2>/dev/null || echo 0)"

        if [[ "$detailed" == "true" ]]; then
          echo
          _net_color blue "Additional Statistics:"
          printf "Collisions:    %'d\n" "$(cat "$stats_dir/collisions" 2>/dev/null || echo 0)"
          printf "Multicast:     %'d\n" "$(cat "$stats_dir/multicast" 2>/dev/null || echo 0)"
          printf "RX Frame Err:  %'d\n" "$(cat "$stats_dir/rx_frame_errors" 2>/dev/null || echo 0)"
          printf "RX CRC Err:    %'d\n" "$(cat "$stats_dir/rx_crc_errors" 2>/dev/null || echo 0)"
        fi
      else
        _net_log WARN "Statistics not available for interface: $interface"
      fi
    else
      if [[ -f /proc/net/dev ]]; then
        cat /proc/net/dev | awk '
                        BEGIN { 
                            printf "%-12s %12s %12s %12s %12s %12s %12s\n", 
                                   "Interface", "RX Bytes", "RX Packets", "RX Errors", 
                                   "TX Bytes", "TX Packets", "TX Errors"
                            printf "================================================================\n"
                        }
                        NR>2 {
                            gsub(/:/, "", $1)
                            printf "%-12s %12s %12s %12s %12s %12s %12s\n", 
                                   $1, $2, $3, $4, $10, $11, $12
                        }
                    '
      fi
    fi
    ;;
  FreeBSD | OpenBSD | NetBSD)
    if [[ -n "$interface" ]]; then
      netstat -I "$interface" -b
    else
      netstat -i -b
    fi
    ;;
  *)
    _net_log ERROR "Unsupported OS: $os"
    return 1
    ;;
  esac
}

# --- network links with speed and duplex information ---
_net_show_links() {
  local show_details="${1:-false}"
  local os
  os=$(_net_get_os)

  _net_color bold "Network Interface Link Status"
  echo "=============================="

  case "$os" in
  macOS)
    if [[ "$show_details" == "true" ]]; then
      networksetup -listallhardwareports 2>/dev/null || {
        _net_log WARN "networksetup not available, falling back to ifconfig"
        ifconfig -a
      }
    else
      ifconfig -a | awk '
                    /^[a-z]/ { 
                        if (prev_iface) printf "%-15s %s\n", prev_iface, prev_status
                        iface=$1; gsub(/:$/, "", iface)
                        status = "DOWN"
                        speed = ""
                    }
                    /status: active/ { status = "UP" }
                    /media:.*<.*>/ { 
                        if (match($0, /[0-9]+[GMK]?base/)) {
                            speed = substr($0, RSTART, RLENGTH)
                        }
                    }
                    /^[a-z]/ { prev_iface = iface; prev_status = status }
                    END { if (prev_iface) printf "%-15s %s\n", prev_iface, prev_status }
                '
    fi
    ;;
  Linux)
    if _net_has_tool ip; then
      if [[ "$show_details" == "true" ]]; then
        ip -details link show
      else
        ip link show | awk '
                        /^[0-9]+:/ {
                            gsub(/:$/, "", $2)
                            iface = $2
                            if ($0 ~ /state UP/) status = "UP"
                            else if ($0 ~ /state DOWN/) status = "DOWN"
                            else if ($0 ~ /state UNKNOWN/) status = "UNKNOWN"
                            else status = "UNKNOWN"
                            
                            # Extract speed if available
                            speed = ""
                            if (getline next_line > 0) {
                                if (next_line ~ /link\/ether/) {
                                    printf "%-15s %-8s", iface, status
                                    # Try to get speed from ethtool if available
                                    if (system("command -v ethtool >/dev/null 2>&1") == 0) {
                                        cmd = "ethtool " iface " 2>/dev/null | grep Speed | cut -d: -f2 | tr -d ' '"
                                        cmd | getline speed
                                        close(cmd)
                                        if (speed) printf " (%s)", speed
                                    }
                                    printf "\n"
                                } else {
                                    printf "%-15s %s\n", iface, status
                                }
                            } else {
                                printf "%-15s %s\n", iface, status
                            }
                        }
                    '
      fi
    elif _net_has_tool ifconfig; then
      ifconfig -a | awk '
                    /^[a-z]/ { 
                        if (prev_iface) printf "%-15s %s\n", prev_iface, prev_status
                        iface=$1; gsub(/:$/, "", iface)
                        status = "DOWN"
                    }
                    /UP.*RUNNING/ { status = "UP" }
                    /^[a-z]/ { prev_iface = iface; prev_status = status }
                    END { if (prev_iface) printf "%-15s %s\n", prev_iface, prev_status }
                '
    else
      _net_log ERROR "Neither ip nor ifconfig available"
      return 1
    fi
    ;;
  FreeBSD | OpenBSD | NetBSD)
    ifconfig -a | awk '
                /^[a-z]/ { 
                    if (prev_iface) printf "%-15s %s\n", prev_iface, prev_status
                    iface=$1; gsub(/:$/, "", iface)
                    status = "DOWN"
                }
                /flags=.*UP.*RUNNING/ { status = "UP" }
                /flags=.*UP/ && !/RUNNING/ { status = "UP (no carrier)" }
                /^[a-z]/ { prev_iface = iface; prev_status = status }
                END { if (prev_iface) printf "%-15s %s\n", prev_iface, prev_status }
            '
    ;;
  *)
    _net_log ERROR "Unsupported OS: $os"
    return 1
    ;;
  esac
}

# --- routing table with metric and interface information ---
_net_show_routes() {
  local family="${1:-all}" # all, ipv4, ipv6
  local detailed="${2:-false}"
  local os
  os=$(_net_get_os)

  _net_color bold "Routing Table"
  echo "============="

  case "$os" in
  macOS)
    case "$family" in
    ipv4)
      netstat -rn -f inet
      ;;
    ipv6)
      netstat -rn -f inet6
      ;;
    *)
      echo "IPv4 Routes:"
      echo "============"
      netstat -rn -f inet
      echo
      echo "IPv6 Routes:"
      echo "============"
      netstat -rn -f inet6
      ;;
    esac
    ;;
  Linux)
    if _net_has_tool ip; then
      case "$family" in
      ipv4)
        if [[ "$detailed" == "true" ]]; then
          ip -4 route show table all
        else
          ip -4 route show
        fi
        ;;
      ipv6)
        if [[ "$detailed" == "true" ]]; then
          ip -6 route show table all
        else
          ip -6 route show
        fi
        ;;
      *)
        echo "IPv4 Routes:"
        echo "============"
        if [[ "$detailed" == "true" ]]; then
          ip -4 route show table all
        else
          ip -4 route show
        fi
        echo
        echo "IPv6 Routes:"
        echo "============"
        if [[ "$detailed" == "true" ]]; then
          ip -6 route show table all
        else
          ip -6 route show
        fi
        ;;
      esac
    elif _net_has_tool route; then
      route -n
    else
      _net_log ERROR "Neither ip nor route available"
      return 1
    fi
    ;;
  FreeBSD | OpenBSD | NetBSD)
    case "$family" in
    ipv4) netstat -rn -f inet ;;
    ipv6) netstat -rn -f inet6 ;;
    *)
      echo "IPv4 Routes:"
      echo "============"
      netstat -rn -f inet
      echo
      echo "IPv6 Routes:"
      echo "============"
      netstat -rn -f inet6
      ;;
    esac
    ;;
  *)
    _net_log ERROR "Unsupported OS: $os"
    return 1
    ;;
  esac
}

# --- default gateway with reachability testing ---
_net_show_gw() {
  local family="${1:-ipv4}" # ipv4, ipv6, all
  local test_connectivity="${2:-false}"
  local os
  os=$(_net_get_os)

  _net_color bold "Default Gateway Information"
  echo "=========================="

  local gateways=()

  case "$os" in
  macOS)
    case "$family" in
    ipv4)
      mapfile -t gateways < <(netstat -rn -f inet | awk '/^default/ {print $2}')
      ;;
    ipv6)
      mapfile -t gateways < <(netstat -rn -f inet6 | awk '/^default/ {print $2}')
      ;;
    *)
      echo "IPv4 Default Routes:"
      netstat -rn -f inet | grep '^default'
      echo -e "\nIPv6 Default Routes:"
      netstat -rn -f inet6 | grep '^default'
      return
      ;;
    esac
    ;;
  Linux)
    if _net_has_tool ip; then
      case "$family" in
      ipv4)
        mapfile -t gateways < <(ip -4 route show default | awk '{print $3}')
        ;;
      ipv6)
        mapfile -t gateways < <(ip -6 route show default | awk '{print $3}')
        ;;
      *)
        echo "IPv4 Default Routes:"
        ip -4 route show default
        echo -e "\nIPv6 Default Routes:"
        ip -6 route show default
        return
        ;;
      esac
    elif _net_has_tool route; then
      mapfile -t gateways < <(route -n | awk '/^0\.0\.0\.0/ {print $2}')
    else
      _net_log ERROR "Neither ip nor route available"
      return 1
    fi
    ;;
  FreeBSD | OpenBSD | NetBSD)
    case "$family" in
    ipv4)
      mapfile -t gateways < <(netstat -rn -f inet | awk '/^default/ {print $2}')
      ;;
    ipv6)
      mapfile -t gateways < <(netstat -rn -f inet6 | awk '/^default/ {print $2}')
      ;;
    *)
      echo "IPv4 Default Routes:"
      netstat -rn -f inet | grep '^default'
      echo -e "\nIPv6 Default Routes:"
      netstat -rn -f inet6 | grep '^default'
      return
      ;;
    esac
    ;;
  *)
    _net_log ERROR "Unsupported OS: $os"
    return 1
    ;;
  esac

  # Display gateways with optional connectivity testing
  for gateway in "${gateways[@]}"; do
    if [[ -n "$gateway" ]]; then
      printf "Gateway: %s" "$gateway"

      if [[ "$test_connectivity" == "true" ]] && _net_has_tool ping; then
        if ping -c 1 -W 2 "$gateway" >/dev/null 2>&1; then
          _net_color green " (reachable)"
        else
          _net_color red " (unreachable)"
        fi
      fi
      echo
    fi
  done
}

# --- DNS configuration with validation ---
_net_show_dns() {
  local detailed="${1:-false}"
  local test_resolution="${2:-false}"
  local os
  os=$(_net_get_os)

  _net_color bold "DNS Configuration"
  echo "================="

  local dns_servers=()

  case "$os" in
  macOS)
    if [[ "$detailed" == "true" ]]; then
      echo "DNS Configuration (via scutil):"
      scutil --dns 2>/dev/null | grep -E 'nameserver|domain|search' | head -20
      echo -e "\nDNS per Network Service:"
      networksetup -listallnetworkservices 2>/dev/null | grep -v "^\\*" | while IFS= read -r service; do
        if [[ -n "$service" ]]; then
          printf "\n%s:\n" "$service"
          local dns_output
          dns_output=$(networksetup -getdnsservers "$service" 2>/dev/null)
          if [[ "$dns_output" != *"aren't any DNS Servers"* ]]; then
            echo "$dns_output" | sed 's/^/  /'
          else
            echo "  No DNS servers configured"
          fi

          local search_output
          search_output=$(networksetup -getsearchdomains "$service" 2>/dev/null)
          if [[ "$search_output" != *"aren't any"* ]]; then
            echo "  Search domains: $search_output"
          fi
        fi
      done
    else
      mapfile -t dns_servers < <(scutil --dns 2>/dev/null | grep 'nameserver\[' | awk '{print $3}' | sort -u)
    fi
    ;;
  Linux)
    if _net_has_tool resolvectl; then
      if [[ "$detailed" == "true" ]]; then
        resolvectl status
      else
        mapfile -t dns_servers < <(resolvectl dns 2>/dev/null | grep -v '^Link' | awk '{for(i=2;i<=NF;i++) print $i}' | sort -u)
      fi
    elif _net_has_tool systemd-resolve; then
      if [[ "$detailed" == "true" ]]; then
        systemd-resolve --status 2>/dev/null
      else
        mapfile -t dns_servers < <(systemd-resolve --status 2>/dev/null | grep -E 'DNS Servers|Current DNS' | awk '{for(i=3;i<=NF;i++) print $i}' | sort -u)
      fi
    elif [[ -f /etc/resolv.conf ]]; then
      if [[ "$detailed" == "true" ]]; then
        echo "DNS Configuration (/etc/resolv.conf):"
        cat /etc/resolv.conf
      else
        mapfile -t dns_servers < <(grep '^nameserver' /etc/resolv.conf | awk '{print $2}')
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
        mapfile -t dns_servers < <(grep '^nameserver' /etc/resolv.conf | awk '{print $2}')
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

  # Display DNS servers with optional resolution testing
  if [[ ${#dns_servers[@]} -gt 0 ]]; then
    echo "DNS Servers:"
    for server in "${dns_servers[@]}"; do
      if [[ -n "$server" ]]; then
        printf "  %s" "$server"

        if [[ "$test_resolution" == "true" ]] && _net_has_tool dig; then
          if dig +short +time=2 @"$server" google.com >/dev/null 2>&1; then
            _net_color green " (responding)"
          else
            _net_color red " (not responding)"
          fi
        fi
        echo
      fi
    done
  fi
}

# --- DNS cache flushing with service detection ---
_net_flush_dns() {
  local os
  os=$(_net_get_os)

  _net_color yellow "Attempting to flush DNS cache..."

  case "$os" in
  macOS)
    local macos_version
    macos_version=$(sw_vers -productVersion 2>/dev/null | cut -d. -f1-2)

    # Different methods for different macOS versions
    if _net_exec_priv dscacheutil dscacheutil -flushcache; then
      case "$macos_version" in
      10.15 | 11.* | 12.* | 13.* | 14.*)
        if _net_exec_priv killall sudo killall -HUP mDNSResponder 2>/dev/null; then
          _net_color green "macOS DNS cache flushed successfully (modern method)"
        else
          _net_color yellow "DNS cache flushed, but couldn't restart mDNSResponder"
        fi
        ;;
      *)
        _net_color green "macOS DNS cache flushed (compatibility method)"
        ;;
      esac
    else
      _net_log ERROR "Failed to flush DNS cache"
      return 1
    fi
    ;;
  Linux)
    local success=false
    local methods_tried=0

    # Try multiple methods in order of preference
    local dns_methods=(
      "resolvectl:resolvectl flush-caches"
      "systemd-resolve:systemd-resolve --flush-caches"
      "nscd:systemctl restart nscd"
      "dnsmasq:systemctl restart dnsmasq"
      "bind:systemctl restart named"
      "unbound:systemctl restart unbound"
    )

    for method in "${dns_methods[@]}"; do
      local tool_name="${method%%:*}"
      local command="${method#*:}"

      if _net_has_tool "${tool_name%% *}"; then
        methods_tried=$((methods_tried + 1))
        _net_log DEBUG "Trying method: $tool_name"

        if _net_exec_priv "$tool_name" $command; then
          _net_color green "$tool_name DNS cache flushed successfully"
          success=true
          break
        fi
      fi
    done

    if ! $success; then
      if [[ $methods_tried -eq 0 ]]; then
        _net_log ERROR "No DNS cache flushing tools found (resolvectl, systemd-resolve, nscd, dnsmasq, etc.)"
      else
        _net_log ERROR "All DNS cache flushing methods failed"
      fi
      return 1
    fi
    ;;
  FreeBSD | OpenBSD | NetBSD)
    # Check for common DNS cache services
    local services=("unbound" "dnsmasq" "named")
    local flushed=false

    for service in "${services[@]}"; do
      if _net_has_tool service && service "$service" status >/dev/null 2>&1; then
        if _net_exec_priv service sudo service "$service" restart; then
          _net_color green "$service DNS cache flushed (service restarted)"
          flushed=true
          break
        fi
      fi
    done

    if ! $flushed; then
      _net_color yellow "BSD systems typically don't cache DNS by default"
      _net_color blue "If using a local DNS cache service, restart it manually"
    fi
    ;;
  *)
    _net_log ERROR "Unsupported OS: $os"
    return 1
    ;;
  esac
}

# --- port listening with process details ---
_net_show_listeners() {
  local protocol="${1:-all}" # all, tcp, udp
  local show_processes="${2:-true}"
  local filter_port="${3:-}"
  local os
  os=$(_net_get_os)

  _net_color bold "Listening Ports"
  echo "==============="

  case "$os" in
  macOS)
    if [[ "$show_processes" == "true" ]]; then
      local lsof_opts="-i -P -n"
      case "$protocol" in
      tcp) lsof_opts="-i TCP $lsof_opts" ;;
      udp) lsof_opts="-i UDP $lsof_opts" ;;
      *) ;;
      esac

      if [[ -n "$filter_port" ]]; then
        lsof_opts="$lsof_opts -i :$filter_port"
      fi

      _net_exec_priv lsof sudo lsof $lsof_opts | awk '
                    NR==1 { print; next }
                    /LISTEN|UDP/ {
                        printf "%-15s %-8s %-6s %-20s %s\n", $1, $2, $3, $9, $8
                    }
                '
    else
      case "$protocol" in
      tcp)
        local cmd="netstat -an -p tcp"
        [[ -n "$filter_port" ]] && cmd="$cmd | grep :$filter_port"
        eval "$cmd" | grep LISTEN
        ;;
      udp)
        local cmd="netstat -an -p udp"
        [[ -n "$filter_port" ]] && cmd="$cmd | grep :$filter_port"
        eval "$cmd"
        ;;
      *)
        local cmd="netstat -an"
        [[ -n "$filter_port" ]] && cmd="$cmd | grep :$filter_port"
        eval "$cmd" | grep -E "LISTEN|UDP"
        ;;
      esac
    fi
    ;;
  Linux)
    if _net_has_tool ss; then
      local ss_opts="-ln"
      [[ "$show_processes" == "true" ]] && ss_opts="${ss_opts}p"

      case "$protocol" in
      tcp) ss_opts="-t $ss_opts" ;;
      udp) ss_opts="-u $ss_opts" ;;
      *) ss_opts="-tu $ss_opts" ;;
      esac

      if [[ -n "$filter_port" ]]; then
        _net_exec_priv ss sudo ss $ss_opts | grep ":${filter_port}[[:space:]]"
      else
        _net_exec_priv ss sudo ss $ss_opts
      fi
    elif _net_has_tool netstat; then
      local netstat_opts="-ln"
      [[ "$show_processes" == "true" ]] && netstat_opts="${netstat_opts}p"

      case "$protocol" in
      tcp) netstat_opts="-t $netstat_opts" ;;
      udp) netstat_opts="-u $netstat_opts" ;;
      *) netstat_opts="-tu $netstat_opts" ;;
      esac

      if [[ -n "$filter_port" ]]; then
        _net_exec_priv netstat sudo netstat $netstat_opts | grep ":${filter_port}[[:space:]]"
      else
        _net_exec_priv netstat sudo netstat $netstat_opts
      fi
    else
      _net_log ERROR "Neither ss nor netstat available"
      return 1
    fi
    ;;
  FreeBSD | OpenBSD | NetBSD)
    if [[ "$show_processes" == "true" ]] && _net_has_tool lsof; then
      local lsof_opts="-i -P -n"
      case "$protocol" in
      tcp) lsof_opts="-i TCP $lsof_opts" ;;
      udp) lsof_opts="-i UDP $lsof_opts" ;;
      *) ;;
      esac

      if [[ -n "$filter_port" ]]; then
        lsof_opts="$lsof_opts -i :$filter_port"
      fi

      _net_exec_priv lsof sudo lsof $lsof_opts | grep -E "LISTEN|UDP"
    else
      case "$protocol" in
      tcp)
        local cmd="netstat -an -p tcp"
        [[ -n "$filter_port" ]] && cmd="$cmd | grep :$filter_port"
        eval "$cmd" | grep LISTEN
        ;;
      udp)
        local cmd="netstat -an -p udp"
        [[ -n "$filter_port" ]] && cmd="$cmd | grep :$filter_port"
        eval "$cmd"
        ;;
      *)
        local cmd="netstat -an"
        [[ -n "$filter_port" ]] && cmd="$cmd | grep :$filter_port"
        eval "$cmd" | grep -E "LISTEN|UDP"
        ;;
      esac
    fi
    ;;
  *)
    _net_log ERROR "Unsupported OS: $os"
    return 1
    ;;
  esac
}

# --- wireless information with signal quality ---
_net_show_wireless() {
  local interface="${1:-}"
  local detailed="${2:-false}"
  local os
  os=$(_net_get_os)

  _net_color bold "Wireless Network Information"
  echo "============================="

  case "$os" in
  macOS)
    local airport_path="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"
    if [[ -x "$airport_path" ]]; then
      if [[ -n "$interface" ]]; then
        "$airport_path" -I "$interface"
      else
        "$airport_path" -I
      fi

      if [[ "$detailed" == "true" ]]; then
        echo -e "\nAvailable Networks:"
        "$airport_path" -s 2>/dev/null | head -10
      fi
    else
      _net_log ERROR "airport command not available"
      return 1
    fi
    ;;
  Linux)
    if _net_has_tool iwconfig; then
      if [[ -n "$interface" ]]; then
        iwconfig "$interface" 2>/dev/null

        if [[ "$detailed" == "true" ]] && _net_has_tool iwlist; then
          echo -e "\nWireless scan results:"
          iwlist "$interface" scan 2>/dev/null | grep -E "Cell|ESSID|Quality|Signal level" | head -20
        fi
      else
        iwconfig 2>/dev/null | grep -v "no wireless extensions"

        if [[ "$detailed" == "true" ]]; then
          echo -e "\nWireless Interfaces:"
          for dev in /sys/class/net/*/wireless; do
            if [[ -d "$dev" ]]; then
              local iface
              iface=$(basename "$(dirname "$dev")")
              echo "=== $iface ==="
              iwconfig "$iface" 2>/dev/null
              echo
            fi
          done
        fi
      fi
    elif _net_has_tool iw; then
      if [[ -n "$interface" ]]; then
        echo "Interface Information:"
        iw dev "$interface" info
        echo -e "\nLink Information:"
        iw dev "$interface" link

        if [[ "$detailed" == "true" ]]; then
          echo -e "\nStation Information:"
          iw dev "$interface" station dump 2>/dev/null
        fi
      else
        for dev in /sys/class/net/*/wireless; do
          if [[ -d "$dev" ]]; then
            local iface
            iface=$(basename "$(dirname "$dev")")
            echo "=== $iface ==="
            iw dev "$iface" info
            echo -e "\nLink Status:"
            iw dev "$iface" link
            echo
          fi
        done
      fi
    else
      _net_log ERROR "Neither iwconfig nor iw available"
      return 1
    fi
    ;;
  FreeBSD)
    if [[ -n "$interface" ]]; then
      ifconfig "$interface" 2>/dev/null

      if [[ "$detailed" == "true" ]]; then
        # Try to get scan results
        ifconfig "$interface" scan 2>/dev/null || echo "Scan not available"
      fi
    else
      ifconfig | grep -A 15 -B 2 "wireless\|ieee80211" 2>/dev/null
    fi
    ;;
  OpenBSD | NetBSD)
    _net_color yellow "Wireless information display partially implemented for $os"
    if [[ -n "$interface" ]]; then
      ifconfig "$interface" 2>/dev/null
    else
      ifconfig | grep -A 10 -B 2 "ieee80211" 2>/dev/null
    fi
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

# --- ping with statistics and formatting ---
_net_ping() {
  local target="$1"
  local count="${2:-4}"
  local interval="${3:-1}"
  local packet_size="${4:-56}"

  if [[ -z "$target" ]]; then
    _net_log ERROR "Target required for ping"
    return 1
  fi

  if ! _net_validate_input "$target" "hostname"; then
    return 1
  fi

  if ! _net_validate_input "$count" "port" || [[ $count -gt 100 ]]; then
    _net_log ERROR "Invalid count (1-100): $count"
    return 1
  fi

  _net_color bold "Pinging $target ($count packets, ${interval}s interval, ${packet_size} bytes)"
  echo "================================================================="

  local os
  os=$(_net_get_os)

  case "$os" in
  macOS | FreeBSD | OpenBSD | NetBSD)
    _net_exec ping -c "$count" -i "$interval" -s "$packet_size" "$target"
    ;;
  Linux)
    _net_exec ping -c "$count" -i "$interval" -s "$packet_size" "$target"
    ;;
  *)
    _net_log ERROR "Unsupported OS: $os"
    return 1
    ;;
  esac
}

# --- traceroute with multiple protocols ---
_net_traceroute() {
  local target="$1"
  local max_hops="${2:-30}"
  local protocol="${3:-icmp}" # icmp, udp, tcp

  if [[ -z "$target" ]]; then
    _net_log ERROR "Target required for traceroute"
    return 1
  fi

  if ! _net_validate_input "$target" "hostname"; then
    return 1
  fi

  _net_color bold "Tracing route to $target (max $max_hops hops, protocol: $protocol)"
  echo "============================================================="

  local traceroute_cmd=""
  local traceroute_opts="-m $max_hops"

  if _net_has_tool traceroute; then
    case "$protocol" in
    tcp)
      if traceroute -T >/dev/null 2>&1; then
        traceroute_opts="$traceroute_opts -T"
      else
        _net_log WARN "TCP traceroute not supported, falling back to ICMP"
      fi
      ;;
    udp)
      traceroute_opts="$traceroute_opts -U"
      ;;
    icmp)
      traceroute_opts="$traceroute_opts -I"
      ;;
    esac
    _net_exec traceroute $traceroute_opts "$target"
  elif _net_has_tool tracepath; then
    _net_log WARN "Using tracepath (limited protocol support)"
    _net_exec tracepath -m "$max_hops" "$target"
  elif _net_has_tool mtr && [[ "$protocol" == "icmp" ]]; then
    _net_log INFO "Using mtr for traceroute"
    _net_exec mtr -c 3 -m "$max_hops" -r "$target"
  else
    _net_log ERROR "No traceroute tool available"
    return 1
  fi
}

# --- public IP detection with geolocation ---
_net_show_public_ip() {
  local protocol="${1:-4}" # 4 for IPv4, 6 for IPv6
  local show_location="${2:-false}"

  _net_color bold "Public IP Address (IPv$protocol)"
  if [[ "$show_location" == "true" ]]; then
    echo "==============================="
  else
    echo "=========================="
  fi

  local sources
  if [[ "$protocol" == "6" ]]; then
    sources=(
      "https://ipv6.icanhazip.com"
      "https://v6.ident.me"
      "https://ipv6.jsonip.com"
      "https://api6.ipify.org"
    )
  else
    sources=(
      "https://ipv4.icanhazip.com"
      "https://v4.ident.me"
      "https://ifconfig.me/ip"
      "https://api.ipify.org"
      "https://checkip.amazonaws.com"
    )
  fi

  local ip_address=""
  for source in "${sources[@]}"; do
    _net_log DEBUG "Trying source: $source"
    if result=$(_net_exec curl -s --max-time 5 --connect-timeout 3 "$source" 2>/dev/null | tr -d '\n\r'); then
      if [[ -n "$result" ]]; then
        # Validate the result
        if [[ "$protocol" == "6" ]]; then
          if [[ "$result" =~ : ]] && _net_validate_input "$result" "ipv6"; then
            ip_address="$result"
            break
          fi
        else
          if _net_validate_input "$result" "ipv4"; then
            ip_address="$result"
            break
          fi
        fi
      fi
    fi
  done

  if [[ -z "$ip_address" ]]; then
    _net_log ERROR "Could not determine public IP address"
    return 1
  fi

  echo "IP Address: $ip_address"

  # Optional geolocation lookup
  if [[ "$show_location" == "true" ]] && [[ "$protocol" == "4" ]]; then
    _net_color blue "Location Information:"
    if _net_has_tool curl; then
      local geo_result
      geo_result=$(_net_exec curl -s --max-time 5 "http://ip-api.com/line/$ip_address?fields=country,regionName,city,isp" 2>/dev/null)
      if [[ -n "$geo_result" ]]; then
        echo "$geo_result" | awk '
                    NR==1 { printf "Country:  %s\n", $0 }
                    NR==2 { printf "Region:   %s\n", $0 }
                    NR==3 { printf "City:     %s\n", $0 }
                    NR==4 { printf "ISP:      %s\n", $0 }
                '
      else
        echo "Location information not available"
      fi
    fi
  fi

  return 0
}

# --- HTTP timing with detailed metrics ---
_net_http_timing() {
  local url="$1"
  local method="${2:-GET}"
  local follow_redirects="${3:-true}"
  local max_redirects="${4:-5}"

  if [[ -z "$url" ]]; then
    _net_log ERROR "URL required"
    return 1
  fi

  if ! _net_validate_input "$url" "url"; then
    return 1
  fi

  _net_color bold "HTTP Timing Analysis: $url"
  echo "Method: $method"
  echo "=========================================="

  if ! _net_has_tool curl; then
    _net_log ERROR "curl not available"
    return 1
  fi

  _net_init_temp
  local output_file="$_NET_TEMP_DIR/http_response"

  local curl_opts=("-X" "$method" "-w" "@-" "-o" "$output_file" "-s")

  if [[ "$follow_redirects" == "true" ]]; then
    curl_opts+=("-L" "--max-redirs" "$max_redirects")
  fi

  # Comprehensive timing format
  local timing_format="
Connection Details:
==================
DNS Lookup Time:        %{time_namelookup}s
TCP Connect Time:       %{time_connect}s
TLS Handshake Time:     %{time_appconnect}s
Pre-transfer Time:      %{time_pretransfer}s
Redirect Time:          %{time_redirect}s
Server Processing Time: %{time_starttransfer}s
Total Time:             %{time_total}s

Transfer Details:
================
HTTP Status Code:       %{http_code}
Response Size:          %{size_download} bytes
Header Size:            %{size_header} bytes
Request Size:           %{size_request} bytes
Download Speed:         %{speed_download} bytes/sec
Upload Speed:           %{speed_upload} bytes/sec

Connection Info:
===============
Remote IP:              %{remote_ip}:%{remote_port}
Local IP:               %{local_ip}:%{local_port}
Redirects:              %{num_redirects}
SSL Verify Result:      %{ssl_verify_result}
"

  echo "$timing_format" | _net_exec curl "${curl_opts[@]}" "$url"
  local curl_exit_code=$?

  if [[ $curl_exit_code -eq 0 ]]; then
    echo
    _net_color blue "Response Headers:"
    echo "=================="
    curl -I -s --max-time 10 "$url" 2>/dev/null | head -10

    # Show response size if available
    if [[ -f "$output_file" ]]; then
      local response_size
      response_size=$(wc -c <"$output_file" 2>/dev/null || echo "0")
      echo "Response Body Size: $response_size bytes"
    fi
  else
    _net_log ERROR "HTTP request failed with exit code: $curl_exit_code"
    return $curl_exit_code
  fi
}

# --- New: Network bandwidth testing ---
_net_bandwidth_test() {
  local server="${1:-auto}"
  local test_type="${2:-both}" # download, upload, both
  local duration="${3:-10}"

  _net_color bold "Network Bandwidth Test"
  echo "======================"

  if _net_has_tool speedtest-cli; then
    local speedtest_opts=()

    if [[ "$server" != "auto" ]]; then
      speedtest_opts+=("--server" "$server")
    fi

    case "$test_type" in
    download)
      speedtest_opts+=("--no-upload")
      ;;
    upload)
      speedtest_opts+=("--no-download")
      ;;
    both)
      # Default behavior
      ;;
    esac

    _net_exec speedtest-cli "${speedtest_opts[@]}"
  elif _net_has_tool iperf3; then
    _net_color yellow "Using iperf3 (requires a server to connect to)"
    echo "Example usage:"
    echo "  Server: iperf3 -s"
    echo "  Client: iperf3 -c <server_ip> -t $duration"

    if [[ "$server" != "auto" ]]; then
      case "$test_type" in
      download)
        _net_exec iperf3 -c "$server" -t "$duration" -R
        ;;
      upload)
        _net_exec iperf3 -c "$server" -t "$duration"
        ;;
      both)
        echo "Upload Test:"
        _net_exec iperf3 -c "$server" -t "$duration"
        echo -e "\nDownload Test:"
        _net_exec iperf3 -c "$server" -t "$duration" -R
        ;;
      esac
    fi
  else
    _net_log ERROR "No bandwidth testing tool available (speedtest-cli, iperf3)"
    return 1
  fi
}

# --- New: Network quality assessment ---
_net_quality_test() {
  local target="${1:-8.8.8.8}"
  local count="${2:-10}"
  local interval="${3:-1}"

  if ! _net_validate_input "$target" "hostname"; then
    return 1
  fi

  _net_color bold "Network Quality Assessment: $target"
  echo "========================================"

  if ! _net_has_tool ping; then
    _net_log ERROR "ping not available"
    return 1
  fi

  _net_init_temp
  local ping_output="$_NET_TEMP_DIR/ping_results"

  echo "Running extended ping test ($count packets)..."
  ping -c "$count" -i "$interval" "$target" >"$ping_output" 2>&1
  local ping_exit_code=$?

  if [[ $ping_exit_code -ne 0 ]]; then
    _net_log ERROR "Ping test failed"
    cat "$ping_output"
    return 1
  fi

  # Parse ping results for quality metrics
  local packet_loss
  packet_loss=$(grep "packet loss" "$ping_output" | awk '{print $6}' | tr -d '%')

  local rtt_stats
  rtt_stats=$(grep "min/avg/max" "$ping_output" | awk -F'/' '{print $4, $5, $6}')

  echo
  _net_color blue "Quality Metrics:"
  echo "================"
  printf "Packet Loss:    %s%%\n" "${packet_loss:-unknown}"

  if [[ -n "$rtt_stats" ]]; then
    echo "$rtt_stats" | awk '{
            printf "RTT Min:        %.2f ms\n", $1
            printf "RTT Average:    %.2f ms\n", $2  
            printf "RTT Max:        %.2f ms\n", $3
            jitter = $3 - $1
            printf "Jitter (est):   %.2f ms\n", jitter
        }'
  fi

  # Quality assessment
  echo
  _net_color blue "Quality Assessment:"
  echo "==================="

  if [[ -n "$packet_loss" ]]; then
    if (($(echo "$packet_loss < 1" | bc -l 2>/dev/null || echo "0"))); then
      _net_color green "Packet Loss: Excellent (< 1%)"
    elif (($(echo "$packet_loss < 3" | bc -l 2>/dev/null || echo "0"))); then
      _net_color yellow "Packet Loss: Good (1-3%)"
    else
      _net_color red "Packet Loss: Poor (> 3%)"
    fi
  fi

  # Show the original ping output
  echo
  _net_color blue "Detailed Results:"
  echo "================="
  cat "$ping_output"
}

# ============================================
# System Service and Firewall Functions
# ============================================

# --- service status with dependency checking ---
_net_service_status() {
  local service="$1"
  local show_logs="${2:-false}"
  local os
  os=$(_net_get_os)

  if [[ -z "$service" ]]; then
    _net_log ERROR "Service name required"
    return 1
  fi

  _net_color bold "Service Status: $service"
  echo "======================="

  case "$os" in
  macOS)
    if _net_has_tool launchctl; then
      # Try different service paths
      local service_paths=(
        "system/$service"
        "user/$(id -u)/$service"
        "gui/$(id -u)/$service"
        "$service"
      )

      local found=false
      for path in "${service_paths[@]}"; do
        if launchctl print "$path" 2>/dev/null; then
          found=true
          break
        fi
      done

      if ! $found; then
        _net_log ERROR "Service $service not found"
        echo "Available services:"
        launchctl list | grep -E "(network|net)" | head -5
      fi
    else
      _net_log ERROR "launchctl not available"
      return 1
    fi
    ;;
  Linux)
    if _net_has_tool systemctl; then
      systemctl status "$service" --no-pager -l

      if [[ "$show_logs" == "true" ]]; then
        echo -e "\nRecent Logs:"
        echo "============"
        journalctl -u "$service" --no-pager -n 10 -l 2>/dev/null || echo "No logs available"
      fi

      echo -e "\nService Dependencies:"
      echo "===================="
      systemctl list-dependencies "$service" --no-pager 2>/dev/null | head -10
    elif _net_has_tool service; then
      service "$service" status
    else
      _net_log ERROR "Neither systemctl nor service available"
      return 1
    fi
    ;;
  FreeBSD)
    if _net_has_tool service; then
      service "$service" status

      echo -e "\nService Configuration:"
      echo "====================="
      grep -E "^${service}_" /etc/rc.conf 2>/dev/null || echo "No configuration found in /etc/rc.conf"
    else
      _net_log ERROR "service command not available"
      return 1
    fi
    ;;
  OpenBSD | NetBSD)
    if _net_has_tool rcctl; then
      rcctl check "$service"
      rcctl get "$service"
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

# --- firewall status with rule analysis ---
_net_firewall_status() {
  local detailed="${1:-false}"
  local analyze_rules="${2:-false}"
  local os
  os=$(_net_get_os)

  _net_color bold "Firewall Status"
  echo "==============="

  case "$os" in
  macOS)
    if _net_has_tool pfctl; then
      echo "PF Firewall Status:"
      echo "==================="
      _net_exec_priv pfctl sudo pfctl -s info

      if [[ "$detailed" == "true" ]]; then
        echo -e "\nPF Rules:"
        echo "========="
        _net_exec_priv pfctl sudo pfctl -s rules

        echo -e "\nPF NAT Rules:"
        echo "============="
        _net_exec_priv pfctl sudo pfctl -s nat 2>/dev/null || echo "No NAT rules"
      fi

      echo -e "\nApplication Firewall:"
      echo "===================="
      if [[ -x "/usr/libexec/ApplicationFirewall/socketfilterfw" ]]; then
        sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null
        if [[ "$detailed" == "true" ]]; then
          sudo /usr/libexec/ApplicationFirewall/socketfilterfw --listapps 2>/dev/null | head -10
        fi
      fi
    else
      _net_log ERROR "pfctl not available"
      return 1
    fi
    ;;
  Linux)
    local firewalls_found=0

    # Check UFW
    if _net_has_tool ufw; then
      echo "UFW Status:"
      echo "==========="
      _net_exec_priv ufw sudo ufw status verbose
      firewalls_found=$((firewalls_found + 1))

      if [[ "$detailed" == "true" ]]; then
        echo -e "\nUFW Application Profiles:"
        echo "========================="
        sudo ufw app list 2>/dev/null | head -10
      fi
      echo
    fi

    # Check firewalld
    if _net_has_tool firewall-cmd; then
      echo "firewalld Status:"
      echo "================="
      if _net_exec_priv firewall-cmd sudo firewall-cmd --state >/dev/null 2>&1; then
        _net_exec_priv firewall-cmd sudo firewall-cmd --list-all

        if [[ "$detailed" == "true" ]]; then
          echo -e "\nActive Zones:"
          echo "============="
          sudo firewall-cmd --get-active-zones 2>/dev/null

          echo -e "\nAll Services:"
          echo "============="
          sudo firewall-cmd --get-services 2>/dev/null | tr ' ' '\n' | head -10
        fi
      else
        echo "firewalld is not running"
      fi
      firewalls_found=$((firewalls_found + 1))
      echo
    fi

    # Check iptables
    if _net_has_tool iptables; then
      echo "iptables Rules:"
      echo "==============="
      _net_exec_priv iptables sudo iptables -L -n -v --line-numbers

      if [[ "$detailed" == "true" ]]; then
        echo -e "\nNAT Table:"
        echo "=========="
        sudo iptables -t nat -L -n -v 2>/dev/null || echo "NAT table not accessible"

        echo -e "\nMangle Table:"
        echo "============="
        sudo iptables -t mangle -L -n -v 2>/dev/null | head -20
      fi
      firewalls_found=$((firewalls_found + 1))
    fi

    if [[ $firewalls_found -eq 0 ]]; then
      _net_log ERROR "No firewall tools found (ufw, firewalld, iptables)"
      return 1
    fi
    ;;
  FreeBSD)
    local found_firewall=false

    if _net_has_tool pfctl; then
      echo "PF Firewall Status:"
      echo "==================="
      _net_exec_priv pfctl sudo pfctl -s info

      if [[ "$detailed" == "true" ]]; then
        echo -e "\nPF Rules:"
        echo "========="
        sudo pfctl -s rules
      fi
      found_firewall=true
    fi

    if _net_has_tool ipfw; then
      echo -e "\nIPFW Status:"
      echo "============"
      _net_exec_priv ipfw sudo ipfw list
      found_firewall=true
    fi

    if ! $found_firewall; then
      _net_log ERROR "Neither pfctl nor ipfw available"
      return 1
    fi
    ;;
  OpenBSD | NetBSD)
    if _net_has_tool pfctl; then
      echo "PF Firewall Status:"
      echo "==================="
      _net_exec_priv pfctl sudo pfctl -s info

      if [[ "$detailed" == "true" ]]; then
        echo -e "\nPF Rules:"
        echo "========="
        sudo pfctl -s rules

        echo -e "\nPF Statistics:"
        echo "=============="
        sudo pfctl -s state | head -10
      fi
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

  # Optional rule analysis
  if [[ "$analyze_rules" == "true" ]]; then
    echo -e "\nFirewall Rule Analysis:"
    echo "======================="
    _net_color blue "Analyzing firewall rules for common issues..."

    # This is a placeholder for more sophisticated rule analysis
    echo "• Check for overly permissive rules"
    echo "• Verify rule ordering and precedence"
    echo "• Look for conflicting rules"
    echo "• Validate port and protocol combinations"
    echo "(Detailed analysis feature coming soon)"
  fi
}

# ============================================
# Aliases with Additional Features
# ============================================

# --- Core Network Information ---
alias net.ip='_net_show_ip'
alias net.ip4='_net_show_ip false'
alias net.ip6='_net_show_ip true'
alias net.links='_net_show_links'
alias net.links.detailed='_net_show_links true'
alias net.stats='_net_show_stats'
alias net.stats.detailed='_net_show_stats "" true'
alias net.wireless='_net_show_wireless'
alias net.wireless.detailed='_net_show_wireless "" true'

# --- Routing Information ---
alias net.routes='_net_show_routes'
alias net.routes.ipv4='_net_show_routes ipv4'
alias net.routes.ipv6='_net_show_routes ipv6'
alias net.routes.detailed='_net_show_routes all true'
alias net.gw='_net_show_gw'
alias net.gw.ipv4='_net_show_gw ipv4'
alias net.gw.ipv6='_net_show_gw ipv6'
alias net.gw.test='_net_show_gw ipv4 true'

# --- DNS Information ---
alias net.dns='_net_show_dns'
alias net.dns.detailed='_net_show_dns true'
alias net.dns.test='_net_show_dns false true'
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
alias net.myip.geo='_net_show_public_ip 4 true'
alias net.http='_net_http_timing'
alias net.speed='_net_bandwidth_test'
alias net.quality='_net_quality_test'

# --- Service Management ---
alias net.svc.nm='_net_service_status NetworkManager'
alias net.svc.networkd='_net_service_status systemd-networkd'
alias net.svc.resolved='_net_service_status systemd-resolved'

# --- Firewall Status ---
alias net.firewall='_net_firewall_status'
alias net.firewall.detailed='_net_firewall_status true'

# --- Advanced Diagnostics ---
if _net_has_tool mtr; then
  alias net.mtr='sudo mtr -b -z -w -n'
  net.mtr.report() {
    local target="${1:-8.8.8.8}"
    local count="${2:-10}"
    sudo mtr -r -c "$count" "$target"
  }
fi

if _net_has_tool iperf3; then
  alias net.iperf.server='iperf3 -s'
  net.iperf.client() {
    local server="$1"
    local duration="${2:-10}"
    if [[ -n "$server" ]]; then
      iperf3 -c "$server" -t "$duration"
    else
      echo "Usage: net.iperf.client <server> [duration]"
    fi
  }
fi

if _net_has_tool nmap; then
  net.scan.local() {
    local network
    if _net_has_tool ip; then
      network=$(ip route | grep "scope link" | head -1 | awk '{print $1}')
    elif _net_has_tool route; then
      network=$(route -n | grep "^192.168" | head -1 | awk '{print $1"/24"}')
    fi

    if [[ -n "$network" ]]; then
      nmap -sn "$network"
    else
      echo "Could not determine local network range"
    fi
  }

  net.scan.port() {
    local host="$1"
    local ports="${2:-1-1000}"
    if [[ -n "$host" ]] && _net_validate_input "$host" "hostname"; then
      nmap -p "$ports" "$host"
    else
      echo "Usage: net.scan.port <host> [port-range]"
    fi
  }
fi

# --- Network Configuration ---
if _net_has_tool nmcli; then
  alias net.conf.wifi='nmcli dev wifi'
  alias net.conf.conn='nmcli conn show'
  alias net.conf.devices='nmcli dev status'

  net.wifi.connect() {
    local ssid="$1"
    local password="$2"
    if [[ -n "$ssid" ]]; then
      if [[ -n "$password" ]]; then
        nmcli dev wifi connect "$ssid" password "$password"
      else
        nmcli dev wifi connect "$ssid"
      fi
    else
      echo "Usage: net.wifi.connect <ssid> [password]"
    fi
  }
fi

if _net_has_tool networkctl; then
  alias net.conf.networkctl='networkctl status'
fi

# --- Container Network Diagnostics ---
if _net_has_tool docker; then
  alias net.docker.networks='docker network ls'
  alias net.docker.inspect='docker network inspect'

  net.docker.containers() {
    echo "Container Network Information:"
    echo "============================="
    docker ps --format "table {{.Names}}\t{{.Ports}}\t{{.Networks}}"
  }
fi

# --- VPN Status Checking ---
net.vpn.status() {
  _net_color bold "VPN Status Check"
  echo "================"

  # Check for common VPN interfaces
  local vpn_interfaces=("tun" "tap" "ppp" "wg" "utun")
  local found_vpn=false

  for iface_type in "${vpn_interfaces[@]}"; do
    local interfaces
    interfaces=$(ip link show 2>/dev/null | grep -E "^[0-9]+: ${iface_type}[0-9]+" | cut -d: -f2 | tr -d ' ' || true)
    if [[ -n "$interfaces" ]]; then
      echo "Found VPN interfaces: $interfaces"
      found_vpn=true
    fi
  done

  if ! $found_vpn; then
    echo "No VPN interfaces detected"
  fi

  # Check for VPN-related processes
  echo -e "\nVPN-related processes:"
  echo "======================"
  ps aux | grep -E "(openvpn|wireguard|strongswan|ipsec)" | grep -v grep || echo "No VPN processes found"
}

# ============================================
# Help and Configuration System
# ============================================

net.help() {
  _net_color bold "Network Tools Suite (net.*)"
  echo "====================================="
  echo "Version: 3.0"
  echo "Compatible with: Linux, macOS, FreeBSD, OpenBSD, NetBSD"
  echo

  _net_color blue "BASIC INFORMATION:"
  echo "  net.ip                    Show all IP addresses"
  echo "  net.ip4                   Show IPv4 addresses only"
  echo "  net.ip6                   Show IPv4 and IPv6 addresses"
  echo "  net.links                 Show network interface status"
  echo "  net.links.detailed        Show detailed interface information"
  echo "  net.stats [interface]     Show network interface statistics"
  echo "  net.stats.detailed [iface] Show detailed interface statistics"
  echo "  net.wireless [interface]  Show wireless network information"
  echo "  net.wireless.detailed     Show detailed wireless information"
  echo

  _net_color blue "ROUTING INFORMATION:"
  echo "  net.routes                Show routing table (all)"
  echo "  net.routes.ipv4           Show IPv4 routing table"
  echo "  net.routes.ipv6           Show IPv6 routing table"
  echo "  net.routes.detailed       Show detailed routing information"
  echo "  net.gw                    Show default gateway"
  echo "  net.gw.ipv4               Show IPv4 default gateway"
  echo "  net.gw.ipv6               Show IPv6 default gateway"
  echo "  net.gw.test               Test gateway connectivity"
  echo

  _net_color blue "DNS INFORMATION:"
  echo "  net.dns                   Show DNS servers"
  echo "  net.dns.detailed          Show detailed DNS configuration"
  echo "  net.dns.test              Test DNS server responsiveness"
  echo "  net.dns.flush             Flush DNS cache (requires admin)"
  echo

  _net_color blue "PORT AND SOCKET INFORMATION:"
  echo "  net.ports                 Show all listening ports with processes"
  echo "  net.ports.tcp             Show TCP listening ports only"
  echo "  net.ports.udp             Show UDP listening ports only"
  echo "  net.ports.simple          Show listening ports without process info"
  echo

  _net_color blue "NETWORK DIAGNOSTICS:"
  echo "  net.ping <host> [count] [interval] [size]  Ping host"
  echo "  net.trace <host> [hops] [protocol]         Traceroute to host"
  echo "  net.myip                  Show public IPv4 address"
  echo "  net.myip6                 Show public IPv6 address"
  echo "  net.myip.geo              Show public IP with location"
  echo "  net.http <url> [method]   HTTP timing analysis"
  echo "  net.speed [server]        Bandwidth test"
  echo "  net.quality [target]      Network quality assessment"
  echo

  _net_color blue "SYSTEM SERVICES:"
  echo "  net.svc.nm                NetworkManager status"
  echo "  net.svc.networkd          systemd-networkd status"
  echo "  net.svc.resolved          systemd-resolved status"
  echo

  _net_color blue "FIREWALL AND SECURITY:"
  echo "  net.firewall              Show firewall status and rules"
  echo "  net.firewall.detailed     Show detailed firewall information"
  echo "  net.vpn.status            Check VPN status"
  echo

  _net_color blue "ADVANCED TOOLS (if available):"
  echo "  net.mtr <host>            MTR network diagnostic"
  echo "  net.mtr.report <host>     MTR report mode"
  echo "  net.iperf.server          Start iperf3 server"
  echo "  net.iperf.client <host>   Connect to iperf3 server"
  echo "  net.scan.local            Scan local network"
  echo "  net.scan.port <host> [range] Port scan"
  echo

  _net_color blue "WIFI AND CONFIGURATION (if available):"
  echo "  net.conf.wifi             WiFi networks (NetworkManager)"
  echo "  net.conf.conn             Network connections"
  echo "  net.conf.devices          Network devices status"
  echo "  net.wifi.connect <ssid> [pass] Connect to WiFi"
  echo

  _net_color blue "CONTAINER NETWORKS (if available):"
  echo "  net.docker.networks       List Docker networks"
  echo "  net.docker.inspect <net>  Inspect Docker network"
  echo "  net.docker.containers     Show container network info"
  echo

  _net_color blue "MANAGEMENT COMMANDS:"
  echo "  net.config                Show configuration and tool availability"
  echo "  net.cache.show            Show cache contents"
  echo "  net.cache.clear           Clear tool cache"
  echo "  net.help                  Show this help"
  echo

  _net_color blue "ENVIRONMENT VARIABLES:"
  echo "  NET_DEBUG=1               Enable debug output (2 for verbose)"
  echo "  NET_COLOR=never           Disable colored output"
  echo "  NET_TIMEOUT=30            Set command timeout (seconds)"
  echo "  NET_CACHE_TTL=3600        Set cache TTL (seconds)"
  echo "  NET_CACHE_MAX_SIZE=10240  Set max cache size (bytes)"
  echo

  _net_color blue "EXAMPLES:"
  echo "  net.ping google.com 10 2 64        # Ping 10 times, 2s interval, 64 bytes"
  echo "  net.trace github.com 25 tcp        # TCP traceroute with max 25 hops"
  echo "  net.http https://example.com POST  # POST request timing"
  echo "  net.stats eth0                     # Statistics for eth0"
  echo "  net.quality 1.1.1.1                # Network quality to Cloudflare DNS"
  echo "  net.speed auto                     # Automatic speed test"
  echo

  _net_color green "Supported Systems: Linux, macOS, FreeBSD, OpenBSD, NetBSD"
  _net_color green "Shell Support: bash 4+, zsh 5+"
}

# --- configuration management ---
net.config() {
  local action="${1:-show}"

  case "$action" in
  show)
    _net_color bold "Network Tools Configuration"
    echo "=========================="
    echo "Shell Type:         $_NET_SHELL_TYPE"
    echo "Config Directory:   $NET_CONFIG_DIR"
    echo "Cache File:         $NET_CACHE_FILE"
    echo "Debug Level:        $NET_DEBUG"
    echo "Color Output:       $NET_COLOR"
    echo "Command Timeout:    ${NET_TIMEOUT}s"
    echo "Cache TTL:          ${NET_CACHE_TTL}s"
    echo "Cache Max Size:     $NET_CACHE_MAX_SIZE bytes"
    echo "Detected OS:        $(_net_get_os)"
    echo "Temp Directory:     ${_NET_TEMP_DIR:-not initialized}"
    echo

    _net_color blue "Cache Status:"
    if [[ -f "$NET_CACHE_FILE" ]]; then
      local cache_size
      cache_size=$(wc -c <"$NET_CACHE_FILE" 2>/dev/null || echo "0")
      local cache_entries
      cache_entries=$(wc -l <"$NET_CACHE_FILE" 2>/dev/null || echo "0")
      echo "Cache Size:         $cache_size bytes"
      echo "Cache Entries:      $cache_entries"
    else
      echo "Cache File:         Not created"
    fi
    echo

    _net_color blue "Available Tools:"
    local essential_tools=(ip ifconfig ss netstat ping curl dig host traceroute)
    local advanced_tools=(nmap mtr iperf3 speedtest-cli nmcli networkctl docker)
    local system_tools=(systemctl service launchctl pfctl iptables ufw firewall-cmd)

    echo "Essential Tools:"
    for tool in "${essential_tools[@]}"; do
      if _net_has_tool "$tool"; then
        _net_color green "  ✓ $tool"
      else
        _net_color red "  ✗ $tool"
      fi
    done

    echo -e "\nAdvanced Tools:"
    for tool in "${advanced_tools[@]}"; do
      if _net_has_tool "$tool"; then
        _net_color green "  ✓ $tool"
      else
        _net_color dim "  - $tool"
      fi
    done

    echo -e "\nSystem Tools:"
    for tool in "${system_tools[@]}"; do
      if _net_has_tool "$tool"; then
        _net_color green "  ✓ $tool"
      else
        _net_color dim "  - $tool"
      fi
    done
    ;;
  reset)
    _net_color yellow "Resetting configuration to defaults..."
    unset NET_DEBUG NET_COLOR NET_TIMEOUT NET_CACHE_TTL NET_CACHE_MAX_SIZE
    NET_DEBUG=0
    NET_COLOR="auto"
    NET_TIMEOUT=30
    NET_CACHE_TTL=3600
    NET_CACHE_MAX_SIZE=10240
    _net_color green "Configuration reset to defaults"
    ;;
  *)
    echo "Usage: net.config [show|reset]"
    ;;
  esac
}

# --- cache management ---
net.cache.clear() {
  if [[ -f "$NET_CACHE_FILE" ]]; then
    rm "$NET_CACHE_FILE"
    _net_color green "Cache cleared successfully"
  else
    _net_color yellow "No cache file found"
  fi
}

net.cache.show() {
  if [[ -f "$NET_CACHE_FILE" ]]; then
    _net_color bold "Cache Contents"
    echo "=============="

    local total_entries
    total_entries=$(wc -l <"$NET_CACHE_FILE" 2>/dev/null || echo "0")
    echo "Total entries: $total_entries"
    echo

    echo "Recent entries:"
    tail -20 "$NET_CACHE_FILE" | while IFS= read -r line; do
      local key="${line%%=*}"
      local value="${line#*=}"
      printf "%-20s %s\n" "$key:" "$value"
    done
  else
    _net_color yellow "No cache file found"
  fi
}

net.cache.stats() {
  if [[ -f "$NET_CACHE_FILE" ]]; then
    _net_color bold "Cache Statistics"
    echo "================"

    local cache_size
    cache_size=$(wc -c <"$NET_CACHE_FILE" 2>/dev/null || echo "0")
    local cache_entries
    cache_entries=$(wc -l <"$NET_CACHE_FILE" 2>/dev/null || echo "0")

    echo "File size:      $cache_size bytes"
    echo "Entries:        $cache_entries"
    echo "Max size:       $NET_CACHE_MAX_SIZE bytes"
    echo "TTL:            ${NET_CACHE_TTL}s"

    # Usage by category
    echo -e "\nEntries by type:"
    grep "^tool_" "$NET_CACHE_FILE" 2>/dev/null | wc -l | awk '{printf "Tools:          %d\n", $1}'
    grep "^os_type" "$NET_CACHE_FILE" 2>/dev/null | wc -l | awk '{printf "OS detection:   %d\n", $1}'
    grep -v -E "^(tool_|os_type)" "$NET_CACHE_FILE" 2>/dev/null | wc -l | awk '{printf "Other:          %d\n", $1}'
  else
    _net_color yellow "No cache file found"
  fi
}

# --- Diagnostic and troubleshooting ---
net.doctor() {
  _net_color bold "Network Tools Diagnostic"
  echo "========================"

  local issues=0
  local warnings=0

  # Check shell compatibility
  echo "Shell Compatibility:"
  echo "==================="
  if [[ "$_NET_SHELL_TYPE" == "bash" ]]; then
    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
      _net_color green "✓ Bash ${BASH_VERSION} (compatible)"
    else
      _net_color red "✗ Bash ${BASH_VERSION} (requires 4.0+)"
      issues=$((issues + 1))
    fi
  elif [[ "$_NET_SHELL_TYPE" == "zsh" ]]; then
    _net_color green "✓ Zsh $ZSH_VERSION (compatible)"
  fi
  echo

  # Check essential tools
  echo "Essential Tools:"
  echo "================"
  local essential=(ping curl)
  for tool in "${essential[@]}"; do
    if _net_has_tool "$tool"; then
      _net_color green "✓ $tool available"
    else
      _net_color red "✗ $tool missing (essential)"
      issues=$((issues + 1))
    fi
  done
  echo

  # Check recommended tools
  echo "Recommended Tools:"
  echo "=================="
  local recommended=(ip ifconfig ss netstat dig host traceroute)
  for tool in "${recommended[@]}"; do
    if _net_has_tool "$tool"; then
      _net_color green "✓ $tool available"
    else
      _net_color yellow "! $tool missing (recommended)"
      warnings=$((warnings + 1))
    fi
  done
  echo

  # Check permissions
  echo "Permissions:"
  echo "============"
  if [[ $EUID -eq 0 ]]; then
    _net_color yellow "! Running as root (not recommended for normal use)"
    warnings=$((warnings + 1))
  else
    _net_color green "✓ Running as non-root user"

    # Check sudo access
    if sudo -n true 2>/dev/null; then
      _net_color green "✓ Passwordless sudo available"
    else
      _net_color yellow "! Sudo may require password (some features need privileges)"
      warnings=$((warnings + 1))
    fi
  fi
  echo

  # Check configuration
  echo "Configuration:"
  echo "=============="
  if [[ -d "$NET_CONFIG_DIR" ]]; then
    _net_color green "✓ Config directory exists: $NET_CONFIG_DIR"
  else
    _net_color yellow "! Config directory missing: $NET_CONFIG_DIR"
    warnings=$((warnings + 1))
  fi

  if [[ -f "$NET_CACHE_FILE" ]]; then
    local cache_size
    cache_size=$(wc -c <"$NET_CACHE_FILE" 2>/dev/null || echo "0")
    if [[ $cache_size -gt $NET_CACHE_MAX_SIZE ]]; then
      _net_color yellow "! Cache file is large (${cache_size}/${NET_CACHE_MAX_SIZE} bytes)"
      warnings=$((warnings + 1))
    else
      _net_color green "✓ Cache file size OK ($cache_size bytes)"
    fi
  else
    _net_color blue "- No cache file (will be created on first use)"
  fi
  echo

  # Summary
  echo "Summary:"
  echo "========"
  if [[ $issues -eq 0 ]]; then
    if [[ $warnings -eq 0 ]]; then
      _net_color green "✓ All checks passed - network tools ready!"
    else
      _net_color yellow "✓ Basic functionality available ($warnings warnings)"
    fi
  else
    _net_color red "✗ Issues found ($issues errors, $warnings warnings)"
    echo
    echo "Recommendations:"
    echo "• Install missing essential tools"
    echo "• Consider installing recommended tools for full functionality"
    echo "• Run 'net.config' to see detailed tool availability"
  fi
}

# Initialize system
_net_log DEBUG "Network tools suite initialized for $(_net_get_os) ($_NET_SHELL_TYPE shell)"
_net_log DEBUG "Essential tools check completed"

# Clean up old cache entries on initialization
_net_cache_cleanup

# Provide usage hint for new users
if [[ $NET_DEBUG -eq 0 ]] && [[ ! -f "$NET_CACHE_FILE" ]]; then
  echo "Network tools loaded. Type 'net.help' for usage information."
fi
