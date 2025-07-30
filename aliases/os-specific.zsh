# ZDOTDIR/aliases/os-specific.zsh
# ==============================================================================
# OS-specific aliases - automatically loaded based on detected platform
# ==============================================================================

# Guard: Exit if not interactive
[[ $- != *i* ]] && return 0

# Ensure Z_OS is set (should be from 05_os.zsh, but set a fallback)
: "${Z_OS:=$(uname -s | tr '[:upper:]' '[:lower:]')}"
: "${Z_PKG:=}"

# --- macOS Specific Aliases ---------------------------------------------------
if [[ "$Z_OS" == "macos" ]]; then
  # System management
  alias flushdns="sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"
  alias showfiles="defaults write com.apple.finder AppleShowAllFiles YES; killall Finder"
  alias hidefiles="defaults write com.apple.finder AppleShowAllFiles NO; killall Finder"
  alias cleanup="find . -type f -name '*.DS_Store' -ls -delete"
  alias sleepoff="caffeinate -d"
  alias afk="pmset displaysleepnow"
  
  # Network management
  alias wifi.on="networksetup -setairportpower en0 on"
  alias wifi.off="networksetup -setairportpower en0 off"
  alias wifi.join="networksetup -setairportnetwork en0"
  alias wifi.list="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -s"
  alias ip.local="ipconfig getifaddr en0"
  
  # Development
  alias xcopen="open *.xcworkspace 2>/dev/null || open *.xcodeproj 2>/dev/null || echo 'No Xcode project found'"
  alias xcode-clean="rm -rf ~/Library/Developer/Xcode/DerivedData"
  
  # Homebrew
  if [[ "$Z_PKG" == "brew" ]]; then
    alias brewup="brew update && brew upgrade && brew cleanup"
    alias brewcl="brew cleanup --prune=all"
    alias brewls="brew leaves"
    alias brewdeps="brew deps --installed --tree"
    alias brewused="brew uses --installed"
    alias caskup="brew upgrade --cask"
  fi

  # Open apps
  alias preview="open -a Preview"
  alias safari="open -a Safari"
  alias firefox="open -a Firefox"
  alias chrome="open -a 'Google Chrome'"
  alias code="open -a 'Visual Studio Code'"
  alias slack="open -a Slack"
fi

# --- Linux Specific Aliases ---------------------------------------------------
# Common Linux aliases
if [[ "$Z_OS" =~ linux|debian|ubuntu|fedora|rhel|arch|centos|alpine ]]; then
  # System info
  alias sysinfo="hostnamectl"
  alias cpuinfo="lscpu"
  alias meminfo="free -h"
  alias diskinfo="df -h"
  alias release="cat /etc/*-release"
  
  # System management
  alias sc-status="systemctl status"
  alias sc-start="systemctl start"
  alias sc-stop="systemctl stop"
  alias sc-restart="systemctl restart"
  alias sc-enable="systemctl enable"
  alias sc-disable="systemctl disable"
  alias sc-user="systemctl --user"
  alias sc-list="systemctl list-unit-files --state=enabled"
  alias sc-failed="systemctl --failed"
  alias sc-timers="systemctl list-timers"
  
  # Logs
  alias logs="journalctl -xe"
  alias logs-follow="journalctl -f"
  alias logs-boot="journalctl -b"
  alias logs-err="journalctl -p 3 -xb"

  # File permissions
  alias fixperms="find . -type d -exec chmod 755 {} \; && find . -type f -exec chmod 644 {} \;"
  alias fixowners="sudo chown -R $(id -u):$(id -g) ."
fi

# --- Debian/Ubuntu Specific ---------------------------------------------------
if [[ "$Z_OS" =~ debian|ubuntu|pop|mint|raspbian ]]; then
  # Package management
  alias apt-update="sudo apt update"
  alias apt-upgrade="sudo apt update && sudo apt upgrade"
  alias apt-dist="sudo apt update && sudo apt dist-upgrade"
  alias apt-install="sudo apt install"
  alias apt-remove="sudo apt remove"
  alias apt-purge="sudo apt purge"
  alias apt-autoremove="sudo apt autoremove"
  alias apt-search="apt search"
  alias apt-show="apt show"
  alias apt-list="apt list --installed"
  alias apt-holds="apt-mark showhold"
  alias apt-clean="sudo apt clean && sudo apt autoclean"
  
  # System maintenance
  alias update-alternatives="sudo update-alternatives"
  alias update-grub="sudo update-grub"
fi

# --- RHEL/Fedora/CentOS Specific ----------------------------------------------
if [[ "$Z_OS" =~ fedora|centos|rhel|rocky|alma ]]; then
  # Package management
  alias dnf-update="sudo dnf update"
  alias dnf-upgrade="sudo dnf upgrade"
  alias dnf-install="sudo dnf install"
  alias dnf-remove="sudo dnf remove"
  alias dnf-search="dnf search"
  alias dnf-info="dnf info"
  alias dnf-list="dnf list installed"
  alias dnf-provides="dnf provides"
  alias dnf-clean="sudo dnf clean all"
  alias dnf-history="sudo dnf history"
  
  # System maintenance
  alias check-selinux="sestatus"
  alias enable-service="sudo systemctl enable --now"
  alias disable-service="sudo systemctl disable --now"
fi

# --- Arch Based Specific ------------------------------------------------------
if [[ "$Z_OS" =~ arch|manjaro|endeavouros ]]; then
  # Package management
  alias pac-update="sudo pacman -Sy"
  alias pac-upgrade="sudo pacman -Syu"
  alias pac-install="sudo pacman -S"
  alias pac-remove="sudo pacman -Rs"
  alias pac-search="pacman -Ss"
  alias pac-info="pacman -Si"
  alias pac-list="pacman -Q"
  alias pac-owns="pacman -Qo"
  alias pac-explicit="pacman -Qe"
  alias pac-orphans="pacman -Qtdq"
  alias pac-clean="sudo pacman -Sc"
  
  # AUR helpers (check if installed first)
  if command -v yay >/dev/null; then
    alias yay-update="yay -Syu"
    alias yay-install="yay -S"
    alias yay-remove="yay -Rs"
    alias yay-search="yay -Ss"
  elif command -v paru >/dev/null; then
    alias paru-update="paru -Syu"
    alias paru-install="paru -S"
    alias paru-remove="paru -Rs"
    alias paru-search="paru -Ss"
  fi
fi

# --- Alpine Specific ----------------------------------------------------------
if [[ "$Z_OS" == "alpine" ]]; then
  # Package management
  alias apk-update="sudo apk update"
  alias apk-upgrade="sudo apk upgrade"
  alias apk-install="sudo apk add"
  alias apk-remove="sudo apk del"
  alias apk-search="apk search"
  alias apk-info="apk info"
  alias apk-list="apk list --installed"
  alias apk-owns="apk info --who-owns"
  alias apk-depends="apk info --depends"
  alias apk-size="apk info --size"
fi

# --- NixOS Specific -----------------------------------------------------------
if [[ "$Z_OS" == "nixos" ]]; then
  alias nix-update="sudo nixos-rebuild switch --upgrade"
  alias nix-boot="sudo nixos-rebuild boot"
  alias nix-switch="sudo nixos-rebuild switch"
  alias nix-test="sudo nixos-rebuild test"
  alias nix-rollback="sudo nixos-rebuild switch --rollback"
  alias nix-clean="sudo nix-collect-garbage -d"
  alias nix-generations="sudo nix-env --list-generations --profile /nix/var/nix/profiles/system"
  alias nix-edit="sudo $EDITOR /etc/nixos/configuration.nix"
fi

# --- WSL Specific -------------------------------------------------------------
if [[ "$Z_OS" == "wsl" ]]; then
  # Windows integration
  alias winuser="cmd.exe /c echo %USERNAME%"
  alias winhome="wslpath \$(cmd.exe /c echo %USERPROFILE% | tr -d '\r')"
  alias explorer="explorer.exe"
  alias clip="clip.exe"
  alias cmd="cmd.exe /c"
  alias pwsh="powershell.exe -Command"
  alias code-win="cmd.exe /c code"
  alias notepad="notepad.exe"
  alias ipconfig="ipconfig.exe"
  alias task-win="tasklist.exe"
  alias kill-win="taskkill.exe /F /IM"
  
  # WSL system management
  alias wsl-shutdown="wsl.exe --shutdown"
  alias wsl-update="wsl.exe --update"
  alias wsl-status="wsl.exe --status"
  
  # Path conversion
  wslpath() {
    wslpath.exe "$@"
  }
  
  # Copy path to Windows clipboard
  wclip() {
    if [[ -e "$1" ]]; then
      wslpath -w "$1" | tr -d '\n' | clip.exe
      echo "Path copied to clipboard: $(wslpath -w "$1")"
    else
      echo "File not found: $1"
    fi
  }
fi

# --- Container Specific -------------------------------------------------------
if [[ -n "$Z_CONTAINER_TYPE" && "$Z_IN_CONTAINER" -eq 1 ]]; then
  # Docker container shortcuts
  alias host-ip="ip route | grep default | cut -d' ' -f3"
  
  # Minimal versions of system commands for containerized environments
  alias sys-info="cat /etc/*release 2>/dev/null || echo 'OS information not available'"
  alias clean="rm -rf /tmp/* 2>/dev/null || true"
end