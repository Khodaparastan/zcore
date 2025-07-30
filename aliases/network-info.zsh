#!/usr/bin/env zsh
# vim: set ft=zsh ts=2 sw=2 et:

# ============================================
# Enhanced Cross-Platform Network Info Aliases (net.*)
# ============================================
# Compatible with: Linux, macOS, FreeBSD, OpenBSD, NetBSD
# Requires: bash 4+ or zsh 5+
# Version: 2.0
# ============================================

# Global configuration
typeset -g NET_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/net-tools"
typeset -g NET_CACHE_FILE="$NET_CONFIG_DIR/cache"
typeset -g NET_DEBUG="${NET_DEBUG:-0}"
typeset -g NET_COLOR="${NET_COLOR:-auto}"
typeset -g NET_TIMEOUT="${NET_TIMEOUT:-30}"

# Ensure config directory exists
[[ ! -d "$NET_CONFIG_DIR" ]] && mkdir -p "$NET_CONFIG_DIR"

# ============================================
# Core Utility Functions
# ============================================

# --- Logging and output functions ---
_net_log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  case "$level" in
  DEBUG) [[ $NET_DEBUG -ge 1 ]] && echo "[DEBUG $timestamp] $message" >&2 ;;
  INFO) [[ $NET_DEBUG -ge 0 ]] && echo "[INFO  $timestamp] $message" >&2 ;;
  WARN) echo "[WARN  $timestamp] $message" >&2 ;;
  ERROR) echo "[ERROR $timestamp] $message" >&2 ;;
  esac
}

# --- Color output support ---
_net_color() {
  local color="$1"
  shift
  local text="$*"

  if [[ "$NET_COLOR" == "never" ]] || [[ "$NET_COLOR" == "auto" && ! -t 1 ]]; then
    echo "$text"
    return
  fi

  case "$color" in
  red) echo -e "\033[31m$text\033[0m" ;;
  green) echo -e "\033[32m$text\033[0m" ;;
  yellow) echo -e "\033[33m$text\033[0m" ;;
  blue) echo -e "\033[34m$text\033[0m" ;;
  bold) echo -e "\033[1m$text\033[0m" ;;
  *) echo "$text" ;;
  esac
}

# --- Input validation and sanitization ---
_net_validate_input() {
  local input="$1"
  local type="${2:-hostname}"

  case "$type" in
  hostname)
    if [[ ! "$input" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
      _net_log ERROR "Invalid hostname: $input"
      return 1
    fi
    ;;
  ip)
    if [[ ! "$input" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && [[ ! "$input" =~ ^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$ ]]; then
      _net_log ERROR "Invalid IP address: $input"
      return 1
    fi
    ;;
  port)
    if [[ ! "$input" =~ ^[0-9]+$ ]] || [[ "$input" -lt 1 || "$input" -gt 65535 ]]; then
      _net_log ERROR "Invalid port number: $input"
      return 1
    fi
    ;;
  esac
  return 0
}

# --- Safe command execution with timeout ---
_net_exec() {
  local timeout_duration="${NET_TIMEOUT}"
  local cmd=("$@")

  _net_log DEBUG "Executing: ${cmd[*]}"

  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_duration" "${cmd[@]}"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$timeout_duration" "${cmd[@]}"
  else
    "${cmd[@]}"
  fi
}

# --- Enhanced OS detection with caching ---
_net_get_os() {
  local cache_file="$NET_CACHE_FILE"
  local cache_key="os_type"

  # Check cache first
  if [[ -f "$cache_file" ]]; then
    local cached_os=$(grep "^$cache_key=" "$cache_file" 2>/dev/null | cut -d= -f2)
    if [[ -n "$cached_os" ]]; then
      echo "$cached_os"
      return 0
    fi
  fi

  local os_type
  case "$(uname -s)" in
  Linux*) os_type="Linux" ;;
  Darwin*) os_type="macOS" ;;
  FreeBSD*) os_type="FreeBSD" ;;
  OpenBSD*) os_type="OpenBSD" ;;
  NetBSD*) os_type="NetBSD" ;;
  *) os_type="Unknown" ;;
  esac

  # Cache the result
  if [[ "$os_type" != "Unknown" ]]; then
    echo "$cache_key=$os_type" >>"$cache_file"
    _net_log DEBUG "Cached OS type: $os_type"
  fi

  echo "$os_type"
}

# --- Tool availability detection with caching ---
_net_has_tool() {
  local tool="$1"
  local cache_file="$NET_CACHE_FILE"
  local cache_key="tool_$tool"

  # Check cache first
  if [[ -f "$cache_file" ]]; then
    local cached_result=$(grep "^$cache_key=" "$cache_file" 2>/dev/null | cut -d= -f2)
    if [[ -n "$cached_result" ]]; then
      [[ "$cached_result" == "1" ]]
      return $?
    fi
  fi

  local result=0
  if command -v "$tool" >/dev/null 2>&1; then
    result=1
  fi

  # Cache the result
  echo "$cache_key=$result" >>"$cache_file"
  _net_log DEBUG "Cached tool availability: $tool=$result"

  [[ $result -eq 1 ]]
}

# --- Privilege escalation check ---
_net_need_sudo() {
  local operation="$1"
  if [[ $EUID -eq 0 ]]; then
    return 1 # Already root, no sudo needed
  fi

  case "$operation" in
  lsof | ss | netstat | pfctl | ufw | firewall-cmd)
    return 0 # Needs sudo
    ;;
  *)
    return 1 # Doesn't need sudo
    ;;
  esac
}

# --- Execute command with appropriate privileges ---
_net_exec_priv() {
  local operation="$1"
  shift
  local cmd=("$@")

  if _net_need_sudo "$operation"; then
    if ! sudo -n true 2>/dev/null; then
      _net_color yellow "This operation requires administrator privileges."
      echo "Command: ${cmd[*]}"
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
# Enhanced Network Information Functions
# ============================================

# --- Function to show IP addresses with enhanced formatting ---
_net_show_ip() {
  local os=$(_net_get_os)
  local show_ipv6="${1:-true}"

  _net_color bold "Network Interface IP Addresses"
  echo "================================"

  case "$os" in
  macOS)
    if _net_has_tool ifconfig; then
      ifconfig | awk '
                    /^[a-z]/ { iface=$1; gsub(/:$/, "", iface) }
                    /inet / && !/127\.0\.0\.1/ { printf "%-12s IPv4: %s\n", iface, $2 }
                    /inet6 / && !/::1/ && !/fe80:/ { if ("'$show_ipv6'" == "true") printf "%-12s IPv6: %s\n", iface, $2 }
                    /status: active/ { printf "%-12s Status: %s\n", iface, "UP" }
                '
    else
      _net_log ERROR "ifconfig not available"
      return 1
    fi
    ;;
  Linux)
    if _net_has_tool ip; then
      ip -br addr show | awk '
                    {
                        iface = $1
                        status = $2
                        for (i=3; i<=NF; i++) {
                            if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/) {
                                printf "%-12s IPv4: %s (Status: %s)\n", iface, $i, status
                            } else if ($i ~ /:/ && "'$show_ipv6'" == "true") {
                                printf "%-12s IPv6: %s (Status: %s)\n", iface, $i, status
                            }
                        }
                    }
                '
    elif _net_has_tool ifconfig; then
      ifconfig | awk '
                    /^[a-z]/ { iface=$1; gsub(/:$/, "", iface) }
                    /inet / && !/127\.0\.0\.1/ { printf "%-12s IPv4: %s\n", iface, $2 }
                    /inet6 / && !/::1/ && !/fe80:/ { if ("'$show_ipv6'" == "true") printf "%-12s IPv6: %s\n", iface, $2 }
                '
    else
      _net_log ERROR "Neither ip nor ifconfig available"
      return 1
    fi
    ;;
  FreeBSD | OpenBSD | NetBSD)
    if _net_has_tool ifconfig; then
      ifconfig | awk '
                    /^[a-z]/ { iface=$1; gsub(/:$/, "", iface) }
                    /inet / && !/127\.0\.0\.1/ { printf "%-12s IPv4: %s\n", iface, $2 }
                    /inet6 / && !/::1/ && !/fe80:/ { if ("'$show_ipv6'" == "true") printf "%-12s IPv6: %s\n", iface, $2 }
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
  local os=$(_net_get_os)
  local interface="${1:-}"

  _net_color bold "Network Interface Statistics"
  echo "============================="

  case "$os" in
  macOS)
    if [[ -n "$interface" ]]; then
      netstat -I "$interface" -b
    else
      netstat -i -b
    fi
    ;;
  Linux)
    if [[ -n "$interface" ]] && [[ -f "/sys/class/net/$interface/statistics/rx_bytes" ]]; then
      local rx_bytes=$(cat "/sys/class/net/$interface/statistics/rx_bytes")
      local tx_bytes=$(cat "/sys/class/net/$interface/statistics/tx_bytes")
      local rx_packets=$(cat "/sys/class/net/$interface/statistics/rx_packets")
      local tx_packets=$(cat "/sys/class/net/$interface/statistics/tx_packets")

      printf "Interface: %s\n" "$interface"
      printf "RX Bytes:  %'d\n" "$rx_bytes"
      printf "TX Bytes:  %'d\n" "$tx_bytes"
      printf "RX Packets: %'d\n" "$rx_packets"
      printf "TX Packets: %'d\n" "$tx_packets"
    else
      cat /proc/net/dev | awk '
                    NR>2 {
                        gsub(/:/, "", $1)
                        printf "%-12s RX: %'"'"'d bytes %'"'"'d packets  TX: %'"'"'d bytes %'"'"'d packets\n", 
                               $1, $2, $3, $10, $11
                    }
                '
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

# --- Enhanced function to show interface link status ---
_net_show_links() {
  local os=$(_net_get_os)
  local show_details="${1:-false}"

  _net_color bold "Network Interface Link Status"
  echo "=============================="

  case "$os" in
  macOS)
    if [[ "$show_details" == "true" ]]; then
      networksetup -listallhardwareports
    else
      ifconfig -a | awk '
                    /^[a-z]/ { 
                        iface=$1; gsub(/:$/, "", iface)
                        status = "DOWN"
                    }
                    /status: active/ { status = "UP" }
                    /flags=/ && /UP/ { if (status == "DOWN") status = "UP" }
                    /^[a-z]/ && NR>1 { 
                        printf "%-12s %s\n", prev_iface, prev_status
                    }
                    /^[a-z]/ { prev_iface = iface; prev_status = status }
                    END { if (prev_iface) printf "%-12s %s\n", prev_iface, prev_status }
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
                            else status = "UNKNOWN"
                            printf "%-12s %s\n", iface, status
                        }
                    '
      fi
    elif _net_has_tool ifconfig; then
      ifconfig -a | awk '
                    /^[a-z]/ { 
                        iface=$1; gsub(/:$/, "", iface)
                        status = "DOWN"
                    }
                    /UP/ && /RUNNING/ { status = "UP" }
                    /^[a-z]/ && NR>1 { 
                        printf "%-12s %s\n", prev_iface, prev_status
                    }
                    /^[a-z]/ { prev_iface = iface; prev_status = status }
                    END { if (prev_iface) printf "%-12s %s\n", prev_iface, prev_status }
                '
    else
      _net_log ERROR "Neither ip nor ifconfig available"
      return 1
    fi
    ;;
  FreeBSD | OpenBSD | NetBSD)
    ifconfig -a | awk '
                /^[a-z]/ { 
                    iface=$1; gsub(/:$/, "", iface)
                    status = "DOWN"
                }
                /flags=/ && /UP/ { status = "UP" }
                /^[a-z]/ && NR>1 { 
                    printf "%-12s %s\n", prev_iface, prev_status
                }
                /^[a-z]/ { prev_iface = iface; prev_status = status }
                END { if (prev_iface) printf "%-12s %s\n", prev_iface, prev_status }
            '
    ;;
  *)
    _net_log ERROR "Unsupported OS: $os"
    return 1
    ;;
  esac
}

# --- Enhanced routing table display ---
_net_show_routes() {
  local os=$(_net_get_os)
  local family="${1:-all}" # all, ipv4, ipv6

  _net_color bold "Routing Table"
  echo "============="

  case "$os" in
  macOS)
    case "$family" in
    ipv4) netstat -rn -f inet ;;
    ipv6) netstat -rn -f inet6 ;;
    *) netstat -rn ;;
    esac
    ;;
  Linux)
    if _net_has_tool ip; then
      case "$family" in
      ipv4) ip -4 route show ;;
      ipv6) ip -6 route show ;;
      *)
        ip route show
        echo
        ip -6 route show
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
    *) netstat -rn ;;
    esac
    ;;
  *)
    _net_log ERROR "Unsupported OS: $os"
    return 1
    ;;
  esac
}

# --- Enhanced default gateway display ---
_net_show_gw() {
  local os=$(_net_get_os)
  local family="${1:-ipv4}" # ipv4, ipv6, all

  _net_color bold "Default Gateway Information"
  echo "=========================="

  case "$os" in
  macOS)
    case "$family" in
    ipv4) netstat -rn -f inet | grep '^default' ;;
    ipv6) netstat -rn -f inet6 | grep '^default' ;;
    *) netstat -rn | grep '^default' ;;
    esac
    ;;
  Linux)
    if _net_has_tool ip; then
      case "$family" in
      ipv4) ip -4 route show default ;;
      ipv6) ip -6 route show default ;;
      *)
        echo "IPv4 Default Routes:"
        ip -4 route show default
        echo -e "\nIPv6 Default Routes:"
        ip -6 route show default
        ;;
      esac
    elif _net_has_tool route; then
      route -n | grep '^0\.0\.0\.0'
    else
      _net_log ERROR "Neither ip nor route available"
      return 1
    fi
    ;;
  FreeBSD | OpenBSD | NetBSD)
    case "$family" in
    ipv4) netstat -rn -f inet | grep '^default' ;;
    ipv6) netstat -rn -f inet6 | grep '^default' ;;
    *) netstat -rn | grep '^default' ;;
    esac
    ;;
  *)
    _net_log ERROR "Unsupported OS: $os"
    return 1
    ;;
  esac
}

# --- Enhanced DNS configuration display ---
_net_show_dns() {
  local os=$(_net_get_os)
  local detailed="${1:-false}"

  _net_color bold "DNS Configuration"
  echo "================="

  case "$os" in
  macOS)
    if [[ "$detailed" == "true" ]]; then
      echo "DNS Servers (via scutil):"
      scutil --dns | grep -E 'nameserver|domain|search'
      echo -e "\nDNS Servers (per network service):"
      networksetup -listallnetworkservices | grep -v "^\*" | while IFS= read -r service; do
        printf "\n%s:\n" "$service"
        networksetup -getdnsservers "$service" 2>/dev/null || echo "  No DNS servers configured"
        networksetup -getsearchdomains "$service" 2>/dev/null | grep -v "There aren't any" && echo "  Search domains: $(networksetup -getsearchdomains "$service" 2>/dev/null)"
      done
    else
      scutil --dns | grep 'nameserver\[' | awk '{print $3}' | sort -u
    fi
    ;;
  Linux)
    if _net_has_tool resolvectl; then
      if [[ "$detailed" == "true" ]]; then
        resolvectl status
      else
        resolvectl dns | grep -v '^Link' | awk '{for(i=2;i<=NF;i++) print $i}' | sort -u
      fi
    elif _net_has_tool systemd-resolve; then
      systemd-resolve --status 2>/dev/null | grep -E 'DNS Servers|Current DNS'
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

# --- Enhanced DNS cache flushing with better error handling ---
_net_flush_dns() {
  local os=$(_net_get_os)

  _net_color yellow "Attempting to flush DNS cache..."

  case "$os" in
  macOS)
    if _net_exec_priv dscacheutil dscacheutil -flushcache; then
      if _net_exec_priv killall sudo killall -HUP mDNSResponder 2>/dev/null; then
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

    # Try systemd-resolved first
    if _net_has_tool resolvectl; then
      if _net_exec_priv resolvectl resolvectl flush-caches; then
        _net_color green "systemd-resolved cache flushed"
        success=true
      fi
    elif _net_has_tool systemd-resolve; then
      if _net_exec_priv systemd-resolve sudo systemd-resolve --flush-caches; then
        _net_color green "systemd-resolve cache flushed"
        success=true
      fi
    fi

    # Try nscd if available
    if ! $success && _net_has_tool nscd; then
      if _net_exec_priv systemctl sudo systemctl restart nscd; then
        _net_color green "nscd service restarted (cache flushed)"
        success=true
      fi
    fi

    # Try dnsmasq if available
    if ! $success && _net_has_tool dnsmasq; then
      if _net_exec_priv systemctl sudo systemctl restart dnsmasq; then
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
    # BSD systems typically don't cache DNS by default
    _net_color yellow "BSD systems typically don't cache DNS by default"
    _net_color blue "If using a local DNS cache (like unbound), restart the service manually"
    ;;
  *)
    _net_log ERROR "Unsupported OS: $os"
    return 1
    ;;
  esac
}

# --- Enhanced port listening display ---
_net_show_listeners() {
  local os=$(_net_get_os)
  local protocol="${1:-all}" # all, tcp, udp
  local show_processes="${2:-true}"

  _net_color bold "Listening Ports"
  echo "==============="

  case "$os" in
  macOS)
    if [[ "$show_processes" == "true" ]]; then
      case "$protocol" in
      tcp) _net_exec_priv lsof sudo lsof -i TCP -P -n | grep LISTEN ;;
      udp) _net_exec_priv lsof sudo lsof -i UDP -P -n ;;
      *) _net_exec_priv lsof sudo lsof -i -P -n | grep -E "LISTEN|UDP" ;;
      esac
    else
      case "$protocol" in
      tcp) netstat -an -p tcp | grep LISTEN ;;
      udp) netstat -an -p udp ;;
      *) netstat -an | grep -E "LISTEN|UDP" ;;
      esac
    fi
    ;;
  Linux)
    if _net_has_tool ss; then
      local ss_opts="-ln"
      [[ "$show_processes" == "true" ]] && ss_opts="${ss_opts}p"

      case "$protocol" in
      tcp) _net_exec_priv ss sudo ss -t $ss_opts ;;
      udp) _net_exec_priv ss sudo ss -u $ss_opts ;;
      *) _net_exec_priv ss sudo ss -tu $ss_opts ;;
      esac
    elif _net_has_tool netstat; then
      local netstat_opts="-ln"
      [[ "$show_processes" == "true" ]] && netstat_opts="${netstat_opts}p"

      case "$protocol" in
      tcp) _net_exec_priv netstat sudo netstat -t $netstat_opts ;;
      udp) _net_exec_priv netstat sudo netstat -u $netstat_opts ;;
      *) _net_exec_priv netstat sudo netstat -tu $netstat_opts ;;
      esac
    else
      _net_log ERROR "Neither ss nor netstat available"
      return 1
    fi
    ;;
  FreeBSD | OpenBSD | NetBSD)
    if [[ "$show_processes" == "true" ]]; then
      case "$protocol" in
      tcp) _net_exec_priv lsof sudo lsof -i TCP -P -n | grep LISTEN ;;
      udp) _net_exec_priv lsof sudo lsof -i UDP -P -n ;;
      *) _net_exec_priv lsof sudo lsof -i -P -n | grep -E "LISTEN|UDP" ;;
      esac
    else
      case "$protocol" in
      tcp) netstat -an -p tcp | grep LISTEN ;;
      udp) netstat -an -p udp ;;
      *) netstat -an | grep -E "LISTEN|UDP" ;;
      esac
    fi
    ;;
  *)
    _net_log ERROR "Unsupported OS: $os"
    return 1
    ;;
  esac
}

# --- Enhanced wireless information display ---
_net_show_wireless() {
  local os=$(_net_get_os)
  local interface="${1:-}"

  _net_color bold "Wireless Network Information"
  echo "============================="

  case "$os" in
  macOS)
    if [[ -n "$interface" ]]; then
      /System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I "$interface"
    else
      /System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I
    fi
    ;;
  Linux)
    if _net_has_tool iwconfig; then
      if [[ -n "$interface" ]]; then
        iwconfig "$interface"
      else
        iwconfig 2>/dev/null | grep -v "no wireless extensions"
      fi
    elif _net_has_tool iw; then
      if [[ -n "$interface" ]]; then
        iw dev "$interface" info
        echo
        iw dev "$interface" link
      else
        for dev in /sys/class/net/*/wireless; do
          if [[ -d "$dev" ]]; then
            local iface=$(basename "$(dirname "$dev")")
            echo "=== $iface ==="
            iw dev "$iface" info
            echo
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
      ifconfig "$interface"
    else
      ifconfig | grep -A 10 -B 2 "wireless"
    fi
    ;;
  OpenBSD | NetBSD)
    _net_color yellow "Wireless information display not yet implemented for $os"
    ;;
  *)
    _net_log ERROR "Unsupported OS: $os"
    return 1
    ;;
  esac
}

# ============================================
# Enhanced Network Diagnostic Functions
# ============================================

# --- Enhanced ping with better defaults ---
_net_ping() {
  local target="$1"
  local count="${2:-4}"
  local interval="${3:-1}"

  if ! _net_validate_input "$target" "hostname"; then
    return 1
  fi

  _net_color bold "Pinging $target ($count packets, ${interval}s interval)"
  echo "================================================"

  local os=$(_net_get_os)
  case "$os" in
  macOS | FreeBSD | OpenBSD | NetBSD)
    _net_exec ping -c "$count" -i "$interval" "$target"
    ;;
  Linux)
    _net_exec ping -c "$count" -i "$interval" "$target"
    ;;
  *)
    _net_log ERROR "Unsupported OS: $os"
    return 1
    ;;
  esac
}

# --- Enhanced traceroute ---
_net_traceroute() {
  local target="$1"
  local max_hops="${2:-30}"

  if ! _net_validate_input "$target" "hostname"; then
    return 1
  fi

  _net_color bold "Tracing route to $target (max $max_hops hops)"
  echo "============================================"

  local os=$(_net_get_os)
  if _net_has_tool traceroute; then
    _net_exec traceroute -m "$max_hops" "$target"
  elif _net_has_tool tracepath; then
    _net_exec tracepath "$target"
  else
    _net_log ERROR "Neither traceroute nor tracepath available"
    return 1
  fi
}

# --- Enhanced public IP detection with multiple sources ---
_net_show_public_ip() {
  local protocol="${1:-4}" # 4 for IPv4, 6 for IPv6

  _net_color bold "Public IP Address (IPv$protocol)"
  echo "=========================="

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
    if result=$(_net_exec curl -s --max-time 10 "$source" 2>/dev/null); then
      if [[ -n "$result" ]]; then
        # Basic validation
        if [[ "$protocol" == "6" ]]; then
          if [[ "$result" =~ : ]]; then
            echo "$result"
            return 0
          fi
        else
          if [[ "$result" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$result"
            return 0
          fi
        fi
      fi
    fi
  done

  _net_log ERROR "Could not determine public IP address"
  return 1
}

# --- Enhanced HTTP timing analysis ---
_net_http_timing() {
  local url="$1"
  local method="${2:-GET}"

  if [[ -z "$url" ]]; then
    _net_log ERROR "URL required"
    return 1
  fi

  _net_color bold "HTTP Timing Analysis: $url"
  echo "=================================="

  if ! _net_has_tool curl; then
    _net_log ERROR "curl not available"
    return 1
  fi

  local timing_format="
    DNS Lookup:        %{time_namelookup}s
    TCP Connect:       %{time_connect}s
    TLS Handshake:     %{time_appconnect}s
    Server Processing: %{time_starttransfer}s
    Total Time:        %{time_total}s
    
    HTTP Status:       %{http_code}
    Size Downloaded:   %{size_download} bytes
    Speed:             %{speed_download} bytes/sec
    "

  _net_exec curl -X "$method" -w "$timing_format" -o /dev/null -s "$url"
}

# ============================================
# System Service and Firewall Functions
# ============================================

# --- Enhanced service status check ---
_net_service_status() {
  local service="$1"
  local os=$(_net_get_os)

  _net_color bold "Service Status: $service"
  echo "======================="

  case "$os" in
  macOS)
    if _net_has_tool launchctl; then
      launchctl print "system/$service" 2>/dev/null ||
        launchctl print "user/$(id -u)/$service" 2>/dev/null ||
        _net_log ERROR "Service $service not found"
    else
      _net_log ERROR "launchctl not available"
      return 1
    fi
    ;;
  Linux)
    if _net_has_tool systemctl; then
      systemctl status "$service" --no-pager
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
    else
      _net_log ERROR "service command not available"
      return 1
    fi
    ;;
  OpenBSD | NetBSD)
    if _net_has_tool rcctl; then
      rcctl check "$service"
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

# --- Enhanced firewall status ---
_net_firewall_status() {
  local os=$(_net_get_os)

  _net_color bold "Firewall Status"
  echo "==============="

  case "$os" in
  macOS)
    if _net_has_tool pfctl; then
      echo "PF Firewall Status:"
      _net_exec_priv pfctl sudo pfctl -s info
      echo -e "\nApplication Firewall Status:"
      sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
    else
      _net_log ERROR "pfctl not available"
      return 1
    fi
    ;;
  Linux)
    local found_firewall=false

    # Check UFW
    if _net_has_tool ufw; then
      echo "UFW Status:"
      _net_exec_priv ufw sudo ufw status verbose
      found_firewall=true
    fi

    # Check firewalld
    if _net_has_tool firewall-cmd; then
      echo -e "\nfirewalld Status:"
      if _net_exec_priv firewall-cmd sudo firewall-cmd --state >/dev/null 2>&1; then
        _net_exec_priv firewall-cmd sudo firewall-cmd --list-all
      else
        echo "firewalld is not running"
      fi
      found_firewall=true
    fi

    # Check iptables
    if _net_has_tool iptables; then
      echo -e "\niptables Rules (filter table):"
      _net_exec_priv iptables sudo iptables -L -n -v --line-numbers
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
      _net_exec_priv pfctl sudo pfctl -s info
      echo -e "\nPF Rules:"
      _net_exec_priv pfctl sudo pfctl -s rules
    elif _net_has_tool ipfw; then
      echo "IPFW Status:"
      _net_exec_priv ipfw sudo ipfw list
    else
      _net_log ERROR "Neither pfctl nor ipfw available"
      return 1
    fi
    ;;
  OpenBSD | NetBSD)
    if _net_has_tool pfctl; then
      echo "PF Firewall Status:"
      _net_exec_priv pfctl sudo pfctl -s info
      echo -e "\nPF Rules:"
      _net_exec_priv pfctl sudo pfctl -s rules
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
# Enhanced Aliases with Improved Functionality
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
  alias net.mtr='sudo mtr -b -z -w -n'
fi

if _net_has_tool iperf3; then
  alias net.iperf.server='iperf3 -s'
  alias net.iperf.client='iperf3 -c'
fi

if _net_has_tool nmap; then
  alias net.scan.local='nmap -sn $(ip route | grep "scope link" | head -1 | awk "{print \$1}")'
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
# Enhanced Help System
# ============================================

net.help() {
  _net_color bold "Enhanced Network Information Commands (net.*)"
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
  echo "  net.scan.local        Scan local network"
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
