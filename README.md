# Zcore: The Zsh Framework for Robust Scripting

[](https://www.google.com/search?q=https://github.com/your-username/zcore/actions)
[](https://opensource.org/licenses/MIT)

**Zcore** is a modern, safe, and performant framework for advanced Zsh scripting. It provides a comprehensive toolkit to build complex, reliable, and user-friendly command-line applications and automation scripts without reinventing the wheel.

It's designed for script authors who need more than basic shell commands, offering features like a security-conscious command runner, a structured logging system, a high-performance cache, and polished UI components.

-----

## Key Features

* 🛡️ **Safe Execution Engine**: A security-focused command runner with a built-in scanner to block dangerous patterns (`rm -rf /`, pipe-to-shell, etc.), subprocess isolation, and timeout protection.
* ✍️ **Structured Logging**: Leveled logging (`debug`, `info`, `warn`, `error`) with color-coded output, timestamping, and runtime verbosity control.
* 🚀 **Performance Caching**: Blazing fast, in-memory caches for command and function lookups to minimize shell startup time and latency in your scripts.
* 📊 **Interactive UI**: A sleek, efficient progress bar that provides clear user feedback for long-running tasks with minimal performance overhead.
* 💻 **Cross-Platform**: A robust platform detection layer that works seamlessly across **macOS**, **Linux**, **BSD**, and **WSL**.
* 🛠️ **Fluent Helpers**: A rich library of helper functions for filesystem operations, path resolution, state management, and more.

-----

## Quick Start

To use Zcore, simply `source` the `zcore.zsh` file at the top of your script.

```zsh
#!/usr/bin/env zsh

# It's recommended to use an absolute path in production scripts.
source "/path/to/zcore.zsh" || exit 1

# Start using the framework immediately.
z::log::info "Zcore is loaded and ready!"

# Safely run a command.
z::exec::run "ls -l"
```

-----

## Usage at a Glance

Zcore's API is fully namespaced under `z::` for clarity and to prevent conflicts.

### Logging

```zsh
z::log::info "Starting deployment..."
z::log::warn "Configuration file is deprecated."
z::log::debug "Connecting to server 'mars.local'..." # Only shows in debug mode
z::log::error "Deployment failed: Connection refused."
```

### Safe Execution

```zsh
# Run a simple command with a 60-second timeout
if z::exec::run "git clone https://github.com/some/repo.git" 60; then
  z::log::info "Repository cloned successfully."
else
  z::log::error "Failed to clone repository. Exit code: $?"
fi
```

### Progress Bar

```zsh
local -i total_files=300
z::log::info "Processing ${total_files} files..."

for i in {1..$total_files}; do
  z::runtime::check_interrupted || break # Allow user to cancel with Ctrl+C
  sleep 0.05 # Simulate work
  z::ui::progress::show $i $total_files "files"
done
```

-----

## Configuration

Zcore can be configured using environment variables or at runtime.

**Via Environment Variables:**

```bash
# Run your script with debug logging enabled
zcore_config_verbose=3 ./my_script.zsh

# Run in performance mode to disable some expensive checks
ZCORE_CONFIG_PERFORMANCE_MODE=true ./my_script.zsh
```

**At Runtime:**

```zsh
# Set a custom timeout for all z::exec calls
z::config::set "timeout_default" "120" # 2 minutes

# Disable the progress bar for a specific part of the script
z::config::set "show_progress" "false"
```

-----

## Documentation

For a deep dive into the framework, see the detailed documentation:

* **[Usage and Examples](https://www.google.com/search?q=./docs/usage_and_examples.md)**: A practical guide with common use cases.
* **[Full API Reference](https://www.google.com/search?q=./docs/API.md)**: A complete reference for every public and internal function.
* **[Architecture Deep Dive](https://www.google.com/search?q=./docs/architecture.md)**: An explanation of the internal design and patterns.

-----

## Contributing

Contributions are welcome\! Please feel free to submit a pull request or open an issue.

-----

## License

This project is licensed under the MIT License. See the [LICENSE](https://www.google.com/search?q=./LICENSE) file for details.
