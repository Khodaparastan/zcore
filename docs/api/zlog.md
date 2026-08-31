# zlog API Reference

> Complete reference for all public-facing functions and constants in `zlog`.
> Every symbol prefixed `zlog::` or `_ZLOG_` is part of the stable public API.
> Symbols prefixed `__zlog` or `_zlog_` are private internals — do not call or
> depend on them directly.

> **Upstream module.** `zlog` is a git submodule
> ([lib/zsh-log](../../lib/zsh-log), maintained separately) and is the only
> module exempt from this repository's
> [file header & comment standard](../conventions.md#file-header--comment-standard).

---

## Table of Contents

1. [Quick Start](#1-quick-start)
2. [Core Logging](#2-core-logging)
3. [Printf-Style Logging](#3-printf-style-logging)
4. [Level Guards](#4-level-guards)
5. [Control-Flow Helpers](#5-control-flow-helpers)
6. [Once & Rate Limiting](#6-once--rate-limiting)
7. [Context Loggers](#7-context-loggers)
8. [Benchmarking](#8-benchmarking)
9. [Timestamp Utilities](#9-timestamp-utilities)
10. [Configuration](#10-configuration)
11. [File Rotation](#11-file-rotation)
12. [Buffering](#12-buffering)
13. [Async Logging](#13-async-logging)
14. [Performance Mode](#14-performance-mode)
15. [Color System](#15-color-system)
16. [Statistics & Diagnostics](#16-statistics--diagnostics)
17. [Cleanup & Resource Management](#17-cleanup--resource-management)
18. [Internal Debug Mode](#18-internal-debug-mode)

---

## Conventions

| Convention | Meaning |
|---|---|
| `REPLY` | Functions that return a value set `$REPLY` instead of using subshells |
| `[key val ...]` | Optional trailing key-value pairs appended to the log line |
| Returns `0` | Success; non-zero on validation failure |
| Level names | Case-insensitive: `error`, `warn` (or `warning`), `info`, `debug` (or `0`–`3`) |

---

## 1. Quick Start

### `zlog::setup`

One-call configuration helper. Sets file, level, and format in a single invocation.

```
zlog::setup <file> [level] [format]
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `file` | string | required | Log file path. Use `"-"` for console-only |
| `level` | string | `info` | Log level: `error`, `warn`, `info`, `debug` |
| `format` | string | `text` | Output format: `text` or `json` |

**Returns:** `0` on success, `1` on invalid arguments.

**Examples:**

```zsh
# Console only, info level, text format
zlog::setup "-" info text

# File + console, debug level
zlog::setup "/var/log/app.log" debug

# JSON output to file
zlog::setup "/var/log/app.log" info json
```

---

## 2. Core Logging

These are the primary logging functions. All accept an optional trailing list of key-value pairs that are appended to the log line as structured context.

### `zlog::error`

Log an error message (level 0). Always reaches console unless logging is fully disabled.

```
zlog::error <message> [key val ...]
```

**Examples:**

```zsh
zlog::error "Database connection failed"
zlog::error "Query failed" "host" "localhost" "port" "5432" "code" "500"
```

**Output (text):**

```
2026-03-01 12:30:45 [ERROR] (1234) Database connection failed
2026-03-01 12:30:45 [ERROR] (1234) Query failed | host=localhost port=5432 code=500
```

---

### `zlog::warn`

Log a warning message (level 1).

```
zlog::warn <message> [key val ...]
```

**Examples:**

```zsh
zlog::warn "Disk space low" "available" "2GB" "threshold" "5GB"
zlog::warn "Deprecated API used" "function" "old_func" "replacement" "new_func"
```

---

### `zlog::info`

Log an informational message (level 2). This is the default level.

```
zlog::info <message> [key val ...]
```

**Examples:**

```zsh
zlog::info "Server started" "port" "8080" "env" "production"
zlog::info "User logged in" "user" "alice" "ip" "192.168.1.1"
```

---

### `zlog::debug`

Log a debug message (level 3). Only emitted when level is set to `debug`.

```
zlog::debug <message> [key val ...]
```

**Examples:**

```zsh
zlog::debug "Processing request" "method" "GET" "path" "/api/users"
zlog::debug "Cache hit" "key" "user:42" "ttl" "300"
```

---

### `zlog::log`

Generic log function — specify level by name or number.

```
zlog::log <level> <message> [key val ...]
```

| Parameter | Type | Description |
|---|---|---|
| `level` | string/int | `error`/`warn`/`warning`/`info`/`debug` or `0`–`3` |
| `message` | string | Log message |
| `key val ...` | pairs | Optional structured context |

**Returns:** `0` on success, `1` on invalid level.

**Examples:**

```zsh
zlog::log info "Server started" "port" "8080"
zlog::log 0 "Critical failure" "code" "500"
zlog::log debug "Trace point reached"

# Dynamic level from variable
local lvl="warn"
zlog::log "$lvl" "Something looks off"
```

---

### Output Formats

**Text format** (default):

```
2026-03-01 12:30:45 [INFO ] (1234) Server started | port=8080 env=production
```

**JSON format** (when `zlog::set_format json`):

```json
{"timestamp":"2026-03-01T12:30:45.123+00:00","level":"INFO","message":"Server started","hostname":"myhost","pid":1234,"user":"alice","port":"8080","env":"production"}
```

---

## 3. Printf-Style Logging

Format a message using `printf` syntax before logging. No key-value pairs are supported (use core functions for structured context).

### `zlog::errorf`

```
zlog::errorf <format> [args ...]
```

### `zlog::warnf`

```
zlog::warnf <format> [args ...]
```

### `zlog::infof`

```
zlog::infof <format> [args ...]
```

### `zlog::debugf`

```
zlog::debugf <format> [args ...]
```

**Examples:**

```zsh
zlog::infof "User %s logged in from %s" "$user" "$ip"
zlog::errorf "Exit code %d from command: %s" "$code" "$cmd"
zlog::debugf "Processing item %d of %d (%.1f%%)" "$i" "$total" "$(( i * 100.0 / total ))"
zlog::warnf "Retry %d/%d after %.2fs" "$attempt" "$max" "$delay"
```

**Notes:**

- Uses `printf` internally; all standard format specifiers apply (`%s`, `%d`, `%f`, `%x`, etc.)
- If `printf` fails (bad format), logs a `<printf format error: '...'>` message at the same level
- Format string cannot be empty

---

## 4. Level Guards

Predicate functions that return `0` (true) if the corresponding level is currently active. Use these to guard expensive computations that would only be needed if logging is enabled.

### `zlog::if_error`

```
zlog::if_error
```

Returns `0` if error logging is enabled, `1` otherwise.

### `zlog::if_warn`

```
zlog::if_warn
```

### `zlog::if_info`

```
zlog::if_info
```

### `zlog::if_debug`

```
zlog::if_debug
```

**Examples:**

```zsh
# Avoid expensive serialization unless debug is on
if zlog::if_debug; then
  local payload=$(serialize_request "$req")
  zlog::debug "Outgoing request" "payload" "$payload"
fi

# Guard costly error context gathering
if zlog::if_error; then
  local stack=$(capture_stack_trace)
  zlog::error "Unexpected failure" "stack" "$stack"
fi
```

---

## 5. Control-Flow Helpers

### `zlog::with_level`

Temporarily change the log level for the duration of a command, then restore it.

```
zlog::with_level <level> <command> [args ...]
```

| Parameter | Type | Description |
|---|---|---|
| `level` | string/int | Temporary level (`error`/`warn`/`info`/`debug` or `0`–`3`) |
| `command` | string | Command or function to execute |
| `args` | any | Arguments passed to the command |

**Returns:** Exit code of the executed command.

**Examples:**

```zsh
# Run a noisy function at warn level only
zlog::with_level warn run_migration

# Temporarily enable debug for one function
zlog::with_level debug my_function arg1 arg2

# Suppress everything below error for a block
zlog::with_level error run_third_party_tool
```

---

### `zlog::silent`

Disable all logging (console and file) for the duration of a command.

```
zlog::silent <command> [args ...]
```

**Returns:** Exit code of the executed command.

**Examples:**

```zsh
# Run without any log output
zlog::silent noisy_function

# Suppress logging during setup
zlog::silent initialize_subsystem --quiet

# Capture only the return code
zlog::silent validate_config && echo "Config OK"
```

---

### `zlog::always`

Force a message to be logged regardless of the current level settings. Logged at ERROR level to ensure it passes all filters.

```
zlog::always <message> [key val ...]
```

**Examples:**

```zsh
zlog::always "Application started" "version" "2.1.0" "pid" "$$"
zlog::always "AUDIT: User privilege escalation" "user" "$USER" "target" "root"
zlog::always "Deployment complete" "env" "production" "sha" "$GIT_SHA"
```

**Notes:**

- Bypasses level filtering — always emitted
- Internally sets both console and file level to `error` (0) temporarily
- Useful for audit trails, startup banners, and critical lifecycle events

---

## 6. Once & Rate Limiting

### `zlog::once`

Log a message only the first time a given key is seen. Subsequent calls with the same key are silently dropped.

```
zlog::once <key> <level> <message> [key val ...]
```

| Parameter | Type | Description |
|---|---|---|
| `key` | string | Unique identifier for this message |
| `level` | string | Log level |
| `message` | string | Message to log |
| `key val ...` | pairs | Optional structured context |

**Returns:** `0` always. Requires at least 3 arguments.

**Examples:**

```zsh
# In a loop — only logs once
for file in *.log; do
  zlog::once "deprecated-format" warn "Old log format detected" "file" "$file"
done

# Feature flag notice
zlog::once "beta-feature-used" info "Beta feature activated" "feature" "new_parser"

# One-time initialization message
zlog::once "db-connected" info "Database connection established" "host" "$DB_HOST"
```

---

### `zlog::clear_once`

Clear one or all "once" markers, allowing those messages to be logged again.

```
zlog::clear_once [key]
```

| Parameter | Type | Description |
|---|---|---|
| `key` | string | Optional. Specific key to clear. If omitted, clears all |

**Examples:**

```zsh
# Clear a specific marker
zlog::clear_once "deprecated-format"

# Clear all once markers (e.g., after config reload)
zlog::clear_once
```

---

### `zlog::rate_limit`

Log a message at most N times within a fixed time window. Excess calls are silently dropped.

```
zlog::rate_limit <key> <max_count> <time_window> <level> <message> [key val ...]
```

| Parameter | Type | Description |
|---|---|---|
| `key` | string | Unique identifier for this rate limit bucket |
| `max_count` | int | Maximum messages allowed in the window |
| `time_window` | int | Window duration in seconds (fixed window, resets after each period) |
| `level` | string | Log level |
| `message` | string | Message to log |
| `key val ...` | pairs | Optional structured context |

**Returns:** `0` if logged, `1` if rate-limited.

**Examples:**

```zsh
# Max 5 warnings per 60 seconds
zlog::rate_limit "disk-warn" 5 60 warn "Disk usage high" "usage" "$usage%"

# Max 1 error per 10 seconds per endpoint
zlog::rate_limit "api-error-${endpoint}" 1 10 error "API call failed" "endpoint" "$endpoint"

# In a tight loop — max 3 debug messages per second
while true; do
  zlog::rate_limit "loop-debug" 3 1 debug "Loop iteration" "i" "$i"
  (( i++ ))
done
```

---

### `zlog::clear_rate_limits`

Clear one or all rate limit counters, resetting their windows.

```
zlog::clear_rate_limits [key]
```

**Examples:**

```zsh
# Clear a specific rate limit
zlog::clear_rate_limits "disk-warn"

# Clear all rate limits
zlog::clear_rate_limits
```

---

## 7. Context Loggers

Context loggers attach a fixed set of key-value pairs to every log call, eliminating repetition in structured logging.

### `zlog::with_context`

Create a context logger. Sets `$REPLY` to the context ID, which is also a callable function prefix.

```
zlog::with_context <key1> <val1> [key2 val2 ...]
local ctx="$REPLY"
```

| Parameter | Type | Description |
|---|---|---|
| `key val ...` | pairs | Even number of args required. Keys: `[a-zA-Z0-9_-]` only |

**Returns:** `0` on success, `1` on error. Sets `$REPLY` to context ID.

**Generated functions** (where `$ctx` is the context ID):

| Function | Equivalent to |
|---|---|
| `${ctx}::error <msg> [kv...]` | `zlog::error <msg> <ctx-kvs...> [kv...]` |
| `${ctx}::warn <msg> [kv...]` | `zlog::warn <msg> <ctx-kvs...> [kv...]` |
| `${ctx}::info <msg> [kv...]` | `zlog::info <msg> <ctx-kvs...> [kv...]` |
| `${ctx}::debug <msg> [kv...]` | `zlog::debug <msg> <ctx-kvs...> [kv...]` |
| `${ctx}::errorf <fmt> [args...]` | printf-style error with context |
| `${ctx}::warnf <fmt> [args...]` | printf-style warn with context |
| `${ctx}::infof <fmt> [args...]` | printf-style info with context |
| `${ctx}::debugf <fmt> [args...]` | printf-style debug with context |

**Examples:**

```zsh
# HTTP request context
zlog::with_context "request_id" "abc-123" "method" "POST" "path" "/api/users"
local req_ctx="$REPLY"

${req_ctx}::info "Request received"
${req_ctx}::debug "Validating payload" "size" "${#body}"
${req_ctx}::warn "Rate limit approaching" "remaining" "5"
${req_ctx}::error "Handler failed" "code" "500"
${req_ctx}::infof "Responded in %dms" "$elapsed"

zlog::remove_context "$req_ctx"
```

```zsh
# Database session context
zlog::with_context "db" "postgres" "host" "db.prod" "pool" "primary"
local db_ctx="$REPLY"

${db_ctx}::info "Connection established"
${db_ctx}::debug "Executing query" "sql" "SELECT * FROM users"
${db_ctx}::error "Query timeout" "duration" "30s"

zlog::remove_context "$db_ctx"
```

**Notes:**

- Maximum 100 contexts active simultaneously (LRU eviction after that)
- Context IDs are unique random strings (`zlog_ctx_XXXXXXXXXX_epoch_pid`, where the numeric prefix is two concatenated `$RANDOM` values)
- Keys must match `^[a-zA-Z0-9_-]+$`; reserved JSON keys (`timestamp`, `level`, `message`, `hostname`, `pid`, `user`) are rejected in JSON format

---

### `zlog::remove_context`

Remove a context logger and undefine its generated functions.

```
zlog::remove_context <ctx_id>
```

**Returns:** `0` on success, `1` if context not found.

**Example:**

```zsh
zlog::remove_context "$req_ctx"
```

---

### `zlog::remove_all_contexts`

Remove all active context loggers at once.

```
zlog::remove_all_contexts
```

**Example:**

```zsh
# Cleanup at end of script
zlog::remove_all_contexts
```

---

### `zlog::list_contexts`

Print all active contexts and their key-value pairs to stdout.

```
zlog::list_contexts
```

**Output format:**

```
zlog_ctx_12345_1704110445_1234 request_id=abc-123 method=POST path=/api/users
zlog_ctx_67890_1704110446_1234 db=postgres host=db.prod
```

---

## 8. Benchmarking

All benchmarking functions are **no-ops** when INFO level is disabled, adding zero overhead in production.

### `zlog::benchmark`

Wrap a command and log its execution time.

```
zlog::benchmark <name> <command> [args ...]
```

| Parameter | Type | Description |
|---|---|---|
| `name` | string | Descriptive label for the operation |
| `command` | string | Command or function to execute |
| `args` | any | Arguments passed to the command |

**Returns:** Exit code of the executed command.

**Example:**

```zsh
zlog::benchmark "database_query" run_query --table users --limit 100
zlog::benchmark "file_compression" gzip -9 large_file.tar
zlog::benchmark "api_call" curl -s "https://api.example.com/data"
```

**Output:**

```
2026-03-01 12:30:45 [INFO ] (1234) Benchmark completed: database_query | duration=245ms
```

---

### `zlog::benchmark_start`

Start a named timer manually. Sets `$REPLY` to the timer ID.

```
zlog::benchmark_start <name>
local timer="$REPLY"
```

**Returns:** `0` on success. Sets `$REPLY` to timer ID (empty string if INFO is disabled).

---

### `zlog::benchmark_end`

Stop a timer and log the elapsed time.

```
zlog::benchmark_end <timer_id>
```

**Returns:** `0` on success, `1` if timer not found or invalid.

**Example:**

```zsh
zlog::benchmark_start "full_pipeline"
local timer="$REPLY"

step_one
step_two
step_three

zlog::benchmark_end "$timer"
# → INFO: Benchmark completed: full_pipeline | duration=1.23s
```

**Notes:**

- If `$timer` is empty (INFO disabled), `benchmark_end` is a safe no-op
- Maximum 50 active timers; oldest is evicted when limit is reached

---

### `zlog::benchmark_block`

Benchmark a heredoc code block read from stdin.

```
zlog::benchmark_block <name> <<'END'
  # code to benchmark
END
```

**Returns:** Exit code of the executed block.

**Example:**

```zsh
zlog::benchmark_block "data_processing" <<'END'
  local count=0
  for file in /data/*.csv; do
    process_file "$file"
    (( count++ ))
  done
  echo "Processed $count files"
END
# → INFO: Benchmark block: data_processing | duration=3.45s exit_code=0
```

---

### `zlog::benchmark_now`

Get the current time in milliseconds for manual timing. Sets `$REPLY`.

```
zlog::benchmark_now
local start="$REPLY"
```

**Example:**

```zsh
zlog::benchmark_now; local t0="$REPLY"
do_work
zlog::benchmark_now; local t1="$REPLY"
zlog::time_diff "$t0" "$t1"
zlog::info "Work done" "elapsed" "$REPLY"
```

---

### `zlog::benchmark_elapsed`

Calculate elapsed time since a start timestamp. Sets `$REPLY` to human-readable duration.

```
zlog::benchmark_elapsed <start_ms>
```

**Example:**

```zsh
zlog::benchmark_now; local start="$REPLY"
sleep 1
zlog::benchmark_elapsed "$start"
echo "Elapsed: $REPLY"   # → "Elapsed: 1.00s"
```

---

### `zlog::list_timers`

Print all currently active timers with their elapsed time.

```
zlog::list_timers
```

**Output:**

```
zbt_12345_1704110445_1234 full_pipeline (elapsed: 2.34s)
zbt_67890_1704110446_1234 db_query (elapsed: 450ms)
```

---

### `zlog::clear_timers`

Remove all active benchmark timers without logging results.

```
zlog::clear_timers
```

---

## 9. Timestamp Utilities

### `zlog::get_timestamp`

Get the current timestamp in various formats. Sets `$REPLY`.

```
zlog::get_timestamp [format]
```

| Format | Example output |
|---|---|
| `human` / `text` (default) | `2026-03-01 12:30:45` |
| `iso` / `iso8601` | `2026-03-01T12:30:45.123+00:00` |
| `epoch` / `unix` | `1704110445` |
| `ms` / `milliseconds` | `1704110445123` |
| `ns` / `nanoseconds` | `1704110445123456000` |

**Returns:** `0` on success, `1` on invalid format.

**Examples:**

```zsh
zlog::get_timestamp human;  echo "$REPLY"   # 2026-03-01 12:30:45
zlog::get_timestamp iso;    echo "$REPLY"   # 2026-03-01T12:30:45.123+00:00
zlog::get_timestamp epoch;  echo "$REPLY"   # 1704110445
zlog::get_timestamp ms;     echo "$REPLY"   # 1704110445123
```

---

### `zlog::set_timestamp_format`

Set a custom `strftime` format for human-readable timestamps.

```
zlog::set_timestamp_format <format>
```

**Returns:** `0` on success, `1` if format is empty or produces no output.

**Examples:**

```zsh
zlog::set_timestamp_format "%H:%M:%S"           # 12:30:45
zlog::set_timestamp_format "%Y-%m-%d"           # 2026-03-01
zlog::set_timestamp_format "%b %d %H:%M:%S"     # Jan 01 12:30:45
zlog::set_timestamp_format "%Y/%m/%d %H:%M:%S"  # 2026/01/01 12:30:45
```

**Common `strftime` codes:**

| Code | Meaning | Example |
|---|---|---|
| `%Y` | Year (4-digit) | `2026` |
| `%m` | Month (01–12) | `01` |
| `%d` | Day (01–31) | `15` |
| `%H` | Hour 24h (00–23) | `14` |
| `%M` | Minute (00–59) | `30` |
| `%S` | Second (00–59) | `45` |
| `%b` | Month name abbrev | `Jan` |
| `%a` | Weekday abbrev | `Mon` |
| `%z` | Timezone offset | `+0100` |
| `%Z` | Timezone name | `UTC` |

---

### `zlog::get_timestamp_format`

Get the current timestamp format string. Sets `$REPLY`.

```
zlog::get_timestamp_format
echo "$REPLY"   # %Y-%m-%d %H:%M:%S  (default)
```

---

### `zlog::reset_timestamp_format`

Reset timestamp format to the default (`%Y-%m-%d %H:%M:%S`).

```
zlog::reset_timestamp_format
```

---

### `zlog::format_epoch`

Format a specific Unix epoch timestamp. Sets `$REPLY`.

```
zlog::format_epoch <epoch> [format]
```

**Returns:** `0` on success, `1` on invalid epoch or format failure.

**Examples:**

```zsh
zlog::format_epoch 1704067200
echo "$REPLY"   # 2026-03-01 00:00:00

zlog::format_epoch 1704067200 "%Y-%m-%d"
echo "$REPLY"   # 2026-03-01

zlog::format_epoch 1704067200 "%b %d, %Y at %I:%M %p"
echo "$REPLY"   # Jan 01, 2026 at 12:00 AM
```

---

### `zlog::time_diff`

Calculate the difference between two millisecond timestamps. Sets `$REPLY` to a human-readable duration.

```
zlog::time_diff <start_ms> <end_ms>
```

**Returns:** `0` on success, `1` if inputs are invalid or `end < start`.

**Examples:**

```zsh
zlog::time_diff 1000 1500      # REPLY = "500ms"
zlog::time_diff 1000 2500      # REPLY = "1.50s"
zlog::time_diff 1000 61000     # REPLY = "1m0s"
zlog::time_diff 1000 3661000   # REPLY = "1h1m0s"
```

---

### `zlog::time_diff_signed`

Like `time_diff` but supports negative durations (when `end < start`).

```
zlog::time_diff_signed <start_ms> <end_ms>
```

**Examples:**

```zsh
zlog::time_diff_signed 1000 2500   # REPLY = "1.50s"
zlog::time_diff_signed 2500 1000   # REPLY = "-1.50s"
```

---

### `zlog::enable_timestamp_cache`

Enable per-second timestamp caching (default). Avoids repeated `strftime` calls.

```
zlog::enable_timestamp_cache
```

---

### `zlog::disable_timestamp_cache`

Disable timestamp caching. Every log call generates a fresh timestamp. Use when millisecond precision is critical.

```
zlog::disable_timestamp_cache
```

**Performance impact:** ~2× slower logging.

---

### `zlog::is_timestamp_cache_enabled`

Check if timestamp caching is enabled.

```
zlog::is_timestamp_cache_enabled
```

**Returns:** `0` if enabled, `1` if disabled.

---

## 10. Configuration

### `zlog::set_level`

Set the console log level.

```
zlog::set_level <level>
```

**Returns:** `0` on success, `1` on invalid level.

**Examples:**

```zsh
zlog::set_level debug    # Show all messages
zlog::set_level info     # Default
zlog::set_level warn     # Warnings and errors only
zlog::set_level error    # Errors only
zlog::set_level 3        # Same as debug
```

---

### `zlog::get_level`

Get the current console log level as a string.

```
level=$(zlog::get_level)
echo "$level"   # INFO
```

---

### `zlog::set_file_level`

Set an independent log level for file output. Defaults to following the console level.

```
zlog::set_file_level <level>
```

| Value | Meaning |
|---|---|
| `error`/`0` | Only errors to file |
| `warn`/`1` | Warnings and errors |
| `info`/`2` | Info and above |
| `debug`/`3` | Everything |
| `-1` or `console` | Follow console level (default) |

**Examples:**

```zsh
# File gets everything, console only errors
zlog::set_level error
zlog::set_file_level debug

# File follows console (default)
zlog::set_file_level console
```

---

### `zlog::get_file_level`

Get the current file log level.

```
level=$(zlog::get_file_level)
echo "$level"   # INFO  (or "console" if following)
```

---

### `zlog::set_format`

Set the output format.

```
zlog::set_format <format>
```

| Value | Description |
|---|---|
| `text` | Human-readable colored text (default) |
| `json` | Structured JSON, one object per line |

**Examples:**

```zsh
zlog::set_format json
zlog::info "Request handled" "status" "200"
# → {"timestamp":"...","level":"INFO","message":"Request handled","status":"200",...}

zlog::set_format text
```

---

### `zlog::get_format`

Get the current output format.

```
format=$(zlog::get_format)
echo "$format"   # text
```

---

### `zlog::set_file`

Set the log file path. Pass an empty string to disable file logging.

```
zlog::set_file <path>
```

**Examples:**

```zsh
zlog::set_file "/var/log/myapp.log"
zlog::set_file ""   # Disable file logging
zlog::set_file "/tmp/debug-$(date +%Y%m%d).log"
```

**Notes:**

- If buffering is active, pending messages are flushed to the old file before switching
- Parent directory must exist and be writable

---

### `zlog::get_file`

Get the current log file path.

```
file=$(zlog::get_file)
```

---

### `zlog::show_config`

Print a formatted table of all current configuration settings.

```
zlog::show_config
```

**Output:**

```
╔════════════════════════════════════════════════════════════════╗
║                    ZLOG Configuration                          ║
╠════════════════════════════════════════════════════════════════╣
║ Console Level:      INFO (2)                                   ║
║ File Level:         FOLLOW_CONSOLE (-1)                        ║
║ Format:             text                                       ║
║ Log File:           /var/log/app.log                           ║
╠════════════════════════════════════════════════════════════════╣
║ Rotation:           enabled                                    ║
║ Rotation Size:      10.00 MB                                   ║
║ Rotation Keep:      5 files                                    ║
...
```

---

### `zlog::reset`

Reset all configuration to factory defaults. Flushes any buffered messages first.

```
zlog::reset
```

**Defaults restored:**

| Setting | Default |
|---|---|
| Console level | `info` (2) |
| File level | follow console (-1) |
| Format | `text` |
| Log file | none |
| Rotation | enabled, 10MB, keep 5 |
| Buffering | disabled |
| Max message size | unlimited |
| Debug mode | disabled |
| Timestamp cache | enabled |

---

### `zlog::set_max_message_size`

Truncate log messages that exceed a size limit.

```
zlog::set_max_message_size <size>
```

| Value | Meaning |
|---|---|
| `0` | Unlimited (default) |
| `1024` | 1024 bytes |
| `"10KB"` | 10 kilobytes |
| `"1.5MB"` | 1.5 megabytes |

**Returns:** `0` on success, `1` on invalid input.

**Examples:**

```zsh
zlog::set_max_message_size 0        # Unlimited
zlog::set_max_message_size 1024     # 1 KB hard limit
zlog::set_max_message_size "10KB"   # 10 KB
zlog::set_max_message_size "1MB"    # 1 MB
```

---

### `zlog::get_max_message_size`

Get the current max message size as a human-readable string.

```
size=$(zlog::get_max_message_size)
echo "$size"   # "unlimited" or "10.00 KB"
```

---

### `zlog::set_truncate_marker`

Set the string appended to truncated messages.

```
zlog::set_truncate_marker <marker>
```

**Default:** `[TRUNCATED]`

**Examples:**

```zsh
zlog::set_truncate_marker " [...]"
zlog::set_truncate_marker "…"
zlog::set_truncate_marker " <truncated>"
```

---

### `zlog::get_truncate_marker`

Get the current truncation marker.

```
marker=$(zlog::get_truncate_marker)
```

---

## 11. File Rotation

### `zlog::set_rotation`

Configure file rotation in one call.

```
zlog::set_rotation <enabled> [max_size] [keep_count]
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `enabled` | `0`/`1` | required | Enable (`1`) or disable (`0`) rotation |
| `max_size` | string | `10MB` | Max file size before rotation. Accepts human-readable |
| `keep_count` | int | `5` | Number of rotated files to keep |

**Returns:** `0` on success, `1` on invalid arguments.

**Examples:**

```zsh
# Enable with defaults (10MB, keep 5)
zlog::set_rotation 1

# 50MB limit, keep 10 old files
zlog::set_rotation 1 "50MB" 10

# 100KB limit for development
zlog::set_rotation 1 "100KB" 3

# Disable rotation
zlog::set_rotation 0
```

**Rotation behavior:**

- `app.log` → `app.log.1` → `app.log.2` → … → `app.log.N`
- Files beyond `keep_count` are deleted
- Uses a lock file (`logfile.lock`) for multi-process safety

---

### `zlog::set_max_size`

Set the maximum log file size in bytes (integers only).

```
zlog::set_max_size <bytes>
```

**Example:**

```zsh
zlog::set_max_size 10485760   # 10MB
zlog::set_max_size 52428800   # 50MB
```

---

### `zlog::set_max_files`

Set the number of rotated files to keep.

```
zlog::set_max_files <count>
```

**Example:**

```zsh
zlog::set_max_files 10
```

---

### `zlog::set_rotation_lock_timeout`

Set the timeout (in seconds) for acquiring the rotation lock file.

```
zlog::set_rotation_lock_timeout <seconds>
```

**Default:** `5` seconds.

**Example:**

```zsh
zlog::set_rotation_lock_timeout 10   # Wait up to 10s for lock
zlog::set_rotation_lock_timeout 1    # Fast-fail after 1s
```

---

## 12. Buffering

### `zlog::enable_buffering`

Enable in-memory buffering. Messages accumulate in an array and are written in bulk.

```
zlog::enable_buffering [max_size]
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `max_size` | int | `50` | Auto-flush when buffer reaches this count |

**Auto-flush triggers:**

- Buffer reaches `max_size`
- An ERROR message is logged
- Script exits (via registered exit hook)
- `zlog::flush` is called manually

**Examples:**

```zsh
# Enable with default buffer size (50)
zlog::enable_buffering

# Enable with larger buffer
zlog::enable_buffering 200

# High-throughput scenario
zlog::enable_buffering 1000
for i in {1..10000}; do
  zlog::info "Processing item $i"
done
zlog::flush
```

---

### `zlog::disable_buffering`

Flush pending messages and disable buffering.

```
zlog::disable_buffering
```

---

### `zlog::flush`

Flush all buffered messages to the log file in a single bulk write.

```
zlog::flush
```

**Notes:**

- Uses a single `printf '%s\n' "${buffer[@]}"` call — much faster than per-line writes
- Safe to call when buffering is disabled (no-op)
- Called automatically on exit if cleanup is registered

---

### `zlog::get_buffer_count`

Get the number of messages currently in the buffer.

```
count=$(zlog::get_buffer_count)
echo "Buffered: $count messages"
```

---

### `zlog::is_buffered`

Check if buffering is currently enabled.

```
zlog::is_buffered
```

**Returns:** `0` if buffering is enabled, `1` otherwise.

**Example:**

```zsh
if zlog::is_buffered; then
  echo "Buffering active: $(zlog::get_buffer_count) messages pending"
fi
```

---

### `zlog::set_buffer_size`

Change the auto-flush threshold while buffering is active.

```
zlog::set_buffer_size <size>
```

**Example:**

```zsh
zlog::set_buffer_size 100
```

---

## 13. Async Logging

> **Experimental.** Async logging offloads file I/O to a background worker process via a FIFO, maximizing throughput for high-volume logging.

### `zlog::enable_async`

Start the async logging worker. Requires a log file to be configured first.

```
zlog::enable_async
```

**Returns:** `0` on success, `1` if no log file is configured or FIFO creation fails.

**Example:**

```zsh
zlog::set_file "/var/log/app.log"
zlog::enable_async

# All subsequent file writes go through the background worker
zlog::info "High-volume processing started"
for i in {1..100000}; do
  zlog::debug "Item $i processed"
done
```

---

### `zlog::disable_async`

Gracefully shut down the async worker. Sends a shutdown sentinel and waits up to 5 seconds.

```
zlog::disable_async
```

**Notes:**

- Sends `__ASYNC_SHUTDOWN__` sentinel through the FIFO
- Waits up to 5 seconds for the worker to finish; force-kills after timeout
- Safe to call even if async is not enabled

---

### `zlog::is_async`

Check if async logging is currently active.

```
zlog::is_async
```

**Returns:** `0` if async worker is running, `1` otherwise.

**Example:**

```zsh
if zlog::is_async; then
  echo "Async worker PID: ${_zlog_config[async_pid]}"
fi
```

---

## 14. Performance Mode

### `zlog::enable_performance_mode`

Hot-swap the logging engine with a faster implementation that skips recursion checking, level validation, and error handling. Provides ~3–4× speed improvement.

```
zlog::enable_performance_mode
```

**Trade-offs:**

- No recursion protection (logging inside log handlers can loop)
- No per-call level validation
- Timestamp cache always enabled
- Internal debug mode disabled
- Rotation checks skipped in buffered mode

**Example:**

```zsh
zlog::enable_buffering 500
zlog::enable_performance_mode

# High-throughput loop
for i in {1..100000}; do
  zlog::info "Event $i"
done

zlog::flush
zlog::disable_performance_mode
```

---

### `zlog::disable_performance_mode`

Restore the original logging engine.

```
zlog::disable_performance_mode
```

---

## 15. Color System

### `zlog::colorize`

Apply a color to a string. Sets `$REPLY` to the colorized string.

```
zlog::colorize <color_spec> <text>
```

| Color spec | Description |
|---|---|
| `red`, `green`, `blue`, `yellow`, `cyan`, `magenta`, `white`, `black` | Basic colors |
| `bright_red`, `bright_green`, etc. | Bright variants |
| `error`, `warn`, `info`, `debug`, `success` | Semantic level colors |
| `bold`, `dim`, `italic`, `underline` | Text styles |
| `rgb(R,G,B)` | True color (if terminal supports it) |
| `rgb(R,G,B,bg)` | True color background |

**Returns:** `0` on success. `$REPLY` is always set (to plain text if color unavailable).

**Examples:**

```zsh
zlog::colorize red "Error occurred"
print "$REPLY"

zlog::colorize "rgb(255,165,0)" "Orange text"
print "$REPLY"

zlog::colorize bold "Important notice"
print "$REPLY"

zlog::colorize "bright_green" "✓ All tests passed"
print "$REPLY"
```

---

### `zlog::set_color_mode`

Override the auto-detected color mode.

```
zlog::set_color_mode <mode>
```

| Mode | Description |
|---|---|
| `auto` | Auto-detect from terminal (default) |
| `none` | No colors (plain text) |
| `basic` | 8 basic ANSI colors |
| `256` | 256-color palette |
| `truecolor` | 24-bit RGB colors |

**Returns:** `0` on success, `1` on invalid mode.

**Examples:**

```zsh
zlog::set_color_mode none       # Force plain output (e.g., for CI)
zlog::set_color_mode truecolor  # Force full color
zlog::set_color_mode auto       # Re-detect
```

---

### `zlog::get_color_mode`

Get the current color mode.

```
mode=$(zlog::get_color_mode)
echo "$mode"   # truecolor
```

---

### `zlog::show_colors`

Print a visual palette of all available colors in the current mode.

```
zlog::show_colors
```

**Output includes:** Basic colors, bright colors, semantic level colors, and an RGB example.

---

## 16. Statistics & Diagnostics

### `zlog::get_stats`

Print runtime statistics to stdout.

```
zlog::get_stats
```

**Output:**

```
Logging Statistics:
  Messages logged:     1523
  Messages dropped:    0
  Rotations performed: 2
  Buffer flushes:      15
  Errors encountered:  0

Active Resources:
  Contexts:            3
  Timers:              1
  Buffered messages:   42
```

---

### `zlog::reset_stats`

Reset all statistics counters to zero.

```
zlog::reset_stats
```

---

### `zlog::clear_sys_cache`

Clear the cached system information (hostname, username, PID). Useful after container migration, user switch, or fork.

```
zlog::clear_sys_cache [type]
```

| Type | Effect |
|---|---|
| `hostname` | Re-detect hostname on next log call |
| `username` | Re-detect username on next log call |
| `pid` | Update PID to current `$$` |
| `all` (default) | Clear all three |

**Returns:** `0` on success, `1` on invalid type.

**Examples:**

```zsh
# After container migration
zlog::clear_sys_cache hostname

# After su/sudo
zlog::clear_sys_cache username

# After fork
zlog::clear_sys_cache pid

# Full reset
zlog::clear_sys_cache
zlog::clear_sys_cache all
```

---

## 17. Cleanup & Resource Management

### `zlog::cleanup`

Flush buffers, close file descriptors, shut down async worker, and release all resources. Idempotent — safe to call multiple times.

```
zlog::cleanup
```

**Actions performed:**

1. Disable async logging (if active)
2. Flush buffered messages
3. Close open file descriptors
4. Remove all context loggers
5. Clear benchmark timers
6. Clear rate limits and once-keys

---

### `zlog::register_cleanup`

Register `zlog::cleanup` to run automatically on script exit. Idempotent.

```
zlog::register_cleanup
```

**Hook registration order (tries each in sequence):**

1. `add-zsh-hook zshexit` (preferred — composable)
2. `TRAPEXIT` function (fallback)

**Example:**

```zsh
source zlog
zlog::set_file "/var/log/app.log"
zlog::enable_buffering
zlog::register_cleanup   # Ensures flush on exit

zlog::info "Script started"
# ... work ...
# On exit: cleanup runs automatically, buffer is flushed
```

---

### `zlog::unregister_cleanup`

Remove the exit hook registered by `zlog::register_cleanup`.

```
zlog::unregister_cleanup
```

**Use case:** Testing, or when you want to manage cleanup manually.

---

### `zlog::get_exit_hook_method`

Get the method used to register the exit hook.

```
method=$(zlog::get_exit_hook_method)
echo "$method"   # "zshexit", "trapexit", or "none"
```

---

## 18. Internal Debug Mode

These functions control zlog's own internal diagnostic output (separate from your application's log level).

### `zlog::enable_debug_mode`

Enable internal zlog diagnostics. Prints timestamped `[DEBUG]` lines to stderr for every internal operation.

```
zlog::enable_debug_mode
```

**Example:**

```zsh
zlog::enable_debug_mode
zlog::set_level debug
# → [12:30:45] zlog[DEBUG]: Color mode set to: auto
# → [12:30:45] zlog[DEBUG]: Log level set to: 3 (DEBUG)
```

---

### `zlog::disable_debug_mode`

Disable internal zlog diagnostics.

```
zlog::disable_debug_mode
```

---

### `zlog::is_debug_mode`

Check if internal debug mode is active.

```
zlog::is_debug_mode
```

**Returns:** `0` if enabled, `1` if disabled.

---

## Complete Usage Example

```zsh
#!/usr/bin/env zsh
source ./zlog

# ── Configuration ──────────────────────────────────────────────
zlog::setup "/var/log/myapp.log" info text
zlog::set_rotation 1 "50MB" 10
zlog::enable_buffering 100
zlog::register_cleanup

# ── Basic logging ──────────────────────────────────────────────
zlog::info  "Application started" "version" "2.1.0" "pid" "$$"
zlog::debug "Config loaded" "path" "/etc/myapp.conf"
zlog::warn  "Deprecated option used" "option" "--old-flag"
zlog::error "Connection refused" "host" "db.prod" "port" "5432"

# ── Printf-style ───────────────────────────────────────────────
zlog::infof  "Listening on port %d" 8080
zlog::debugf "Cache hit ratio: %.1f%%" 94.7
zlog::errorf "Exit code %d from: %s" $? "$last_cmd"

# ── Level guards ───────────────────────────────────────────────
if zlog::if_debug; then
  local expensive=$(gather_debug_info)
  zlog::debug "System state" "info" "$expensive"
fi

# ── Context logger ─────────────────────────────────────────────
zlog::with_context "request_id" "req-abc" "user" "alice" "method" "POST"
local ctx="$REPLY"

${ctx}::info  "Request received"
${ctx}::debug "Validating payload" "size" "1024"
${ctx}::warn  "Slow query detected" "duration" "2.3s"
${ctx}::error "Handler failed" "code" "500"
${ctx}::infof "Responded in %dms" 245

zlog::remove_context "$ctx"

# ── Once & rate limiting ───────────────────────────────────────
for host in "${hosts[@]}"; do
  zlog::once "legacy-host-$host" warn "Legacy host detected" "host" "$host"
  zlog::rate_limit "connect-$host" 3 60 info "Connecting" "host" "$host"
done

# ── Benchmarking ───────────────────────────────────────────────
zlog::benchmark "db_migration" run_migration --env prod

zlog::benchmark_start "full_pipeline"; local timer="$REPLY"
stage_one && stage_two && stage_three
zlog::benchmark_end "$timer"

zlog::benchmark_block "data_import" <<'END'
  import_csv /data/users.csv
  import_csv /data/orders.csv
END

# ── Control flow ───────────────────────────────────────────────
zlog::with_level debug run_verbose_tool
zlog::silent run_noisy_library
zlog::always "Deployment complete" "env" "production" "sha" "$GIT_SHA"

# ── Timestamps ─────────────────────────────────────────────────
zlog::get_timestamp iso;   local ts_iso="$REPLY"
zlog::get_timestamp epoch; local ts_epoch="$REPLY"
zlog::format_epoch "$ts_epoch" "%b %d, %Y"
zlog::info "Formatted date" "date" "$REPLY"

# ── Async (high-throughput) ────────────────────────────────────
zlog::enable_async
zlog::enable_performance_mode
for i in {1..100000}; do
  zlog::info "Event $i"
done
zlog::disable_performance_mode
zlog::disable_async

# ── Diagnostics ────────────────────────────────────────────────
zlog::show_config
zlog::get_stats
```

---

## Function Index

| Function                             | Category | Description                        |
|--------------------------------------|----------|------------------------------------|
| `zlog::setup`                      | Config   | One-call quick start               |
| `zlog::error`                      | Core     | Log error (level 0)                |
| `zlog::warn`                       | Core     | Log warning (level 1)              |
| `zlog::info`                       | Core     | Log info (level 2)                 |
| `zlog::debug`                      | Core     | Log debug (level 3)                |
| `zlog::log`                        | Core     | Log at named/numeric level         |
| `zlog::errorf`                     | Printf   | Printf-style error                 |
| `zlog::warnf`                      | Printf   | Printf-style warn                  |
| `zlog::infof`                      | Printf   | Printf-style info                  |
| `zlog::debugf`                     | Printf   | Printf-style debug                 |
| `zlog::if_error`                   | Guards   | Is error level active?             |
| `zlog::if_warn`                    | Guards   | Is warn level active?              |
| `zlog::if_info`                    | Guards   | Is info level active?              |
| `zlog::if_debug`                   | Guards   | Is debug level active?             |
| `zlog::with_level`                 | Control  | Temp level change for command      |
| `zlog::silent`                     | Control  | Suppress all logging for command   |
| `zlog::always`                     | Control  | Force log regardless of level      |
| `zlog::once`                       | Dedup    | Log only first occurrence          |
| `zlog::clear_once`                 | Dedup    | Reset once markers                 |
| `zlog::rate_limit`                 | Dedup    | Max N logs per time window         |
| `zlog::clear_rate_limits`          | Dedup    | Reset rate limit counters          |
| `zlog::with_context`               | Context  | Create context logger              |
| `zlog::remove_context`             | Context  | Remove context logger              |
| `zlog::remove_all_contexts`        | Context  | Remove all contexts                |
| `zlog::list_contexts`              | Context  | List active contexts               |
| `zlog::benchmark`                  | Bench    | Time a command                     |
| `zlog::benchmark_start`            | Bench    | Start manual timer                 |
| `zlog::benchmark_end`              | Bench    | Stop timer and log                 |
| `zlog::benchmark_block`            | Bench    | Time a heredoc block               |
| `zlog::benchmark_now`              | Bench    | Get current ms timestamp           |
| `zlog::benchmark_elapsed`          | Bench    | Elapsed since start                |
| `zlog::list_timers`                | Bench    | List active timers                 |
| `zlog::clear_timers`               | Bench    | Remove all timers                  |
| `zlog::get_timestamp`              | Time     | Get timestamp in any format        |
| `zlog::set_timestamp_format`       | Time     | Set strftime format                |
| `zlog::get_timestamp_format`       | Time     | Get current format                 |
| `zlog::reset_timestamp_format`     | Time     | Reset to default                   |
| `zlog::format_epoch`               | Time     | Format a Unix epoch                |
| `zlog::time_diff`                  | Time     | Duration between two ms timestamps |
| `zlog::time_diff_signed`           | Time     | Duration (supports negative)       |
| `zlog::enable_timestamp_cache`     | Time     | Enable caching (default)           |
| `zlog::disable_timestamp_cache`    | Time     | Disable caching                    |
| `zlog::is_timestamp_cache_enabled` | Time     | Check cache state                  |
| `zlog::set_level`                  | Config   | Set console level                  |
| `zlog::get_level`                  | Config   | Get console level                  |
| `zlog::set_file_level`             | Config   | Set file level                     |
| `zlog::get_file_level`             | Config   | Get file level                     |
| `zlog::set_format`                 | Config   | Set output format                  |
| `zlog::get_format`                 | Config   | Get output format                  |
| `zlog::set_file`                   | Config   | Set log file path                  |
| `zlog::get_file`                   | Config   | Get log file path                  |
| `zlog::show_config`                | Config   | Print config table                 |
| `zlog::reset`                      | Config   | Restore all defaults               |
| `zlog::set_max_message_size`       | Config   | Set message size limit             |
| `zlog::get_max_message_size`       | Config   | Get message size limit             |
| `zlog::set_truncate_marker`        | Config   | Set truncation suffix              |
| `zlog::get_truncate_marker`        | Config   | Get truncation suffix              |
| `zlog::set_rotation`               | Rotation | Configure rotation                 |
| `zlog::set_max_size`               | Rotation | Set max file size (bytes)          |
| `zlog::set_max_files`              | Rotation | Set files to keep                  |
| `zlog::set_rotation_lock_timeout`  | Rotation | Set lock timeout                   |
| `zlog::enable_buffering`           | Buffer   | Enable buffering                   |
| `zlog::disable_buffering`          | Buffer   | Disable buffering                  |
| `zlog::flush`                      | Buffer   | Flush buffer to file               |
| `zlog::get_buffer_count`           | Buffer   | Count buffered messages            |
| `zlog::is_buffered`                | Buffer   | Is buffering active?               |
| `zlog::set_buffer_size`            | Buffer   | Set auto-flush threshold           |
| `zlog::enable_async`               | Async    | Start async worker                 |
| `zlog::disable_async`              | Async    | Stop async worker                  |
| `zlog::is_async`                   | Async    | Is async active?                   |
| `zlog::enable_performance_mode`    | Perf     | Use fast engine                    |
| `zlog::disable_performance_mode`   | Perf     | Restore normal engine              |
| `zlog::colorize`                   | Color    | Apply color to text                |
| `zlog::set_color_mode`             | Color    | Override color detection           |
| `zlog::get_color_mode`             | Color    | Get current color mode             |
| `zlog::show_colors`                | Color    | Print color palette                |
| `zlog::get_stats`                  | Stats    | Print statistics                   |
| `zlog::reset_stats`                | Stats    | Reset counters                     |
| `zlog::clear_sys_cache`            | Stats    | Clear hostname/user/pid cache      |
| `zlog::cleanup`                    | Cleanup  | Release all resources              |
| `zlog::register_cleanup`           | Cleanup  | Register exit hook                 |
| `zlog::unregister_cleanup`         | Cleanup  | Remove exit hook                   |
| `zlog::get_exit_hook_method`       | Cleanup  | Get hook method                    |
| `zlog::enable_debug_mode`          | Debug    | Enable internal diagnostics        |
| `zlog::disable_debug_mode`         | Debug    | Disable internal diagnostics       |
| `zlog::is_debug_mode`              | Debug    | Is debug mode active?              |
