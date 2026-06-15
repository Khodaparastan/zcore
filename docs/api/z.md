# z API Reference

> Complete reference for the Zcore integration layer in `z`.
> Public API: `z::cache::*`, `z::config::*`, `z::sys::*`, `z::event::*`,
> `z::debug::*`, `z::help::*`, and `z::probe::cache`.
> Private API: `__z::*`, `_zcore_*` — do not call or depend on them directly.

---

## Table of Contents

1. [Quick Start](#1-quick-start)
2. [Architecture](#2-architecture)
3. [Conventions](#3-conventions)
4. [Constants & Globals](#4-constants--globals)
5. [Initialization](#5-initialization)
6. [Cache](#6-cache)
7. [Configuration](#7-configuration)
8. [System](#8-system)
9. [Event Integration](#9-event-integration)
10. [Debugging](#10-debugging)
11. [Help](#11-help)
12. [Built-in Events](#12-built-in-events)
13. [Dependencies](#13-dependencies)

---

## 1. Quick Start

```zsh
#!/usr/bin/env zsh

# Source prerequisites in dependency order
source ./zlog
source ./zbase
source ./ui      # required for progress/trap paths used by z::sys::*
source ./zkv
source ./zbus    # optional; enables z::event::* wrappers
source ./z

# ── Platform detection ─────────────────────────────────────────
z::sys::platform
(( IS_MACOS )) && echo "Running on macOS"

# ── Configuration ──────────────────────────────────────────────
z::config::get show_progress
local show="$REPLY"          # → true

z::config::set timeout_default 60
z::config::watch "timeout_*" _on_timeout_change

# ── Cache ──────────────────────────────────────────────────────
z::cache::set "app:version" "1.2.3" --ttl 300
local version
version=$(z::cache::get "app:version")

# ── Memoized computation ─────────────────────────────────────────
z::cache::memoize "expensive:result" 60 _compute_expensive arg1

# ── Events (when zbus is loaded) ───────────────────────────────
z::event::on "config:changed" _handle_config_change
z::event::emit "app:ready"

# ── Fatal error handling ─────────────────────────────────────────
z::sys::die "Unrecoverable error" $ZCORE_ERROR_GENERAL
```

---

## 2. Architecture

`z` is the **integration layer** that wires Zcore pillars into a unified
runtime. It does not replace the underlying modules — it adds cross-cutting
facilities on top of them.

| Namespace | Responsibility | Backing store |
|---|---|---|
| `z::cache::*` | In-memory TTL cache with namespace stats | Process-scoped associative arrays |
| `z::config::*` | Typed configuration with watch/save/load | zkv store `config` |
| `z::sys::*` | Platform detection, traps, fatal exits | Cache + global `IS_*` flags |
| `z::event::*` | Thin wrappers over zbus (when loaded) | Delegates to `z::bus::*` |
| `z::debug::*` | Profiling, assertions, stack traces | zkv store `profiling` |
| `z::help::*` | Function discovery | N/A |

**Subsystem flags** (`_zcore_subsys`, internal):

| Key | Set when | Meaning |
|---|---|---|
| `cache` | Always (after `z` loads) | In-memory cache available |
| `kv` | `z::kv::open` present at load | Config store initialized |
| `bus` | `z::bus::emit` present at load | Event integration active |

On load, `z` automatically:

1. Opens the `config` zkv store and writes defaults (only for missing keys)
2. Wires `z::event::*` wrappers when zbus is present
3. Calls `z::bus::init` and emits `zcore:initialized`
4. Installs `INT`/`TERM` traps in interactive shells (or when `ZCORE_INSTALL_TRAPS=true`)

---

## 3. Conventions

| Convention | Meaning |
|---|---|
| `REPLY` | Primary scalar result channel (from `z::config::get`, inherited from zkv) |
| `reply` | Array result channel (from `z::kv::keys` via config helpers) |
| Returns `0` | Success; non-zero on validation failure or error |
| `ZCORE_ERROR_*` | Named error codes — aliases of `ZBASE_ERROR_*` from zbase |
| Cache keys | Use `namespace:field` form (e.g. `ui:term_width`, `sys:platform`) |
| `__z::*` | Private internal function — not part of the public API |
| `_zcore_*` | Private internal variable — not part of the public API |

### Result Convention

`z::config::get` delegates to `z::kv::get` and sets `$REPLY` to the stored value.
Read `$REPLY` immediately after the call.

`z::cache::get` prints the cached value to **stdout** (not `$REPLY`). Capture with
command substitution: `value=$(z::cache::get "key")`.

### Error Codes

| Constant | Value | Meaning |
|---|---|---|
| `ZCORE_SUCCESS` | `0` | Success |
| `ZCORE_ERROR_GENERAL` | `1` | Unspecified failure (alias of `ZBASE_ERROR_GENERAL`) |
| `ZCORE_ERROR_INVALID_INPUT` | `2` | Bad argument type, format, or value |
| `ZCORE_ERROR_NOT_FOUND` | `3` | Cache miss, missing config key, unreadable file |
| `ZCORE_ERROR_PERMISSION` | `4` | Permission or safety check denied |
| `ZCORE_ERROR_TIMEOUT` | `124` | z-specific timeout code |
| `ZCORE_ERROR_INTERRUPTED` | `130` | User interrupt (Ctrl+C) |

---

## 4. Constants & Globals

| Symbol | Type | Description |
|---|---|---|
| `ZCORE_VERSION` | string (`"0.3.0"`) | Framework version |
| `ZCORE_SUCCESS` | integer (`0`) | Success return code |
| `ZCORE_ERROR_TIMEOUT` | integer (`124`) | Timeout return code |
| `ZCORE_ERROR_INTERRUPTED` | integer (`130`) | Interrupt return code |
| `IS_MACOS` | integer | `1` when running on macOS |
| `IS_LINUX` | integer | `1` when running on Linux |
| `IS_BSD` | integer | `1` when running on a BSD variant |
| `IS_CYGWIN` | integer | `1` when running on Cygwin/MSYS/MingW |
| `IS_WSL` | integer | `1` when running Linux under WSL |
| `IS_TERMUX` | integer | `1` when running in Termux on Android |
| `IS_UNKNOWN` | integer | `1` when platform could not be classified |

Platform globals are populated by `z::sys::platform` and cached under the
`sys:*` cache namespace. All default to `0` except `IS_UNKNOWN` which defaults
to `1` until detection runs.

---

## 5. Initialization

`z` initializes automatically when sourced. No explicit init call is required.

**Source order** (enforced by dependency checks and `init` loader):

```zsh
source ./zlog
source ./zbase
source ./ui
source ./zkv
source ./zbus    # optional
source ./z
```

**Environment overrides** applied during config default initialization:

| Variable | Config key | Effect |
|---|---|---|
| `ZCORE_PERFORMANCE_MODE` | `performance_mode` | Override performance mode boolean |
| `ZCORE_SHOW_PROGRESS` | `show_progress` | Override progress bar visibility |
| `ZCORE_PROGRESS_STYLE` | `progress_style` | Override progress bar style |
| `ZCORE_INSTALL_TRAPS` | — | Install `INT`/`TERM` traps in non-interactive shells when `true` |

**Load guard:** Sourcing `z` twice is a no-op (`_zcore_loaded` guard).

**Failure modes:** Missing `zlog`, `zbase`, or `zkv` prints a fatal error to
stderr and aborts with exit/return code `1`.

---

## 6. Cache

Process-scoped in-memory cache with optional TTL, namespace-scoped statistics,
and memoization helper. Keys use a `namespace:field` convention — the portion
before the first `:` is used for stats grouping.

When the event bus is active, cache operations emit built-in events (see
[Built-in Events](#12-built-in-events)).

### `z::cache::set`

Store a value in the cache.

```
z::cache::set <key> <value> [--ttl <seconds>]
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `key` | string | required | Cache key (recommended: `namespace:field`) |
| `value` | string | required | Value to store |
| `--ttl` | integer | `0` (no expiry) | Time-to-live in seconds |

**Returns:** `0` on success; `ZCORE_ERROR_INVALID_INPUT` on missing key or invalid TTL.

**Examples:**

```zsh
z::cache::set "ui:term_width" "120"
z::cache::set "api:token" "$token" --ttl 3600
```

---

### `z::cache::get`

Retrieve a cached value.

```
z::cache::get <key>
```

**Output:** stdout — prints the cached value on hit.

**Returns:** `0` on hit; `ZCORE_ERROR_NOT_FOUND` on miss or expired entry;
`ZCORE_ERROR_INVALID_INPUT` when key is empty.

**Examples:**

```zsh
local width
width=$(z::cache::get "ui:term_width") || width=80

if z::cache::get "api:token" 2>/dev/null; then
  token=$(z::cache::get "api:token")
fi
```

---

### `z::cache::del`

Delete a cache entry and its TTL metadata.

```
z::cache::del <key>
```

**Returns:** `0` on success; `ZCORE_ERROR_INVALID_INPUT` when key is empty.

---

### `z::probe::cache`

Predicate: returns whether a key exists and has not expired.

```
z::probe::cache <key>
```

**Returns:** `0` if the key is present and valid; `1` otherwise.

---

### `z::cache::clear`

Delete all cache entries matching a glob pattern.

```
z::cache::clear [<glob-pattern>]
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `glob-pattern` | string | `*` | zsh glob matched against cache keys |

**Returns:** `0`. Sets no counter — check logs or emit handler for count.

---

### `z::cache::stats`

Print cache hit/miss/write/expired statistics to stdout.

```
z::cache::stats [<namespace>]
```

| Parameter | Type | Description |
|---|---|---|
| `namespace` | string | Optional — show stats for one namespace only |

When omitted, prints stats for all namespaces plus total entry count.

**Returns:** `0`.

---

### `z::cache::memoize`

Call a function and cache its stdout result, returning the cached value on
subsequent calls.

```
z::cache::memoize <cache-key> [<ttl>] <func> [args ...]
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `cache-key` | string | required | Cache key for the result |
| `ttl` | integer | `0` (no expiry) | TTL in seconds |
| `func` | string | required | Name of a defined function to invoke on miss |
| `args` | strings | — | Arguments passed to `func` on miss |

**Output:** stdout — prints the (cached or freshly computed) result.

**Returns:** `0` on success; `ZCORE_ERROR_INVALID_INPUT` on missing key/func;
`ZCORE_ERROR_NOT_FOUND` when func is undefined; propagates func exit code on failure.

**Examples:**

```zsh
_fetch_version() { curl -sf https://api.example.com/version; }

z::cache::memoize "app:version" 300 _fetch_version
# Second call within 300s returns cached value without HTTP request
```

---

## 7. Configuration

KV-backed configuration stored in the zkv `config` handle. Defaults are written
only for keys that do not already exist, so user values persist across sessions
when zkv auto-persist is enabled.

### Default Keys

| Key | Type | Default | Description |
|---|---|---|---|
| `log_level` | int | zlog current level | Console log verbosity |
| `cache_max_size` | int | `100` | Cache size hint |
| `timeout_default` | int | `30` | Default command timeout (seconds) |
| `performance_mode` | bool | `false` | Framework performance mode |
| `show_progress` | bool | `true` | Show progress bars during init |
| `symlink_max_iterations` | int | `40` | Max symlink resolution depth |
| `progress_update_interval` | int | `10` | Progress bar update interval |
| `progress_style` | string | `classic` | Progress bar visual style |

---

### `z::config::get`

Read a configuration value.

```
z::config::get <key>
```

**Returns:** `0` on success. Sets `$REPLY` to the value (and `$REPLY2` to the
stored type name via zkv). Returns zkv error code on failure.

**Examples:**

```zsh
z::config::get show_progress
local show="$REPLY"    # → true
local type="$REPLY2"   # → bool
```

---

### `z::config::set`

Write a configuration value with automatic type coercion.

```
z::config::set <key> <value>
```

Type is inferred from the key name:

| Key pattern | Expected type | Storage |
|---|---|---|
| `*_mode`, `show_*`, `enable_*` | boolean (`true`/`false`) | `z::kv::set_bool` |
| `*_size`, `*_timeout`, `*_depth`, `*_threshold`, `*_interval`, `*_iterations`, `*_level` | integer | `z::kv::set_int` |
| everything else | string | `z::kv::set` |

**Returns:** `0` on success; `ZCORE_ERROR_INVALID_INPUT` on type mismatch or
empty key.

Emits `config:changed` on the event bus when active.

**Examples:**

```zsh
z::config::set show_progress false
z::config::set timeout_default 120
z::config::set progress_style "minimal"
```

---

### `z::config::watch`

Register a zkv change watcher on the config store.

```
z::config::watch <pattern> <handler-func>
```

Delegates to `z::kv::watch config`. The handler is invoked by zkv when a
matching key changes.

**Returns:** zkv return code.

---

### `z::config::show`

Print all configuration key/value pairs to stdout in a formatted table.

```
z::config::show
```

**Returns:** `0`.

---

### `z::config::save`

Export configuration to a `key=value` file.

```
z::config::save <file>
```

**Returns:** `0` on success; `ZCORE_ERROR_INVALID_INPUT` when path is empty.

---

### `z::config::load`

Import configuration from a `key=value` file. Lines starting with `#` and blank
lines are skipped. Each pair is applied via `z::config::set` (with type coercion).

```
z::config::load <file>
```

**Returns:** `0` on success; `ZCORE_ERROR_INVALID_INPUT` when path is empty;
`ZCORE_ERROR_NOT_FOUND` when the file is missing or unreadable.

Individual key failures are logged as warnings but do not abort the load.

---

## 8. System

### `z::sys::platform`

Detect the current platform and populate global `IS_*` flags. Results are
cached under `sys:*` keys — subsequent calls restore from cache without
re-detection.

```
z::sys::platform
```

**Detection order:**

1. Cache hit → restore `IS_*` flags from `sys:is_*` cache entries
2. `$OSTYPE` (with `uname -s` fallback)
3. WSL detection (Linux only): `$WSL_DISTRO_NAME`, `$WSLENV`, `/proc/version`
4. Termux detection (Linux only): `/data/data/com.termux/files/usr`

**Platform names:** `macos`, `linux`, `bsd`, `cygwin`, `unknown`

**Returns:** `0`.

Emits `sys:platform_detected` on the event bus when active.

**Examples:**

```zsh
z::sys::platform
if (( IS_MACOS && ! IS_WSL )); then
  echo "Native macOS"
fi
```

---

### `z::sys::is_macos`

### `z::sys::is_linux`

### `z::sys::is_bsd`

### `z::sys::is_wsl`

Platform predicate shortcuts. Each calls `z::sys::platform` then returns the
inverse of the corresponding `IS_*` flag.

```
z::sys::is_macos
z::sys::is_linux
z::sys::is_bsd
z::sys::is_wsl
```

**Returns:** `0` if the platform matches; `1` otherwise.

---

### `z::sys::interrupted`

Check whether the user has sent an interrupt (Ctrl+C).

```
z::sys::interrupted
```

**Returns:** `0` if no interrupt; `ZCORE_ERROR_INTERRUPTED` (`130`) if the
interrupt trap has fired.

Use in long-running loops to exit gracefully after the first interrupt warning.

---

### `z::sys::die`

Log a fatal error and terminate.

```
z::sys::die <message> [<exit-code>]
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `message` | string | required | Error message logged at ERROR level |
| `exit-code` | integer | `$ZCORE_ERROR_GENERAL` | Exit/return code |

Clears any active progress bar before exiting. Returns (does not exit) when
sourced in a file context; calls `exit` otherwise.

**Returns/Exits:** Does not return in script context — calls `exit <code>`.
Returns `<code>` when sourced.

---

## 9. Event Integration

When `zbus` is sourced before `z`, thin `z::event::*` wrappers are installed
over the corresponding `z::bus::*` functions. This keeps subsystem code
decoupled from the bus module namespace.

| Wrapper | Delegates to |
|---|---|
| `z::event::emit` | `z::bus::emit` |
| `z::event::emit_safe` | `z::bus::emit_safe` |
| `z::event::emit_async` | `z::bus::emit_async` |
| `z::event::on` | `z::bus::on` |
| `z::event::once` | `z::bus::once` |
| `z::event::off` | `z::bus::off` |
| `z::event::off_id` | `z::bus::off_id` |
| `z::event::has` | `z::bus::has` |
| `z::event::subscribe` | `z::bus::subscribe` |
| `z::event::unsubscribe` | `z::bus::unsubscribe` |
| `z::event::publish` | `z::bus::publish` |

All wrappers pass arguments through unchanged. See [zbus API Reference](zbus.md)
for full semantics, return codes, and handler contracts.

When zbus is **not** loaded, `z::event::*` functions are undefined and
`_zcore_subsys[bus]` remains `0`. All internal event emissions are guarded and
silently skipped.

---

## 10. Debugging

### `z::debug::trace`

Print the current function call stack to stderr.

```
z::debug::trace
```

**Returns:** `0`.

---

### `z::debug::dump`

Print the full configuration table (alias for `z::config::show`).

```
z::debug::dump
```

**Returns:** `0`.

---

### `z::debug::profile_start`

Record a high-resolution start timestamp for a named operation.

```
z::debug::profile_start [<operation>]
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `operation` | string | `operation` | Profile session name |

Opens the ephemeral zkv `profiling` store and writes `{operation}.start`.

**Returns:** `0` on success; `ZCORE_ERROR_GENERAL` if the profiling store cannot be opened.

---

### `z::debug::profile_end`

Compute elapsed time for a named operation and log the result.

```
z::debug::profile_end [<operation>]
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `operation` | string | `operation` | Must match the name passed to `profile_start` |

Writes `{operation}.end` and `{operation}.duration` to the profiling store.
Emits `debug:profile` on the event bus when active.

**Returns:** `0` on success; `ZCORE_ERROR_NOT_FOUND` when no start time exists.

**Examples:**

```zsh
z::debug::profile_start "module_load"
source ./heavy_module.zsh
z::debug::profile_end "module_load"
# DEBUG: Profiling for operation: module_load finished in: 0.342s
```

---

### `z::debug::assert`

Assert a condition or terminate with a stack trace.

```
z::debug::assert <condition> [<message>]
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `condition` | integer | `1` (fail) | `0` = pass; any non-zero = fail |
| `message` | string | `Assertion failed` | Message passed to `z::sys::die` |

On failure: prints stack trace via `z::debug::trace`, then calls
`z::sys::die` with `$ZCORE_ERROR_GENERAL`.

**Returns:** `0` when condition is `0`.

---

## 11. Help

### `z::help::list`

List public function names matching a namespace prefix.

```
z::help::list [<namespace>]
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `namespace` | string | `z::` | Function name prefix to match |

Functions containing `::_` (private/internal) are excluded.

**Output:** stdout — one function name per line.

**Returns:** `0`.

---

### `z::help::quick`

Print a quick-reference header to stdout. Currently outputs the title banner
only — extend as needed.

```
z::help::quick
```

**Returns:** `0`.

---

## 12. Built-in Events

When the event bus is active (`_zcore_subsys[bus] == 1`), `z` emits these
events automatically. Subscribe with `z::event::on`.

| Event | Emitted by | Arguments |
|---|---|---|
| `zcore:initialized` | Init (once at load) | `$ZCORE_VERSION` |
| `zcore:session_ready` | Interactive init (after modules) | `$ZCORE_VERSION` |
| `cache:set` | `z::cache::set` | `key`, `value` |
| `cache:hit` | `z::cache::get` | `key` |
| `cache:miss` | `z::cache::get` | `key`, reason (`expired` \| `not_found`) |
| `cache:delete` | `z::cache::del` | `key` |
| `cache:cleared` | `z::cache::clear` | `pattern`, `count` |
| `config:changed` | `z::config::set` | `key`, `value` |
| `sys:platform_detected` | `z::sys::platform` | platform name |
| `sys:interrupted` | Interrupt trap | — |
| `debug:profile` | `z::debug::profile_end` | `operation`, `duration` (seconds) |

---

## 13. Dependencies

| Dependency | Required | Used for |
|---|---|---|
| `zlog` | Yes | All `z::log::*` calls (must be sourced first) |
| `zbase` | Yes | `ZCORE_ERROR_*` aliases, validation indirectly via zkv |
| `ui` | Yes* | `z::progress::clear` in trap and die paths |
| `zkv` | Yes | Config store, profiling store |
| `zbus` | No | Event integration via `z::event::*` wrappers |
| `zsh/datetime` | Optional | `$EPOCHSECONDS` / `$EPOCHREALTIME` for TTL and profiling |

\* `ui` is not checked at load time but is required at runtime for interrupt
and fatal-exit paths. The framework `init` loader always sources `ui` before `z`.

**Source order:**

```zsh
source ./zlog
source ./zbase
source ./ui
source ./zkv
source ./zbus    # optional
source ./z
```

**Framework init:** In a full Zcore shell, all of the above is handled by
`init` via `z::interactive::load_libs`.

---

## Function & Constant Index

| Symbol | Category | Description |
|---|---|---|
| `ZCORE_VERSION` | Constants | Framework version (`0.3.0`) |
| `ZCORE_SUCCESS` | Constants | Success return code (`0`) |
| `ZCORE_ERROR_TIMEOUT` | Constants | Timeout return code (`124`) |
| `ZCORE_ERROR_INTERRUPTED` | Constants | Interrupt return code (`130`) |
| `IS_MACOS` … `IS_UNKNOWN` | Globals | Platform detection flags |
| `z::cache::set` | Cache | Store value with optional TTL |
| `z::cache::get` | Cache | Retrieve value (stdout) |
| `z::cache::del` | Cache | Delete entry |
| `z::probe::cache` | Cache | Key-exists predicate |
| `z::cache::clear` | Cache | Delete entries by glob |
| `z::cache::stats` | Cache | Print hit/miss statistics |
| `z::cache::memoize` | Cache | Cache function result |
| `z::config::get` | Config | Read config value → `$REPLY` |
| `z::config::set` | Config | Write typed config value |
| `z::config::watch` | Config | Register change watcher |
| `z::config::show` | Config | Print all config |
| `z::config::save` | Config | Export to file |
| `z::config::load` | Config | Import from file |
| `z::sys::platform` | System | Detect platform, set `IS_*` |
| `z::sys::is_macos` | System | macOS predicate |
| `z::sys::is_linux` | System | Linux predicate |
| `z::sys::is_bsd` | System | BSD predicate |
| `z::sys::is_wsl` | System | WSL predicate |
| `z::sys::interrupted` | System | Interrupt-check predicate |
| `z::sys::die` | System | Fatal error + exit |
| `z::event::emit` | Events | Dispatch event (zbus wrapper) |
| `z::event::emit_safe` | Events | Safe dispatch (zbus wrapper) |
| `z::event::emit_async` | Events | Async dispatch (zbus wrapper) |
| `z::event::on` | Events | Subscribe handler (zbus wrapper) |
| `z::event::once` | Events | One-shot handler (zbus wrapper) |
| `z::event::off` | Events | Unsubscribe (zbus wrapper) |
| `z::event::off_id` | Events | Unsubscribe by ID (zbus wrapper) |
| `z::event::has` | Events | Handler-exists predicate (zbus wrapper) |
| `z::event::subscribe` | Events | Pub/sub subscribe (zbus wrapper) |
| `z::event::unsubscribe` | Events | Pub/sub unsubscribe (zbus wrapper) |
| `z::event::publish` | Events | Pub/sub publish (zbus wrapper) |
| `z::debug::trace` | Debug | Print call stack |
| `z::debug::dump` | Debug | Print configuration |
| `z::debug::profile_start` | Debug | Start profiler |
| `z::debug::profile_end` | Debug | End profiler |
| `z::debug::assert` | Debug | Assert or die |
| `z::help::list` | Help | List public functions |
| `z::help::quick` | Help | Quick reference banner |
