# ============================================
# Nix/NixOS/nix-darwin Aliases (nix.*)
# ============================================
# Comprehensive aliases for Nix package manager, NixOS, and nix-darwin
# Designed for developers, system administrators, and NixOS/nix-darwin users

# ============================================
# Helper Functions
# ============================================

# --- Check Nix Environment Type ---
_nix_detect_env() {
  # Default to basic Nix if nothing else detected
  NIX_ENV_TYPE="nix"
  
  # Check for NixOS
  if [ -e /etc/nixos ] || [ -e /run/current-system ]; then
    NIX_ENV_TYPE="nixos"
  # Check for Darwin
  elif [ "$(uname)" = "Darwin" ] && [ -e /run/current-system ] || [ -e /nix/var/nix/profiles/system ] || [ -e ~/.nixpkgs/darwin-configuration.nix ]; then
    NIX_ENV_TYPE="darwin"
  fi
  
  # Check for flakes support
  if nix --version 2>/dev/null | grep -q "nix (Nix) 2\.[4-9]"; then
    NIX_FLAKES_SUPPORTED=1
  else
    NIX_FLAKES_SUPPORTED=0
  fi
  
  # Export for other functions to use
  export NIX_ENV_TYPE
  export NIX_FLAKES_SUPPORTED
}

# --- Check if a command is available ---
_nix_check_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# --- Check for Flakes support ---
_nix_check_flakes() {
  if [ "$NIX_FLAKES_SUPPORTED" -eq 0 ]; then
    echo "ERROR: This command requires Nix Flakes support (Nix ≥ 2.4)"
    echo "Enable with: export NIX_CONFIG=\"experimental-features = nix-command flakes\""
    return 1
  fi
  return 0
}

# --- Get NixOS configuration path ---
_nix_get_config_path() {
  if [ -e /etc/nixos/configuration.nix ]; then
    echo "/etc/nixos"
  elif [ -e /etc/nixos/flake.nix ]; then
    echo "/etc/nixos"
  elif [ -e ~/.config/nixos/configuration.nix ]; then
    echo "$HOME/.config/nixos"
  elif [ -e ~/.config/nixos/flake.nix ]; then
    echo "$HOME/.config/nixos"
  else
    echo "/etc/nixos"
  fi
}

# --- Get nix-darwin configuration path ---
_nix_get_darwin_config_path() {
  if [ -e ~/.nixpkgs/darwin-configuration.nix ]; then
    echo "$HOME/.nixpkgs"
  elif [ -e ~/.config/nixpkgs/darwin-configuration.nix ]; then
    echo "$HOME/.config/nixpkgs"
  elif [ -e ~/.config/nix-darwin/configuration.nix ]; then
    echo "$HOME/.config/nix-darwin"
  else
    echo "$HOME/.nixpkgs"
  fi
}

# Run detection on load
_nix_detect_env

# ============================================
# Basic Nix Package Management
# ============================================

# --- Search for packages ---
# Usage: nix.search <query>
alias nix.search='nix search nixpkgs'

# --- Install package to user profile ---
# Usage: nix.install <package>
alias nix.install='nix-env -iA nixpkgs.'

# --- Install package with attribute path ---
# Usage: nix.install.attr nixpkgs.ripgrep
alias nix.install.attr='nix-env -iA'

# --- Uninstall package from user profile ---
# Usage: nix.uninstall <package>
alias nix.uninstall='nix-env -e'

# --- Upgrade user profile packages ---
# Usage: nix.upgrade
alias nix.upgrade='nix-env -u'

# --- List installed packages ---
# Usage: nix.list
alias nix.list='nix-env -q'

# --- Show derivation for a package ---
# Usage: nix.show <package>
alias nix.show='nix-env -qa --description'

# --- Show package information from flake registry ---
# Usage: nix.info <package>
alias nix.info='_nix_info() {
  _nix_check_flakes || return 1
  nix search nixpkgs "$1" --json | jq
}; _nix_info'

# --- Run software without installing ---
# Usage: nix.run <package>
alias nix.run='_nix_run() {
  if _nix_check_flakes; then
    nix run "nixpkgs#$1" -- "${@:2}"
  else
    nix-shell -p "$1" --run "${*:2}"
  fi
}; _nix_run'

# --- Build a single package ---
# Usage: nix.build <package>
alias nix.build='_nix_build() {
  if _nix_check_flakes; then
    nix build "nixpkgs#$1" "$@"
  else
    nix-build "<nixpkgs>" -A "$1"
  fi
}; _nix_build'

# ============================================
# Nix Development
# ============================================

# --- Start a nix-shell with packages ---
# Usage: nix.shell <pkg1> <pkg2>...
alias nix.shell='nix-shell -p'

# --- Start a pure nix-shell with packages ---
# Usage: nix.shell.pure <pkg1> <pkg2>...
alias nix.shell.pure='nix-shell -p --pure'

# --- Start a shell from a flake ---
# Usage: nix.develop [flake-uri]
alias nix.develop='_nix_develop() {
  _nix_check_flakes || return 1
  if [ -z "$1" ]; then
    nix develop
  else
    nix develop "$1"
  fi
}; _nix_develop'

# --- Enter a development shell for a package ---
# Usage: nix.dev.pkg <package>
alias nix.dev.pkg='_nix_dev_pkg() {
  if [ -z "$1" ]; then
    echo "Usage: nix.dev.pkg <package>"
    return 1
  fi
  nix-shell "<nixpkgs>" -A "$1"
}; _nix_dev_pkg'

# --- Create a shell.nix file interactively ---
# Usage: nix.mkshell <pkg1> <pkg2>...
alias nix.mkshell='_nix_mkshell() {
  if [ "$#" -eq 0 ]; then
    echo "Usage: nix.mkshell <pkg1> <pkg2>..."
    return 1
  fi
  
  pkgs=""
  for pkg in "$@"; do
    pkgs="$pkgs $pkg"
  done
  
  cat > shell.nix << EOF
{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [$pkgs];
  
  shellHook = ''
    echo "Welcome to the development environment"
  '';
}
EOF
  echo "Created shell.nix with packages:$pkgs"
}; _nix_mkshell'

# --- Create a flake.nix template interactively ---
# Usage: nix.mkflake [template]
alias nix.mkflake='_nix_mkflake() {
  _nix_check_flakes || return 1
  
  local template="${1:-basic}"
  nix flake init -t "nixpkgs#$template"
}; _nix_mkflake'

# ============================================
# NixOS System Management
# ============================================

# --- Rebuild NixOS system ---
# Usage: nixos.rebuild
alias nixos.rebuild='_nixos_rebuild() {
  if [ "$NIX_ENV_TYPE" != "nixos" ]; then
    echo "This command is only available on NixOS"
    return 1
  fi
  sudo nixos-rebuild switch
}; _nixos_rebuild'

# --- Rebuild NixOS system with flake ---
# Usage: nixos.rebuild.flake [flake-uri] [host]
alias nixos.rebuild.flake='_nixos_rebuild_flake() {
  if [ "$NIX_ENV_TYPE" != "nixos" ]; then
    echo "This command is only available on NixOS"
    return 1
  fi
  _nix_check_flakes || return 1
  
  local flake="${1:-.}"
  local host="${2:-$(hostname)}"
  
  sudo nixos-rebuild switch --flake "$flake#$host"
}; _nixos_rebuild_flake'

# --- Test NixOS configuration without switching ---
# Usage: nixos.test
alias nixos.test='_nixos_test() {
  if [ "$NIX_ENV_TYPE" != "nixos" ]; then
    echo "This command is only available on NixOS"
    return 1
  fi
  sudo nixos-rebuild test
}; _nixos_test'

# --- Build NixOS configuration but don't activate ---
# Usage: nixos.build
alias nixos.build='_nixos_build() {
  if [ "$NIX_ENV_TYPE" != "nixos" ]; then
    echo "This command is only available on NixOS"
    return 1
  fi
  sudo nixos-rebuild build
}; _nixos_build'

# --- Edit NixOS configuration file ---
# Usage: nixos.edit [editor]
alias nixos.edit='_nixos_edit() {
  if [ "$NIX_ENV_TYPE" != "nixos" ]; then
    echo "This command is only available on NixOS"
    return 1
  fi
  
  local editor="${1:-${EDITOR:-vim}}"
  local config_path=$(_nix_get_config_path)
  
  if [ -e "$config_path/flake.nix" ]; then
    $editor "$config_path/flake.nix"
  else
    $editor "$config_path/configuration.nix"
  fi
}; _nixos_edit'

# --- Edit hardware-configuration.nix ---
# Usage: nixos.edit.hardware [editor]
alias nixos.edit.hardware='_nixos_edit_hardware() {
  if [ "$NIX_ENV_TYPE" != "nixos" ]; then
    echo "This command is only available on NixOS"
    return 1
  fi
  
  local editor="${1:-${EDITOR:-vim}}"
  local config_path=$(_nix_get_config_path)
  
  $editor "$config_path/hardware-configuration.nix"
}; _nixos_edit_hardware'

# --- Go to NixOS configuration directory ---
# Usage: nixos.cd
alias nixos.cd='_nixos_cd() {
  if [ "$NIX_ENV_TYPE" != "nixos" ]; then
    echo "This command is only available on NixOS"
    return 1
  fi
  
  cd "$(_nix_get_config_path)"
}; _nixos_cd'

# --- List current NixOS system generations ---
# Usage: nixos.generations
alias nixos.generations='_nixos_generations() {
  if [ "$NIX_ENV_TYPE" != "nixos" ]; then
    echo "This command is only available on NixOS"
    return 1
  fi
  
  sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
}; _nixos_generations'

# --- Boot into a specific NixOS generation ---
# Usage: nixos.boot-generation <gen_number>
alias nixos.boot-generation='_nixos_boot_generation() {
  if [ "$NIX_ENV_TYPE" != "nixos" ]; then
    echo "This command is only available on NixOS"
    return 1
  fi
  
  if [ -z "$1" ]; then
    echo "Usage: nixos.boot-generation <gen_number>"
    return 1
  fi
  
  sudo nixos-rebuild boot --rollback-generation "$1"
}; _nixos_boot_generation'

# --- Show current system version ---
# Usage: nixos.version
alias nixos.version='_nixos_version() {
  if [ "$NIX_ENV_TYPE" != "nixos" ]; then
    echo "This command is only available on NixOS"
    return 1
  fi
  
  echo "NixOS Version Information:"
  nixos-version
  echo "Nix Version:"
  nix --version
}; _nixos_version'

# ============================================
# nix-darwin System Management
# ============================================

# --- Rebuild Darwin system ---
# Usage: darwin.rebuild
alias darwin.rebuild='_darwin_rebuild() {
  if [ "$NIX_ENV_TYPE" != "darwin" ]; then
    echo "This command is only available on nix-darwin systems"
    return 1
  fi
  
  if _nix_check_cmd "darwin-rebuild"; then
    darwin-rebuild switch
  else
    echo "darwin-rebuild not found. Is nix-darwin installed?"
    return 1
  fi
}; _darwin_rebuild'

# --- Rebuild Darwin system with flake ---
# Usage: darwin.rebuild.flake [flake-uri] [host]
alias darwin.rebuild.flake='_darwin_rebuild_flake() {
  if [ "$NIX_ENV_TYPE" != "darwin" ]; then
    echo "This command is only available on nix-darwin systems"
    return 1
  fi
  _nix_check_flakes || return 1
  
  if ! _nix_check_cmd "darwin-rebuild"; then
    echo "darwin-rebuild not found. Is nix-darwin installed?"
    return 1
  fi
  
  local flake="${1:-.}"
  local host="${2:-$(hostname -s)}"
  
  darwin-rebuild switch --flake "$flake#$host"
}; _darwin_rebuild_flake'

# --- Edit Darwin configuration file ---
# Usage: darwin.edit [editor]
alias darwin.edit='_darwin_edit() {
  if [ "$NIX_ENV_TYPE" != "darwin" ]; then
    echo "This command is only available on nix-darwin systems"
    return 1
  fi
  
  local editor="${1:-${EDITOR:-vim}}"
  local config_path=$(_nix_get_darwin_config_path)
  
  if [ -e "$config_path/flake.nix" ]; then
    $editor "$config_path/flake.nix"
  else
    $editor "$config_path/darwin-configuration.nix"
  fi
}; _darwin_edit'

# --- Go to Darwin configuration directory ---
# Usage: darwin.cd
alias darwin.cd='_darwin_cd() {
  if [ "$NIX_ENV_TYPE" != "darwin" ]; then
    echo "This command is only available on nix-darwin systems"
    return 1
  fi
  
  cd "$(_nix_get_darwin_config_path)"
}; _darwin_cd'

# ============================================
# Flake Management
# ============================================

# --- Update flake inputs ---
# Usage: nix.flake.update [input]
alias nix.flake.update='_nix_flake_update() {
  _nix_check_flakes || return 1
  
  if [ -z "$1" ]; then
    nix flake update
  else
    nix flake update --update-input "$1"
  fi
}; _nix_flake_update'

# --- Lock flake to specific input ---
# Usage: nix.flake.lock <input> <rev>
alias nix.flake.lock='_nix_flake_lock() {
  _nix_check_flakes || return 1
  
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: nix.flake.lock <input> <rev>"
    return 1
  fi
  
  nix flake lock --override-input "$1" "$2"
}; _nix_flake_lock'

# --- Show flake info ---
# Usage: nix.flake.info [flake-uri]
alias nix.flake.info='_nix_flake_info() {
  _nix_check_flakes || return 1
  
  local flake="${1:-.}"
  nix flake show "$flake"
}; _nix_flake_info'

# --- Check flake outputs ---
# Usage: nix.flake.check [flake-uri]
alias nix.flake.check='_nix_flake_check() {
  _nix_check_flakes || return 1
  
  local flake="${1:-.}"
  nix flake check "$flake"
}; _nix_flake_check'

# --- List flake inputs ---
# Usage: nix.flake.inputs [flake-uri]
alias nix.flake.inputs='_nix_flake_inputs() {
  _nix_check_flakes || return 1
  
  local flake="${1:-.}"
  nix flake metadata "$flake" | grep -A 100 "Inputs:"
}; _nix_flake_inputs'

# ============================================
# Nix Store & Garbage Collection
# ============================================

# --- Collect garbage (with confirmation) ---
# Usage: nix.gc
alias nix.gc='_nix_gc() {
  echo "This will remove all unreachable paths from the Nix store."
  read -p "Are you sure you want to continue? [y/N] " answer
  
  if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
    nix-collect-garbage
    echo "Garbage collection completed."
  else
    echo "Aborted."
  fi
}; _nix_gc'

# --- Aggressive garbage collection (delete all older generations) ---
# Usage: nix.gc.all
alias nix.gc.all='_nix_gc_all() {
  echo "WARNING: This will remove ALL old generations and unreachable paths."
  echo "Only the current generation will be kept."
  read -p "Are you absolutely sure? [y/N] " answer
  
  if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
    nix-collect-garbage -d
    echo "Aggressive garbage collection completed."
  else
    echo "Aborted."
  fi
}; _nix_gc_all'

# --- Clean up old generations ---
# Usage: nix.gc.old [keep_count]
alias nix.gc.old='_nix_gc_old() {
  local keep="${1:-5}"  # Default: keep last 5 generations
  
  echo "This will remove all but the last $keep generations from the nix store."
  read -p "Are you sure you want to continue? [y/N] " answer
  
  if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
    nix-env --delete-generations +$keep
    echo "Old generations removed. Kept the last $keep generations."
  else
    echo "Aborted."
  fi
}; _nix_gc_old'

# --- Show store path references ---
# Usage: nix.store.refs <store-path>
alias nix.store.refs='nix-store -q --references'

# --- Show reverse references ---
# Usage: nix.store.referrers <store-path>
alias nix.store.referrers='nix-store -q --referrers'

# --- Show store path closure size ---
# Usage: nix.store.size <store-path>
alias nix.store.size='_nix_store_size() {
  nix path-info -S "$1" | awk "{print \$2 \" \" \$1}" | numfmt --to=iec --field=1
}; _nix_store_size'

# ============================================
# Deterministic Nix Builds
# ============================================

# --- Print derivation for a package ---
# Usage: nix.drv <package>
alias nix.drv='_nix_drv() {
  nix-instantiate "<nixpkgs>" -A "$1"
}; _nix_drv'

# --- Show build dependencies of a package ---
# Usage: nix.deps <package>
alias nix.deps='_nix_deps() {
  nix-store -q --tree $(nix-instantiate "<nixpkgs>" -A "$1")
}; _nix_deps'

# --- Check if paths have the same content ---
# Usage: nix.diff <path1> <path2>
alias nix.diff='nix-diff'

# --- Generate a reproducible source archive ---
# Usage: nix.bundle <package>
alias nix.bundle='_nix_bundle() {
  if ! _nix_check_cmd "nix-bundle"; then
    echo "nix-bundle not found. Install with: nix-env -iA nixpkgs.nix-bundle"
    return 1
  fi
  
  nix-bundle nixpkgs."$1"
}; _nix_bundle'

# --- Show build log ---
# Usage: nix.log <store-path>
alias nix.log='nix-store -l'

# ============================================
# Nix Configuration
# ============================================

# --- Show Nix config ---
# Usage: nix.config
alias nix.config='_nix_config() {
  if [ "$NIX_FLAKES_SUPPORTED" -eq 1 ]; then
    nix show-config
  else
    cat /etc/nix/nix.conf 2>/dev/null || echo "No nix.conf found"
  fi
}; _nix_config'

# --- Edit global Nix config ---
# Usage: nix.config.edit [editor]
alias nix.config.edit='_nix_config_edit() {
  local editor="${1:-${EDITOR:-vim}}"
  
  if [ -e /etc/nix/nix.conf ]; then
    sudo $editor /etc/nix/nix.conf
  else
    echo "nix.conf not found at /etc/nix/nix.conf"
    echo "Creating a new one..."
    sudo mkdir -p /etc/nix
    sudo touch /etc/nix/nix.conf
    sudo $editor /etc/nix/nix.conf
  fi
}; _nix_config_edit'

# --- Enable flake support ---
# Usage: nix.enable.flakes
alias nix.enable.flakes='_nix_enable_flakes() {
  if [ "$NIX_FLAKES_SUPPORTED" -eq 1 ]; then
    echo "Flakes already supported in your Nix version."
  fi
  
  if [ ! -d "$HOME/.config/nix" ]; then
    mkdir -p "$HOME/.config/nix"
  fi
  
  echo "Enabling flakes in ~/.config/nix/nix.conf"
  echo "experimental-features = nix-command flakes" >> "$HOME/.config/nix/nix.conf"
  
  echo "Adding NIX_CONFIG environment variable to your shell..."
  export NIX_CONFIG="experimental-features = nix-command flakes"
  echo 'export NIX_CONFIG="experimental-features = nix-command flakes"' >> "$HOME/.zshrc"
  
  echo "Flakes support enabled. Please restart your shell or source your zshrc."
}; _nix_enable_flakes'

# ============================================
# Nix Information & Diagnostics
# ============================================

# --- Show Nix channels ---
# Usage: nix.channels
alias nix.channels='nix-channel --list'

# --- Update all channels ---
# Usage: nix.channels.update
alias nix.channels.update='nix-channel --update'

# --- Add a new channel ---
# Usage: nix.channels.add <name> <url>
alias nix.channels.add='nix-channel --add'

# --- Remove a channel ---
# Usage: nix.channels.remove <name>
alias nix.channels.remove='nix-channel --remove'

# --- Check the health of the nix installation ---
# Usage: nix.doctor
alias nix.doctor='_nix_doctor() {
  echo "== Nix Health Check =="
  
  echo -n "Nix version: "
  nix --version || echo "ERROR: Nix not installed or not in PATH"
  
  echo -n "Nix daemon status: "
  if pgrep nix-daemon >/dev/null; then
    echo "Running"
  else
    echo "Not running"
  fi
  
  echo "Nix store: "
  df -h /nix 2>/dev/null || echo "ERROR: /nix not found"
  
  echo "Nix channels: "
  nix-channel --list || echo "ERROR: Channels not available"
  
  if [ "$NIX_FLAKES_SUPPORTED" -eq 1 ]; then
    echo "Flakes support: Enabled"
  else
    echo "Flakes support: Not enabled"
  fi
  
  echo "Environment: $NIX_ENV_TYPE"
  
  echo "== Checks completed =="
}; _nix_doctor'

# --- Show top packages by closure size ---
# Usage: nix.top [count]
alias nix.top='_nix_top() {
  local count="${1:-10}"  # Default: show top 10
  
  echo "Top $count installed packages by closure size:"
  
  nix-env -q --installed | while read pkg; do
    size=$(nix path-info -s $(which "$pkg" 2>/dev/null || echo "") 2>/dev/null || echo "0")
    echo "$size $pkg"
  done | sort -rn | head -n "$count" | numfmt --to=iec --field=1
}; _nix_top'

# ============================================
# Help Function
# ============================================

# Help function to list all available nix aliases
nix.help() {
  echo "Nix/NixOS/nix-darwin Aliases"
  echo "============================"
  echo
  echo "PACKAGE MANAGEMENT:"
  echo "  nix.search              Search for packages"
  echo "  nix.install             Install package to user profile"
  echo "  nix.install.attr        Install package with attribute path"
  echo "  nix.uninstall           Uninstall package from user profile"
  echo "  nix.upgrade             Upgrade user profile packages"
  echo "  nix.list                List installed packages"
  echo "  nix.show                Show derivation for a package"
  echo "  nix.info                Show package information"
  echo "  nix.run                 Run software without installing"
  echo "  nix.build               Build a single package"
  echo
  echo "NIX DEVELOPMENT:"
  echo "  nix.shell               Start a nix-shell with packages"
  echo "  nix.shell.pure          Start a pure nix-shell with packages"
  echo "  nix.develop             Start a shell from a flake"
  echo "  nix.dev.pkg             Enter a development shell for a package"
  echo "  nix.mkshell             Create a shell.nix file interactively"
  echo "  nix.mkflake             Create a flake.nix template interactively"
  echo
  if [ "$NIX_ENV_TYPE" = "nixos" ]; then
    echo "NIXOS SYSTEM MANAGEMENT:"
    echo "  nixos.rebuild           Rebuild NixOS system"
    echo "  nixos.rebuild.flake     Rebuild NixOS system with flake"
    echo "  nixos.test              Test NixOS configuration without switching"
    echo "  nixos.build             Build NixOS configuration but don't activate"
    echo "  nixos.edit              Edit NixOS configuration file"
    echo "  nixos.edit.hardware     Edit hardware-configuration.nix"
    echo "  nixos.cd                Go to NixOS configuration directory"
    echo "  nixos.generations       List current NixOS system generations"
    echo "  nixos.boot-generation   Boot into a specific NixOS generation"
    echo "  nixos.version           Show current system version"
    echo
  fi
  if [ "$NIX_ENV_TYPE" = "darwin" ]; then
    echo "NIX-DARWIN SYSTEM MANAGEMENT:"
    echo "  darwin.rebuild         Rebuild Darwin system"
    echo "  darwin.rebuild.flake   Rebuild Darwin system with flake"
    echo "  darwin.edit            Edit Darwin configuration file"
    echo "  darwin.cd              Go to Darwin configuration directory"
    echo
  fi
  if [ "$NIX_FLAKES_SUPPORTED" -eq 1 ]; then
    echo "FLAKE MANAGEMENT:"
    echo "  nix.flake.update       Update flake inputs"
    echo "  nix.flake.lock         Lock flake to specific input"
    echo "  nix.flake.info         Show flake info"
    echo "  nix.flake.check        Check flake outputs"
    echo "  nix.flake.inputs       List flake inputs"
    echo
  fi
  echo "NIX STORE & GARBAGE COLLECTION:"
  echo "  nix.gc                  Collect garbage (with confirmation)"
  echo "  nix.gc.all              Aggressive garbage collection"
  echo "  nix.gc.old              Clean up old generations"
  echo "  nix.store.refs          Show store path references"
  echo "  nix.store.referrers     Show reverse references"
  echo "  nix.store.size          Show store path closure size"
  echo
  echo "DETERMINISTIC BUILDS:"
  echo "  nix.drv                 Print derivation for a package"
  echo "  nix.deps                Show build dependencies of a package"
  echo "  nix.diff                Check if paths have the same content"
  echo "  nix.bundle              Generate a reproducible source archive"
  echo "  nix.log                 Show build log"
  echo
  echo "NIX CONFIGURATION:"
  echo "  nix.config              Show Nix config"
  echo "  nix.config.edit         Edit global Nix config"
  echo "  nix.enable.flakes       Enable flake support"
  echo
  echo "INFORMATION & DIAGNOSTICS:"
  echo "  nix.channels            Show Nix channels"
  echo "  nix.channels.update     Update all channels"
  echo "  nix.channels.add        Add a new channel"
  echo "  nix.channels.remove     Remove a channel"
  echo "  nix.doctor              Check the health of the nix installation"
  echo "  nix.top                 Show top packages by closure size"
  echo
  echo "ENVIRONMENT INFO:"
  echo "  Current environment: $NIX_ENV_TYPE"
  echo "  Flakes supported: $([ "$NIX_FLAKES_SUPPORTED" -eq 1 ] && echo "Yes" || echo "No")"
  echo
  echo "EXAMPLES:"
  echo "  nix.search firefox          # Search for Firefox packages"
  echo "  nix.install.attr nixpkgs.ripgrep  # Install ripgrep"
  echo "  nix.shell git vim           # Start a shell with git and vim"
  echo "  nix.gc.old 3                # Keep only last 3 generations"
  if [ "$NIX_ENV_TYPE" = "nixos" ]; then
    echo "  nixos.rebuild               # Rebuild NixOS system"
  fi
  if [ "$NIX_ENV_TYPE" = "darwin" ]; then
    echo "  darwin.rebuild             # Rebuild nix-darwin system"
  fi
}; nix.help'