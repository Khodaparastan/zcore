# zbus API Reference

> Complete reference for all public-facing functions and constants in `zbus`.
> Every symbol prefixed `z::bus::` or `ZBUS_` is part of the stable public API.
> Symbols prefixed `_z::bus::` or `_zbus_` are private internals — do not call or
> depend on them directly.

---

## Table of Contents

1. [Quick Start](#1-quick-start)
2. [Architecture](#2-architecture)
3. [Conventions](#3-conventions)
4. [Constants](#4-constants)
5. [Initialization](#5-initialization)
6. [Subscriptions](#6-subscriptions)
7. [Dispatch](#7-dispatch)
8. [Introspection](#8-introspection)
9. [History](#9-history)
10. [Statistics](#10-statistics)
11. [Configuration](#11-configuration)
12. [Performance Mode](#12-performance-mode)
13. [Pub/Sub Channels](#13-pubsub-channels)
14. [Reset & Cleanup](#14-reset--cleanup)
15. [Handler Contract](#15-handler-contract)
16. [Dependencies](#16-dependencies)

---

## 1. Quick Start

```zsh
#!/usr/bin/env zsh

# zlog, zbase, and zkv must be sourced first (in that order)
source ./zlog
source ./zbase
source ./zkv
source ./zbus

# ── Initialize (lazy-init also works on first public call) ─────
z::bus::init

# ── Subscribe to events ────────────────────────────────────────
_my_handler() {
  local event="$1"; shift
  echo "got $event with args: $*"
}
z::bus::on "user.login" _my_handler --priority 75
z::bus::once "app.ready" _startup_handler

# Wildcard subscription
z::bus::on "user.*" _user_event_handler

# ── Emit events ────────────────────────────────────────────────
z::bus::emit "user.login" "alice" "192.168.1.1"
z::bus::emit_safe "risky.operation"   # isolated subshell per handler
z::bus::emit_async "background.task" # returns PID via REPLY
z::bus::wait_all_async

# ── Pub/sub channels (separate from the event system) ──────────
z::bus::subscribe "notifications" _notify_handler
z::bus::publish "notifications" "Server restarted"

# ── Introspection ──────────────────────────────────────────────
z::bus::has "user.login"     # predicate: any handlers?
z::bus::count "user.login"   # REPLY → handler count
z::bus::list                 # formatted table to stdout
z::bus::history 10           # last 10 emissions
z::bus::stats
```

---

## 2. Architecture

`zbus` is a process-scoped, in-memory event bus with priority-ordered dispatch,
wildcard subscriptions, a ring-buffer history, per-event statistics, and a
separate pub/sub channel layer.

| Component | Storage | Scope |
|---|---|---|
| Handler registry | `_zbus_handlers_exact`, `_zbus_handlers_wildcard`, `_zbus_handler_meta` | Process |
| Pub/sub channels | `_zbus_channels` | Process |
| History ring buffer | `_zbus_history_ring` | Process |
| Statistics | `_zbus_stats` | Process |
| Configuration | `__zbus` zkv store | Process (persisted if zkv auto-persist enabled) |

**Dispatch modes**

| Mode | Function | Handler isolation | Side effects visible to caller |
|---|---|---|---|
| Sync | `z::bus::emit` | None — runs in current shell | Yes |
| Safe | `z::bus::emit_safe` | Subshell + watchdog per handler | No |
| Async | `z::bus::emit_async` | Background job (sync dispatch inside) | No |

**Lazy initialization:** Every public entry point calls `_z::bus::ensure_init`,
which invokes `z::bus::init` on first use if the bus has not been initialized.

---

## 3. Conventions

| Convention | Meaning |
|---|---|
| `event` | Event name or wildcard pattern. Allowed chars: `a-z A-Z 0-9 _ : * . -` |
| `channel` | Pub/sub channel name. Any non-empty string |
| `handler-func` | Name of a defined zsh function. Must exist at subscription time |
| `handler-id` | Opaque ID returned by `z::bus::on` (format: `zbus_h_<n>`) |
| `REPLY` | Primary scalar result channel |
| `reply` | Array result channel (handler ID lists) |
| `REPLY2` | Secondary scalar; used internally by safe dispatch (`ok` / `fail` / `timeout`) |
| Returns `0` | Success; non-zero on validation failure or partial handler failure |
| `ZBASE_ERROR_*` | Named error codes from `zbase` (required dependency) |
| `_z::bus::*` | Private internal function — not part of the public API |
| `_zbus_*` | Private internal variable — not part of the public API |

### Result Convention

Read `REPLY`, `reply`, and `REPLY2` **immediately** after each call. Subsequent
`z::bus::*` calls may overwrite them.

### Error Codes

| Constant | Typical zbus usage |
|---|---|
| `ZBASE_ERROR_INVALID_INPUT` | Bad event name, missing argument, out-of-range config value |
| `ZBASE_ERROR_NOT_FOUND` | Unknown handler ID, no handlers removed by `z::bus::off`, unknown config key |
| `ZBASE_ERROR_PERMISSION` | Handler limit reached per event, async PID cap exceeded |
| `ZBASE_ERROR_GENERAL` | zkv store open failure during init |

---

## 4. Constants

| Constant | Value | Description |
|---|---|---|
| `ZBUS_VERSION` | `3` | Module version integer |
| `ZBUS_PRIORITY_HIGHEST` | `100` | Named priority for `z::bus::on --priority` |
| `ZBUS_PRIORITY_HIGH` | `75` | Named priority |
| `ZBUS_PRIORITY_NORMAL` | `50` | Default priority when `--priority` is omitted |
| `ZBUS_PRIORITY_LOW` | `25` | Named priority |
| `ZBUS_PRIORITY_LOWEST` | `0` | Named priority |

All are declared `typeset -gri` (global, readonly integer).

Priority values must be in the range `0`–`100`. Handlers with higher priority
values run first during dispatch.

---

## 5. Initialization

### `z::bus::init`

Open the internal `__zbus` zkv store, write default configuration (via `setnx` so
persisted values are preserved), apply any option overrides, and populate the
in-memory config cache.

```
z::bus::init [options...]
```

| Option | Type | Default | Description |
|---|---|---|---|
| `--max-history` | integer `0..1000000` | `100` | Ring buffer capacity for event history |
| `--handler-timeout` | integer `1..86400` | `5` | Per-handler timeout in seconds for `emit_safe` |
| `--max-handlers` | integer `1..100000` | `50` | Maximum handlers per event/pattern |
| `--disable-history` | flag | — | Disable history recording |
| `--disable-stats` | flag | — | Disable per-event statistics |
| `--disable-wildcards` | flag | — | Disable wildcard pattern matching |
| `--reset` | flag | — | Clear all handlers, channels, history, and stats before applying options |

**Returns:** `0` on success; `ZBASE_ERROR_GENERAL` if the zkv store cannot be opened;
`ZBASE_ERROR_INVALID_INPUT` on invalid option values.

Unknown options are logged as warnings and skipped.

**Examples:**

```zsh
z::bus::init
z::bus::init --max-history 500 --handler-timeout 10
z::bus::init --disable-wildcards --disable-stats
z::bus::init --reset
```

---

## 6. Subscriptions

### `z::bus::on`

Register a handler function for an event name or wildcard pattern.

```
z::bus::on <event> <handler-func> [--priority <0-100>] [--once]
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `event` | string | required | Exact event name or glob pattern containing `*` |
| `handler-func` | string | required | Name of a defined function |
| `--priority` | integer `0..100` | `50` (`ZBUS_PRIORITY_NORMAL`) | Dispatch order; higher runs first |
| `--once` | flag | — | Remove handler after first successful dispatch |

**Returns:** `0` on success. Sets `$REPLY` to the opaque handler ID.

**Errors:**

| Code | Condition |
|---|---|
| `ZBASE_ERROR_INVALID_INPUT` | Invalid event name or priority |
| `ZBASE_ERROR_NOT_FOUND` | Handler function not defined |
| `ZBASE_ERROR_PERMISSION` | Handler limit (`max_handlers_per_event`) reached |

**Examples:**

```zsh
z::bus::on "order.placed" _handle_order --priority $ZBUS_PRIORITY_HIGH
z::bus::on "user.*" _handle_user_event
z::bus::on "deploy.done" _cleanup --once
local hid="$REPLY"   # e.g. zbus_h_3
```

---

### `z::bus::once`

Convenience wrapper that registers a handler with `--once`.

```
z::bus::once <event> <handler-func> [options...]
```

Accepts the same options as `z::bus::on` (except `--once`, which is implicit).
Returns the handler ID via `$REPLY`.

---

### `z::bus::off`

Remove handlers matching an event pattern.

```
z::bus::off <event-pattern> [handler-func]
```

| Parameter | Type | Description |
|---|---|---|
| `event-pattern` | string | Matches registered exact names and wildcard patterns |
| `handler-func` | string | Optional — remove only handlers with this function name |

**Returns:** `0` if at least one handler was removed. Sets `$REPLY` to the count
of removed handlers. Returns `ZBASE_ERROR_NOT_FOUND` when nothing matched.

**Examples:**

```zsh
z::bus::off "user.*"              # remove all handlers for matching patterns
z::bus::off "order.placed" _handle_order   # remove only _handle_order
z::bus::off "evt"
echo "removed $REPLY handler(s)"
```

---

### `z::bus::off_id`

Remove a single handler by its opaque ID.

```
z::bus::off_id <handler-id>
```

**Returns:** `0` on success; `ZBASE_ERROR_INVALID_INPUT` if ID is empty;
`ZBASE_ERROR_NOT_FOUND` if the ID is unknown.

---

## 7. Dispatch

All dispatch functions record the emission in history (when enabled) and update
statistics (when enabled) before invoking handlers. Handlers are collected from
exact matches and matching wildcard patterns, then sorted by priority descending.

### `z::bus::emit`

Synchronous dispatch. Handlers run in the current shell process in priority order.
Handler side effects (variable mutations, directory changes) **are** visible to the caller.

```
z::bus::emit <event> [args ...]
```

| Parameter | Type | Description |
|---|---|---|
| `event` | string | Event name to dispatch |
| `args` | strings | Optional arguments passed to each handler after the event name |

**Returns:** `0` if all handlers succeeded; non-zero if any handler failed.
Sets `$REPLY` to the number of failed handlers.

**Handler invocation:** `"$handler_func" "$event" "$@"`

**Examples:**

```zsh
z::bus::emit "user.login" "alice"
z::bus::emit "config.changed" "theme" "dark"

z::bus::emit "risky.event" || {
  echo "$REPLY handler(s) failed"
}
```

---

### `z::bus::emit_safe`

Safe dispatch. Each handler runs in a forked subshell with a watchdog timer
(`handler_timeout` seconds). A two-stage kill is used: `SIGTERM`, then `SIGKILL`
after a 1-second grace period.

Handler side effects do **not** propagate to the caller. Timeout detection uses
elapsed wall-clock time to avoid misclassifying handlers that exit with code 143
or 137 for unrelated reasons.

```
z::bus::emit_safe <event> [args ...]
```

**Returns:** Same as `z::bus::emit` — `0` if all succeeded; `$REPLY` = failed count
(including timeouts).

**Examples:**

```zsh
z::bus::emit_safe "untrusted.plugin.event" "$payload"
z::bus::emit_safe "long.running.task" || echo "$REPLY failures"
```

---

### `z::bus::emit_async`

Background the entire dispatch as a forked job. The background job runs
`z::bus::emit` (sync mode) with a snapshot of the current handler registry.

```
z::bus::emit_async <event> [args ...]
```

**Returns:** `0` on success. Sets `$REPLY` to the PID of the background dispatcher.
Returns `ZBASE_ERROR_PERMISSION` when the async PID cap (200) is reached.

Handler exit codes and side effects are **not** observable by the caller. Use
`z::bus::wait_all_async` to block until all async jobs complete.

**Examples:**

```zsh
z::bus::emit_async "background.index" "/data"
local pid="$REPLY"

z::bus::emit_async "task.a"
z::bus::emit_async "task.b"
z::bus::wait_all_async || echo "some async dispatch failed"
```

---

### `z::bus::wait_all_async`

Block until all tracked async dispatch PIDs have completed. Clears the PID list
when done.

```
z::bus::wait_all_async
```

**Returns:** `0` if all jobs succeeded. Returns the exit code of the last failed
job otherwise. Exit code `127` (already reaped) is not counted as a failure.

---

## 8. Introspection

### `z::bus::has`

Predicate: returns whether at least one handler is registered for an event,
including handlers from matching wildcard patterns.

```
z::bus::has <event-name>
```

**Returns:** `0` if handlers exist; `1` if none.

---

### `z::bus::count`

Return the total number of handlers applicable to an event.

```
z::bus::count <event-name>
```

**Returns:** `0`. Sets `$REPLY` to the handler count.

---

### `z::bus::handlers`

Return handler IDs for an event, sorted by priority descending.

```
z::bus::handlers <event-name>
```

**Returns:** `0`. Populates the `reply` array with handler IDs.

**Example:**

```zsh
z::bus::handlers "user.login"
for hid in "${reply[@]}"; do
  echo "handler: $hid"
done
```

---

### `z::bus::list`

Print a formatted table of all registered event handlers to stdout.

```
z::bus::list [<glob-filter>]
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `glob-filter` | string | `*` | Filter registered event patterns |

Handlers are shown in priority order per event. Output includes function name,
handler ID, priority, and `[once]` marker when applicable.

**Returns:** `0`.

---

## 9. History

Event history is stored in a fixed-size ring buffer. Each entry records the epoch
timestamp, event name, and space-separated arguments.

History is disabled when `enable_history` is `false` or when performance mode is
active.

### `z::bus::history`

Print the most recent history entries to stdout.

```
z::bus::history [<limit>] [<glob-filter>]
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `limit` | integer | `20` | Maximum entries to display |
| `glob-filter` | string | — | Optional glob filter on event names |

Entries are shown newest-first with formatted timestamps and argument lists.

**Returns:** `0`.

---

### `z::bus::clear_history`

Reset the history ring buffer to empty.

```
z::bus::clear_history
```

**Returns:** `0`.

---

## 10. Statistics

Per-event counters are tracked in memory when `enable_stats` is enabled (and
performance mode is off).

| Counter | Incremented when |
|---|---|
| `emitted` | Event is dispatched |
| `handled` | Handler completes successfully |
| `failed` | Handler returns non-zero or times out |
| `timeout` | Handler exceeds `handler_timeout` in safe mode |

### `z::bus::stats`

Print per-event operation counters to stdout.

```
z::bus::stats [<substring-filter>]
```

| Parameter | Type | Description |
|---|---|---|
| `substring-filter` | string | Optional — show only events whose name contains this substring |

**Returns:** `0`.

---

### `z::bus::clear_stats`

Reset all per-event operation counters to zero.

```
z::bus::clear_stats
```

**Returns:** `0`.

---

## 11. Configuration

Configuration is persisted in the internal `__zbus` zkv store and cached in memory
for hot-path access. Values written via `z::bus::init` options or
`z::bus::config` survive process restarts when zkv auto-persist is enabled for
the store.

### Config Keys

| Key | Type | Default | Description |
|---|---|---|---|
| `max_history` | integer `0..1000000` | `100` | Ring buffer capacity |
| `handler_timeout` | integer `1..86400` | `5` | Safe-mode timeout in seconds |
| `max_handlers_per_event` | integer `1..100000` | `50` | Handler limit per event/pattern |
| `enable_history` | boolean | `true` | Record emissions in the ring buffer |
| `enable_stats` | boolean | `true` | Track per-event counters |
| `enable_wildcards` | boolean | `true` | Match `*` glob patterns in subscriptions |

Boolean values accept `true`/`false`, `1`/`0`, `yes`/`no`, `on`/`off`
(case-insensitive) when read from the zkv store.

---

### `z::bus::config`

Update a single configuration parameter. Persists to zkv and refreshes the
in-memory cache.

```
z::bus::config <key> <value>
```

**Returns:** `0` on success; `ZBASE_ERROR_INVALID_INPUT` on bad value;
`ZBASE_ERROR_NOT_FOUND` on unknown key.

When `max_history` is reduced below the current entry count, the history ring
is cleared.

**Examples:**

```zsh
z::bus::config handler_timeout 10
z::bus::config max_history 500
z::bus::config enable_wildcards false
```

---

### `z::bus::get_config`

Read a configuration parameter.

```
z::bus::get_config <key>
```

**Returns:** `0`. Sets `$REPLY` to the current value. Boolean keys return
`"true"` or `"false"`.

---

### `z::bus::show_config`

Print all configuration parameters and runtime state to stdout.

```
z::bus::show_config
```

Includes `performance_mode` and `async_pids_in_flight` (current count / cap of 200).

**Returns:** `0`.

---

## 12. Performance Mode

Performance mode suspends history recording and statistics updates on the emit
hot path. Handler dispatch and wildcard matching are unaffected.

The in-memory flags are modified directly; the zkv store is **not** updated.
Disabling performance mode restores the persisted values from zkv.

### `z::bus::enable_performance_mode`

```
z::bus::enable_performance_mode
```

**Returns:** `0`.

---

### `z::bus::disable_performance_mode`

```
z::bus::disable_performance_mode
```

**Returns:** `0`. Restores `enable_history` and `enable_stats` from zkv.

---

## 13. Pub/Sub Channels

Lightweight synchronous message passing, separate from the event handler system.
No priority ordering, no history, no statistics. Duplicate `(channel, handler)`
pairs are silently ignored.

### `z::bus::subscribe`

Register a handler to receive messages on a channel.

```
z::bus::subscribe <channel> <handler-func>
```

**Returns:** `0` on success; `ZBASE_ERROR_INVALID_INPUT` if channel is empty;
`ZBASE_ERROR_NOT_FOUND` if handler is not defined.

---

### `z::bus::unsubscribe`

Remove a handler from a channel, or all handlers if no function is specified.

```
z::bus::unsubscribe <channel> [handler-func]
```

**Returns:** `0` on success; `ZBASE_ERROR_NOT_FOUND` if channel or handler
not found (when a specific handler is given).

---

### `z::bus::publish`

Deliver a message to all handlers subscribed to a channel.

```
z::bus::publish <channel> <message>
```

Handlers are invoked as: `"$handler" "$channel" "$message"`

Stale handlers (no longer defined) are logged once and skipped. Non-zero handler
exit codes are rate-limited in the log but do not fail the publish call.

**Returns:** `0` (even when there are no subscribers).

**Examples:**

```zsh
_on_notify() {
  local channel="$1" message="$2"
  echo "[$channel] $message"
}

z::bus::subscribe "alerts" _on_notify
z::bus::publish "alerts" "Disk usage above 90%"
z::bus::unsubscribe "alerts" _on_notify
```

---

## 14. Reset & Cleanup

### `z::bus::reset`

Clear all handlers, channels, history, stats, and async state. Marks the bus as
uninitialized so the next public call triggers a fresh `z::bus::init`.

```
z::bus::reset
```

Can also be invoked via `z::bus::init --reset`.

**Returns:** `0`.

Does **not** delete the zkv configuration store — persisted config values remain
and are reloaded on the next init.

---

## 15. Handler Contract

### Event handlers

Registered via `z::bus::on`, `z::bus::once`, or `z::bus::off_id`.

```zsh
my_handler() {
  local event="$1"; shift
  local arg1="${1:-}"
  # ...
}
```

| Argument | Description |
|---|---|
| `$1` | Event name that was emitted |
| `$2…` | Optional arguments passed to `emit` / `emit_safe` / `emit_async` |

**Lifecycle rules:**

- Handlers marked `--once` are removed after dispatch, regardless of exit code.
- Handlers whose function is no longer defined at dispatch time are removed
  automatically (logged once via `z::log::once`).
- In safe mode, a handler that exceeds `handler_timeout` is killed with
  `SIGTERM` then `SIGKILL`; counted as both `timeout` and `failed`.

### Pub/sub handlers

Registered via `z::bus::subscribe`.

```zsh
my_subscriber() {
  local channel="$1" message="$2"
  # ...
}
```

### Wildcard patterns

Patterns containing `*` are stored in the wildcard registry and matched via
zsh glob expansion (`${~pattern}`). Wildcard matching can be disabled globally
with `enable_wildcards false`.

**Examples:**

| Pattern | Matches |
|---|---|
| `user.*` | `user.login`, `user.logout` |
| `*.error` | `db.error`, `api.error` |
| `app.startup` | Only `app.startup` (exact) |

---

## 16. Dependencies

| Dependency | Required | Used for |
|---|---|---|
| `zlog` | Yes | All `z::log::*` calls (must be sourced first) |
| `zbase` | Yes | `z::validate::*`, `z::probe::func`, `z::time::epoch`, `Z_SEP`/`Z_RECSEP`, `ZBASE_ERROR_*` |
| `zkv` v4+ | Yes | Internal `__zbus` config store via `z::kv::open`, `z::kv::set`, `z::kv::setnx`, `z::kv::get` |

**Source order:**

```zsh
source ./zlog
source ./zbase
source ./zkv
source ./zbus
```

Sourcing `zbus` without its dependencies prints a fatal error to stderr and
returns `1`.

**Version requirement:** `ZKV_VERSION >= 4`. Older zkv versions are rejected at
load time.

---

## Function & Constant Index

| Symbol | Category | Description |
|---|---|---|
| `ZBUS_VERSION` | Constants | Module version (`3`) |
| `ZBUS_PRIORITY_HIGHEST` | Constants | Priority level `100` |
| `ZBUS_PRIORITY_HIGH` | Constants | Priority level `75` |
| `ZBUS_PRIORITY_NORMAL` | Constants | Priority level `50` (default) |
| `ZBUS_PRIORITY_LOW` | Constants | Priority level `25` |
| `ZBUS_PRIORITY_LOWEST` | Constants | Priority level `0` |
| `z::bus::init` | Lifecycle | Open config store and initialize bus |
| `z::bus::reset` | Lifecycle | Clear all runtime state |
| `z::bus::on` | Subscriptions | Register event handler |
| `z::bus::once` | Subscriptions | Register one-shot handler |
| `z::bus::off` | Subscriptions | Remove handlers by pattern |
| `z::bus::off_id` | Subscriptions | Remove handler by ID |
| `z::bus::emit` | Dispatch | Synchronous dispatch |
| `z::bus::emit_safe` | Dispatch | Isolated subshell dispatch with timeout |
| `z::bus::emit_async` | Dispatch | Background dispatch |
| `z::bus::wait_all_async` | Dispatch | Wait for all async jobs |
| `z::bus::has` | Introspection | Handler-exists predicate |
| `z::bus::count` | Introspection | Handler count for event |
| `z::bus::handlers` | Introspection | Handler IDs for event |
| `z::bus::list` | Introspection | Formatted handler table |
| `z::bus::history` | History | Print recent emissions |
| `z::bus::clear_history` | History | Reset ring buffer |
| `z::bus::stats` | Statistics | Print per-event counters |
| `z::bus::clear_stats` | Statistics | Reset counters |
| `z::bus::config` | Configuration | Update config key |
| `z::bus::get_config` | Configuration | Read config key |
| `z::bus::show_config` | Configuration | Print all config + runtime state |
| `z::bus::enable_performance_mode` | Performance | Suspend history and stats |
| `z::bus::disable_performance_mode` | Performance | Restore history and stats |
| `z::bus::subscribe` | Pub/Sub | Register channel handler |
| `z::bus::unsubscribe` | Pub/Sub | Remove channel handler |
| `z::bus::publish` | Pub/Sub | Deliver message to channel |
