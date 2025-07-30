# ============================================
# Nmap Aliases (nmap.*)
# ============================================
# Assumes nmap is installed. Many scans require sudo.

# --------------------------------------------
# Safety Warning Function
# --------------------------------------------
# Display warning for potentially aggressive/detectable scan types
_nmap_warn() {
  local scan_type="$1"
  local risk="$2" # high, medium, low
  local color="\033[0;33m" # yellow for medium by default
  local reset="\033[0m"
  
  # Set color based on risk level
  if [[ "$risk" == "high" ]]; then
    color="\033[0;31m" # red
  elif [[ "$risk" == "low" ]]; then
    color="\033[0;32m" # green
  fi
  
  echo -e "${color}WARNING:${reset} You're about to run a ${color}$scan_type${reset} scan"
  
  case "$risk" in
    high)
      echo -e "${color}RISK:${reset} This scan is ${color}HIGHLY DETECTABLE${reset} and may trigger IDS/IPS systems!"
      echo -e "      This could potentially violate network policies or laws without proper authorization."
      ;;
    medium)
      echo -e "${color}RISK:${reset} This scan is ${color}MODERATELY DETECTABLE${reset} and may be logged by firewalls."
      ;;
    low)
      echo -e "${color}RISK:${reset} This scan is ${color}RELATIVELY STEALTHY${reset} but still detectable."
      ;;
  esac
  
  echo "Target: $3"
  echo -e "Continue? [y/N] "
  read response
  
  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "Scan aborted"
    return 1
  fi
  
  return 0
}


# ============================================
# Example Usage:
# ============================================

#nmap.scan.tcp.web 192.168.1.1          # Scan common web ports on 192.168.1.1 (needs sudo)
#nmap.scan.aggressive scanme.nmap.org   # Perform OS/Version/Script/Traceroute scan
#nmap.ping 192.168.1.0/24               # Discover hosts on the local /24 network
#nmap.scripts.vuln -p 80,443 target.com # Check for web vulnerabilities
#nmap.scan.version.intense --top-ports 20 10.0.0.5 # Intense version scan on top 20 ports
#nmap.out.all myscan nmap.scan.tcp -p 1-1000 server.local # Scan TCP 1-1000, output all formats to myscan.*

# --- Basic Host Discovery (Ping Scans) ---
# Standard Ping Scan (ICMP Echo/Timestamp, TCP SYN/ACK) - No ports scanned
# (Append <target(s)>)
alias nmap.ping='nmap -sn'
# Ping Scan using only ARP (Fast on Local Network)
# (Append <target(s)>)
alias nmap.ping.arp='sudo nmap -sn -PR'
# Ping Scan using only ICMP echo
# (Append <target(s)>)
alias nmap.ping.icmp='sudo nmap -sn -PE'
# Ping Scan using TCP SYN to specific ports (e.g., 80, 443)
# (Append -PS80,443 <target(s)>)
alias nmap.ping.syn='sudo nmap -sn -PS'
# Ping Scan using TCP ACK to specific ports (Good for stateless firewalls)
# (Append -PA80,443 <target(s)>)
alias nmap.ping.ack='sudo nmap -sn -PA'
# Scan ALL targets: Skip host discovery, assume all are up (Useful if ping is blocked)
# (Append <target(s)>)
alias nmap.scan.no-ping='nmap -Pn'

# --- Common Port Scan Techniques ---
# Default TCP SYN Scan (Stealthy, requires sudo) - Scans default ~1000 ports
# (Append <target(s)>)
alias nmap.scan.tcp='sudo nmap -sS'
# TCP Connect Scan (No sudo needed, more noisy/detectable) - Scans default ~1000 ports
# (Append <target(s)>)
alias nmap.scan.tcp.connect='nmap -sT'
# UDP Scan (Slow, requires sudo) - Scans default ~1000 UDP ports
# (Append <target(s)>)
alias nmap.scan.udp='sudo nmap -sU'
# Fast Scan (Top 100 ports, combines methods)
# (Append <target(s)>)
alias nmap.scan.fast='nmap -F'
# Scan ALL TCP ports (65535 ports - VERY SLOW)
# (Append <target(s)>)
alias nmap.scan.tcp.allports='sudo nmap -sS -p-'
# Scan common TCP web ports (80, 443, 8080, 8443)
# (Append <target(s)>)
alias nmap.scan.tcp.web='sudo nmap -sS -p 80,443,8080,8443'

# --- Advanced/Stealth TCP Scans (Require sudo) ---
# TCP Null Scan (-sN), FIN Scan (-sF), Xmas Scan (-sX) - Can bypass some firewalls/IDS
# (Append <target(s)>)
alias nmap.scan.tcp.null='_nmap_scan_stealth() { _nmap_warn "TCP NULL" medium "$1" && sudo nmap -sN "$@"; }; _nmap_scan_stealth'
alias nmap.scan.tcp.fin='_nmap_scan_stealth() { _nmap_warn "TCP FIN" medium "$1" && sudo nmap -sF "$@"; }; _nmap_scan_stealth'
alias nmap.scan.tcp.xmas='_nmap_scan_stealth() { _nmap_warn "TCP XMAS" medium "$1" && sudo nmap -sX "$@"; }; _nmap_scan_stealth'
# TCP ACK Scan (Good for mapping firewall rulesets, doesn't determine open/closed well)
# (Append <target(s)>)
alias nmap.scan.tcp.ack='sudo nmap -sA'
# TCP Window Scan (Similar to ACK but can sometimes differentiate open/closed)
# (Append <target(s)>)
alias nmap.scan.tcp.window='sudo nmap -sW'

# --- Service, Version & OS Detection ---
# Default Service/Version Detection scan (Uses -sS if root, -sT otherwise)
# (Append <target(s)>)
alias nmap.scan.version='nmap -sV'
# More intense version detection (Level 9)
# (Append <target(s)>)
alias nmap.scan.version.intense='nmap -sV --version-intensity 9'
# OS Detection (Requires sudo, needs open and closed TCP port)
# (Append <target(s)>)
alias nmap.scan.os='sudo nmap -O'
# Aggressive Scan: Enables OS detection (-O), version detection (-sV), script scanning (-sC), and traceroute (--traceroute)
# (Append <target(s)>)
alias nmap.scan.aggressive='_nmap_scan_aggressive() { _nmap_warn "AGGRESSIVE" high "$1" && nmap -A "$@"; }; _nmap_scan_aggressive'

# --- Nmap Scripting Engine (NSE) ---
# Run Default safe scripts (equivalent to -sC)
# (Append <target(s)>)
alias nmap.scripts.default='nmap -sC'
# Scan with 'discovery' category scripts
# (Append <target(s)>)
alias nmap.scripts.discovery='nmap --script discovery'
# Scan with 'vuln' category scripts (Potentially intrusive, use responsibly)
# (Append <target(s)>)
alias nmap.scripts.vuln='_nmap_scan_vuln() { _nmap_warn "VULNERABILITY" high "$1" && nmap --script vuln "$@"; }; _nmap_scan_vuln'
# Scan with 'auth' category scripts
# (Append <target(s)>)
alias nmap.scripts.auth='_nmap_scan_auth() { _nmap_warn "AUTHENTICATION" medium "$1" && nmap --script auth "$@"; }; _nmap_scan_auth'
# Scan with 'exploit' category scripts (Highly intrusive, use with extreme caution and permission)
# (Append <target(s)>)
alias nmap.scripts.exploit='_nmap_scan_exploit() { _nmap_warn "EXPLOIT" high "$1" && nmap --script exploit "$@"; }; _nmap_scan_exploit'
# Run specific script(s)
# (Append --script=http-title,dns-brute <target(s)>)
alias nmap.scripts.custom='nmap --script'
# Run scripts with arguments
# (Append --script=http-enum --script-args http-enum.fingerprintPath=/path/to/list <target(s)>)
alias nmap.scripts.withargs='nmap --script-args' # Remember to also specify --script

# --- Timing & Performance ---
# Insane speed scan (T5 - very fast, assumes reliable network, may sacrifice accuracy)
# (Append <target(s)>)
alias nmap.timing.insane='nmap -T5'
# Aggressive speed scan (T4 - default)
alias nmap.timing.aggressive='nmap -T4' # This is default but explicit alias can be useful
# Polite speed scan (T2 - slower, less likely to overwhelm targets/IDS)
# (Append <target(s)>)
alias nmap.timing.polite='nmap -T2'
# Sneaky speed scan (T1 - very slow, for IDS evasion)
# (Append <target(s)>)
alias nmap.timing.sneaky='nmap -T1'

# --- Output Formats ---
# Save output to Normal format
# (Append -oN scan_output.txt <target(s)>)
alias nmap.out.normal='nmap -oN'
# Save output to XML format
# (Append -oX scan_output.xml <target(s)>)
alias nmap.out.xml='nmap -oX'
# Save output to Grepable format
# (Append -oG scan_output.gnmap <target(s)>)
alias nmap.out.grep='nmap -oG'
# Save output to ALL major formats (Normal, XML, Grepable) - needs base filename
# (Append -oA scan_output_basename <target(s)>)
alias nmap.out.all='nmap -oA'
# Increase verbosity (-v or -vv)
alias nmap.verbose='nmap -v'
alias nmap.vverbose='nmap -vv'
# Show reason port is open/closed/filtered
alias nmap.reason='nmap --reason'
# Only show open ports (and potentially open|filtered)
alias nmap.open='nmap --open'
# Show packet trace (very verbose)
alias nmap.debug.packets='nmap --packet-trace'

# --- Firewall/IDS Evasion (Use ethically and responsibly) ---
# Fragment packets (-f uses 8-byte fragments, --mtu sets specific size)
# (Append -f <target(s)> or --mtu 16 <target(s)>)
alias nmap.evade.frag='_nmap_scan_evade() { _nmap_warn "FRAGMENTATION EVASION" medium "$1" && nmap -f "$@"; }; _nmap_scan_evade'
# Use Decoys (Makes scan appear to come from decoys too; ME=your real IP)
# (Append -D RND:5,ME <target(s)>) # Example: 5 random decoys + you
alias nmap.evade.decoy='_nmap_scan_evade() { _nmap_warn "DECOY EVASION" high "$1" && nmap -D "$@"; }; _nmap_scan_evade'
# Specify source port
# (Append -g <port_num> <target(s)>)
alias nmap.evade.srcport='_nmap_scan_evade() { _nmap_warn "SOURCE PORT EVASION" medium "$1" && nmap -g "$@"; }; _nmap_scan_evade'
# Randomize target scan order
alias nmap.evade.random='_nmap_scan_evade() { _nmap_warn "RANDOMIZED SCAN" low "$1" && nmap --randomize-hosts "$@"; }; _nmap_scan_evade'

# --- Miscellaneous ---
# Enable IPv6 scanning
# (Append -6 <target(s)>)
alias nmap.ipv6='nmap -6'
# List interfaces and routes as seen by nmap
alias nmap.iflist='nmap --iflist'
# Resume an aborted scan (from -oN or -oG output file)
# (Append <scan_output.nmap or scan_output.gnmap>)
alias nmap.resume='nmap --resume'

# --------------------------------------------
# Help System
# --------------------------------------------
# Show help information for nmap aliases
nmap.help() {
  echo "Nmap Scanning Aliases - Simplified Network Scanning"
  echo "====================================================="
  echo
  echo "HOST DISCOVERY:"
  echo "  nmap.ping                 Standard ping scan (no port scan)"
  echo "  nmap.ping.arp             ARP ping scan (fast, LAN only)"
  echo "  nmap.ping.icmp            ICMP echo ping scan"
  echo "  nmap.ping.syn             TCP SYN ping scan"
  echo "  nmap.ping.ack             TCP ACK ping scan"
  echo "  nmap.scan.no-ping         Skip host discovery (assume up)"
  echo
  echo "BASIC PORT SCANS:"
  echo "  nmap.scan.tcp             TCP SYN scan (stealthy, default ports)"
  echo "  nmap.scan.tcp.connect     TCP Connect scan (no sudo needed)"
  echo "  nmap.scan.udp             UDP scan (slow)"
  echo "  nmap.scan.fast            Fast scan (top 100 ports)"
  echo "  nmap.scan.tcp.allports    Scan all 65535 TCP ports (very slow)"
  echo "  nmap.scan.tcp.web         Scan common web ports (80,443,8080,8443)"
  echo
  echo "STEALTH/ADVANCED SCANS:"
  echo "  nmap.scan.tcp.null        TCP NULL scan (no flags set, stealthy) ⚠️"
  echo "  nmap.scan.tcp.fin         TCP FIN scan (FIN flag only, stealthy) ⚠️"
  echo "  nmap.scan.tcp.xmas        TCP XMAS scan (FIN,PSH,URG flags, stealthy) ⚠️"
  echo "  nmap.scan.tcp.ack         TCP ACK scan (firewall rule mapping)"
  echo "  nmap.scan.tcp.window      TCP Window scan (more accurate than ACK)"
  echo
  echo "SERVICE/VERSION DETECTION:"
  echo "  nmap.scan.version         Basic version detection scan"
  echo "  nmap.scan.version.intense Intense version detection (level 9)"
  echo "  nmap.scan.os              OS detection scan (needs sudo)"
  echo "  nmap.scan.aggressive      OS, version, scripts, traceroute scan ⚠️"
  echo
  echo "NSE SCRIPTING:"
  echo "  nmap.scripts.default      Run default safe scripts"
  echo "  nmap.scripts.discovery    Run discovery category scripts"
  echo "  nmap.scripts.vuln         Run vulnerability scripts ⚠️"
  echo "  nmap.scripts.auth         Run authentication scripts ⚠️"
  echo "  nmap.scripts.exploit      Run exploit scripts ⚠️⚠️"
  echo "  nmap.scripts.custom       Run specific script(s)"
  echo "  nmap.scripts.withargs     Run scripts with args"
  echo
  echo "TIMING TEMPLATES:"
  echo "  nmap.timing.insane        T5 (very fast, noisy)"
  echo "  nmap.timing.aggressive    T4 (default)"
  echo "  nmap.timing.polite        T2 (slower, less noisy)"
  echo "  nmap.timing.sneaky        T1 (very slow, IDS evasion)"
  echo
  echo "OUTPUT FORMATS:"
  echo "  nmap.out.normal           Normal output format"
  echo "  nmap.out.xml              XML output format"
  echo "  nmap.out.grep             Grepable output format"
  echo "  nmap.out.all              All output formats"
  echo "  nmap.verbose              Increase verbosity"
  echo "  nmap.open                 Only show open ports"
  echo
  echo "EVASION TECHNIQUES: (⚠️ USE ETHICALLY AND WITH PERMISSION ONLY)"
  echo "  nmap.evade.frag           Fragment packets ⚠️"
  echo "  nmap.evade.decoy          Use decoy IPs to mask scan origin ⚠️"
  echo "  nmap.evade.srcport        Specify source port ⚠️"
  echo "  nmap.evade.random         Randomize target scan order ⚠️"
  echo
  echo "EXAMPLES:"
  echo "  nmap.ping 192.168.1.0/24                  # Discover hosts on a network"
  echo "  nmap.scan.tcp -p 80,443,8080 example.com  # Scan specific TCP ports"
  echo "  nmap.scan.version --top-ports 100 10.0.0.5    # Get top 100 ports versions"
  echo "  nmap.out.all myscan nmap.scan.tcp target.com  # Save all formats"
  echo
  echo "NOTE: Items marked with ⚠️ require caution as they may be detected by IDS/IPS"
  echo "      systems or violate acceptable use policies. Always have permission."
}