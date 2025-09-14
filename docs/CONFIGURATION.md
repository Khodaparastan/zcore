# ZCore Usage: Interactive Shell Configuration

This document shows how to use the ZCore library for interactive shell configuration. This is just one example use case of the ZCore library.

## Overview

This example configuration uses ZCore to provide:

- **Modular Architecture**: Clean separation of concerns with pluggable modules
- **Intelligent Loading**: Smart module loading with progress tracking and error handling
- **Cross-Platform Support**: Works seamlessly across different operating systems
- **Plugin Management**: Integrated ZI plugin manager support
- **Performance Optimized**: Fast startup with intelligent caching

## Example Project Structure

This is an example of how to structure a Zsh configuration using ZCore:

```text
zsh_config/
├── .zshrc                    # Shell entry point
├── init.zsh                  # Configuration orchestrator (uses ZCore)
├── conf.zsh                  # Alternative entry point
├── lib/                      # ZCore library
│   ├── core.zsh             # Core utility library
│   ├── platform.zsh         # Platform detection
│   └── ARCHITECTURE.md      # Library documentation
├── modules/                  # Example configuration modules (using ZCore)
│   ├── aliases.zsh          # Command aliases
│   ├── clipboard.zsh        # Clipboard utilities
│   ├── completions.zsh      # Tab completion setup
│   ├── environment.zsh      # Environment variables
│   ├── external_tools.zsh   # External tool integration
│   ├── extra.zsh            # Additional configurations
│   ├── funcs.zsh            # Custom functions
│   ├── keybindings.zsh      # Key bindings
│   ├── load_zi.zsh          # ZI plugin manager
│   ├── options.zsh          # Shell options
│   ├── path.zsh             # PATH management
│   ├── prompt.zsh           # Prompt configuration
│   ├── python.zsh           # Python environment
│   └── utils.zsh            # Utility functions
├── aliases/                  # Alias definitions
└── tests/                    # Test suite
```

## Example: Setting Up Interactive Shell Configuration

This shows how to use ZCore for shell configuration:

1. **Source ZCore library**:

   ```zsh
   # In your .zshrc or init script
   source /path/to/lib/core.zsh
   source /path/to/lib/platform.zsh
   ```

2. **Use ZCore functions for configuration**:

   ```zsh
   # Detect platform
   z::detect::platform

   # Set up environment
   z::log::info "Setting up shell environment"

   # Add to PATH safely
   z::path::add "/usr/local/bin" prepend

   # Create aliases safely
   z::alias::define "ll" "ls -la"
   ```

3. **Organize into modules**:

   ```zsh
   # Load configuration modules
   for module in environment aliases completions; do
       z::path::source "/path/to/modules/${module}.zsh"
   done
   ```

## ZCore Configuration for Shell Use

### Environment Variables

Control ZCore behavior in your shell configuration:

```bash
# Performance optimization
export ZCORE_CONFIG_PERFORMANCE_MODE=true

# UI control
export ZCORE_CONFIG_SHOW_PROGRESS=false

# Verbosity control (0=error, 1=warn, 2=info, 3=debug)
export zcore_config_verbose=2
```

### Runtime Configuration

Modify settings during execution:

```zsh
# Update configuration
z::config::set "timeout_default" 60
z::config::set "cache_max_size" 200
z::config::set "performance_mode" true
```

## Example: Using ZCore in Configuration Modules

### Core Configuration Modules

#### Environment (`modules/environment.zsh`)

Manages environment variables, package managers, and XDG directories.

**Features:**

- XDG directory setup (`XDG_CONFIG_HOME`, `XDG_DATA_HOME`, etc.)
- Package manager configuration (Homebrew, apt, pacman, etc.)
- Environment variable management
- Platform-specific settings

**Key Functions:**

- `_initialize_environment()`: Sets up XDG directories
- `_setup_package_managers()`: Configures package managers
- `_setup_environment()`: Sets environment variables

**Example Usage:**

```zsh
# Using ZCore for environment setup
z::detect::platform
if (( IS_MACOS )); then
    export HOMEBREW_NO_ANALYTICS=1
    z::log::info "Homebrew configured for macOS"
fi
```

#### Path Management (`modules/path.zsh`)

Handles PATH building and directory management.

**Features:**

- Intelligent PATH building
- Directory existence checking
- Platform-specific path additions
- Cleanup of non-existent directories

**Key Functions:**

- `_build_path()`: Builds the PATH variable
- `_add_to_path()`: Adds directories to PATH
- `_cleanup_path()`: Removes non-existent directories

**Example Usage:**

```zsh
# Using ZCore for PATH management
z::path::add "/usr/local/bin" prepend
z::path::add "$HOME/.local/bin" append
z::log::debug "PATH updated"
```

#### Aliases (`modules/aliases.zsh`)

Manages command aliases and shortcuts.

**Features:**

- Command aliases and shortcuts
- Platform-specific aliases
- Safe alias creation using ZCore functions

**Key Functions:**

- `_define_aliases()`: Defines common aliases
- `setup_platform_aliases()`: Sets platform-specific aliases
- `z::alias::define()`: Creates safe aliases

**Example Usage:**

```zsh
# Using ZCore for safe alias creation
z::alias::define "ll" "ls -la"
z::alias::define "gst" "git status"
z::alias::define "gco" "git checkout"
z::log::info "Aliases created"
```

#### Completions (`modules/completions.zsh`)

Sets up tab completion system.

**Features:**

- Tab completion setup
- Zsh completion system configuration
- Custom completion functions

**Key Functions:**

- `_setup_completions()`: Initializes completion system
- `_load_completion_plugins()`: Loads completion plugins

#### Key Bindings (`modules/keybindings.zsh`)

Manages custom key bindings.

**Features:**

- Custom key bindings
- Vi/Emacs mode configuration
- Platform-specific bindings

**Key Functions:**

- `_setup_keybindings()`: Sets up key bindings
- `_setup_vi_mode()`: Configures vi mode
- `_setup_emacs_mode()`: Configures emacs mode

#### Prompt (`modules/prompt.zsh`)

Configures shell prompt.

**Features:**

- Shell prompt configuration
- Git integration
- Platform-specific prompt elements

**Key Functions:**

- `_setup_prompt()`: Configures the prompt
- `_setup_git_prompt()`: Sets up git prompt
- `_setup_platform_prompt()`: Platform-specific prompt elements

### Utility Modules

#### Python (`modules/python.zsh`)

Manages Python environment.

**Features:**

- Python environment setup
- Virtual environment management
- Python-specific aliases and functions

**Key Functions:**

- `_setup_python_env()`: Sets up Python environment
- `_setup_pyenv()`: Configures pyenv if available
- `_setup_virtualenv()`: Sets up virtual environment tools

#### External Tools (`modules/external_tools.zsh`)

Integrates external tools.

**Features:**

- External tool integration
- Tool-specific configurations
- Conditional loading based on tool availability

**Key Functions:**

- `_setup_external_tools()`: Sets up external tools
- `_setup_fzf()`: Configures fzf if available
- `_setup_bat()`: Configures bat if available

#### Utils (`modules/utils.zsh`)

Provides utility functions.

**Features:**

- Utility functions
- Helper commands
- Custom shell functions

**Key Functions:**

- `_setup_utils()`: Sets up utility functions
- `_create_helper_functions()`: Creates helper functions

#### Clipboard (`modules/clipboard.zsh`)

Manages clipboard operations.

**Features:**

- Cross-platform clipboard support
- Clipboard utilities
- Platform-specific clipboard commands

**Key Functions:**

- `_setup_clipboard()`: Sets up clipboard utilities
- `_setup_pbcopy()`: macOS clipboard support
- `_setup_xclip()`: Linux clipboard support

#### Extra (`modules/extra.zsh`)

Additional configurations.

**Features:**

- Additional configurations
- Custom settings
- Extra utilities

**Key Functions:**

- `_setup_extra()`: Sets up additional configurations
- `_setup_custom_settings()`: Custom settings

#### Options (`modules/options.zsh`)

Configures shell options.

**Features:**

- Shell options configuration
- Zsh-specific options
- Performance optimizations

**Key Functions:**

- `_setup_options()`: Sets up shell options
- `_configure_setopts()`: Configures setopt options

#### Load ZI (`modules/load_zi.zsh`)

Manages ZI plugin manager.

**Features:**

- ZI plugin manager integration
- Plugin loading
- Plugin management

**Key Functions:**

- `_install_zi()`: Installs ZI if not available
- `_load_plugins()`: Loads configured plugins
- `_setup_zi()`: Sets up ZI configuration

## Example: Customizing Shell Configuration with ZCore

### Adding New Configuration Modules

1. Create a new file in `modules/`:

   ```bash
   touch ~/.config/zsh/modules/my_module.zsh
   ```

2. Add your configuration using ZCore:

   ```zsh
   #!/usr/bin/env zsh
   # My custom configuration module using ZCore

   # Use ZCore for logging
   z::log::info "Loading my custom module"

   # Use ZCore for platform detection
   z::detect::platform

   # Use ZCore for safe operations
   export MY_VAR="value"
   z::path::add "/custom/path" prepend
   z::alias::define "mycmd" "custom_command"

   z::log::info "My module loaded successfully"
   ```

3. Load it in your shell configuration:

   ```zsh
   # In your .zshrc or init script
   z::path::source "/path/to/modules/my_module.zsh"
   ```

### Custom Functions Using ZCore

Add custom functions that use ZCore utilities:

```zsh
# Custom function using ZCore utilities
my_function() {
    emulate -L zsh

    # Use ZCore logging
    z::log::info "Running my_function"

    # Use ZCore for safe execution
    z::exec::run "ls -la" || return $?

    # Use ZCore for progress tracking
    z::ui::progress::show 1 1 "completed"
}
```

### Custom Aliases Using ZCore

Add aliases using ZCore's safe alias creation:

```zsh
# Safe alias creation using ZCore
z::alias::define "ll" "ls -la"
z::alias::define "gst" "git status"
z::alias::define "gco" "git checkout"
```

### Custom Environment Variables Using ZCore

Add environment variables with ZCore platform detection:

```zsh
# Use ZCore for platform detection
z::detect::platform

# Custom environment variables
export MY_CUSTOM_VAR="value"
export MY_OTHER_VAR="another_value"

# Platform-specific variables using ZCore platform flags
if (( IS_MACOS )); then
    export MACOS_SPECIFIC_VAR="mac_value"
    z::log::debug "macOS-specific variables set"
elif (( IS_LINUX )); then
    export LINUX_SPECIFIC_VAR="linux_value"
    z::log::debug "Linux-specific variables set"
fi
```

## Example: Module Loading Order

This example shows how modules are loaded in a specific order when using ZCore:

1. **environment** - Sets up basic environment
2. **path** - Builds PATH variable
3. **extra** - Additional configurations
4. **aliases** - Command aliases
5. **load_zi** - ZI plugin manager
6. **completions** - Tab completion
7. **keybindings** - Key bindings
8. **utils** - Utility functions
9. **python** - Python environment
10. **funcs** - Custom functions
11. **external_tools** - External tool integration
12. **prompt** - Shell prompt
13. **clipboard** - Clipboard utilities

## Performance Considerations

### Using ZCore for Performance

When using ZCore for shell configuration, consider these optimizations:

- **Intelligent Module Loading**: Only loads necessary modules
- **Progress Tracking**: Shows loading progress with minimal overhead
- **ZCore Caching**: Leverages ZCore's intelligent caching system
- **Performance Mode**: Can disable expensive operations for faster startup

### Performance Modes

Enable performance mode for faster startup:

```bash
export ZCORE_CONFIG_PERFORMANCE_MODE=true
```

This mode:

- Reduces security scanning overhead
- Skips expensive path resolution
- Minimizes progress display
- Optimizes for high-throughput scenarios

## Troubleshooting ZCore Usage

### Common Issues When Using ZCore

1. **ZCore not loaded**: Ensure ZCore library is sourced before using its functions
2. **Slow startup**: Enable ZCore performance mode or reduce module count
3. **Missing functions**: Check if ZCore functions are available with `z::func::exists`
4. **Platform detection issues**: Ensure ZCore platform detection is called first

### Debug Mode

Enable debug mode for detailed logging:

```bash
export zcore_config_verbose=3
```

This will show detailed information about module loading and function execution.

### Testing

Run the test suite to verify everything is working:

```bash
zsh ~/.config/zsh/tests/run.zsh
```

## Best Practices for Using ZCore

1. **Source ZCore first**: Always source ZCore before using its functions
2. **Use ZCore functions**: Leverage ZCore's safe execution, logging, and platform detection
3. **Handle errors gracefully**: Use ZCore's error handling and logging
4. **Test thoroughly**: Test your ZCore usage on different platforms
5. **Document ZCore usage**: Document how you're using ZCore functions

## Migration to ZCore

### From Other Zsh Configurations

When migrating to use ZCore:

1. **Backup existing config**: Save your current `.zshrc`
2. **Source ZCore**: Add ZCore library sourcing to your config
3. **Replace functions**: Replace custom functions with ZCore equivalents
4. **Test thoroughly**: Verify ZCore functions work as expected
5. **Clean up**: Remove redundant custom code

### Updating ZCore Usage

To update your ZCore usage:

1. **Backup customizations**: Save any custom ZCore usage
2. **Update ZCore**: Pull latest ZCore library updates
3. **Test**: Verify ZCore functions still work
4. **Restart shell**: `exec zsh` to reload

---

This example shows how to use the ZCore library for interactive shell configuration. ZCore can be used for many other purposes beyond shell configuration.
