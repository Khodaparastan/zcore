# zlog API Reference

> Complete reference for all public-facing functions in `zlog`.  
> Every function prefixed `z::log::` is part of the stable public API.

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

### `z::log::setup`

One-call configuration helper. Sets file, level, and format in a single invocation.

```
z::log::setup <file> [level] [format]
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
z::log::setup "-" info text

# File + console, debug level
z::log::setup "/var/log/app.log" debug

# JSON output to file
z::log::setup "/var/log/app.log" info json
```

---

## 2. Core Logging

These are the primary logging functions. All accept an optional trailing list of key-value pairs that are appended to the log line as structured context.

### `z::log::error`

Log an error message (level 0). Always reaches console unless logging is fully disabled.

```
z::log::error <message> [key val ...]
```

**Examples:**

```zsh
z::log::error "Database connection failed"
z::log::error "Query failed" "host" "localhost" "port" "5432" "code" "500"
```

**Output (text):**

```
2026-03-01 12:30:45 [ERROR] (1234) Database connection failed
2026-03-01 12:30:45 [ERROR] (1234) Query failed | host=localhost port=5432 code=500
```

---

### `z::log::warn`

Log a warning message (level 1).

```
z::log::warn <message> [key val ...]
```

**Examples:**

```zsh
z::log::warn "Disk space low" "available" "2GB" "threshold" "5GB"
z::log::warn "Deprecated API used" "function" "old_func" "replacement" "new_func"
```

---

### `z::log::info`

Log an informational message (level 2). This is the default level.

```
z::log::info <message> [key val ...]
```

**Examples:**

```zsh
z::log::info "Server started" "port" "8080" "env" "production"
z::log::info "User logged in" "user" "alice" "ip" "192.168.1.1"
```

---

### `z::log::debug`

Log a debug message (level 3). Only emitted when level is set to `debug`.

```
z::log::debug <message> [key val ...]
```

**Examples:**

```zsh
z::log::debug "Processing request" "method" "GET" "path" "/api/users"
z::log::debug "Cache hit" "key" "user:42" "ttl" "300"
```

---

### `z::log::log`

Generic log function — specify level by name or number.

```
z::log::log <level> <message> [key val ...]
```

| Parameter | Type | Description |
|---|---|---|
| `level` | string/int | `error`/`warn`/`warning`/`info`/`debug` or `0`–`3` |
| `message` | string | Log message |
| `key val ...` | pairs | Optional structured context |

**Returns:** `0` on success, `1` on invalid level.

**Examples:**

```zsh
z::log::log info "Server started" "port" "8080"
z::log::log 0 "Critical failure" "code" "500"
z::log::log debug "Trace point reached"

# Dynamic level from variable
local lvl="warn"
z::log::log "$lvl" "Something looks off"
```

---

### Output Formats

**Text format** (default):

```
2026-03-01 12:30:45 [INFO ] (1234) Server started | port=8080 env=production
```

**JSON format** (when `z::log::set_format json`):

```json
{"timestamp":"2026-03-01T12:30:45.123+00:00","level":"INFO","message":"Server started","hostname":"myhost","pid":1234,"user":"alice","port":"8080","env":"production"}
```

---

## 3. Printf-Style Logging

Format a message using `printf` syntax before logging. No key-value pairs are supported (use core functions for structured context).

### `z::log::errorf`

```
z::log::errorf <format> [args ...]
```

### `z::log::warnf`

```
z::log::warnf <format> [args ...]
```

### `z::log::infof`

```
z::log::infof <format> [args ...]
```

### `z::log::debugf`

```
z::log::debugf <format> [args ...]
```

**Examples:**

```zsh
z::log::infof "User %s logged in from %s" "$user" "$ip"
z::log::errorf "Exit code %d from command: %s" "$code" "$cmd"
z::log::debugf "Processing item %d of %d (%.1f%%)" "$i" "$total" "$(( i * 100.0 / total ))"
z::log::warnf "Retry %d/%d after %.2fs" "$attempt" "$max" "$delay"
```

**Notes:**

- Uses `printf` internally; all standard format specifiers apply (`%s`, `%d`, `%f`, `%x`, etc.)
- If `printf` fails (bad format), logs a `<printf format error: '...'>` message at the same level
- Format string cannot be empty

---

## 4. Level Guards

Predicate functions that return `0` (true) if the corresponding level is currently active. Use these to guard expensive computations that would only be needed if logging is enabled.

### `z::log::if_error`

```
z::log::if_error
```

Returns `0` if error logging is enabled, `1` otherwise.

### `z::log::if_warn`

```
z::log::if_warn
```

### `z::log::if_info`

```
z::log::if_info
```

### `z::log::if_debug`

```
z::log::if_debug
```

**Examples:**

```zsh
# Avoid expensive serialization unless debug is on
if z::log::if_debug; then
  local payload=$(serialize_request "$req")
  z::log::debug "Outgoing request" "payload" "$payload"
fi

# Guard costly error context gathering
if z::log::if_error; then
  local stack=$(capture_stack_trace)
  z::log::error "Unexpected failure" "stack" "$stack"
fi
```

---

## 5. Control-Flow Helpers

### `z::log::with_level`

Temporarily change the log level for the duration of a command, then restore it.

```
z::log::with_level <level> <command> [args ...]
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
z::log::with_level warn run_migration

# Temporarily enable debug for one function
z::log::with_level debug my_function arg1 arg2

# Suppress everything below error for a block
z::log::with_level error run_third_party_tool
```

---

### `z::log::silent`

Disable all logging (console and file) for the duration of a command.

```
z::log::silent <command> [args ...]
```

**Returns:** Exit code of the executed command.

**Examples:**

```zsh
# Run without any log output
z::log::silent noisy_function

# Suppress logging during setup
z::log::silent initialize_subsystem --quiet

# Capture only the return code
z::log::silent validate_config && echo "Config OK"
```

---

### `z::log::always`

Force a message to be logged regardless of the current level settings. Logged at ERROR level to ensure it passes all filters.

```
z::log::always <message> [key val ...]
```

**Examples:**

```zsh
z::log::always "Application started" "version" "2.1.0" "pid" "$$"
z::log::always "AUDIT: User privilege escalation" "user" "$USER" "target" "root"
z::log::always "Deployment complete" "env" "production" "sha" "$GIT_SHA"
```

**Notes:**

- Bypasses level filtering — always emitted
- Internally sets both console and file level to `error` (0) temporarily
- Useful for audit trails, startup banners, and critical lifecycle events

---

## 6. Once & Rate Limiting

### `z::log::once`

Log a message only the first time a given key is seen. Subsequent calls with the same key are silently dropped.

```
z::log::once <key> <level> <message> [key val ...]
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
  z::log::once "deprecated-format" warn "Old log format detected" "file" "$file"
done

# Feature flag notice
z::log::once "beta-feature-used" info "Beta feature activated" "feature" "new_parser"

# One-time initialization message
z::log::once "db-connected" info "Database connection established" "host" "$DB_HOST"
```

---

### `z::log::clear_once`

Clear one or all "once" markers, allowing those messages to be logged again.

```
z::log::clear_once [key]
```

| Parameter | Type | Description |
|---|---|---|
| `key` | string | Optional. Specific key to clear. If omitted, clears all |

**Examples:**

```zsh
# Clear a specific marker
z::log::clear_once "deprecated-format"

# Clear all once markers (e.g., after config reload)
z::log::clear_once
```

---

### `z::log::rate_limit`

Log a message at most N times within a fixed time window. Excess calls are silently dropped.

```
z::log::rate_limit <key> <max_count> <time_window> <level> <message> [key val ...]
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
z::log::rate_limit "disk-warn" 5 60 warn "Disk usage high" "usage" "$usage%"

# Max 1 error per 10 seconds per endpoint
z::log::rate_limit "api-error-${endpoint}" 1 10 error "API call failed" "endpoint" "$endpoint"

# In a tight loop — max 3 debug messages per second
while true; do
  z::log::rate_limit "loop-debug" 3 1 debug "Loop iteration" "i" "$i"
  (( i++ ))
done
```

---

### `z::log::clear_rate_limits`

Clear one or all rate limit counters, resetting their windows.

```
z::log::clear_rate_limits [key]
```

**Examples:**

```zsh
# Clear a specific rate limit
z::log::clear_rate_limits "disk-warn"

# Clear all rate limits
z::log::clear_rate_limits
```

---

## 7. Context Loggers

Context loggers attach a fixed set of key-value pairs to every log call, eliminating repetition in structured logging.

### `z::log::with_context`

Create a context logger. Sets `$REPLY` to the context ID, which is also a callable function prefix.

```
z::log::with_context <key1> <val1> [key2 val2 ...]
local ctx="$REPLY"
```

| Parameter | Type | Description |
|---|---|---|
| `key val ...` | pairs | Even number of args required. Keys: `[a-zA-Z0-9_-]` only |

**Returns:** `0` on success, `1` on error. Sets `$REPLY` to context ID.

**Generated functions** (where `$ctx` is the context ID):

| Function | Equivalent to |
|---|---|
| `${ctx}::error <msg> [kv...]` | `z::log::error <msg> <ctx-kvs...> [kv...]` |
| `${ctx}::warn <msg> [kv...]` | `z::log::warn <msg> <ctx-kvs...> [kv...]` |
| `${ctx}::info <msg> [kv...]` | `z::log::info <msg> <ctx-kvs...> [kv...]` |
| `${ctx}::debug <msg> [kv...]` | `z::log::debug <msg> <ctx-kvs...> [kv...]` |
| `${ctx}::errorf <fmt> [args...]` | printf-style error with context |
| `${ctx}::warnf <fmt> [args...]` | printf-style warn with context |
| `${ctx}::infof <fmt> [args...]` | printf-style info with context |
| `${ctx}::debugf <fmt> [args...]` | printf-style debug with context |

**Examples:**

```zsh
# HTTP request context
z::log::with_context "request_id" "abc-123" "method" "POST" "path" "/api/users"
local req_ctx="$REPLY"

${req_ctx}::info "Request received"
${req_ctx}::debug "Validating payload" "size" "${#body}"
${req_ctx}::warn "Rate limit approaching" "remaining" "5"
${req_ctx}::error "Handler failed" "code" "500"
${req_ctx}::infof "Responded in %dms" "$elapsed"

z::log::remove_context "$req_ctx"
```

```zsh
# Database session context
z::log::with_context "db" "postgres" "host" "db.prod" "pool" "primary"
local db_ctx="$REPLY"

${db_ctx}::info "Connection established"
${db_ctx}::debug "Executing query" "sql" "SELECT * FROM users"
${db_ctx}::error "Query timeout" "duration" "30s"

z::log::remove_context "$db_ctx"
```

**Notes:**

- Maximum 100 contexts active simultaneously (LRU eviction after that)
- Context IDs are unique random strings (`zlog_ctx_XXXXXXXXXX_epoch_pid`, where the numeric prefix is two concatenated `$RANDOM` values)
- Keys must match `^[a-zA-Z0-9_-]+$`; reserved JSON keys (`timestamp`, `level`, `message`, `hostname`, `pid`, `user`) are rejected in JSON format

---

### `z::log::remove_context`

Remove a context logger and undefine its generated functions.

```
z::log::remove_context <ctx_id>
```

**Returns:** `0` on success, `1` if context not found.

**Example:**

```zsh
z::log::remove_context "$req_ctx"
```

---

### `z::log::remove_all_contexts`

Remove all active context loggers at once.

```
z::log::remove_all_contexts
```

**Example:**

```zsh
# Cleanup at end of script
z::log::remove_all_contexts
```

---

### `z::log::list_contexts`

Print all active contexts and their key-value pairs to stdout.

```
z::log::list_contexts
```

**Output format:**

```
zlog_ctx_12345_1704110445_1234 request_id=abc-123 method=POST path=/api/users
zlog_ctx_67890_1704110446_1234 db=postgres host=db.prod
```

---

## 8. Benchmarking

All benchmarking functions are **no-ops** when INFO level is disabled, adding zero overhead in production.

### `z::log::benchmark`

Wrap a command and log its execution time.

```
z::log::benchmark <name> <command> [args ...]
```

| Parameter | Type | Description |
|---|---|---|
| `name` | string | Descriptive label for the operation |
| `command` | string | Command or function to execute |
| `args` | any | Arguments passed to the command |

**Returns:** Exit code of the executed command.

**Example:**

```zsh
z::log::benchmark "database_query" run_query --table users --limit 100
z::log::benchmark "file_compression" gzip -9 large_file.tar
z::log::benchmark "api_call" curl -s "https://api.example.com/data"
```

**Output:**

```
2026-03-01 12:30:45 [INFO ] (1234) Benchmark completed: database_query | duration=245ms
```

---

### `z::log::benchmark_start`

Start a named timer manually. Sets `$REPLY` to the timer ID.

```
z::log::benchmark_start <name>
local timer="$REPLY"
```

**Returns:** `0` on success. Sets `$REPLY` to timer ID (empty string if INFO is disabled).

---

### `z::log::benchmark_end`

Stop a timer and log the elapsed time.

```
z::log::benchmark_end <timer_id>
```

**Returns:** `0` on success, `1` if timer not found or invalid.

**Example:**

```zsh
z::log::benchmark_start "full_pipeline"
local timer="$REPLY"

step_one
step_two
step_three

z::log::benchmark_end "$timer"
# → INFO: Benchmark completed: full_pipeline | duration=1.23s
```

**Notes:**

- If `$timer` is empty (INFO disabled), `benchmark_end` is a safe no-op
- Maximum 50 active timers; oldest is evicted when limit is reached

---

### `z::log::benchmark_block`

Benchmark a heredoc code block read from stdin.

```
z::log::benchmark_block <name> <<'END'
  # code to benchmark
END
```

**Returns:** Exit code of the executed block.

**Example:**

```zsh
z::log::benchmark_block "data_processing" <<'END'
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

### `z::log::benchmark_now`

Get the current time in milliseconds for manual timing. Sets `$REPLY`.

```
z::log::benchmark_now
local start="$REPLY"
```

**Example:**

```zsh
z::log::benchmark_now; local t0="$REPLY"
do_work
z::log::benchmark_now; local t1="$REPLY"
z::log::time_diff "$t0" "$t1"
z::log::info "Work done" "elapsed" "$REPLY"
```

---

### `z::log::benchmark_elapsed`

Calculate elapsed time since a start timestamp. Sets `$REPLY` to human-readable duration.

```
z::log::benchmark_elapsed <start_ms>
```

**Example:**

```zsh
z::log::benchmark_now; local start="$REPLY"
sleep 1
z::log::benchmark_elapsed "$start"
echo "Elapsed: $REPLY"   # → "Elapsed: 1.00s"
```

---

### `z::log::list_timers`

Print all currently active timers with their elapsed time.

```
z::log::list_timers
```

**Output:**

```
zbt_12345_1704110445_1234 full_pipeline (elapsed: 2.34s)
zbt_67890_1704110446_1234 db_query (elapsed: 450ms)
```

---

### `z::log::clear_timers`

Remove all active benchmark timers without logging results.

```
z::log::clear_timers
```

---

## 9. Timestamp Utilities

### `z::log::get_timestamp`

Get the current timestamp in various formats. Sets `$REPLY`.

```
z::log::get_timestamp [format]
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
z::log::get_timestamp human;  echo "$REPLY"   # 2026-03-01 12:30:45
z::log::get_timestamp iso;    echo "$REPLY"   # 2026-03-01T12:30:45.123+00:00
z::log::get_timestamp epoch;  echo "$REPLY"   # 1704110445
z::log::get_timestamp ms;     echo "$REPLY"   # 1704110445123
```

---

### `z::log::set_timestamp_format`

Set a custom `strftime` format for human-readable timestamps.

```
z::log::set_timestamp_format <format>
```

**Returns:** `0` on success, `1` if format is empty or produces no output.

**Examples:**

```zsh
z::log::set_timestamp_format "%H:%M:%S"           # 12:30:45
z::log::set_timestamp_format "%Y-%m-%d"           # 2026-03-01
z::log::set_timestamp_format "%b %d %H:%M:%S"     # Jan 01 12:30:45
z::log::set_timestamp_format "%Y/%m/%d %H:%M:%S"  # 2026/01/01 12:30:45
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

### `z::log::get_timestamp_format`

Get the current timestamp format string. Sets `$REPLY`.

```
z::log::get_timestamp_format
echo "$REPLY"   # %Y-%m-%d %H:%M:%S  (default)
```

---

### `z::log::reset_timestamp_format`

Reset timestamp format to the default (`%Y-%m-%d %H:%M:%S`).

```
z::log::reset_timestamp_format
```

---

### `z::log::format_epoch`

Format a specific Unix epoch timestamp. Sets `$REPLY`.

```
z::log::format_epoch <epoch> [format]
```

**Returns:** `0` on success, `1` on invalid epoch or format failure.

**Examples:**

```zsh
z::log::format_epoch 1704067200
echo "$REPLY"   # 2026-03-01 00:00:00

z::log::format_epoch 1704067200 "%Y-%m-%d"
echo "$REPLY"   # 2026-03-01

z::log::format_epoch 1704067200 "%b %d, %Y at %I:%M %p"
echo "$REPLY"   # Jan 01, 2026 at 12:00 AM
```

---

### `z::log::time_diff`

Calculate the difference between two millisecond timestamps. Sets `$REPLY` to a human-readable duration.

```
z::log::time_diff <start_ms> <end_ms>
```

**Returns:** `0` on success, `1` if inputs are invalid or `end < start`.

**Examples:**

```zsh
z::log::time_diff 1000 1500      # REPLY = "500ms"
z::log::time_diff 1000 2500      # REPLY = "1.50s"
z::log::time_diff 1000 61000     # REPLY = "1m0s"
z::log::time_diff 1000 3661000   # REPLY = "1h1m0s"
```

---

### `z::log::time_diff_signed`

Like `time_diff` but supports negative durations (when `end < start`).

```
z::log::time_diff_signed <start_ms> <end_ms>
```

**Examples:**

```zsh
z::log::time_diff_signed 1000 2500   # REPLY = "1.50s"
z::log::time_diff_signed 2500 1000   # REPLY = "-1.50s"
```

---

### `z::log::enable_timestamp_cache`

Enable per-second timestamp caching (default). Avoids repeated `strftime` calls.

```
z::log::enable_timestamp_cache
```

---

### `z::log::disable_timestamp_cache`

Disable timestamp caching. Every log call generates a fresh timestamp. Use when millisecond precision is critical.

```
z::log::disable_timestamp_cache
```

**Performance impact:** ~2× slower logging.

---

### `z::log::is_timestamp_cache_enabled`

Check if timestamp caching is enabled.

```
z::log::is_timestamp_cache_enabled
```

**Returns:** `0` if enabled, `1` if disabled.

---

## 10. Configuration

### `z::log::set_level`

Set the console log level.

```
z::log::set_level <level>
```

**Returns:** `0` on success, `1` on invalid level.

**Examples:**

```zsh
z::log::set_level debug    # Show all messages
z::log::set_level info     # Default
z::log::set_level warn     # Warnings and errors only
z::log::set_level error    # Errors only
z::log::set_level 3        # Same as debug
```

---

### `z::log::get_level`

Get the current console log level as a string.

```
level=$(z::log::get_level)
echo "$level"   # INFO
```

---

### `z::log::set_file_level`

Set an independent log level for file output. Defaults to following the console level.

```
z::log::set_file_level <level>
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
z::log::set_level error
z::log::set_file_level debug

# File follows console (default)
z::log::set_file_level console
```

---

### `z::log::get_file_level`

Get the current file log level.

```
level=$(z::log::get_file_level)
echo "$level"   # INFO  (or "console" if following)
```

---

### `z::log::set_format`

Set the output format.

```
z::log::set_format <format>
```

| Value | Description |
|---|---|
| `text` | Human-readable colored text (default) |
| `json` | Structured JSON, one object per line |

**Examples:**

```zsh
z::log::set_format json
z::log::info "Request handled" "status" "200"
# → {"timestamp":"...","level":"INFO","message":"Request handled","status":"200",...}

z::log::set_format text
```

---

### `z::log::get_format`

Get the current output format.

```
format=$(z::log::get_format)
echo "$format"   # text
```

---

### `z::log::set_file`

Set the log file path. Pass an empty string to disable file logging.

```
z::log::set_file <path>
```

**Examples:**

```zsh
z::log::set_file "/var/log/myapp.log"
z::log::set_file ""   # Disable file logging
z::log::set_file "/tmp/debug-$(date +%Y%m%d).log"
```

**Notes:**

- If buffering is active, pending messages are flushed to the old file before switching
- Parent directory must exist and be writable

---

### `z::log::get_file`

Get the current log file path.

```
file=$(z::log::get_file)
```

---

### `z::log::show_config`

Print a formatted table of all current configuration settings.

```
z::log::show_config
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

### `z::log::reset`

Reset all configuration to factory defaults. Flushes any buffered messages first.

```
z::log::reset
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

### `z::log::set_max_message_size`

Truncate log messages that exceed a size limit.

```
z::log::set_max_message_size <size>
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
z::log::set_max_message_size 0        # Unlimited
z::log::set_max_message_size 1024     # 1 KB hard limit
z::log::set_max_message_size "10KB"   # 10 KB
z::log::set_max_message_size "1MB"    # 1 MB
```

---

### `z::log::get_max_message_size`

Get the current max message size as a human-readable string.

```
size=$(z::log::get_max_message_size)
echo "$size"   # "unlimited" or "10.00 KB"
```

---

### `z::log::set_truncate_marker`

Set the string appended to truncated messages.

```
z::log::set_truncate_marker <marker>
```

**Default:** `[TRUNCATED]`

**Examples:**

```zsh
z::log::set_truncate_marker " [...]"
z::log::set_truncate_marker "…"
z::log::set_truncate_marker " <truncated>"
```

---

### `z::log::get_truncate_marker`

Get the current truncation marker.

```
marker=$(z::log::get_truncate_marker)
```

---

## 11. File Rotation

### `z::log::set_rotation`

Configure file rotation in one call.

```
z::log::set_rotation <enabled> [max_size] [keep_count]
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
z::log::set_rotation 1

# 50MB limit, keep 10 old files
z::log::set_rotation 1 "50MB" 10

# 100KB limit for development
z::log::set_rotation 1 "100KB" 3

# Disable rotation
z::log::set_rotation 0
```

**Rotation behavior:**

- `app.log` → `app.log.1` → `app.log.2` → … → `app.log.N`
- Files beyond `keep_count` are deleted
- Uses a lock file (`logfile.lock`) for multi-process safety

---

### `z::log::set_max_size`

Set the maximum log file size in bytes (integers only).

```
z::log::set_max_size <bytes>
```

**Example:**

```zsh
z::log::set_max_size 10485760   # 10MB
z::log::set_max_size 52428800   # 50MB
```

---

### `z::log::set_max_files`

Set the number of rotated files to keep.

```
z::log::set_max_files <count>
```

**Example:**

```zsh
z::log::set_max_files 10
```

---

### `z::log::set_rotation_lock_timeout`

Set the timeout (in seconds) for acquiring the rotation lock file.

```
z::log::set_rotation_lock_timeout <seconds>
```

**Default:** `5` seconds.

**Example:**

```zsh
z::log::set_rotation_lock_timeout 10   # Wait up to 10s for lock
z::log::set_rotation_lock_timeout 1    # Fast-fail after 1s
```

---

## 12. Buffering

### `z::log::enable_buffering`

Enable in-memory buffering. Messages accumulate in an array and are written in bulk.

```
z::log::enable_buffering [max_size]
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `max_size` | int | `50` | Auto-flush when buffer reaches this count |

**Auto-flush triggers:**

- Buffer reaches `max_size`
- An ERROR message is logged
- Script exits (via registered exit hook)
- `z::log::flush` is called manually

**Examples:**

```zsh
# Enable with default buffer size (50)
z::log::enable_buffering

# Enable with larger buffer
z::log::enable_buffering 200

# High-throughput scenario
z::log::enable_buffering 1000
for i in {1..10000}; do
  z::log::info "Processing item $i"
done
z::log::flush
```

---

### `z::log::disable_buffering`

Flush pending messages and disable buffering.

```
z::log::disable_buffering
```

---

### `z::log::flush`

Flush all buffered messages to the log file in a single bulk write.

```
z::log::flush
```

**Notes:**

- Uses a single `printf '%s\n' "${buffer[@]}"` call — much faster than per-line writes
- Safe to call when buffering is disabled (no-op)
- Called automatically on exit if cleanup is registered

---

### `z::log::get_buffer_count`

Get the number of messages currently in the buffer.

```
count=$(z::log::get_buffer_count)
echo "Buffered: $count messages"
```

---

### `z::log::is_buffered`

Check if buffering is currently enabled.

```
z::log::is_buffered
```

**Returns:** `0` if buffering is enabled, `1` otherwise.

**Example:**

```zsh
if z::log::is_buffered; then
  echo "Buffering active: $(z::log::get_buffer_count) messages pending"
fi
```

---

### `z::log::set_buffer_size`

Change the auto-flush threshold while buffering is active.

```
z::log::set_buffer_size <size>
```

**Example:**

```zsh
z::log::set_buffer_size 100
```

---

## 13. Async Logging

> **Experimental.** Async logging offloads file I/O to a background worker process via a FIFO, maximizing throughput for high-volume logging.

### `z::log::enable_async`

Start the async logging worker. Requires a log file to be configured first.

```
z::log::enable_async
```

**Returns:** `0` on success, `1` if no log file is configured or FIFO creation fails.

**Example:**

```zsh
z::log::set_file "/var/log/app.log"
z::log::enable_async

# All subsequent file writes go through the background worker
z::log::info "High-volume processing started"
for i in {1..100000}; do
  z::log::debug "Item $i processed"
done
```

---

### `z::log::disable_async`

Gracefully shut down the async worker. Sends a shutdown sentinel and waits up to 5 seconds.

```
z::log::disable_async
```

**Notes:**

- Sends `__ASYNC_SHUTDOWN__` sentinel through the FIFO
- Waits up to 5 seconds for the worker to finish; force-kills after timeout
- Safe to call even if async is not enabled

---

### `z::log::is_async`

Check if async logging is currently active.

```
z::log::is_async
```

**Returns:** `0` if async worker is running, `1` otherwise.

**Example:**

```zsh
if z::log::is_async; then
  echo "Async worker PID: ${_zlog_config[async_pid]}"
fi
```

---

## 14. Performance Mode

### `z::log::enable_performance_mode`

Hot-swap the logging engine with a faster implementation that skips recursion checking, level validation, and error handling. Provides ~3–4× speed improvement.

```
z::log::enable_performance_mode
```

**Trade-offs:**

- No recursion protection (logging inside log handlers can loop)
- No per-call level validation
- Timestamp cache always enabled
- Internal debug mode disabled
- Rotation checks skipped in buffered mode

**Example:**

```zsh
z::log::enable_buffering 500
z::log::enable_performance_mode

# High-throughput loop
for i in {1..100000}; do
  z::log::info "Event $i"
done

z::log::flush
z::log::disable_performance_mode
```

---

### `z::log::disable_performance_mode`

Restore the original logging engine.

```
z::log::disable_performance_mode
```

---

## 15. Color System

### `z::log::colorize`

Apply a color to a string. Sets `$REPLY` to the colorized string.

```
z::log::colorize <color_spec> <text>
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
z::log::colorize red "Error occurred"
print "$REPLY"

z::log::colorize "rgb(255,165,0)" "Orange text"
print "$REPLY"

z::log::colorize bold "Important notice"
print "$REPLY"

z::log::colorize "bright_green" "✓ All tests passed"
print "$REPLY"
```

---

### `z::log::set_color_mode`

Override the auto-detected color mode.

```
z::log::set_color_mode <mode>
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
z::log::set_color_mode none       # Force plain output (e.g., for CI)
z::log::set_color_mode truecolor  # Force full color
z::log::set_color_mode auto       # Re-detect
```

---

### `z::log::get_color_mode`

Get the current color mode.

```
mode=$(z::log::get_color_mode)
echo "$mode"   # truecolor
```

---

### `z::log::show_colors`

Print a visual palette of all available colors in the current mode.

```
z::log::show_colors
```

**Output includes:** Basic colors, bright colors, semantic level colors, and an RGB example.

---

## 16. Statistics & Diagnostics

### `z::log::get_stats`

Print runtime statistics to stdout.

```
z::log::get_stats
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

### `z::log::reset_stats`

Reset all statistics counters to zero.

```
z::log::reset_stats
```

---

### `z::log::clear_sys_cache`

Clear the cached system information (hostname, username, PID). Useful after container migration, user switch, or fork.

```
z::log::clear_sys_cache [type]
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
z::log::clear_sys_cache hostname

# After su/sudo
z::log::clear_sys_cache username

# After fork
z::log::clear_sys_cache pid

# Full reset
z::log::clear_sys_cache
z::log::clear_sys_cache all
```

---

## 17. Cleanup & Resource Management

### `z::log::cleanup`

Flush buffers, close file descriptors, shut down async worker, and release all resources. Idempotent — safe to call multiple times.

```
z::log::cleanup
```

**Actions performed:**

1. Disable async logging (if active)
2. Flush buffered messages
3. Close open file descriptors
4. Remove all context loggers
5. Clear benchmark timers
6. Clear rate limits and once-keys

---

### `z::log::register_cleanup`

Register `z::log::cleanup` to run automatically on script exit. Idempotent.

```
z::log::register_cleanup
```

**Hook registration order (tries each in sequence):**

1. `add-zsh-hook zshexit` (preferred — composable)
2. `TRAPEXIT` function (fallback)

**Example:**

```zsh
source zlog
z::log::set_file "/var/log/app.log"
z::log::enable_buffering
z::log::register_cleanup   # Ensures flush on exit

z::log::info "Script started"
# ... work ...
# On exit: cleanup runs automatically, buffer is flushed
```

---

### `z::log::unregister_cleanup`

Remove the exit hook registered by `z::log::register_cleanup`.

```
z::log::unregister_cleanup
```

**Use case:** Testing, or when you want to manage cleanup manually.

---

### `z::log::get_exit_hook_method`

Get the method used to register the exit hook.

```
method=$(z::log::get_exit_hook_method)
echo "$method"   # "zshexit", "trapexit", or "none"
```

---

## 18. Internal Debug Mode

These functions control zlog's own internal diagnostic output (separate from your application's log level).

### `z::log::enable_debug_mode`

Enable internal zlog diagnostics. Prints timestamped `[DEBUG]` lines to stderr for every internal operation.

```
z::log::enable_debug_mode
```

**Example:**

```zsh
z::log::enable_debug_mode
z::log::set_level debug
# → [12:30:45] zlog[DEBUG]: Color mode set to: auto
# → [12:30:45] zlog[DEBUG]: Log level set to: 3 (DEBUG)
```

---

### `z::log::disable_debug_mode`

Disable internal zlog diagnostics.

```
z::log::disable_debug_mode
```

---

### `z::log::is_debug_mode`

Check if internal debug mode is active.

```
z::log::is_debug_mode
```

**Returns:** `0` if enabled, `1` if disabled.

---

## Complete Usage Example

```zsh
#!/usr/bin/env zsh
source ./zlog

# ── Configuration ──────────────────────────────────────────────
z::log::setup "/var/log/myapp.log" info text
z::log::set_rotation 1 "50MB" 10
z::log::enable_buffering 100
z::log::register_cleanup

# ── Basic logging ──────────────────────────────────────────────
z::log::info  "Application started" "version" "2.1.0" "pid" "$$"
z::log::debug "Config loaded" "path" "/etc/myapp.conf"
z::log::warn  "Deprecated option used" "option" "--old-flag"
z::log::error "Connection refused" "host" "db.prod" "port" "5432"

# ── Printf-style ───────────────────────────────────────────────
z::log::infof  "Listening on port %d" 8080
z::log::debugf "Cache hit ratio: %.1f%%" 94.7
z::log::errorf "Exit code %d from: %s" $? "$last_cmd"

# ── Level guards ───────────────────────────────────────────────
if z::log::if_debug; then
  local expensive=$(gather_debug_info)
  z::log::debug "System state" "info" "$expensive"
fi

# ── Context logger ─────────────────────────────────────────────
z::log::with_context "request_id" "req-abc" "user" "alice" "method" "POST"
local ctx="$REPLY"

${ctx}::info  "Request received"
${ctx}::debug "Validating payload" "size" "1024"
${ctx}::warn  "Slow query detected" "duration" "2.3s"
${ctx}::error "Handler failed" "code" "500"
${ctx}::infof "Responded in %dms" 245

z::log::remove_context "$ctx"

# ── Once & rate limiting ───────────────────────────────────────
for host in "${hosts[@]}"; do
  z::log::once "legacy-host-$host" warn "Legacy host detected" "host" "$host"
  z::log::rate_limit "connect-$host" 3 60 info "Connecting" "host" "$host"
done

# ── Benchmarking ───────────────────────────────────────────────
z::log::benchmark "db_migration" run_migration --env prod

z::log::benchmark_start "full_pipeline"; local timer="$REPLY"
stage_one && stage_two && stage_three
z::log::benchmark_end "$timer"

z::log::benchmark_block "data_import" <<'END'
  import_csv /data/users.csv
  import_csv /data/orders.csv
END

# ── Control flow ───────────────────────────────────────────────
z::log::with_level debug run_verbose_tool
z::log::silent run_noisy_library
z::log::always "Deployment complete" "env" "production" "sha" "$GIT_SHA"

# ── Timestamps ─────────────────────────────────────────────────
z::log::get_timestamp iso;   local ts_iso="$REPLY"
z::log::get_timestamp epoch; local ts_epoch="$REPLY"
z::log::format_epoch "$ts_epoch" "%b %d, %Y"
z::log::info "Formatted date" "date" "$REPLY"

# ── Async (high-throughput) ────────────────────────────────────
z::log::enable_async
z::log::enable_performance_mode
for i in {1..100000}; do
  z::log::info "Event $i"
done
z::log::disable_performance_mode
z::log::disable_async

# ── Diagnostics ────────────────────────────────────────────────
z::log::show_config
z::log::get_stats
```

---

## Function Index

| Function                             | Category | Description                        |
|--------------------------------------|----------|------------------------------------|
| `z::log::setup`                      | Config   | One-call quick start               |
| `z::log::error`                      | Core     | Log error (level 0)                |
| `z::log::warn`                       | Core     | Log warning (level 1)              |
| `z::log::info`                       | Core     | Log info (level 2)                 |
| `z::log::debug`                      | Core     | Log debug (level 3)                |
| `z::log::log`                        | Core     | Log at named/numeric level         |
| `z::log::errorf`                     | Printf   | Printf-style error                 |
| `z::log::warnf`                      | Printf   | Printf-style warn                  |
| `z::log::infof`                      | Printf   | Printf-style info                  |
| `z::log::debugf`                     | Printf   | Printf-style debug                 |
| `z::log::if_error`                   | Guards   | Is error level active?             |
| `z::log::if_warn`                    | Guards   | Is warn level active?              |
| `z::log::if_info`                    | Guards   | Is info level active?              |
| `z::log::if_debug`                   | Guards   | Is debug level active?             |
| `z::log::with_level`                 | Control  | Temp level change for command      |
| `z::log::silent`                     | Control  | Suppress all logging for command   |
| `z::log::always`                     | Control  | Force log regardless of level      |
| `z::log::once`                       | Dedup    | Log only first occurrence          |
| `z::log::clear_once`                 | Dedup    | Reset once markers                 |
| `z::log::rate_limit`                 | Dedup    | Max N logs per time window         |
| `z::log::clear_rate_limits`          | Dedup    | Reset rate limit counters          |
| `z::log::with_context`               | Context  | Create context logger              |
| `z::log::remove_context`             | Context  | Remove context logger              |
| `z::log::remove_all_contexts`        | Context  | Remove all contexts                |
| `z::log::list_contexts`              | Context  | List active contexts               |
| `z::log::benchmark`                  | Bench    | Time a command                     |
| `z::log::benchmark_start`            | Bench    | Start manual timer                 |
| `z::log::benchmark_end`              | Bench    | Stop timer and log                 |
| `z::log::benchmark_block`            | Bench    | Time a heredoc block               |
| `z::log::benchmark_now`              | Bench    | Get current ms timestamp           |
| `z::log::benchmark_elapsed`          | Bench    | Elapsed since start                |
| `z::log::list_timers`                | Bench    | List active timers                 |
| `z::log::clear_timers`               | Bench    | Remove all timers                  |
| `z::log::get_timestamp`              | Time     | Get timestamp in any format        |
| `z::log::set_timestamp_format`       | Time     | Set strftime format                |
| `z::log::get_timestamp_format`       | Time     | Get current format                 |
| `z::log::reset_timestamp_format`     | Time     | Reset to default                   |
| `z::log::format_epoch`               | Time     | Format a Unix epoch                |
| `z::log::time_diff`                  | Time     | Duration between two ms timestamps |
| `z::log::time_diff_signed`           | Time     | Duration (supports negative)       |
| `z::log::enable_timestamp_cache`     | Time     | Enable caching (default)           |
| `z::log::disable_timestamp_cache`    | Time     | Disable caching                    |
| `z::log::is_timestamp_cache_enabled` | Time     | Check cache state                  |
| `z::log::set_level`                  | Config   | Set console level                  |
| `z::log::get_level`                  | Config   | Get console level                  |
| `z::log::set_file_level`             | Config   | Set file level                     |
| `z::log::get_file_level`             | Config   | Get file level                     |
| `z::log::set_format`                 | Config   | Set output format                  |
| `z::log::get_format`                 | Config   | Get output format                  |
| `z::log::set_file`                   | Config   | Set log file path                  |
| `z::log::get_file`                   | Config   | Get log file path                  |
| `z::log::show_config`                | Config   | Print config table                 |
| `z::log::reset`                      | Config   | Restore all defaults               |
| `z::log::set_max_message_size`       | Config   | Set message size limit             |
| `z::log::get_max_message_size`       | Config   | Get message size limit             |
| `z::log::set_truncate_marker`        | Config   | Set truncation suffix              |
| `z::log::get_truncate_marker`        | Config   | Get truncation suffix              |
| `z::log::set_rotation`               | Rotation | Configure rotation                 |
| `z::log::set_max_size`               | Rotation | Set max file size (bytes)          |
| `z::log::set_max_files`              | Rotation | Set files to keep                  |
| `z::log::set_rotation_lock_timeout`  | Rotation | Set lock timeout                   |
| `z::log::enable_buffering`           | Buffer   | Enable buffering                   |
| `z::log::disable_buffering`          | Buffer   | Disable buffering                  |
| `z::log::flush`                      | Buffer   | Flush buffer to file               |
| `z::log::get_buffer_count`           | Buffer   | Count buffered messages            |
| `z::log::is_buffered`                | Buffer   | Is buffering active?               |
| `z::log::set_buffer_size`            | Buffer   | Set auto-flush threshold           |
| `z::log::enable_async`               | Async    | Start async worker                 |
| `z::log::disable_async`              | Async    | Stop async worker                  |
| `z::log::is_async`                   | Async    | Is async active?                   |
| `z::log::enable_performance_mode`    | Perf     | Use fast engine                    |
| `z::log::disable_performance_mode`   | Perf     | Restore normal engine              |
| `z::log::colorize`                   | Color    | Apply color to text                |
| `z::log::set_color_mode`             | Color    | Override color detection           |
| `z::log::get_color_mode`             | Color    | Get current color mode             |
| `z::log::show_colors`                | Color    | Print color palette                |
| `z::log::get_stats`                  | Stats    | Print statistics                   |
| `z::log::reset_stats`                | Stats    | Reset counters                     |
| `z::log::clear_sys_cache`            | Stats    | Clear hostname/user/pid cache      |
| `z::log::cleanup`                    | Cleanup  | Release all resources              |
| `z::log::register_cleanup`           | Cleanup  | Register exit hook                 |
| `z::log::unregister_cleanup`         | Cleanup  | Remove exit hook                   |
| `z::log::get_exit_hook_method`       | Cleanup  | Get hook method                    |
| `z::log::enable_debug_mode`          | Debug    | Enable internal diagnostics        |
| `z::log::disable_debug_mode`         | Debug    | Disable internal diagnostics       |
| `z::log::is_debug_mode`              | Debug    | Is debug mode active?              |
