# ============================================
# Cross-Platform Network Configuration Aliases
# ============================================
# Provides consistent interface for network configuration across platforms
# Supports Wi-Fi operations, interface management, and system configurations


# ============================================
# Helper Funcs
# ============================================
# --- Function to get OS type (same as before) ---
_net_get_os() {
  case "$(uname)" in
    Linux*)   echo "Linux";;
    Darwin*)  echo "macOS";;
    *)        echo "Unknown";;
  esac
}

# --- Function to guide network configuration editing ---
_net_conf_edit_guide() {
  local os=$(_net_get_os)
  echo "--- Network Configuration Guidance ---"
  if [[ "$os" == "macOS" ]]; then
    echo "On macOS, use 'System Settings' -> 'Network' (GUI)."
    echo "For command line, use 'networksetup'. Examples:"
    echo "  networksetup -listallnetworkservices"
    echo "  networksetup -getinfo <networkservice>"
    echo "  networksetup -setmanual <networkservice> <ip> <subnet> <router>"
    echo "  networksetup -setdhcp <networkservice>"
    echo "Run 'man networksetup' or 'networksetup -help' for details."
  elif [[ "$os" == "Linux" ]]; then
    if command -v netplan >/dev/null; then
      echo "On Ubuntu (likely), use Netplan."
      echo "Edit YAML files in '/etc/netplan/' (e.g., sudo nano /etc/netplan/00-installer-config.yaml)."
      echo "Use 'man netplan' or check Netplan online documentation for syntax."
      echo "After editing, run 'sudo netplan apply' or 'sudo netplan try'."
      echo "You can change directory there using 'net.conf.cd.netplan'."
    elif command -v nmcli >/dev/null; then
      echo "On RHEL/CentOS or Ubuntu with NetworkManager, use 'nmcli' or 'nmtui'."
      echo "  nmcli connection show         # List connections"
      echo "  nmcli connection edit <name>  # Interactive editor"
      echo "  nmcli connection modify <name> setting.property value"
      echo "  sudo nmtui                    # Text User Interface"
      echo "Config files are usually in '/etc/NetworkManager/system-connections/' (keyfile format)."
      echo "Run 'man nmcli' or 'man nm-settings' for details."
      echo "You can change directory there using 'net.conf.cd.nm'."
    elif command -v systemd-networkd >/dev/null; then
       echo "Systemd-networkd detected (possibly configured by Netplan or directly)."
       echo "Primary config is likely Netplan (see above)."
       echo "Direct *.network files are in '/etc/systemd/network/'."
       echo "Use 'man systemd.network' for syntax."
    else
       echo "Could not detect primary Linux network config method (Netplan, NetworkManager, networkd)."
    fi
  else
    echo "Unsupported OS for network configuration guidance."
  fi
  echo "--------------------------------------"
}

# --- Function to guide DNS configuration ---
_net_conf_dns_guide() {
    local os=$(_net_get_os)
    echo "--- DNS Configuration Guidance ---"
    if [[ "$os" == "macOS" ]]; then
        echo "On macOS, use 'System Settings' -> 'Network' -> Select Service -> 'Details...' -> 'DNS'."
        echo "For command line, use 'networksetup -setdnsservers <networkservice> <server1> [server2] ...'"
        echo "Example: networksetup -setdnsservers Wi-Fi 8.8.8.8 1.1.1.1"
        echo "Use 'networksetup -setdnsservers <networkservice> empty' to clear."
    elif [[ "$os" == "Linux" ]]; then
        if command -v netplan > /dev/null; then
            echo "On Ubuntu (likely), edit the 'nameservers:' section in your /etc/netplan/*.yaml file."
            echo "Example within a device definition:"
            echo "  nameservers:"
            echo "    addresses: [8.8.8.8, 1.1.1.1]"
            echo "    search: [mydomain.local]"
            echo "Then run 'sudo netplan apply'."
        elif command -v nmcli > /dev/null; then
            echo "On RHEL/CentOS or Ubuntu with NetworkManager:"
            echo "Use 'nmcli connection modify <con-name> ipv4.dns \"<ip1> <ip2>\" ipv4.ignore-auto-dns yes'"
            echo "And potentially 'nmcli connection modify <con-name> ipv6.dns \"<ip6_1> <ip6_2>\" ipv6.ignore-auto-dns yes'"
            echo "Then bring the connection up: 'nmcli connection up <con-name>'"
            echo "Alternatively, use 'sudo nmtui' (Text UI)."
        elif [ -d /etc/systemd/resolved.conf.d ]; then
             echo "Systemd-resolved detected. You can create a file in /etc/systemd/resolved.conf.d/ with DNS settings,"
             echo "or modify /etc/systemd/resolved.conf directly (less recommended)."
             echo "See 'man resolved.conf'."
        else
            echo "Could not detect standard Linux DNS config method. Might need manual /etc/resolv.conf editing (often overwritten)."
        fi
    else
        echo "Unsupported OS for DNS configuration guidance."
    fi
    echo "--------------------------------"
}


# --- Function to apply network configuration changes ---
_net_conf_apply_guide() {
    local os=$(_net_get_os)
    echo "--- Applying Network Changes Guidance ---"
    if [[ "$os" == "macOS" ]]; then
        echo "On macOS, changes made via 'networksetup' often apply immediately."
        echo "For some changes (e.g., related to DHCP leases or hardware), toggling the network service off/on might help:"
        echo "  networksetup -setnetworkserviceenabled <service> off"
        echo "  networksetup -setnetworkserviceenabled <service> on"
        echo "Or toggle Wi-Fi/Ethernet via the GUI."
    elif [[ "$os" == "Linux" ]]; then
        if command -v netplan > /dev/null; then
            echo "For Netplan (Ubuntu likely): Run 'sudo netplan apply' or 'sudo netplan try'."
        elif command -v nmcli > /dev/null; then
            echo "For NetworkManager (RHEL likely, some Ubuntu):"
            echo "If config files were edited manually: 'sudo nmcli connection reload'"
            echo "To apply changes to an active connection: 'sudo nmcli connection up <con-name_or_uuid>'"
            echo "Or sometimes: 'sudo nmcli device reapply <device_name>'"
            echo "Restarting may also work: 'sudo systemctl restart NetworkManager'"
        elif command -v systemd-networkd >/dev/null; then
            echo "For systemd-networkd (if not using Netplan/NM): 'sudo systemctl restart systemd-networkd'"
        else
            echo "Could not detect standard Linux network apply method."
        fi
    else
        echo "Unsupported OS for applying network changes."
    fi
    echo "---------------------------------------"
}

# --- Function to set hostname ---
_net_conf_set_hostname() {
    local os=$(_net_get_os)
    local new_hostname="$1"

    if [ -z "$new_hostname" ]; then
        echo "Usage: net.hostname.set <new_hostname>"
        return 1
    fi

    echo "Attempting to set hostname to '$new_hostname'..."
    if [[ "$os" == "macOS" ]]; then
        echo "Setting macOS HostName, LocalHostName, and ComputerName (requires sudo)..."
        # Use base name for LocalHostName and ComputerName if FQDN is given for HostName
        local base_name=$(echo "$new_hostname" | cut -d. -f1)
        sudo scutil --set HostName "$new_hostname" && \
        sudo scutil --set LocalHostName "$base_name" && \
        sudo scutil --set ComputerName "$base_name" && \
        echo "macOS hostname components set. A restart might be needed for all services to reflect the change." || \
        echo "Error setting macOS hostname." >&2
    elif [[ "$os" == "Linux" ]]; then
        if command -v hostnamectl >/dev/null; then
            echo "Setting Linux hostname via hostnamectl (requires sudo)..."
            sudo hostnamectl set-hostname "$new_hostname" && \
            echo "Linux hostname set." || \
            echo "Error setting Linux hostname via hostnamectl." >&2
        elif command -v hostname >/dev/null; then
             echo "Attempting to set Linux hostname via hostname command (temporary) and /etc/hostname (persistent)..."
             sudo hostname "$new_hostname" && \
             echo "$new_hostname" | sudo tee /etc/hostname > /dev/null && \
             echo "Linux hostname potentially set. Check /etc/hosts file too. A restart might be needed." || \
             echo "Error setting Linux hostname via hostname command." >&2
        else
             echo "Error: Could not find hostnamectl or hostname command on Linux." >&2
             return 1
        fi
    else
        echo "Error: Unsupported OS for setting hostname." >&2
        return 1
    fi
}

# --- Wi-Fi Functions ---
# Scan for available Wi-Fi networks
_net_wifi_scan() {
    local os=$(_net_get_os)
    if [[ "$os" == "macOS" ]]; then
        # Use Apple's airport utility (pre-installed but hidden)
        /System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -s
    elif [[ "$os" == "Linux" ]]; then
        if command -v nmcli >/dev/null; then
            # NetworkManager CLI
            nmcli device wifi list
        elif command -v iwlist >/dev/null; then
            # Legacy wireless tools
            sudo iwlist scanning | grep -E "ESSID|Quality|Encryption"
        else
            echo "Error: No suitable Wi-Fi scanning tool found (nmcli or iwlist)." >&2
            return 1
        fi
    else
        echo "Error: Unsupported OS for Wi-Fi scanning." >&2
        return 1
    fi
}

# Connect to a Wi-Fi network
_net_wifi_connect() {
    local os=$(_net_get_os)
    local ssid="$1"
    local password="$2"
    
    if [ -z "$ssid" ]; then
        echo "Usage: net.wifi.connect SSID [PASSWORD]"
        return 1
    fi
    
    if [[ "$os" == "macOS" ]]; then
        if [ -z "$password" ]; then
            # Connect to open network
            networksetup -setairportnetwork en0 "$ssid"
        else
            # Connect to secured network
            networksetup -setairportnetwork en0 "$ssid" "$password"
        fi
    elif [[ "$os" == "Linux" ]]; then
        if command -v nmcli >/dev/null; then
            if [ -z "$password" ]; then
                # Connect to open network
                nmcli device wifi connect "$ssid"
            else
                # Connect to secured network
                nmcli device wifi connect "$ssid" password "$password"
            fi
        else
            echo "Error: NetworkManager (nmcli) not found. Manual configuration required." >&2
            echo "Try using wpa_supplicant directly or install NetworkManager." >&2
            return 1
        fi
    else
        echo "Error: Unsupported OS for Wi-Fi connection." >&2
        return 1
    fi
}

# Show Wi-Fi signal strength
_net_wifi_signal() {
    local os=$(_net_get_os)
    if [[ "$os" == "macOS" ]]; then
        # Use Apple's airport utility
        /System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | grep -E "SSID|agrCtlRSSI"
    elif [[ "$os" == "Linux" ]]; then
        if command -v nmcli >/dev/null; then
            # NetworkManager - show active connection
            nmcli -f ACTIVE,SIGNAL,SSID device wifi list | grep -E "yes|SIGNAL"
        elif command -v iwconfig >/dev/null; then
            # Legacy wireless tools
            iwconfig 2>/dev/null | grep -E "ESSID|Signal|Quality"
        else
            echo "Error: No suitable Wi-Fi signal tool found (nmcli or iwconfig)." >&2
            return 1
        fi
    else
        echo "Error: Unsupported OS for Wi-Fi signal check." >&2
        return 1
    fi
}

# Toggle Wi-Fi on/off
_net_wifi_toggle() {
    local os=$(_net_get_os)
    local action="$1" # Optional: 'on', 'off', or empty to toggle
    
    if [[ "$os" == "macOS" ]]; then
        if [[ "$action" == "on" ]]; then
            networksetup -setairportpower en0 on
            echo "Wi-Fi turned ON"
        elif [[ "$action" == "off" ]]; then
            networksetup -setairportpower en0 off
            echo "Wi-Fi turned OFF"
        else
            # Toggle current state
            local current_state=$(networksetup -getairportpower en0 | awk '{print $4}')
            if [[ "$current_state" == "On" ]]; then
                networksetup -setairportpower en0 off
                echo "Wi-Fi turned OFF"
            else
                networksetup -setairportpower en0 on
                echo "Wi-Fi turned ON"
            fi
        fi
    elif [[ "$os" == "Linux" ]]; then
        if command -v nmcli >/dev/null; then
            if [[ "$action" == "on" ]]; then
                nmcli radio wifi on
                echo "Wi-Fi turned ON"
            elif [[ "$action" == "off" ]]; then
                nmcli radio wifi off
                echo "Wi-Fi turned OFF"
            else
                # Toggle current state
                local current_state=$(nmcli radio wifi)
                if [[ "$current_state" == "enabled" ]]; then
                    nmcli radio wifi off
                    echo "Wi-Fi turned OFF"
                else
                    nmcli radio wifi on
                    echo "Wi-Fi turned ON"
                fi
            fi
        else
            echo "Error: NetworkManager (nmcli) not found." >&2
            return 1
        fi
    else
        echo "Error: Unsupported OS for Wi-Fi toggle." >&2
        return 1
    fi
}

# List saved Wi-Fi networks
_net_wifi_saved() {
    local os=$(_net_get_os)
    if [[ "$os" == "macOS" ]]; then
        networksetup -listpreferredwirelessnetworks en0
    elif [[ "$os" == "Linux" ]]; then
        if command -v nmcli >/dev/null; then
            # List saved connections
            nmcli connection show | grep -i wifi
        else
            echo "Error: NetworkManager (nmcli) not found." >&2
            # Fallback to viewing files
            if [ -d "/etc/NetworkManager/system-connections" ]; then
                echo "Saved connections in /etc/NetworkManager/system-connections/ (view with sudo):"
                ls -l /etc/NetworkManager/system-connections/
            else
                echo "Error: No suitable method found to list saved networks." >&2
                return 1
            fi
        fi
    else
        echo "Error: Unsupported OS for listing saved Wi-Fi networks." >&2
        return 1
    fi
}


# ============================================
# Aliases
# ============================================

# --- Config Editing Guidance ---
# Provides guidance on HOW/WHERE to edit network configurations per OS
alias net.conf.edit='_net_conf_edit_guide'
# Provides guidance on HOW/WHERE to edit DNS configurations per OS
alias net.conf.dns.edit='_net_conf_dns_guide'

# --- Config Directory Access (Linux Specific) ---
# Change directory to Netplan config folder (Ubuntu)
alias net.conf.cd.netplan='cd /etc/netplan/ 2>/dev/null || echo "Directory /etc/netplan/ not found."'
# Change directory to NetworkManager keyfile folder (RHEL/Linux)
alias net.conf.cd.nm='cd /etc/NetworkManager/system-connections/ 2>/dev/null || echo "Directory /etc/NetworkManager/system-connections/ not found."'

# --- Applying Config Changes ---
# Provides guidance and attempts common commands to apply network changes
alias net.conf.apply='_net_conf_apply_guide'

# --- Wi-Fi Network Management ---
# Scan for available Wi-Fi networks
alias net.wifi.scan='_net_wifi_scan'
# Connect to a Wi-Fi network (with optional password)
# Usage: net.wifi.connect SSID [password]
alias net.wifi.connect='_net_wifi_connect'
# Show signal strength of current Wi-Fi connection
alias net.wifi.signal='_net_wifi_signal'
# Turn Wi-Fi on
alias net.wifi.on='_net_wifi_toggle on'
# Turn Wi-Fi off
alias net.wifi.off='_net_wifi_toggle off'
# Toggle Wi-Fi on/off
alias net.wifi.toggle='_net_wifi_toggle'
# List saved Wi-Fi networks
alias net.wifi.saved='_net_wifi_saved'

# --- Hostname Configuration ---
# Set the system hostname (requires sudo and new hostname argument)
alias net.hostname.set='_net_conf_set_hostname'
# Show current hostname details (uses previous alias/function if defined, or basic hostname)
alias net.hostname.show='if type net.info.hostname &>/dev/null; then net.info.hostname; else hostname; fi'

# --- Help Function ---
net.conf.help() {
    echo "Network Configuration Commands (net.conf.*)"
    echo "==========================================="
    echo "GUIDES:"
    echo "  net.conf.edit            Show network config editing guidance"
    echo "  net.conf.dns.edit        Show DNS configuration guidance"
    echo "  net.conf.apply           Guidance for applying network changes"
    echo
    echo "DIRECTORIES:"
    echo "  net.conf.cd.netplan      Go to Netplan config dir (Ubuntu)"
    echo "  net.conf.cd.nm           Go to NetworkManager connections dir"
    echo
    echo "WI-FI MANAGEMENT:"
    echo "  net.wifi.scan            Scan available Wi-Fi networks"
    echo "  net.wifi.connect         Connect to Wi-Fi network"
    echo "  net.wifi.signal          Show current Wi-Fi signal strength"
    echo "  net.wifi.on              Turn Wi-Fi on"
    echo "  net.wifi.off             Turn Wi-Fi off"
    echo "  net.wifi.toggle          Toggle Wi-Fi on/off"
    echo "  net.wifi.saved           List saved Wi-Fi networks"
    echo
    echo "HOSTNAME:"
    echo "  net.hostname.set         Set system hostname"
    echo "  net.hostname.show        Show current hostname"
    echo
    echo "EXAMPLES:"
    echo "  net.wifi.scan                          # Show available networks"
    echo "  net.wifi.connect \"My Network\" mypassword  # Connect to network"
    echo
    echo "For network information commands, see: net.info.help"
}
