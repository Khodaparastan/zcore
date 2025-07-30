# ZSH Aliases Collection

A comprehensive, cross-platform collection of ZSH aliases organized by category for developers, system administrators, and DevOps professionals.

## Features

- **Cross-platform**: Designed to work on macOS, Linux distributions (RHEL, Debian, NixOS, etc.), WSL, and containers
- **Specialized tools**: Support for Ansible, Nix ecosystem, RHEL Identity Management, and more
- **Modular**: Organized by category for easy management and selective loading
- **Self-contained**: Each alias file contains relevant documentation and help functions
- **Plugin-compatible**: Works with zi, Oh My Zsh, or as standalone ZSH configuration
- **Intelligent**: Auto-detects OS, package manager, and runtime environment

## Quick Start

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/zsh-aliases.git
cd zsh-aliases/aliases

# Run the installer script (see options below)
./install.sh
```

### Installation Options

```
Usage: bash install.sh [options]

Options:
  --dest DIR      Install to DIR instead of default location
  --system        Install system-wide (requires sudo)
  --user          Install for current user only (default)
  --plugin TYPE   Configure for plugin manager: zi, omz, vanilla (default)
  --no-backup     Skip backup of existing files
  --no-modify     Don't modify zshrc, just install files
  --minimal       Install minimal set of aliases
  --help          Show this help message
```

### Manual Installation

1. Copy the `aliases` directory to your preferred location (e.g., `~/.zsh/aliases`)
2. Add to your `.zshrc`:

```zsh
# Load ZSH Aliases
source ~/.zsh/aliases/index.zsh
```

### With zi Plugin Manager

```zsh
# In your .zshrc
zi ice depth=1
zi load ~/.zsh/aliases
```

### With Oh My Zsh

```zsh
# Link or copy files to custom plugins directory
ln -sf ~/.zsh/aliases ~/.oh-my-zsh/custom/plugins/zsh-aliases

# Add to plugins in .zshrc
plugins=(... zsh-aliases)
```

## Usage

After installation, the aliases are automatically loaded when you start a new shell session.

### Getting Help

```zsh
# Show general help about the aliases system
aliases_help

# Show help for a specific category
ansible.help
gpg.help
idm.help
net.info.help
nix.help
nmap.help
ossl.help
# etc.
```

### Managing Alias Categories

```zsh
# List available and loaded categories
list_aliases_categories

# Add a category dynamically
add_aliases_category ansible

# Reload all aliases (after editing files)
reload_aliases
```

## Available Categories

| Category | Description | Common Commands |
|----------|-------------|----------------|
| **ansible** | Ansible automation & orchestration | `ansible.play`, `ansible.vault.edit`, `ansible.adhoc` |
| **gpg** | GPG key and encryption management | `gpg.list`, `gpg.encrypt`, `gpg.sign` |
| **idm** | RHEL Identity Management (FreeIPA) | `idm.user.add`, `idm.group.show`, `idm.hbac.find` |
| **network-info** | Network information and diagnostics | `net.ip`, `net.dns`, `net.diag.ping` |
| **network-config** | Network configuration helpers | `net.wifi.scan`, `net.hostname.set` |
| **nix** | Nix package manager, NixOS & nix-darwin | `nix.install`, `nixos.rebuild`, `nix.flake.update` |
| **nmap** | Nmap scanning shortcuts | `nmap.scan.tcp`, `nmap.scan.version` |
| **openssl** | OpenSSL encryption and certificate tools | `ossl.gen.rsa`, `ossl.view.cert` |
| **os-specific** | OS-specific commands (auto-loaded) | Various OS-specific helpers |
| **remote** | Remote server management | `srv.run`, `srv.info.disk`, `srv.docker.ps` |
| **ssh** | SSH connection and key management | `sshkey`, `sshcopy`, `sshchk` |

## Environment Detection

The system automatically detects:

- Operating System (macOS, Debian-based, RHEL-based, Arch, etc.)
- Package Manager (apt, dnf, brew, pacman, etc.)
- Container environments (Docker, etc.)
- WSL (Windows Subsystem for Linux)

These variables are exposed for use in your own scripts:

- `ZSH_OS` - Detected operating system
- `ZSH_PACKAGE_MANAGER` - Detected package manager
- `ZSH_CONTAINER` - Set to 1 if running in a container
- `ZSH_CONTAINER_TYPE` - Type of container detected
- `ZSH_OS_WSL` - Set to 1 if running in WSL

## Configuration

Set these variables **before** sourcing the `index.zsh` file to customize behavior:

```zsh
# Override the directory where aliases are stored
export ZSH_ALIASES_DIR=~/.config/zsh/aliases

# Load only specific categories
export ZSH_ALIASES_CATEGORIES=(network-info ssh gpg)

# Exclude specific categories
export ZSH_ALIASES_EXCLUDE=(nmap)

# Enable verbose loading messages
export ZSH_ALIASES_DEBUG=1

# Skip OS detection (use ZSH_OS instead)
export ZSH_ALIASES_NO_OS_DETECT=1
export ZSH_OS="custom"
```

## Customization

### Adding Custom Aliases

Create a new file in the aliases directory:

```zsh
# ~/.zsh/aliases/myalias.zsh
# My custom aliases
alias hello='echo "Hello, World!"'

# With documentation
myalias.help() {
  echo "My custom aliases:"
  echo "  hello - Print a greeting"
}
```

Then load it:

```zsh
add_aliases_category myalias
```

### Extending Existing Categories

Either edit the existing file directly or create a file with `_additions` suffix:

```zsh
# ~/.zsh/aliases/openssl_additions.zsh
# Additional OpenSSL aliases
alias ossl.verify.chain='openssl verify -CAfile'
```

## Troubleshooting

### Command Not Found

If aliases are not available:

1. Make sure the aliases are properly sourced in your `.zshrc`
2. Try reloading with `reload_aliases` or restart your terminal
3. Check if the category is loaded with `list_aliases_categories`
4. Look for error messages when starting ZSH with `ZSH_ALIASES_DEBUG=1`

### Platform-Specific Issues

- **macOS**: Some commands require Homebrew packages
- **Linux**: Some commands require additional packages depending on distribution
- **WSL**: May need adjustments for Windows integration

## Contributing

Contributions are welcome! Please follow these guidelines:

1. Keep aliases organized by category
2. Include documentation and help functions
3. Ensure cross-platform compatibility where possible
4. Add specific checks for required dependencies

## License

This project is licensed under the MIT License - see the LICENSE file for details.