# ZCORE: The Zsh SDK for Secure, Modular, and Deterministic Shell Environments

[![Build Status](https://img.shields.io/github/actions/workflow/status/your-username/zcore/ci.yml?branch=main&style=for-the-badge)](https://github.com/your-username/zcore/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)
[![Language: Zsh](https://img.shields.io/badge/language-Zsh-blue.svg?style=for-the-badge)](https://www.zsh.org/)

**ZCORE** is a complete Software Development Kit (SDK) and runtime for Zsh, designed for building professional-grade, modular, and secure shell environments. It replaces fragile, monolithic shell scripts with a robust, engineered system, providing the power of a modern development framework directly in your terminal.

It is built for developers, DevOps engineers, and AI researchers who demand reliability, security, and maintainability from their shell automation, their personal dotfiles, and the sandboxed environments they provision for AI agents.

---

## The Three Pillars of ZCORE

ZCORE is a fully integrated system built on three core pillars that work together to provide a complete solution.

### 1. The Robust SDK Core: A Foundation of Safety and Performance

The heart of ZCORE is a rich, low-level API that provides the building blocks for all other functionality.

*   🛡️ **Safe Execution Engine**: A security-first command runner with a built-in scanner that blocks catastrophic patterns (`rm -rf /`, `dd`, pipe-to-shell). It provides subprocess isolation, timeout protection, and controlled `eval` for trusted inputs.
*   ✍️ **Structured Logging**: Rich, leveled logging (`debug`, `info`, `warn`, `error`) with timestamps, color-coding, and runtime verbosity control, providing a clear audit trail for complex operations.
*   🚀 **High-Performance Caching**: A sophisticated LRU caching subsystem for command (`$+commands`) and function (`$+functions`) lookups, drastically reducing latency in repetitive tasks and speeding up conditional logic.
*   📊 **Polished UI Components**: A sleek, efficient progress bar and other UI helpers provide clear user feedback for long-running tasks with minimal performance overhead.
*   💻 **Cross-Platform API**: A rich set of helpers for path resolution, state management, and system introspection that abstracts away the differences between **macOS**, **Linux**, **BSD**, and **WSL**.

### 2. The Integrated Plugin System: Extensible and Dependency-Aware

ZCORE includes a powerful, manifest-driven plugin manager, enabling you to build complex applications with a clean, modular architecture.

*   📦 **Manifest-Driven Plugins**: Define plugins with a simple `plugin.zsh-plugin` file, specifying name, version, entry points, and dependencies.
*   🔗 **Advanced Dependency Resolution**: Automatically resolves dependencies between plugins using a topological sort to ensure correct load order. It can also validate that required external commands (e.g., `git`, `kubectl`) are present.
*   훅 **Lifecycle Hooks**: Plugins can hook into the ZCORE lifecycle with functions like `on_load`, `on_unload`, and `on_enable`, allowing for clean setup and teardown.
*   📜 **Declarative Management API**: A full suite of `z::plugin::*` commands to discover, load, list, and manage plugins programmatically.

### 3. The Modular Configuration Engine: Dotfiles as Code, Done Right

Leverage the SDK and Plugin System to transform your chaotic `.zshrc` into a clean, maintainable, and deterministic application.

*   🧩 **Orchestrated Loading**: Replace a single, monolithic `.zshrc` with a lean orchestrator that loads self-contained modules in a specific, reliable order.
*   🔧 **Self-Contained Modules**: Encapsulate every piece of your shell's functionality—completions, aliases, Python environment, prompt—into its own module, making your setup easy to debug, modify, and version control.
*   ⏱️ **Performance-Aware Startup**: The entire initialization process is performance-managed, with tools to time startup and identify bottlenecks.

---

## Why Zsh? A Deliberate Choice for Power and Security

ZCORE is built exclusively for the Zsh shell. This is not a limitation, but a deliberate design choice that enables the framework's entire value proposition. Modern Zsh provides advanced programming constructs—such as a built-in lexer, powerful data structures, and robust environment controls (`emulate`)—that are essential for ZCORE's security engine, plugin system, and high-performance APIs. A version for Bash or POSIX sh would be a fundamentally less capable and less secure product.

---

## At a Glance: The ZCORE Workflow

See how the three pillars work together in practice.

**1. Write a self-contained module (e.g., `modules/git.zsh`):**

```zsh
# modules/git.zsh
z::log::info "Initializing Git module..."
z::alias::define "ga" "git add"
z::alias::define "gc" "git commit"
# ... more aliases and functions
```

**2. Define a plugin with a manifest (e.g., `plugins/sysinfo/plugin.zsh-plugin`):**

```yaml
# plugins/sysinfo/plugin.zsh-plugin
name: "zcore-sysinfo"
version: "1.0.0"
entry_point: "sysinfo::init"
dependencies:
  - "uname"
  - "cut"
exports:
  - "sysinfo::show"
```

**3. Use the SDK in a script:**

```zsh
#!/usr/bin/env zsh
source "/path/to/zcore.zsh" || exit 1

# Use the SDK Core
z::log::info "Starting backup..."
local total_files=500
for i in {1..$total_files}; do
  z::runtime::check_interrupted || break
  z::ui::progress::show $i $total_files "files"
  sleep 0.01
done

# Use the Plugin System
z::plugin::load "zcore-sysinfo"
if z::func::exists "sysinfo::show"; then
  sysinfo::show
fi

# Use the Safe Execution Engine
z::exec::run "tar -czf /backups/archive.tar.gz /data" 300
```

---

## Use Cases

| For Developers & DevOps                        | For AI Agents                                  |
|:-----------------------------------------------|:-----------------------------------------------|
| Build complex CLI applications with plugins.   | Provision deterministic, sandboxed shells.     |
| Engineer professional-grade, modular dotfiles. | Enforce safety policies via the `z::exec` API. |
| Create robust, auditable CI/CD automation.     | Create a high-level, observable action space.  |
| Write portable, cross-platform utilities.      | Prevent catastrophic, hallucinated commands.   |

---

## Documentation

For a deep dive into the framework, see the detailed documentation:

*   **[Usage and Examples](./docs/usage_and_examples.md)**: A practical guide with common use cases.
*   **[Full API Reference](./docs/API.md)**: A complete reference for every public function.
*   **[Architecture Deep Dive](./docs/ARCHITECTURE.md)**: An explanation of the internal design and security patterns.

---

## Contributing

Contributions are welcome! Whether you're improving the core, adding examples, or fixing bugs, please feel free to submit a pull request or open an issue.

---

## License

This project is licensed under the MIT License. See the [LICENSE](./LICENSE) file for details.
