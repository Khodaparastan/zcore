#!/usr/bin/env bash
# ============================================================================
# ZSH Aliases Installation Script
# ============================================================================
# This script installs the ZSH aliases collection to the specified location
# and configures your zshrc to load them.
#
# Usage: bash install.sh [options]
#
# Options:
#   --dest DIR      Install to DIR instead of default location
#   --system        Install system-wide (requires sudo)
#   --user          Install for current user only (default)
#   --plugin TYPE   Configure for plugin manager: zi, omz, vanilla (default)
#   --no-backup     Skip backup of existing files
#   --no-modify     Don't modify zshrc, just install files
#   --minimal       Install minimal set of aliases
#   --help          Show this help message
# ============================================================================

set -e

# Default settings
INSTALL_MODE="user"
PLUGIN_TYPE="vanilla"
BACKUP=1
MODIFY_ZSHRC=1
MINIMAL=0

# Directories
USER_INSTALL_DIR="${HOME}/.zsh/aliases"
SYSTEM_INSTALL_DIR="/usr/local/share/zsh/aliases"
DEST_DIR=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print usage
print_usage() {
  echo -e "${BLUE}ZSH Aliases Installer${NC}"
  echo
  echo "Usage: bash install.sh [options]"
  echo
  echo "Options:"
  echo "  --dest DIR      Install to DIR instead of default location"
  echo "  --system        Install system-wide (requires sudo)"
  echo "  --user          Install for current user only (default)"
  echo "  --plugin TYPE   Configure for plugin manager: zi, omz, vanilla (default)"
  echo "  --no-backup     Skip backup of existing files"
  echo "  --no-modify     Don't modify zshrc, just install files"
  echo "  --minimal       Install minimal set of aliases"
  echo "  --help          Show this help message"
  echo
}

# Process command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest)
      DEST_DIR="$2"
      shift 2
      ;;
    --system)
      INSTALL_MODE="system"
      shift
      ;;
    --user)
      INSTALL_MODE="user"
      shift
      ;;
    --plugin)
      PLUGIN_TYPE="$2"
      shift 2
      ;;
    --no-backup)
      BACKUP=0
      shift
      ;;
    --no-modify)
      MODIFY_ZSHRC=0
      shift
      ;;
    --minimal)
      MINIMAL=1
      shift
      ;;
    --help)
      print_usage
      exit 0
      ;;
    *)
      echo -e "${RED}Error: Unknown option $1${NC}"
      print_usage
      exit 1
      ;;
  esac
done

# Set destination directory
if [[ -z "$DEST_DIR" ]]; then
  if [[ "$INSTALL_MODE" == "system" ]]; then
    DEST_DIR="$SYSTEM_INSTALL_DIR"
  else
    DEST_DIR="$USER_INSTALL_DIR"
  fi
fi

# Check for zsh
if ! command -v zsh >/dev/null 2>&1; then
  echo -e "${RED}Error: ZSH is not installed. Please install zsh first.${NC}"
  exit 1
fi

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Check if source files exist
if [[ ! -f "$SCRIPT_DIR/index.zsh" ]]; then
  echo -e "${RED}Error: Source files not found. Are you running from the correct directory?${NC}"
  exit 1
fi

# Create installation directory
echo -e "${BLUE}Installing ZSH aliases to: ${DEST_DIR}${NC}"

if [[ "$INSTALL_MODE" == "system" ]]; then
  # Check for sudo
  if ! command -v sudo >/dev/null 2>&1; then
    echo -e "${RED}Error: System-wide installation requires sudo.${NC}"
    exit 1
  fi
  
  # Create directory with sudo
  sudo mkdir -p "$DEST_DIR"
else
  # Create directory
  mkdir -p "$DEST_DIR"
fi

# Backup existing files if needed
if [[ $BACKUP -eq 1 && -d "$DEST_DIR" && "$(ls -A "$DEST_DIR" 2>/dev/null)" ]]; then
  BACKUP_DIR="${DEST_DIR}.backup-$(date +%Y%m%d%H%M%S)"
  echo -e "${YELLOW}Backing up existing files to: ${BACKUP_DIR}${NC}"
  
  if [[ "$INSTALL_MODE" == "system" ]]; then
    sudo cp -R "$DEST_DIR" "$BACKUP_DIR"
  else
    cp -R "$DEST_DIR" "$BACKUP_DIR"
  fi
fi

# Copy files
if [[ "$MINIMAL" -eq 1 ]]; then
  echo -e "${BLUE}Installing minimal set of aliases...${NC}"
  INSTALL_FILES=("index.zsh" "os-specific.zsh" "network-info.zsh" "network-config.zsh")
else
  echo -e "${BLUE}Installing all aliases...${NC}"
  INSTALL_FILES=("*.zsh")
fi

if [[ "$INSTALL_MODE" == "system" ]]; then
  # Copy with sudo
  for file in $SCRIPT_DIR/*.zsh; do
    if [[ "$MINIMAL" -eq 1 ]]; then
      # Check if this file should be included in minimal install
      filename=$(basename "$file")
      if [[ " ${INSTALL_FILES[@]} " =~ " ${filename} " ]]; then
        sudo cp "$file" "$DEST_DIR/"
      fi
    else
      sudo cp "$file" "$DEST_DIR/"
    fi
  done
  
  # Set permissions
  sudo chmod -R 755 "$DEST_DIR"
else
  # Copy without sudo
  for file in $SCRIPT_DIR/*.zsh; do
    if [[ "$MINIMAL" -eq 1 ]]; then
      # Check if this file should be included in minimal install
      filename=$(basename "$file")
      if [[ " ${INSTALL_FILES[@]} " =~ " ${filename} " ]]; then
        cp "$file" "$DEST_DIR/"
      fi
    else
      cp "$file" "$DEST_DIR/"
    fi
  done
fi

# Success message for file installation
echo -e "${GREEN}ZSH aliases files installed successfully!${NC}"

# Modify zshrc if requested
if [[ $MODIFY_ZSHRC -eq 1 ]]; then
  ZSHRC="${HOME}/.zshrc"
  
  if [[ ! -f "$ZSHRC" ]]; then
    echo -e "${YELLOW}Warning: No .zshrc found, creating one.${NC}"
    touch "$ZSHRC"
  fi
  
  # Create backup of zshrc
  if [[ $BACKUP -eq 1 ]]; then
    cp "$ZSHRC" "${ZSHRC}.backup-$(date +%Y%m%d%H%M%S)"
    echo -e "${YELLOW}Created backup of .zshrc${NC}"
  fi
  
  echo -e "${BLUE}Configuring .zshrc...${NC}"

  # Different configuration for different plugin managers
  case "$PLUGIN_TYPE" in
    zi)
      # Check if zi is actually installed
      if grep -q "zi.zsh" "$ZSHRC" || grep -q "zinit.zsh" "$ZSHRC"; then
        echo -e "${BLUE}Configuring for zi plugin manager...${NC}"
        if ! grep -q "zi ice depth" "$ZSHRC"; then
          echo >> "$ZSHRC"
          echo "# ZSH Aliases" >> "$ZSHRC"
          echo "zi ice depth=1" >> "$ZSHRC"
          echo "zi load \"$DEST_DIR\"" >> "$ZSHRC"
        else
          echo -e "${YELLOW}zi configuration already exists in .zshrc. Manual configuration required.${NC}"
        fi
      else
        echo -e "${YELLOW}Warning: zi not detected in .zshrc. Using vanilla configuration.${NC}"
        echo >> "$ZSHRC"
        echo "# ZSH Aliases" >> "$ZSHRC"
        echo "source \"$DEST_DIR/index.zsh\"" >> "$ZSHRC"
      fi
      ;;
      
    omz)
      # Check if oh-my-zsh is actually installed
      if grep -q "oh-my-zsh.sh" "$ZSHRC"; then
        echo -e "${BLUE}Configuring for Oh My Zsh...${NC}"
        if [[ ! -d "${HOME}/.oh-my-zsh/custom/plugins/zsh-aliases" ]]; then
          # Create custom plugin directory
          mkdir -p "${HOME}/.oh-my-zsh/custom/plugins/zsh-aliases"
          # Link or copy files
          ln -sf "$DEST_DIR"/*.zsh "${HOME}/.oh-my-zsh/custom/plugins/zsh-aliases/"
          # Create plugin file
          cat > "${HOME}/.oh-my-zsh/custom/plugins/zsh-aliases/zsh-aliases.plugin.zsh" << EOF
# ZSH Aliases Plugin
source "\${0:A:h}/index.zsh"
EOF
          echo -e "${YELLOW}Remember to add 'zsh-aliases' to your plugins list in .zshrc${NC}"
        else
          echo -e "${YELLOW}ZSH Aliases already exists as an OMZ plugin. Manual configuration required.${NC}"
        fi
      else
        echo -e "${YELLOW}Warning: Oh My Zsh not detected. Using vanilla configuration.${NC}"
        echo >> "$ZSHRC"
        echo "# ZSH Aliases" >> "$ZSHRC"
        echo "source \"$DEST_DIR/index.zsh\"" >> "$ZSHRC"
      fi
      ;;
      
    vanilla|*)
      # Vanilla ZSH configuration
      if ! grep -q "source.*$DEST_DIR/index.zsh" "$ZSHRC"; then
        echo >> "$ZSHRC"
        echo "# ZSH Aliases" >> "$ZSHRC"
        echo "source \"$DEST_DIR/index.zsh\"" >> "$ZSHRC"
      else
        echo -e "${YELLOW}Aliases already configured in .zshrc${NC}"
      fi
      ;;
  esac
  
  echo -e "${GREEN}Configuration added to .zshrc${NC}"
fi

# Final success message
echo -e "${GREEN}Installation complete!${NC}"
echo -e "${BLUE}To start using the aliases immediately, run:${NC}"
echo -e "  source ~/.zshrc"
echo -e "${BLUE}or start a new terminal session.${NC}"

if [[ "$MINIMAL" -eq 1 ]]; then
  echo -e "${YELLOW}Note: You installed the minimal set of aliases.${NC}"
  echo -e "${YELLOW}To view available aliases categories, run:${NC}"
  echo -e "  list_aliases_categories"
  echo -e "${YELLOW}To add more categories, run:${NC}"
  echo -e "  add_aliases_category CATEGORY_NAME"
fi

echo -e "${BLUE}For help and available commands, run:${NC}"
echo -e "  aliases_help"

exit 0