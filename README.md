# ZCore - Zsh Utility Library

A utility library for Zsh that provides safe command execution, logging, caching, and platform detection. Built for reliability and performance in shell environments.

## Overview

ZCore provides:

- **Safe Command Execution**: Subprocess isolation with timeout protection and security scanning
- **Logging System**: 4-level verbosity with recursion protection
- **Caching**: LRU-based function and command existence caching
- **Cross-Platform Support**: Works on macOS, Linux, BSD, WSL, and Termux
- **User Interface**: Progress bars and terminal detection
- **Platform Detection**: OS and environment detection
- **State Management**: Safe variable and function cleanup

## 📁 Project Structure

```text
zsh_config/
├── lib/                      # ZCore Library
│   ├── core.zsh             # Main utility library
│   ├── platform.zsh         # Platform detection
│   └── ARCHITECTURE.md      # Detailed architecture docs
├── modules/                  # Example usage modules
│   ├── aliases.zsh          # Example alias usage
│   ├── environment.zsh      # Example environment setup
│   ├── funcs.zsh            # Example function usage
│   └── ...                  # Other example modules
├── tests/                    # Test suite
└── README.md                # This file
```

## 🚀 Quick Start

### Prerequisites

- **Zsh 5.0+**: Required for all features
- **Standard Unix tools**: `tput`, `date`, `uname` (usually pre-installed)

### Basic Usage

1. **Source the library**:

   ```zsh
   source /path/to/lib/core.zsh
   source /path/to/lib/platform.zsh
   ```

2. **Use ZCore functions**:

   ```zsh
   # Logging
   z::log::info "Hello from ZCore"
   z::log::error "Error message"

   # Safe execution
   z::exec::run "ls -la" 30

   # Platform detection
   z::detect::platform
   if (( IS_MACOS )); then
       echo "Running on macOS"
   fi
   ```

3. **See [EXAMPLES.md](docs/EXAMPLES.md) for comprehensive usage examples**

## Core Features

### Logging System

Logging with 4 levels of verbosity:

```zsh
# Logging functions
z::log::error "Error message"
z::log::warn "Warning message"
z::log::info "Info message"
z::log::debug "Debug message"

# Control logging
z::log::enable_debug
z::log::get_level
z::log::toggle_progress
```

### Safe Execution

Command execution with protection layers:

```zsh
# Safe command execution
z::exec::run "command" [timeout]

# Safe evaluation with security scanning
z::exec::eval "command" [timeout] [force_shell]

# Safe function calling
z::func::call "function_name" "arg1" "arg2"
```

### Path Management

Path resolution and management:

```zsh
# Resolve paths with symlink following
z::path::resolve "~/Documents"

# Add directories to PATH
z::path::add "/usr/local/bin" prepend

# Safe file sourcing
z::path::source "~/.config/script.zsh"
```

### State Management

Safe variable and function cleanup:

```zsh
# Check existence (cached)
z::cmd::exists "git"
z::func::exists "my_function"

# Safe cleanup
z::state::unset "variable_name"
z::var::unset "variable_name"
z::func::unset "function_name"
```

### User Interface

Progress tracking and terminal utilities:

```zsh
# Progress tracking
z::ui::progress::show 5 10 "processing items"

# Terminal utilities
z::ui::term::width
z::ui::progress::clear
```

### Platform Detection

Operating system and environment detection:

```zsh
# Detect platform
z::detect::platform

# Check platform flags
if (( IS_MACOS )); then
    echo "macOS detected"
elif (( IS_LINUX )); then
    echo "Linux detected"
fi
```

## ⚙️ Configuration

### Environment Variables

Control library behavior:

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

## Security Features

- **Input Validation**: Parameter sanitization
- **Pattern Scanning**: Regex-based threat detection
- **Subprocess Isolation**: Commands run in separate processes
- **Timeout Protection**: Prevents resource exhaustion
- **Dangerous Command Detection**: Blocks harmful operations

### Threat Detection

The library detects and blocks:

- File system destruction (`rm -rf`, `sudo rm`)
- Device manipulation (`dd`, `mkfs`)
- Network exploitation (pipe-to-shell patterns)
- Process manipulation (fork bombs, signal abuse)
- Permission escalation (dangerous chmod operations)

## Performance

### Caching System

Caching with LRU eviction:

- **Function existence cache**: Avoids repeated `typeset -f` calls
- **Command existence cache**: Avoids repeated `command -v` calls
- **LRU eviction**: Automatically manages cache size
- **Configurable limits**: Adjust cache size as needed

### Performance Modes

Enable performance mode for faster execution:

```bash
export ZCORE_CONFIG_PERFORMANCE_MODE=true
```

This mode:

- Reduces security scanning overhead
- Skips expensive path resolution
- Minimizes progress display
- Optimizes for high-throughput scenarios

## Platform Support

### Supported Platforms

- **macOS**: Full support with native optimizations
- **Linux**: Complete compatibility including WSL
- **BSD**: FreeBSD, OpenBSD, NetBSD, DragonFly
- **WSL**: Windows Subsystem for Linux
- **Termux**: Android terminal environment
- **Cygwin**: Windows compatibility layer

### Platform Flags

Automatic platform detection sets these flags:

- `IS_MACOS`: macOS/Darwin systems
- `IS_LINUX`: Linux systems
- `IS_BSD`: BSD variants
- `IS_CYGWIN`: Cygwin/MSYS/MinGW
- `IS_WSL`: Windows Subsystem for Linux
- `IS_TERMUX`: Termux on Android
- `IS_UNKNOWN`: Unrecognized platforms

## Testing

Run the test suite:

```bash
# Run all tests
zsh ~/path/to/tests/run.zsh

# Run specific test
zsh ~/path/to/tests/run.zsh test_name
```

## Documentation

- **[Architecture Documentation](docs/ARCHITECTURE.md)**: Detailed technical documentation
- **[Usage Examples](docs/EXAMPLES.md)**: Practical examples for various scripting scenarios
- **[Configuration Guide](docs/CONFIGURATION.md)**: Using ZCore for shell configuration
- **API Reference**: Complete function reference in the architecture docs

## Integration

### Using ZCore in Your Scripts

```zsh
#!/usr/bin/env zsh

# Source ZCore
source /path/to/lib/core.zsh
source /path/to/lib/platform.zsh

# Use ZCore functions
z::log::info "Starting script"
z::detect::platform

if z::cmd::exists "git"; then
    z::exec::run "git status" || z::log::warn "Git command failed"
fi

z::log::info "Script completed"
```

### Using ZCore in Shell Configuration

```zsh
# In your .zshrc
source /path/to/lib/core.zsh
source /path/to/lib/platform.zsh

# Use ZCore for safe operations
z::detect::platform
z::path::add "/usr/local/bin" prepend
z::alias::define "ll" "ls -la"
```

### More Examples

- **[EXAMPLES.md](docs/EXAMPLES.md)**: Comprehensive examples for various scripting scenarios
- **[CONFIGURATION.md](docs/CONFIGURATION.md)**: Detailed guide for shell configuration usage

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

### Development Guidelines

- Follow the existing code style
- Add appropriate error handling
- Include logging for debugging
- Update documentation as needed
- Maintain backward compatibility

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built on the solid foundation of Zsh
- Inspired by modern shell utility practices
- Community-driven development and feedback

## Support

- **Issues**: Report bugs and request features on GitHub
- **Discussions**: Ask questions and share ideas
- **Documentation**:
  - [Architecture docs](docs/ARCHITECTURE.md) for technical details
  - [Examples](docs/EXAMPLES.md) for practical usage
  - [Configuration guide](docs/CONFIGURATION.md) for shell setup

---

**Note**: ZCore includes error handling, security features, and performance optimizations for reliable shell scripting.
