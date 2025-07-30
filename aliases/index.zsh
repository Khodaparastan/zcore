#!/usr/bin/env zsh
# ============================================================================
# ZSH Aliases Bootstrap System
# ============================================================================
# Purpose: Auto-detect environment and load appropriate aliases
# Usage:   Source this file from your zshrc or through zi/other plugin manager
# Example: source /path/to/aliases/index.zsh
#
# Configuration (set before sourcing):
#   ZSH_ALIASES_DIR         Override the directory where aliases are stored
#   ZSH_ALIASES_CATEGORIES  Array of categories to load (default: all)
#   ZSH_ALIASES_EXCLUDE     Array of categories to exclude
#   ZSH_ALIASES_DEBUG       Set to 1 to enable verbose loading messages
#   ZSH_ALIASES_NO_OS_DETECT Skip OS detection (use ZSH_OS instead)
# ============================================================================

# Guard against non-ZSH shells
[[ -n "$ZSH_VERSION" ]] || { echo "This file requires ZSH. Aborting."; return 1; }

# ============================================================================
# Environment Detection & Configuration
# ============================================================================

# Store directory where this script resides to correctly locate other aliases
: ${ZSH_ALIASES_DIR:=${0:A:h}}

# Enable debug mode if set
: ${ZSH_ALIASES_DEBUG:=0}

# Skip OS detection if explicitly requested
: ${ZSH_ALIASES_NO_OS_DETECT:=0}

# Create log function
_zsh_aliases_log() {
  [[ "$ZSH_ALIASES_DEBUG" == "1" ]] && echo "[ZSH-ALIASES] $*"
}

# Detect OS if not skipped
if [[ "$ZSH_ALIASES_NO_OS_DETECT" != "1" ]]; then
  case "$(uname -s)" in
    Linux*)
      if [[ -f /etc/os-release ]]; then
        # Get Linux distribution from os-release file
        source /etc/os-release
        OS_ID="${ID}"
        OS_VERSION="${VERSION_ID}"
        
        # Set OS based on ID
        case "${ID}" in
          debian|ubuntu|elementary|mint|pop|kali) 
            export ZSH_OS="debian" ;;
          fedora|rhel|centos|rocky|alma|ol|amzn) 
            export ZSH_OS="rhel" ;;
          arch|manjaro|endeavouros)
            export ZSH_OS="arch" ;;
          opensuse*|suse|sles)
            export ZSH_OS="suse" ;;
          alpine)
            export ZSH_OS="alpine" ;;
          *)
            export ZSH_OS="linux" ;;
        esac
        
        # Check for WSL (Windows Subsystem for Linux)
        if [[ -n "$(grep -i microsoft /proc/version 2>/dev/null)" ]]; then
          export ZSH_OS_WSL=1
        else
          export ZSH_OS_WSL=0
        fi
        
      else
        export ZSH_OS="linux"
      fi
      ;;
    Darwin*)
      export ZSH_OS="macos"
      ;;
    CYGWIN*|MINGW*|MSYS*)
      export ZSH_OS="windows"
      ;;
    *)
      export ZSH_OS="unknown"
      ;;
  esac
else
  # Make sure ZSH_OS is set to some value
  : ${ZSH_OS:=unknown}
fi

# Detect if running inside a container
if [[ -f /.dockerenv ]] || [[ -f /run/.containerenv ]]; then
  export ZSH_CONTAINER=1
  
  # Detect container type if possible
  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    export ZSH_CONTAINER_TYPE="${ID}"
  else
    export ZSH_CONTAINER_TYPE="unknown"
  fi
else
  export ZSH_CONTAINER=0
  export ZSH_CONTAINER_TYPE=""
fi

# Detect package manager
if [[ -z "$ZSH_PACKAGE_MANAGER" ]]; then
  if command -v apt &>/dev/null; then
    export ZSH_PACKAGE_MANAGER="apt"
  elif command -v dnf &>/dev/null; then
    export ZSH_PACKAGE_MANAGER="dnf"
  elif command -v yum &>/dev/null; then
    export ZSH_PACKAGE_MANAGER="yum"
  elif command -v pacman &>/dev/null; then
    export ZSH_PACKAGE_MANAGER="pacman"
  elif command -v apk &>/dev/null; then
    export ZSH_PACKAGE_MANAGER="apk"
  elif command -v brew &>/dev/null; then
    export ZSH_PACKAGE_MANAGER="brew"
  elif command -v port &>/dev/null; then
    export ZSH_PACKAGE_MANAGER="port"
  elif command -v nix-env &>/dev/null; then
    export ZSH_PACKAGE_MANAGER="nix"
  else
    export ZSH_PACKAGE_MANAGER="unknown"
  fi
fi

# Log environment details
_zsh_aliases_log "OS detected: $ZSH_OS"
_zsh_aliases_log "Package manager: $ZSH_PACKAGE_MANAGER"
[[ "$ZSH_CONTAINER" == "1" ]] && _zsh_aliases_log "Running in container: $ZSH_CONTAINER_TYPE"
[[ "$ZSH_OS_WSL" == "1" ]] && _zsh_aliases_log "Running in WSL"

# ============================================================================
# Alias Loading System
# ============================================================================

# Get list of all available alias categories
_zsh_aliases_get_all_categories() {
  local aliases_dir="$1"
  local categories=()
  
  # Find all .zsh files in the aliases directory
  for file in "$aliases_dir"/*.zsh; do
    [[ -f "$file" ]] || continue
    
    # Skip the index.zsh file (this file)
    if [[ "$(basename "$file")" == "index.zsh" ]]; then
      continue
    fi
    
    # Extract basename without extension
    local basename=$(basename "$file" .zsh)
    categories+=("$basename")
  done
  
  echo "${categories[@]}"
}

# Default categories: All available in the directory
: ${ZSH_ALIASES_CATEGORIES:=$(_zsh_aliases_get_all_categories "$ZSH_ALIASES_DIR")}

# Load a specific aliases file
_zsh_aliases_load_category() {
  local aliases_dir="$1"
  local category="$2"
  local file="${aliases_dir}/${category}.zsh"
  
  # Check if file exists
  if [[ ! -f "$file" ]]; then
    _zsh_aliases_log "Warning: Alias category '$category' not found at $file"
    return 1
  fi
  
  # Check if category is excluded
  if [[ -n "$ZSH_ALIASES_EXCLUDE" ]]; then
    for excluded in "${ZSH_ALIASES_EXCLUDE[@]}"; do
      if [[ "$category" == "$excluded" ]]; then
        _zsh_aliases_log "Skipping excluded category: $category"
        return 0
      fi
    done
  fi
  
  # Source the file
  _zsh_aliases_log "Loading aliases: $category"
  source "$file"
  return $?
}

# ============================================================================
# Bootstrap the Aliases
# ============================================================================

# Create convenience function to reload aliases
reload_aliases() {
  _zsh_aliases_log "Reloading aliases from $ZSH_ALIASES_DIR"
  source "$ZSH_ALIASES_DIR/index.zsh"
  echo "Aliases reloaded!"
}

# Create function to add a new category to active categories
add_aliases_category() {
  local category="$1"
  if [[ -z "$category" ]]; then
    echo "Usage: add_aliases_category CATEGORY"
    return 1
  fi
  
  # Check if already loaded
  for loaded_category in "${ZSH_ALIASES_CATEGORIES[@]}"; do
    if [[ "$loaded_category" == "$category" ]]; then
      echo "Category '$category' is already loaded."
      return 0
    fi
  done
  
  # Try to load the category
  if _zsh_aliases_load_category "$ZSH_ALIASES_DIR" "$category"; then
    # Add to loaded categories
    ZSH_ALIASES_CATEGORIES+=("$category")
    echo "Successfully loaded aliases category: $category"
  else
    echo "Failed to load aliases category: $category"
    return 1
  fi
}

# List all available categories
list_aliases_categories() {
  local all_categories=($(_zsh_aliases_get_all_categories "$ZSH_ALIASES_DIR"))
  local loaded=()
  local available=()
  
  # Check which categories are loaded
  for category in "${all_categories[@]}"; do
    local is_loaded=0
    for loaded_category in "${ZSH_ALIASES_CATEGORIES[@]}"; do
      if [[ "$category" == "$loaded_category" ]]; then
        is_loaded=1
        break
      fi
    done
    
    if [[ "$is_loaded" == "1" ]]; then
      loaded+=("$category")
    else
      available+=("$category")
    fi
  done
  
  echo "Loaded Alias Categories:"
  for category in "${loaded[@]}"; do
    echo "  - $category"
  done
  
  if [[ ${#available[@]} -gt 0 ]]; then
    echo "Available but Not Loaded:"
    for category in "${available[@]}"; do
      echo "  - $category"
    done
  fi
}

# Load all specified categories
for category in "${ZSH_ALIASES_CATEGORIES[@]}"; do
  _zsh_aliases_load_category "$ZSH_ALIASES_DIR" "$category"
done

# Create help function
aliases_help() {
  echo "ZSH Aliases System"
  echo "=================="
  echo "Usage:"
  echo "  reload_aliases                 - Reload all aliases"
  echo "  add_aliases_category CATEGORY  - Load a specific aliases category"
  echo "  list_aliases_categories        - List loaded and available categories"
  echo ""
  echo "Current environment:"
  echo "  OS: $ZSH_OS"
  echo "  Package manager: $ZSH_PACKAGE_MANAGER"
  if [[ "$ZSH_CONTAINER" == "1" ]]; then
    echo "  Container: $ZSH_CONTAINER_TYPE"
  fi
  if [[ "$ZSH_OS_WSL" == "1" ]]; then
    echo "  WSL: Yes"
  fi
  echo ""
  echo "Configure by setting these variables before sourcing:"
  echo "  ZSH_ALIASES_DIR         - Override aliases directory"
  echo "  ZSH_ALIASES_CATEGORIES  - Specific categories to load"
  echo "  ZSH_ALIASES_EXCLUDE     - Categories to exclude"
  echo "  ZSH_ALIASES_DEBUG       - Enable verbose loading (1=on)"
  echo ""
  echo "For help with specific alias categories, try:"
  echo "  ansible.help, gpg.help, idm.help, net.info.help, net.conf.help, nix.help, nmap.help, ossl.help, etc."
}

_zsh_aliases_log "Aliases bootstrap complete!"