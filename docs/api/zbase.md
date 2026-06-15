# zbase API Reference

> Complete reference for all public-facing functions and constants in `zbase`.
> Every symbol prefixed `z::` or `Z_` is part of the stable public API.
> Symbols prefixed `_z::` or `_ZBASE_` are private internals — do not call or
> depend on them directly.

---

## Table of Contents

1. [Quick Start](#1-quick-start)
2. [Error Codes](#2-error-codes)
3. [Result Convention](#3-result-convention)
4. [Binary Separator Constants](#4-binary-separator-constants)
5. [Time Primitives](#5-time-primitives)
6. [Option Parsing](#6-option-parsing)
7. [Validation](#7-validation)
8. [Filesystem Probes](#8-filesystem-probes)
9. [Command Introspection](#9-command-introspection)
10. [Function Utilities](#10-function-utilities)
11. [Variable Utilities](#11-variable-utilities)
12. [Environment Management](#12-environment-management)
13. [Safe Execution](#13-safe-execution)
14. [File Utilities](#14-file-utilities)

---

## Conventions

| Convention | Meaning |
|---|---|
| `REPLY` | Functions that return a scalar set `$REPLY` instead of using subshells |
| `reply` | Functions that return a list set `$reply` (array) |
| `REPLY2` | Optional secondary scalar; only populated when explicitly documented |
| Returns `0` | Success; non-zero on validation failure or error |
| `ZBASE_ERROR_*` | Named error codes returned by all public functions |
| `_z::` prefix | Private internal function — not part of the public API |
| `_ZBASE_` prefix | Private internal variable — not part of the public API |

---

## 1. Quick Start

```zsh
#!/usr/bin/env zsh

# zlog must be sourced first — zbase depends on it
source ./zlog
source ./zbase

# ── Binary-safe encoding ───────────────────────────────────────
# Use Z_SEP / Z_RECSEP / Z_ESC when building binary-safe records
local record="${field1}${Z_SEP}${field2}${Z_RECSEP}"

# ── Time primitives ────────────────────────────────────────────
z::time::epoch;    local ts_s="$REPLY"
z::time::epoch_ms; local ts_ms="$REPLY"

# ── PATH management ────────────────────────────────────────────
z::env::path_add "$HOME/.local/bin" prepend
z::env::path_add "/opt/tools/bin"

# ── Validation ─────────────────────────────────────────────────
z::validate::nonempty "$1"    "username"    || exit 1
z::validate::integer  "$2"    "port"        || exit 1
z::validate::enum "dev|staging|prod" "$3" "environment" || exit 1

# ── Option parsing ─────────────────────────────────────────────
local -A opts
zparseopts -D -A opts -- f -force v -verbose n -dry-run

z::opt::parse::force   opts; local force=$REPLY
z::opt::parse::verbose opts; local verbose=$REPLY
z::opt::parse::dryrun  opts; local dry_run=$REPLY

z::opt::get opts 'o' 'output' '/tmp/out.log'
local output_file="$REPLY"

# ── Safe execution ─────────────────────────────────────────────
z::exec::run "ls -la /tmp" 10

# ── Tool initialization ────────────────────────────────────────
z::exec::from_hook starship
z::exec::from_hook mise
z::exec::from_hook zoxide init zsh

# ── File sourcing ──────────────────────────────────────────────
z::file::source "$HOME/.config/myapp/config.zsh"
z::file::source --global "$HOME/.zshenv"

# ── Async jobs ─────────────────────────────────────────────────
z::exec::async "sleep 2 && echo done" my_callback
z::exec::wait_all
```

---

## 2. Error Codes

All public `z::*` functions return one of these named codes on failure. Both
`ZBASE_ERROR_*` and `ZCORE_ERROR_*` names refer to the same values —
`ZCORE_ERROR_*` is a backwards-compatible alias retained for callers that
predated the zbase rename.

| Constant | Value | Meaning |
|---|---|---|
| `ZBASE_ERROR_GENERAL` | `1` | Unspecified or catch-all failure |
| `ZBASE_ERROR_INVALID_INPUT` | `2` | Bad argument type, format, or value |
| `ZBASE_ERROR_NOT_FOUND` | `3` | Resource (file, command, variable) not found |
| `ZBASE_ERROR_PERMISSION` | `4` | Permission or safety check denied |

**Example:**

```zsh
z::file::source "/etc/missing.zsh"
local rc=$?

case $rc in
  $ZBASE_ERROR_NOT_FOUND)     echo "File not found"     ;;
  $ZBASE_ERROR_PERMISSION)    echo "Permission denied"  ;;
  $ZBASE_ERROR_INVALID_INPUT) echo "Bad argument"       ;;
  $ZBASE_ERROR_GENERAL)       echo "Unexpected failure" ;;
esac
```

---

## 3. Result Convention

Every public function that produces a value uses these globals as its return
channel. Read the relevant variable **immediately** after the call and before
invoking any other `z::*` function, which may overwrite it.

| Variable | Type | Description |
|---|---|---|
| `REPLY` | scalar | Primary result. Set to `""` on entry; reset to `""` on error |
| `reply` | array | List result. Set to `()` on entry of every list-returning function |
| `REPLY2` | scalar | Optional secondary result. Only populated when explicitly documented |

Functions that never produce a value (pure predicates, setters) do not touch
`REPLY`, `reply`, or `REPLY2`.

**Example:**

```zsh
# Scalar result
z::var::get "MY_VAR" "default_value"
local value="$REPLY"
local type="$REPLY2"   # e.g. "scalar", "integer", "array", "association"

# Array result
z::func::list "z::env::*"
local -a funcs=("${reply[@]}")

# Read immediately — the next z:: call will overwrite REPLY
z::cmd::which "git"
local git_path="$REPLY"
local git_type="$REPLY2"   # "external", "function", "alias", or "builtin"
```

---

## 4. Binary Separator Constants

Three read-only global constants for binary-safe field and record encoding.
Chosen from the C0 control range: outside printable ASCII, extremely unlikely
to appear in real-world values, and safely round-tripped through zsh string
operations.

| Constant | Byte | C0 Name | Role |
|---|---|---|---|
| `Z_SEP` | `\x01` | US — Unit Separator | Field delimiter |
| `Z_RECSEP` | `\x02` | STX — Start of Text | Record delimiter |
| `Z_ESC` | `\x03` | ETX — End of Text | Escape prefix |

All three are declared `typeset -gr` (global, readonly). They are part of the
public contract consumed by `zkv`, `zbus`, and any component that needs
binary-safe encoding.

**Examples:**

```zsh
# Build a binary-safe record
local record="${key}${Z_SEP}${value}${Z_RECSEP}"

# Split a record on the field separator
local -a fields=("${(@s:$Z_SEP:)record}")

# Escape a value that may contain Z_SEP
local safe_value="${value//$Z_SEP/${Z_ESC}${Z_SEP}}"
```

---

## 5. Time Primitives

Zero-dependency, `REPLY`-based time functions. No fork on the hot path when
`zsh/datetime` is loaded (which zbase attempts at startup). All functions set
`$REPLY`; they do not print to stdout.

---

### `z::time::epoch`

Sets `$REPLY` to the current Unix epoch in whole seconds.

```
z::time::epoch
```

**Returns:** `0` always. Sets `$REPLY` to an integer second count.

**Notes:**

- Uses `$EPOCHSECONDS` (from `zsh/datetime`) when available — no fork
- Falls back to `$(date +%s)` otherwise

**Example:**

```zsh
z::time::epoch
local start_ts="$REPLY"
do_work
z::time::epoch
local elapsed=$(( REPLY - start_ts ))
echo "Elapsed: ${elapsed}s"
```

---

### `z::time::epoch_ms`

Sets `$REPLY` to the current Unix epoch in milliseconds. Uses integer string
composition to avoid floating-point precision loss.

```
z::time::epoch_ms
```

**Returns:** `0` always. Sets `$REPLY` to an integer millisecond count.

**Notes:**

- Uses `$EPOCHREALTIME` (from `zsh/datetime`) when available — no fork
- `$EPOCHREALTIME` carries a 6-digit microsecond fraction; only the first 3
  digits (milliseconds) are used
- Falls back to `date +%s%3N`, then `$(date +%s) * 1000`

**Example:**

```zsh
z::time::epoch_ms
local t0="$REPLY"
do_work
z::time::epoch_ms
echo "Elapsed: $(( REPLY - t0 ))ms"
```

---

### `z::time::epoch_ns`

Sets `$REPLY` to the current Unix epoch in nanoseconds.

```
z::time::epoch_ns
```

**Returns:** `0` always. Sets `$REPLY` to an integer nanosecond count.

**Notes:**

- Uses `$EPOCHREALTIME` when available. Because `$EPOCHREALTIME` has
  microsecond precision, the last three nanosecond digits are always `000` —
  this is a known platform limitation, not a bug
- Falls back to `date +%s%N`, then `$(date +%s) * 1000000000`

**Example:**

```zsh
z::time::epoch_ns
local ns_before="$REPLY"
do_work
z::time::epoch_ns
echo "Elapsed: $(( REPLY - ns_before ))ns"
```

---

### `z::time::monotonic_ms`

Sets `$REPLY` to milliseconds since an arbitrary fixed point. Intended for
benchmarks where wall-clock jumps would corrupt measurements.

```
z::time::monotonic_ms
```

**Returns:** `0` always. Sets `$REPLY` to a millisecond count.

**Notes:**

- **Current limitation:** zsh exposes no native `CLOCK_MONOTONIC` and
  `$SECONDS` is also wall-clock. Without a compiled C helper, this function
  falls back to `z::time::epoch_ms`. Callers that require true monotonic
  behaviour should use a compiled helper
- The function signature is stable; the implementation will be upgraded if a
  native monotonic source becomes available

**Example:**

```zsh
z::time::monotonic_ms; local t0="$REPLY"
heavy_operation
z::time::monotonic_ms
echo "Duration: $(( REPLY - t0 ))ms"
```

---

## 6. Option Parsing

Helpers for reading values out of an associative array populated by
`zparseopts`. Array keys are the raw flag strings (e.g. `"-v"`, `"--verbose"`).

### Typical Setup

```zsh
local -A opts
zparseopts -D -A opts -- \
  f -force \
  v -verbose \
  n -dry-run \
  o: -output:

# Then use z::opt::* to read from $opts
```

---

### `z::opt::get`

Retrieve the value of a short or long option from a parsed-options map. Sets
`$REPLY` to the matched value, or to `$default_value` if the flag is absent.
`REPLY2` and `reply` are cleared on entry but not otherwise populated.

```
z::opt::get <opts_var> <short_opt> <long_opt> [default_value]
```

| Parameter | Type | Description |
|---|---|---|
| `opts_var` | string | Name of the associative array holding parsed flags |
| `short_opt` | string | Single-character flag name, without leading `"-"` |
| `long_opt` | string | Long flag name, without leading `"--"` |
| `default_value` | string | Value to use when the flag is absent (default: `""`) |

**Returns:** `0` always. `ZBASE_ERROR_INVALID_INPUT` if `opts_var` is empty.

**Examples:**

```zsh
local -A opts
zparseopts -D -A opts -- o: -output: p: -port: e: -env:

# Read --output / -o with a default
z::opt::get opts 'o' 'output' '/tmp/app.log'
local output_file="$REPLY"   # → /tmp/app.log  (if flag absent)

# Read --port / -p
z::opt::get opts 'p' 'port' '8080'
local port="$REPLY"

# Long-only flag (no short equivalent — pass empty string for short_opt)
z::opt::get opts '' 'env' 'development'
local env="$REPLY"
```

---

### `z::opt::has`

Predicate: returns `0` if the short or long option is present in the map.

```
z::opt::has <opts_var> <short_opt> <long_opt>
```

**Returns:** `0` if present, `1` if absent. `ZBASE_ERROR_INVALID_INPUT` if
`opts_var` is empty. Returns `1` (not an error) if both `short_opt` and
`long_opt` are empty.

**Examples:**

```zsh
local -A opts
zparseopts -D -A opts -- f -force v -verbose

if z::opt::has opts 'f' 'force'; then
  echo "Force mode enabled"
fi

if z::opt::has opts 'v' 'verbose'; then
  echo "Verbose mode enabled"
fi

# Long-only check
if z::opt::has opts '' 'dry-run'; then
  echo "Dry run mode"
fi
```

---

### `z::opt::parse::bool`

Sets `$REPLY` to `1` if the option is present, `0` if absent. Thin wrapper
around `z::opt::has` for boolean flag semantics.

```
z::opt::parse::bool <opts_var> <short_opt> <long_opt>
```

**Returns:** `0` always. Sets `$REPLY` to `1` or `0`.

**Example:**

```zsh
local -A opts
zparseopts -D -A opts -- v -verbose

z::opt::parse::bool opts 'v' 'verbose'
local is_verbose=$REPLY   # → 1 or 0
```

---

### `z::opt::parse::force`

Sets `$REPLY` to `1` if `-f` or `--force` is present, `0` otherwise.

```
z::opt::parse::force <opts_var> [default]
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `opts_var` | string | required | Name of the associative array |
| `default` | `0`\|`1` | `0` | Value when flag is absent; must be `0` or `1` |

**Returns:** `0` always. Sets `$REPLY` to `1` or `0`.

---

### `z::opt::parse::dryrun`

Sets `$REPLY` to `1` if `-n` or `--dry-run` is present, `0` otherwise.

```
z::opt::parse::dryrun <opts_var> [default]
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `opts_var` | string | required | Name of the associative array |
| `default` | `0`\|`1` | `0` | Value when flag is absent; must be `0` or `1` |

**Returns:** `0` always. Sets `$REPLY` to `1` or `0`.

---

### `z::opt::parse::verbose`

Sets `$REPLY` to `1` if `-v` or `--verbose` is present, `0` otherwise.

```
z::opt::parse::verbose <opts_var> [default]
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `opts_var` | string | required | Name of the associative array |
| `default` | `0`\|`1` | `0` | Value when flag is absent; must be `0` or `1` |

**Returns:** `0` always. Sets `$REPLY` to `1` or `0`.

---

### `z::opt::parse::quiet`

Sets `$REPLY` to `1` if `-q` or `--quiet` is present, `0` otherwise.

```
z::opt::parse::quiet <opts_var> [default]
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `opts_var` | string | required | Name of the associative array |
| `default` | `0`\|`1` | `0` | Value when flag is absent; must be `0` or `1` |

**Returns:** `0` always. Sets `$REPLY` to `1` or `0`.

**Combined example:**

```zsh
local -A opts
zparseopts -D -A opts -- f -force n -dry-run v -verbose q -quiet

z::opt::parse::force   opts; local force=$REPLY
z::opt::parse::dryrun  opts; local dry_run=$REPLY
z::opt::parse::verbose opts; local verbose=$REPLY
z::opt::parse::quiet   opts; local quiet=$REPLY

(( force   )) && z::log::warn "Force mode active — skipping safety checks"
(( dry_run )) && z::log::info "Dry run — no changes will be made"
```

---

## 7. Validation

Input-validation helpers. Each function logs a structured error and returns
non-zero on failure, enabling clean `|| return $?` idioms.

### `z::validate::nonempty`

Validates that a value is not an empty string.

```
z::validate::nonempty <value> [field_name]
```

| Parameter | Type | Description |
|---|---|---|
| `value` | string | Value to check |
| `field_name` | string | Human-readable label for error messages (default: `"Value"`) |

**Returns:** `0` if non-empty, `1` if empty.

**Examples:**

```zsh
z::validate::nonempty "$username"    "username"    || return 1
z::validate::nonempty "$config_path" "config_path" || return $ZBASE_ERROR_INVALID_INPUT

my_func() {
  local name="${1:-}"
  z::validate::nonempty "$name" "name" || return $ZBASE_ERROR_INVALID_INPUT
  echo "Hello, $name"
}
```

---

### `z::validate::integer`

Validates that a value is a well-formed integer. Accepts negative integers;
rejects leading zeros on multi-digit values (e.g. `"007"` is rejected).

```
z::validate::integer <value> [field_name]
```

**Returns:** `0` if valid, `1` if not an integer.

**Examples:**

```zsh
z::validate::integer "$port"    "port"    || return 1
z::validate::integer "$timeout" "timeout" || return 1
z::validate::integer "-42"      "offset"  # → valid
z::validate::integer "3.14"     "value"   # → invalid (not an integer)
z::validate::integer "007"      "value"   # → invalid (leading zero)
z::validate::integer "0"        "value"   # → valid (literal zero is accepted)
```

---

### `z::validate::integer::range`

Validates that a value is an integer within an inclusive `[min, max]` range.
Also validates that `min` and `max` are themselves valid integers and that
`min <= max`. Uses base-10 forced arithmetic to prevent octal interpretation.

```
z::validate::integer::range <value> <min> <max> [field_name]
```

| Parameter | Type | Description |
|---|---|---|
| `value` | string | Value to validate |
| `min` | string | Inclusive lower bound |
| `max` | string | Inclusive upper bound |
| `field_name` | string | Human-readable label (default: `"Value"`) |

**Returns:** `0` if valid, `1` on any failure (invalid format, out of range,
or invalid bounds).

**Examples:**

```zsh
z::validate::integer::range "$port"    1    65535 "port"    || return 1
z::validate::integer::range "$workers" 1    32    "workers" || return 1
z::validate::integer::range "$level"   0    3     "level"   || return 1
z::validate::integer::range "$offset"  -100 100   "offset"  || return 1
```

---

### `z::validate::identifier`

Validates that a value is a non-empty string containing only alphanumerics,
underscores, and hyphens. Suitable for user-facing identifiers, keys, and
slugs.

```
z::validate::identifier <name> [context]
```

**Returns:** `0` if valid, `1` if invalid.

**Examples:**

```zsh
z::validate::identifier "$plugin_name" "plugin_name" || return 1
z::validate::identifier "my-service"   "service"     # → valid
z::validate::identifier "my service"   "service"     # → invalid (space)
z::validate::identifier "my.service"   "service"     # → invalid (dot)
```

---

### `z::validate::varname`

Validates that a value is a legal Zsh variable name: must start with a letter
or underscore, followed by zero or more alphanumerics or underscores.

```
z::validate::varname <name> [context]
```

**Returns:** `0` if valid, `1` if invalid.

**Examples:**

```zsh
z::validate::varname "$target_var" "target_var" || return 1
z::validate::varname "_MY_VAR"     "var"        # → valid
z::validate::varname "2bad"        "var"        # → invalid (leading digit)
z::validate::varname "my-var"      "var"        # → invalid (hyphen not allowed)
```

---

### `z::validate::enum`

Validates that a value is one of a pipe-delimited set of allowed values.

```
z::validate::enum <allowed_values> <value> [field_name]
```

| Parameter | Type | Description |
|---|---|---|
| `allowed_values` | string | Pipe-delimited list of valid values (e.g. `"a\|b\|c"`) |
| `value` | string | Value to validate |
| `field_name` | string | Human-readable label (default: `"Value"`) |

**Returns:** `0` if valid, `1` if not in the allowed set or if
`allowed_values` is empty.

**Examples:**

```zsh
z::validate::enum "dev|staging|prod"      "$env"    "environment" || return 1
z::validate::enum "text|json"             "$format" "format"      || return 1
z::validate::enum "prepend|append"        "$pos"    "position"    || return 1
z::validate::enum "error|warn|info|debug" "$level"  "level"       || return 1
```

---

### `z::validate::boolean`

Validates that a value is a recognised boolean representation. Accepted values
are case-insensitive.

```
z::validate::boolean <value> [field_name]
```

| Accepted values | |
|---|---|
| Truthy | `1`, `true`, `yes`, `on` |
| Falsy | `0`, `false`, `no`, `off` |

**Returns:** `0` if valid, `1` if not a recognised boolean.

**Examples:**

```zsh
z::validate::boolean "$enable_feature" "enable_feature" || return 1
z::validate::boolean "true"   "flag"   # → valid
z::validate::boolean "True"   "flag"   # → valid (case-insensitive)
z::validate::boolean "yes"    "flag"   # → valid
z::validate::boolean "maybe"  "flag"   # → invalid
```

---

## 8. Filesystem Probes

Two tiers of filesystem testing:

**Full functions** (`z::probe::path`, `z::probe::path::readable`,
`z::probe::path::writable`) — log structured errors and return named error
codes. Use these when you want automatic error reporting.

**Lightweight predicates** (`z::probe::file`, `z::probe::dir`,
`z::probe::readable`, `z::probe::writable`) — pure filesystem tests with no
logging overhead. Use these in hot paths or simple guards.

---

### `z::probe::path`

Checks that a path exists and optionally matches a specific filesystem type.

```
z::probe::path <path> [path_type] [field_name]
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `path` | string | required | Filesystem path to check |
| `path_type` | string | `any` | `"file"`, `"dir"`, or `"any"` |
| `field_name` | string | `"Path"` | Label for error messages |

**Returns:** `0` if the path exists and matches the type, `1` otherwise.

**Examples:**

```zsh
z::probe::path "/etc/hosts"  file "config file"   || return 1
z::probe::path "/var/log"    dir  "log directory"  || return 1
z::probe::path "/tmp/work"   any  "work path"      || return 1

deploy() {
  z::probe::path "$1" file "deploy script" || return $?
  z::probe::path "$2" dir  "target dir"    || return $?
}
```

---

### `z::probe::path::readable`

Checks that a path exists and is readable by the current process.

```
z::probe::path::readable <path> [field_name]
```

**Returns:** `0` if readable, `1` otherwise.

**Examples:**

```zsh
z::probe::path::readable "/etc/passwd"       "passwd file" || return 1
z::probe::path::readable "$HOME/.ssh/id_rsa" "private key" || return 1
```

---

### `z::probe::path::writable`

Checks that a path is writable. If the path does not yet exist, checks that
its parent directory is writable (i.e. the file could be created).

```
z::probe::path::writable <path> [field_name]
```

**Returns:** `0` if writable (or creatable), `1` otherwise.

**Examples:**

```zsh
z::probe::path::writable "/var/log/app.log"          "log file"     || return 1
z::probe::path::writable "/tmp/new_file.txt"          "output file"  || return 1
z::probe::path::writable "/data/output/results.csv"   "results file" || return 1
```

---

### Lightweight Predicates

Pure filesystem-test one-liners. No logging, no error codes — just a boolean
return value. Suitable for guards in hot paths.

| Function | Test | Equivalent |
|---|---|---|
| `z::probe::file <path>` | Regular file exists | `[[ -f $path ]]` |
| `z::probe::dir <path>` | Directory exists | `[[ -d $path ]]` |
| `z::probe::readable <path>` | Path is readable | `[[ -r $path ]]` |
| `z::probe::writable <path>` | Path is writable | `[[ -w $path ]]` |

**Examples:**

```zsh
if z::probe::file "$config"; then
  source "$config"
fi

z::probe::dir "$cache_dir" || mkdir -p "$cache_dir"

if ! z::probe::writable "$log_file"; then
  echo "Cannot write to log" >&2
  exit 1
fi
```

---

### `z::probe::cmd`

Returns `0` if a command is resolvable as any of: external binary, function,
builtin, or alias.

```
z::probe::cmd <cmd>
```

**Returns:** `0` if found in any namespace, `1` if not found.
`ZBASE_ERROR_INVALID_INPUT` if `cmd` is empty.

**Examples:**

```zsh
z::probe::cmd "git"     || { echo "git required"; exit 1; }
z::probe::cmd "jq"      || z::log::warn "jq not found; JSON output disabled"
z::probe::cmd "my_func" && my_func --init
```

---

### `z::probe::func`

Returns `0` if a Zsh function with the given name is currently defined.

```
z::probe::func <func>
```

**Returns:** `0` if defined, `1` if not. `ZBASE_ERROR_INVALID_INPUT` if
`func` is empty.

**Examples:**

```zsh
if z::probe::func "my_plugin::init"; then
  my_plugin::init
fi

z::probe::func "cleanup_handler" && cleanup_handler
```

---

### `z::probe::var`

Returns `0` if a variable with the given name is currently set (any type).

```
z::probe::var <name>
```

**Returns:** `0` if set, `1` if unset. `ZBASE_ERROR_INVALID_INPUT` if `name`
is empty.

**Examples:**

```zsh
if z::probe::var "MY_CONFIG"; then
  z::log::debug "Using existing config" value "$MY_CONFIG"
fi

z::probe::var "PLUGIN_LOADED" || source plugin.zsh
```

---

## 9. Command Introspection

### `z::cmd::which`

Locate a command and report its type. Sets `$REPLY` to the resolved path or
definition, and `$REPLY2` to the type string.

Resolution order: **function → alias → builtin → external command**

```
z::cmd::which <cmd>
```

**Returns:** `0` on success. `ZBASE_ERROR_NOT_FOUND` if not found.
`ZBASE_ERROR_INVALID_INPUT` if `cmd` is empty.

| `$REPLY2` value | Meaning | `$REPLY` content |
|---|---|---|
| `function` | Defined Zsh function | Function body source |
| `alias` | Shell alias | Alias expansion string |
| `builtin` | Zsh builtin | Command name (same as input) |
| `external` | Binary on `$PATH` | Absolute path to binary |

**Examples:**

```zsh
z::cmd::which "ls"
echo "$REPLY"    # → /bin/ls
echo "$REPLY2"   # → external

z::cmd::which "cd"
echo "$REPLY2"   # → builtin

z::cmd::which "ll"
echo "$REPLY2"   # → alias  (if ll is aliased)

z::cmd::which "my_func"
echo "$REPLY2"   # → function

if ! z::cmd::which "required_tool"; then
  z::log::error "required_tool is not installed"
  exit $ZBASE_ERROR_NOT_FOUND
fi
local tool_path="$REPLY"
```

---

## 10. Function Utilities

### `z::func::call`

Call a named function with optional arguments. In debug mode, automatically
wraps the call with a context logger and benchmark timer for tracing.

```
z::func::call <func> [args ...]
```

| Parameter | Type | Description |
|---|---|---|
| `func` | string | Name of the function to call |
| `args` | any | Arguments forwarded to the function |

**Returns:** Exit code of the called function. `ZBASE_ERROR_NOT_FOUND` if the
function is not defined. `ZBASE_ERROR_INVALID_INPUT` if `func` is empty.

**Examples:**

```zsh
z::func::call "my_deploy" --env prod --force
local rc=$?

# Dynamic dispatch
local handler="handle_${event_type}"
if z::probe::func "$handler"; then
  z::func::call "$handler" "$payload"
fi

# In debug mode, the following are logged automatically:
# [DEBUG] func=my_deploy | Calling function argc=2
# [INFO ] Benchmark: z::func::call:my_deploy | duration=245ms
# [DEBUG] func=my_deploy | Function returned non-zero exit_code=1
```

---

### `z::func::unset`

Remove a function definition from the current shell environment.

```
z::func::unset <target>
```

**Returns:** `0` on success. `ZBASE_ERROR_NOT_FOUND` if not defined.
`ZBASE_ERROR_INVALID_INPUT` if `target` is empty. `ZBASE_ERROR_GENERAL` if
`unfunction` fails unexpectedly.

**Examples:**

```zsh
z::func::unset "my_temp_func"

if z::probe::func "legacy_init"; then
  z::func::unset "legacy_init"
fi
```

---

### `z::func::list`

List all defined functions matching an optional glob pattern. Sets `$reply`
to the sorted array and prints each name on its own line for pipeline
consumers.

```
z::func::list [pattern]
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `pattern` | glob | `*` | Glob pattern to filter function names |

**Returns:** `0` always. Sets `$reply` to the sorted matching function names.
Also prints each name to stdout (one per line) for pipeline use.

**Notes:**

- Passing an explicit empty string as the pattern triggers a one-time warning
  and defaults to `*`

**Examples:**

```zsh
# List all functions
z::func::list
local -a all_funcs=("${reply[@]}")

# List all z::env:: functions
z::func::list "z::env::*"
local -a env_funcs=("${reply[@]}")

# Pipeline use
z::func::list "z::*" | grep "validate"
```

---

## 11. Variable Utilities

### `z::var::get`

Retrieve the value of a variable by name. Sets `$REPLY` to the value (or
`$default` if unset) and `$REPLY2` to the Zsh type string.

```
z::var::get <name> [default]
```

| Parameter | Type | Description |
|---|---|---|
| `name` | string | Variable name to read |
| `default` | string | Value to return if the variable is unset (default: `""`) |

**Returns:** `0` always. Sets `$REPLY` to the value and `$REPLY2` to the Zsh
type string (e.g. `"scalar"`, `"array"`, `"integer"`, `"association"`).

**Notes:**

- If `name` is empty, returns immediately with `REPLY=""` and no error
- `$REPLY2` is the raw `${(tP)name}` type string from zsh, which may include
  qualifiers such as `"scalar-export"` or `"array-readonly"`

**Examples:**

```zsh
z::var::get "MY_CONFIG" "/etc/default.conf"
local config="$REPLY"
local type="$REPLY2"   # → "scalar" or "scalar-export", etc.

z::var::get "UNSET_VAR" "fallback"
echo "$REPLY"   # → fallback

z::var::get "MY_ARRAY"
if [[ $REPLY2 == *array* ]]; then
  echo "It's an array"
fi
```

---

### `z::var::set`

Set a global variable by name. Validates the name before assignment.

```
z::var::set <name> [value]
```

**Returns:** `0` on success. `ZBASE_ERROR_INVALID_INPUT` if `name` is not a
valid Zsh identifier.

**Examples:**

```zsh
z::var::set "APP_ENV"     "production"
z::var::set "APP_VERSION" "2.1.0"
z::var::set "APP_DEBUG"   "0"

local var_name="PLUGIN_${plugin_id}_LOADED"
z::var::set "$var_name" "1"
```

---

### `z::var::unset`

Remove a variable from the current shell environment. Refuses to unset
readonly variables.

```
z::var::unset <target>
```

**Returns:** `0` on success. `ZBASE_ERROR_NOT_FOUND` if not set.
`ZBASE_ERROR_PERMISSION` if readonly. `ZBASE_ERROR_INVALID_INPUT` if `target`
is empty. `ZBASE_ERROR_GENERAL` if `unset` fails unexpectedly.

**Examples:**

```zsh
z::var::unset "TEMP_TOKEN"

if z::probe::var "OLD_CONFIG"; then
  z::var::unset "OLD_CONFIG"
fi
```

---

## 12. Environment Management

### `z::env::path_add`

Add a directory to `$PATH` with duplicate detection and optional position
control. Skips silently if the directory does not exist.

```
z::env::path_add <dir> [position]
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `dir` | string | required | Directory to add. Tilde and relative paths are normalized |
| `position` | string | `append` | `"prepend"` or `"append"` |

**Returns:** `0` on success or if already in `$PATH`.
`ZBASE_ERROR_NOT_FOUND` if the directory does not exist.
`ZBASE_ERROR_INVALID_INPUT` on bad arguments.

**Notes:**

- Tilde expansions (`~`, `~/...`, `~+`, `~-`) are resolved before comparison
- Relative paths are resolved relative to `$PWD`
- Invalidates the command hash table (`hash -r`) after modification
- Duplicate detection uses the normalized absolute path

**Examples:**

```zsh
z::env::path_add "$HOME/.local/bin" prepend
z::env::path_add "/opt/homebrew/bin" prepend
z::env::path_add "/opt/tools/bin"
z::env::path_add "bin"               # relative → $PWD/bin
z::env::path_add "~/.cargo/bin" prepend
```

---

### `z::env::path_remove`

Remove all occurrences of a directory from `$PATH`.

```
z::env::path_remove <dir>
```

**Returns:** `0` always (removing a non-present directory is a no-op).
`ZBASE_ERROR_INVALID_INPUT` if `dir` is empty.

**Examples:**

```zsh
z::env::path_remove "/opt/old-tools/bin"
z::env::path_remove "$HOME/.rbenv/bin"
```

---

### `z::env::path_has`

Predicate: returns `0` if a directory is currently in `$PATH`.

```
z::env::path_has <dir>
```

**Returns:** `0` if present, `1` if absent. `ZBASE_ERROR_INVALID_INPUT` if
`dir` is empty.

**Examples:**

```zsh
if z::env::path_has "/usr/local/bin"; then
  z::log::debug "Standard local bin already in PATH"
fi

z::env::path_has "$HOME/.cargo/bin" || z::env::path_add "$HOME/.cargo/bin"
```

---

### `z::env::alias_set`

Create or update a shell alias. Validates the name and verifies the alias was
registered after creation.

```
z::env::alias_set <alias_name> <alias_value>
```

**Returns:** `0` on success. `ZBASE_ERROR_INVALID_INPUT` if either argument is
empty or the name contains spaces or `=`. `ZBASE_ERROR_GENERAL` if the alias
was not registered after creation.

**Examples:**

```zsh
z::env::alias_set "ll"   "ls -lah"
z::env::alias_set "gs"   "git status"
z::env::alias_set "k"    "kubectl"
z::env::alias_set "grep" "grep --color=auto"
```

---

### `z::env::alias_unset`

Remove an alias from the current shell environment.

```
z::env::alias_unset <alias_name>
```

**Returns:** `0` on success. `ZBASE_ERROR_NOT_FOUND` if the alias is not
defined. `ZBASE_ERROR_INVALID_INPUT` if `alias_name` is empty.
`ZBASE_ERROR_GENERAL` if removal fails unexpectedly.

**Examples:**

```zsh
z::env::alias_unset "ll"
z::env::alias_unset "old_shortcut"
```

---

### `z::env::export`

Set and export a variable to the environment of child processes. Validates the
name before assignment.

```
z::env::export <name> [value]
```

**Returns:** `0` on success. `ZBASE_ERROR_INVALID_INPUT` if `name` is not a
valid Zsh identifier.

**Examples:**

```zsh
z::env::export "APP_ENV"      "production"
z::env::export "DATABASE_URL" "postgres://localhost/mydb"
z::env::export "DEBUG"        "0"
z::env::export "API_KEY"      "$secret_key"
```

---

## 13. Safe Execution

The execution subsystem provides a layered security model for running shell
commands from strings.

### Security Model

| Layer | Function | What it blocks |
|---|---|---|
| Metacharacter check | `z::exec::run` | `;` `&` `(` `)` `` ` `` — compound commands and subshells |
| Pattern scanner | `z::exec::scan` | Fork bombs, `rm -rf /`, `dd of=/dev/<disk>`, direct shell invocations |
| Trusted eval | `_z::exec::eval_trusted` | Nothing — explicit trust boundary for known tool output |

---

### `z::exec::scan`

Lexically scan a command string for dangerous patterns. Does **not** parse
shell syntax — uses whitespace tokenization and heuristics.

```
z::exec::scan <input>
```

**Returns:** `0` if no dangerous patterns found, `1` if blocked (also logs
via `z::log::always`). `ZBASE_ERROR_INVALID_INPUT` if `input` is empty.

**Blocked patterns:**

| Pattern | Example |
|---|---|
| Fork bomb | `:() { :|: & }; :` |
| Direct shell invocation | `bash script.sh`, `zsh -c "..."` |
| Dangerous `rm` | `rm -rf /`, `rm -rf ~`, `rm --no-preserve-root -rf /` |
| Dangerous `dd` | `dd if=/dev/zero of=/dev/sda`, `dd if=x of=/dev/nvme0n1` |

**Notes:**

- Whitelisted init commands (matching `_ZBASE_EXEC_INIT_CMD_RE`) bypass all
  pattern scanning
- Scanning is lexical (whitespace-split), not syntactic; quoted arguments
  containing spaces may not be detected correctly

**Examples:**

```zsh
if z::exec::scan "$user_input"; then
  echo "Input is safe"
else
  echo "Dangerous input rejected"
fi

z::exec::is_safe "$user_input" && process_input "$user_input"
```

---

### `z::exec::is_safe`

Alias for `z::exec::scan`. Returns `0` if the input passes all security
checks.

```
z::exec::is_safe <input>
```

---

### `z::exec::run`

Execute a command string in a child `zsh -c` process with optional timeout.
Applies the metacharacter check and security scanner before execution.

```
z::exec::run <input> [timeout]
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `input` | string | required | Command string to execute |
| `timeout` | int | `30` | Timeout in seconds. `0` = no timeout. Max: `3600` |

**Returns:** Exit code of the command, or:

| Code | Meaning |
|---|---|
| `ZBASE_ERROR_INVALID_INPUT` | Empty input or invalid/out-of-range timeout |
| `ZBASE_ERROR_PERMISSION` | Metacharacters or scanner blocked the input |
| `124` | Command timed out (POSIX `timeout(1)` sentinel) |

**Notes:**

- Runs in a child `zsh -o pipefail -c` process — **cannot** modify the
  caller's environment
- Uses `gtimeout` (preferred on macOS) or `timeout` if available; degrades
  gracefully without them, logging a one-time debug warning
- Shell init commands (matching `_ZBASE_EXEC_INIT_CMD_RE`) bypass the
  metacharacter check but still go through the pattern scanner

**Examples:**

```zsh
z::exec::run "ls -la /tmp"
z::exec::run "curl -s https://api.example.com/health" 10

z::exec::run "make -j4" 300
local rc=$?
if (( rc == 124 )); then
  z::log::error "Build timed out after 300s"
elif (( rc != 0 )); then
  z::log::error "Build failed" exit_code "$rc"
fi

z::exec::run "long_running_process" 0   # no timeout
```

---

### `z::exec::eval`

Thin wrapper around `z::exec::run`. Provided as a semantic alias for callers
that prefer "eval" terminology. Identical behaviour and return codes.

```
z::exec::eval <input> [timeout]
```

**Returns:** Same as `z::exec::run`.

**Example:**

```zsh
z::exec::eval "$dynamic_command" 60
```

---

### `z::exec::from_hook`

Initialize a known shell tool by running its init subcommand and eval'ing the
output in the **live shell environment**. Skips silently if the tool is not
installed.

```
z::exec::from_hook <tool_name> [subcommand] [shell_arg]
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `tool_name` | string | required | Name of the tool binary (looked up via `$commands[]`) |
| `subcommand` | string | `init` | Subcommand passed as the first argument to the tool |
| `shell_arg` | string | `zsh` | Shell name passed as the second argument to the tool |

The tool is invoked as: `<tool_name> <subcommand> <shell_arg>`

**Returns:** `0` if initialized successfully, if the tool is not found, or if
the tool produced no output. `ZBASE_ERROR_GENERAL` if the tool's init output
fails to eval.

**Notes:**

- The tool's output is eval'd via `_z::exec::eval_trusted`, which runs in the
  **live shell** without `emulate -L zsh` — tool init code can modify `$PATH`,
  set hooks, configure the prompt, define functions, etc.
- The tool binary resolved via `$commands[]` is the trust boundary; its output
  is **not** pattern-scanned (unlike `z::exec::run`)
- If the tool exits non-zero but still produces output, the output is eval'd
  and a debug message is logged
- In debug mode, wraps the entire init in a benchmark timer

**Examples:**

```zsh
# Standard two-argument init (tool init zsh)
z::exec::from_hook starship          # → starship init zsh
z::exec::from_hook mise              # → mise init zsh
z::exec::from_hook direnv            # → direnv init zsh
z::exec::from_hook zoxide            # → zoxide init zsh
z::exec::from_hook atuin             # → atuin init zsh

# Custom subcommand
z::exec::from_hook pyenv "init" "-"  # → pyenv init -
```

---

### `z::exec::async`

Run a command string in a background subshell via `z::exec::run`. Tracks the
PID and optionally calls a callback function when the job completes.

```
z::exec::async <cmd> [callback]
```

| Parameter | Type | Description |
|---|---|---|
| `cmd` | string | Command string to run asynchronously |
| `callback` | string | Optional function name; called as `callback <exit_code> <output>` |

**Returns:** `0` on success; `$REPLY` = PID of the background job.
`ZBASE_ERROR_INVALID_INPUT` if `cmd` is empty. `ZBASE_ERROR_GENERAL` if the
PID cap (`50`) is reached.

**Notes:**

- Dead PIDs are pruned automatically before each new job is launched
- The callback receives combined stdout+stderr as its second argument
- Call `z::exec::wait_all` to reap all pending jobs before the shell exits

**Examples:**

```zsh
# Fire and forget
z::exec::async "rsync -av /src/ /backup/"
local job_pid="$REPLY"

# With callback
on_build_done() {
  local exit_code="$1" output="$2"
  if (( exit_code == 0 )); then
    z::log::info "Build succeeded"
  else
    z::log::error "Build failed" output "$output"
  fi
}

z::exec::async "make -j4" on_build_done

# Multiple parallel jobs
z::exec::async "process_shard_1.sh"
z::exec::async "process_shard_2.sh"
z::exec::async "process_shard_3.sh"
z::exec::wait_all
```

---

### `z::exec::wait_all`

Wait for all tracked async jobs to complete. Clears the internal PID list.

```
z::exec::wait_all
```

**Returns:** `0` if all jobs succeeded. Non-zero exit code of the last failed
job. Exit code `127` (already reaped or never existed) is treated as success.

**Examples:**

```zsh
z::exec::async "job_a.sh"
z::exec::async "job_b.sh"
z::exec::async "job_c.sh"

z::exec::wait_all
local rc=$?
if (( rc != 0 )); then
  z::log::error "One or more async jobs failed" last_exit_code "$rc"
fi
```

---

## 14. File Utilities

### `z::file::resolve`

Resolve a path to its physical (non-symlink) location, following symlink
chains up to 40 steps. Detects and aborts on cycles. Sets `$REPLY` to the
resolved path.

```
z::file::resolve <path>
```

**Returns:** `0` on success; `$REPLY` = physical path.
`ZBASE_ERROR_INVALID_INPUT` if path is empty or whitespace-only.
`ZBASE_ERROR_GENERAL` if max iterations exceeded or a symlink cycle is
detected (`$REPLY` is set to the last known path before the error).

**Notes:**

- Uses `zsh/stat` (`zstat`) if available (zero-fork); otherwise falls back to
  `readlink(1)`
- Tilde and relative paths are normalized before resolution
- Uses `cd -P && pwd -P` to resolve the physical directory component
- If neither `zsh/stat` nor `readlink` is available, symlink resolution is
  skipped and the normalized path is returned as-is

**Examples:**

```zsh
z::file::resolve "/usr/bin/python3"
local real_path="$REPLY"
# → /usr/bin/python3.12  (or wherever the chain ends)

z::file::resolve "~/bin/my-script"
echo "$REPLY"   # → /home/alice/bin/my-script

z::file::resolve "/etc/localtime"
echo "$REPLY"   # → /usr/share/zoneinfo/America/New_York

if ! z::file::resolve "$symlink_path"; then
  z::log::warn "Could not resolve symlink" path "$symlink_path"
fi
```

---

### `z::file::source`

Source a file with optional scope control. Validates, normalizes, and
readability-checks the path before sourcing. In debug mode, wraps the source
in a benchmark timer.

```
z::file::source [--global] <file> [args ...]
```

| Parameter | Type | Description |
|---|---|---|
| `--global` | flag | Source in the live shell scope (no `emulate -L`). Required for files that modify shell options, define hooks, or configure the prompt |
| `file` | string | Path to the file to source |
| `args` | any | Additional arguments passed to the sourced file as `$@` |

**Returns:** Exit code of the sourced file, or a `ZBASE_ERROR_*` code on
failure.

**Scope behaviour:**

| Mode | Shell options | Use case |
|---|---|---|
| Default | `emulate -L zsh` + `extendedglob warncreateglobal typesetsilent noshortloops nopromptsubst` | Library files, config files, plugins |
| `--global` | Live shell environment (no emulate) | `.zshenv`, tool init files, prompt themes |

**Notes:**

- Symlink resolution is skipped when `_ZBASE_PERF_MODE=1`
- The file must exist as a regular file and be readable; a warning is logged
  and `ZBASE_ERROR_NOT_FOUND` is returned otherwise

**Examples:**

```zsh
# Standard isolated scope
z::file::source "$HOME/.config/myapp/config.zsh"
z::file::source "/usr/local/lib/mylib.zsh"

# Live shell scope — needed for files that set options or hooks
z::file::source --global "$HOME/.zshenv"
z::file::source --global "/etc/zsh/zshrc.d/prompt.zsh"

# Pass arguments to the sourced file ($@ inside the file will be set)
z::file::source "setup.zsh" "--env" "production" "--debug"

# Error handling
if ! z::file::source "$plugin_file"; then
  z::log::warn "Plugin failed to load" path "$plugin_file"
fi

# Conditional sourcing
local extra_config="$HOME/.zshrc.local"
z::probe::file "$extra_config" && z::file::source "$extra_config"
```

---

## Function & Constant Index

| Symbol | Category | Description |
|---|---|---|
| `Z_SEP` | Constants | Field delimiter (`\x01`) |
| `Z_RECSEP` | Constants | Record delimiter (`\x02`) |
| `Z_ESC` | Constants | Escape prefix (`\x03`) |
| `z::time::epoch` | Time | Current Unix epoch in seconds |
| `z::time::epoch_ms` | Time | Current Unix epoch in milliseconds |
| `z::time::epoch_ns` | Time | Current Unix epoch in nanoseconds |
| `z::time::monotonic_ms` | Time | Monotonic milliseconds (falls back to epoch_ms) |
| `z::opt::get` | Options | Get option value from parsed-opts map |
| `z::opt::has` | Options | Check if option is present |
| `z::opt::parse::bool` | Options | Parse any flag as boolean |
| `z::opt::parse::force` | Options | Parse `-f` / `--force` |
| `z::opt::parse::dryrun` | Options | Parse `-n` / `--dry-run` |
| `z::opt::parse::verbose` | Options | Parse `-v` / `--verbose` |
| `z::opt::parse::quiet` | Options | Parse `-q` / `--quiet` |
| `z::validate::nonempty` | Validation | Reject empty strings |
| `z::validate::integer` | Validation | Validate integer format |
| `z::validate::integer::range` | Validation | Validate integer within bounds |
| `z::validate::identifier` | Validation | Validate alphanumeric/hyphen/underscore |
| `z::validate::varname` | Validation | Validate Zsh variable name |
| `z::validate::enum` | Validation | Validate against allowed values |
| `z::validate::boolean` | Validation | Validate boolean representation |
| `z::probe::path` | Probes | Check path existence and type |
| `z::probe::path::readable` | Probes | Check path is readable |
| `z::probe::path::writable` | Probes | Check path is writable or creatable |
| `z::probe::file` | Probes | Lightweight regular-file test |
| `z::probe::dir` | Probes | Lightweight directory test |
| `z::probe::readable` | Probes | Lightweight readable test |
| `z::probe::writable` | Probes | Lightweight writable test |
| `z::probe::cmd` | Probes | Check command exists in any namespace |
| `z::probe::func` | Probes | Check function is defined |
| `z::probe::var` | Probes | Check variable is set |
| `z::cmd::which` | Introspection | Locate command and report type |
| `z::func::call` | Functions | Call function with debug tracing |
| `z::func::unset` | Functions | Remove function definition |
| `z::func::list` | Functions | List functions by glob pattern |
| `z::var::get` | Variables | Get variable value by name |
| `z::var::set` | Variables | Set global variable by name |
| `z::var::unset` | Variables | Remove variable |
| `z::env::path_add` | Environment | Add directory to `$PATH` |
| `z::env::path_remove` | Environment | Remove directory from `$PATH` |
| `z::env::path_has` | Environment | Check directory is in `$PATH` |
| `z::env::alias_set` | Environment | Create or update alias |
| `z::env::alias_unset` | Environment | Remove alias |
| `z::env::export` | Environment | Set and export variable |
| `z::exec::scan` | Execution | Scan command string for dangerous patterns |
| `z::exec::is_safe` | Execution | Predicate alias for `z::exec::scan` |
| `z::exec::run` | Execution | Run command string in child shell |
| `z::exec::eval` | Execution | Semantic alias for `z::exec::run` |
| `z::exec::from_hook` | Execution | Initialize tool via its init subcommand |
| `z::exec::async` | Execution | Run command in background with PID tracking |
| `z::exec::wait_all` | Execution | Wait for all async jobs |
| `z::file::resolve` | Files | Resolve path through symlink chain |
| `z::file::source` | Files | Source file with scope control |
