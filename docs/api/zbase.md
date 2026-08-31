# zbase API Reference

> Complete reference for all public-facing functions and constants in
> `zbase` v3. Every symbol prefixed `z::is::`, `z::ensure::`, `z::get::`,
> `z::set::`, `z::do::`, `Z_ERR_`, `Z_SEP`, `Z_RECSEP`, or `Z_ESC` is part
> of the stable public API. Symbols prefixed `_z::` or `_Z_` are private
> internals — do not call or depend on them directly.

---

## Table of Contents

1. [Quick Start](#1-quick-start)
2. [Error Codes](#2-error-codes)
3. [Result Convention](#3-result-convention)
4. [Binary Separator Constants](#4-binary-separator-constants)
5. [Time](#5-time)
6. [Predicates — `z::is::`](#6-predicates--zis)
7. [Guards — `z::ensure::`](#7-guards--zensure)
8. [Value Queries — `z::get::`](#8-value-queries--zget)
9. [Mutators — `z::set::`](#9-mutators--zset)
10. [Effects — `z::do::`](#10-effects--zdo)
11. [Dependencies](#11-dependencies)

---

## Conventions

| Convention | Meaning |
|---|---|
| `REPLY` | Scalar result channel for functions that document it |
| `reply` | Array result channel (`z::get::funcs`) |
| `REPLY2` | Secondary scalar; only populated when documented |
| Returns `0` | Success; non-zero on validation failure or error |
| `Z_ERR_*` | Named error codes returned by public functions |
| `_z::` prefix | Private internal function — not part of the public API |

The **verb root is the contract**:

| Root | Contract |
|---|---|
| `z::is::` | Silent predicate — branch on `$?`, never sets `REPLY` |
| `z::ensure::` | Guard — returns a code, logs on failure, never sets `REPLY` |
| `z::get::` | Value query — uses the documented `REPLY`, `reply`, or stdout channel |
| `z::set::` | State mutator — status only, never sets `REPLY` |
| `z::do::` | Effects — sets `REPLY` only where documented (`run_async`) |

---

## 1. Quick Start

```zsh
#!/usr/bin/env zsh
source /path/to/zcore/zcore.zsh
# or, for zbase alone: source zlog; source zbase

main() {
  # ── Predicates ───────────────────────────────────────────────
  z::is::file "$path" || return
  z::is::int  "$port" || return

  # ── Guards (log on failure) ──────────────────────────────────
  z::ensure::nonempty "$1" "username" || return 1
  z::ensure::int      "$2" "port"     || return 1
  z::ensure::enum "dev|staging|prod" "$3" "environment" || return 1

  # ── Time ─────────────────────────────────────────────────────
  z::get::epoch;    local ts_s="$REPLY"
  z::get::epoch_ms; local ts_ms="$REPLY"

  # ── Option parsing ───────────────────────────────────────────
  local -A opts
  zparseopts -D -A opts -- f -force v -verbose n -dry-run
  z::get::flag_force   opts; local force=$REPLY
  z::get::flag_verbose opts; local verbose=$REPLY
  z::get::opt opts o output /tmp/out.log
  local output_file="$REPLY"

  # ── Paths ────────────────────────────────────────────────────
  z::get::abspath  ~/src;  local abs="$REPLY"
  z::get::realpath /usr/bin/python; local real="$REPLY"

  # ── Effects ──────────────────────────────────────────────────
  z::do::run "ls -la /tmp" 10
  z::do::hook starship
  z::do::source "$HOME/.config/myapp/config.zsh"
}

main "$@"
```

---

## 2. Error Codes

Public `zbase` functions that can fail use these named codes where their
individual contract does not specify a plain predicate or command status.
There are no `ZBASE_ERROR_*` aliases.

| Constant | Value | Meaning |
|---|---|---|
| `Z_ERR_GENERAL` | 1 | Unspecified or catch-all failure |
| `Z_ERR_INPUT` | 2 | Bad argument type, format, or value |
| `Z_ERR_NOTFOUND` | 3 | Resource (file, command, variable) not found |
| `Z_ERR_PERM` | 4 | Permission or safety check denied |

Most `z::ensure::*` guards return a plain `1` on failure. `z::ensure::cmd`,
`z::ensure::func`, and `z::ensure::var` return `Z_ERR_INPUT` /
`Z_ERR_NOTFOUND` instead.

```zsh
z::get::realpath "$path" || {
  case $? in
    $Z_ERR_INPUT)    print -u2 "empty path" ;;
    $Z_ERR_GENERAL)  print -u2 "symlink cycle" ;;
  esac
  return 1
}
```

Module-specific codes (for example `ZCORE_ERROR_TIMEOUT=124` in `z`) live
in the module that defines them.

---

## 3. Result Convention

- Read `REPLY`, `reply`, and `REPLY2` **immediately** after the call,
  before calling another zcore function.
- `z::is::` and `z::ensure::` never use the return channels for a result.
- Most `z::get::` functions write `REPLY`; list and discovery functions may
  use `reply` or stdout when documented. Read the function contract rather
  than inferring the channel from the namespace alone.
- On error, `REPLY` is `""` or the documented default.
- Emit-path `zlog` is REPLY-neutral; raising the log level does not change
  the values your code receives.

---

## 4. Binary Separator Constants

Shared with `zkv` and `zbus` for binary-safe records:

| Constant | Byte | Role |
|---|---|---|
| `Z_SEP` | `\x01` | Field delimiter |
| `Z_RECSEP` | `\x02` | Record delimiter |
| `Z_ESC` | `\x03` | Escape prefix |

Declared `typeset -gr`. Callers that build records must encode values that
contain these bytes.

---

## 5. Time

All four functions always return `0`. They set `REPLY` and clear `REPLY2`
and `reply`.

| Function | `REPLY` |
|---|---|
| `z::get::epoch` | Whole seconds since the Unix epoch |
| `z::get::epoch_ms` | Milliseconds since the epoch |
| `z::get::epoch_ns` | Nanoseconds since the epoch (last three digits are `0`; zsh has microsecond resolution) |
| `z::get::mono_ms` | Alias of `z::get::epoch_ms` |

`z::get::mono_ms` is wall-clock time: zsh exposes no monotonic clock, so a
system clock adjustment can make two successive readings go backwards.

```zsh
z::get::epoch_ms
local start=$REPLY
# ... work ...
z::get::epoch_ms
print $(( REPLY - start ))   # elapsed ms
```

---

## 6. Predicates — `z::is::`

Every predicate answers through `$?` alone: no logging, no fork, and the
return channels are left exactly as the caller left them. A missing or
empty argument is a "no" (return 1), never an error.

### Filesystem

| Function | Yes when |
|---|---|
| `z::is::file <path>` | Regular file (`-f`); follows symlinks |
| `z::is::dir <path>` | Directory (`-d`); follows symlinks |
| `z::is::readable <path>` | Readable (`-r`) |
| `z::is::writable <path>` | Writable (`-w`) |
| `z::is::exec <path>` | Executable (`-x`) |

### Shell tables

| Function | Yes when |
|---|---|
| `z::is::cmd <name>` | External command, function, builtin, or alias (no `$PATH` walk) |
| `z::is::func <name>` | Function is defined |
| `z::is::builtin <name>` | Builtin is defined |
| `z::is::alias <name>` | Alias is defined |
| `z::is::var <name>` | Parameter is declared (empty still counts) |
| `z::is::set <name>` | Alias of `z::is::var` |

### Values

| Function | Yes when |
|---|---|
| `z::is::empty <value>` | The value is the empty string (takes the value, not a name) |
| `z::is::blank <value>` | Empty or whitespace only |
| `z::is::int <value>` | Canonical decimal integer: optional minus, no leading zeros, no surrounding whitespace |
| `z::is::bool <value>` | One of `0`, `1`, `true`, `false`, `yes`, `no`, `on`, `off` (case-insensitive). Tests spelling only |

### Types and options

| Function | Yes when |
|---|---|
| `z::is::assoc <name>` | Named parameter exists and is an associative array |
| `z::is::array <name>` | Named parameter exists and is an array. Associative arrays also match — use `z::is::assoc` to tell them apart |
| `z::is::opt <opts-assoc-name> [short] [long]` | The named assoc holds `-<short>` or `--<long>` |
| `z::is::path <dir>` | Directory is present in `$path` (absolutised first; compared literally) |

`z::is::path` saves and restores the return channels around an internal
`z::get::abspath` call, so the `z::is::` contract still holds.

```zsh
z::is::int "$port" || { print -u2 "not an integer"; return 1; }
z::is::cmd jq     || { print -u2 "jq required";     return 1; }
```

---

## 7. Guards — `z::ensure::`

Each guard validates one condition, logs through `zlog` on failure, and
reports only through its exit status. Most take a trailing field name used
purely to label the log record.

Unless noted, failure is a plain `1`.

| Function | Requires | Failure |
|---|---|---|
| `z::ensure::set <name> [context]` | Parameter is declared | 1 |
| `z::ensure::nonempty <value> [field]` | Non-empty value (takes the value, not a name) | 1 |
| `z::ensure::identifier <name> [context]` | `[[:alnum:]_-]##` — handles and keys; may start with a digit | 1 |
| `z::ensure::varname <name> [context]` | Legal shell variable name (`[[:alpha:]_][[:alnum:]_]#`) | 1 |
| `z::ensure::int <value> [field]` | Same grammar as `z::is::int` | 1 |
| `z::ensure::int_range <value> <min> <max> [field]` | Integer in an inclusive range; boundaries validated first | 1 |
| `z::ensure::bool <value> [field]` | Accepted truth spelling | 1 |
| `z::ensure::enum <a\|b\|c> <value> [field]` | Value is a member of the pipe-separated list (literal match, not glob) | 1 |
| `z::ensure::path <path> [file\|dir\|any] [field]` | Path exists; type defaults to `any` | 1 |
| `z::ensure::path::readable <path> [field]` | Path exists and is readable | 1 |
| `z::ensure::path::writable <path> [field]` | Path is writable, or its parent is (so it can be created) | 1 |
| `z::ensure::cmd <name>` | Name is runnable | `Z_ERR_INPUT` / `Z_ERR_NOTFOUND` |
| `z::ensure::func <name>` | Function is defined (missing logged at warn) | `Z_ERR_INPUT` / `Z_ERR_NOTFOUND` |
| `z::ensure::var <name>` | Parameter is declared | `Z_ERR_INPUT` / `Z_ERR_NOTFOUND` |

```zsh
z::ensure::nonempty "$1" "username" || return 1
z::ensure::int_range "$port" 1 65535 "port" || return 1
z::ensure::enum "dev|staging|prod" "$env" "environment" || return 1
z::ensure::path "$cfg" file "config" || return 1
```

Use `z::ensure::identifier` for store handles and keys; use
`z::ensure::varname` before any `typeset -g` of a caller-supplied name.

---

## 8. Value Queries — `z::get::`

Every function in this section sets `REPLY` before returning, on the
success and the failure path alike.

### Options

Options maps are associative arrays filled by `zparseopts -D -A opts`.

#### `z::get::opt`

```
z::get::opt <opts-assoc-name> [short-opt] [long-opt] [default]
```

Look up an option value, preferring the short form. Sets `REPLY` to the
matched value or to `<default>`; clears `REPLY2` and `reply`.

**Returns:** `0` on success. `Z_ERR_INPUT` when the map name is empty (REPLY
still holds the default). An absent, non-assoc, or unmatched map is not an
error and yields the default.

```zsh
local -A opts
zparseopts -D -A opts -- o: -output:
z::get::opt opts o output /tmp/out.log
local output="$REPLY"
```

#### `z::get::opt_bool`

```
z::get::opt_bool <opts-assoc-name> [short-opt] [long-opt]
```

Sets `REPLY` to `1` when the option is present and `0` otherwise. Always
returns `0`.

#### `z::get::flag`

```
z::get::flag <opts-assoc-name> <short-flag> <long-flag> [default] [caller]
```

Resolve a boolean flag: present means `1`, otherwise `<default>` (must be
`0` or `1`; anything else is warned about and treated as `0`). Sets
`REPLY` to `0` or `1`. Returns `Z_ERR_INPUT` when the map name is empty,
with `REPLY` still holding the default. `<caller>` only labels log records.

Shorthands — each takes `<opts-assoc-name> [default]`:

| Function | Flags |
|---|---|
| `z::get::flag_force` | `-f` / `--force` |
| `z::get::flag_dryrun` | `-n` / `--dry-run` |
| `z::get::flag_verbose` | `-v` / `--verbose` |
| `z::get::flag_quiet` | `-q` / `--quiet` |

```zsh
z::get::flag_force opts
(( REPLY )) && print "forcing"
```

### Introspection

#### `z::get::var`

```
z::get::var <name> [default]
```

Read a parameter indirectly by name. Sets `REPLY` to the value or to
`<default>` when unset, and `REPLY2` to the zsh type string (empty when
unset). Always returns `0`. Distinguish "unset" from "set to the default"
via `REPLY2`.

#### `z::get::cmd`

```
z::get::cmd <name>
```

Resolve how a name would run in this shell. Sets `REPLY2` to the kind and
`REPLY` to the detail:

| `REPLY2` | `REPLY` |
|---|---|
| `function` | Function body |
| `alias` | Alias expansion |
| `builtin` | The name itself |
| `external` | Absolute path |

Resolution order is function, alias, builtin, external. Returns
`Z_ERR_INPUT` when empty, `Z_ERR_NOTFOUND` when unknown.

#### `z::get::funcs`

```
z::get::funcs [pattern]
```

Collect defined function names matching a glob (default `*`). Sets `reply`
to the sorted matches and clears `REPLY` / `REPLY2`. Nothing is written to
stdout. Always returns `0`. An explicit empty pattern warns once and
defaults to `*`.

```zsh
z::get::funcs 'z::kv::*'
print -l -- "${reply[@]}"
```

### Paths

#### `z::get::abspath`

```
z::get::abspath <path>
```

Absolutise a path logically: expand a leading `~`, `~+`, or `~-`, prefix a
relative path with `$PWD`, then collapse `.` and `..`. Symlinks are **not**
resolved — use `z::get::realpath` for that. Always returns `0`; the path
need not exist.

#### `z::get::realpath`

```
z::get::realpath <path>
```

Resolve a path to its physical form with symlinks followed, in-process.
Sets `REPLY` to the resolved path.

**Returns:** `0` on success. `Z_ERR_INPUT` on an empty or all-whitespace
path. `Z_ERR_GENERAL` on a symlink cycle or on exceeding
`_Z_FILE_SYMLINK_MAX_ITER` hops (default 40) — in both cases `REPLY` holds
the last path reached, not a resolved one.

```zsh
z::get::realpath /usr/bin/python || return $?
local real="$REPLY"
```

---

## 9. Mutators — `z::set::`

These change shell state and report only through their exit status. None
of them produces a value.

#### `z::set::var` / `z::set::export`

```
z::set::var    <name> <value>
z::set::export <name> <value>
```

Define or overwrite a global scalar. `export` also marks it exported. The
name is validated first (`z::ensure::varname`), so the `typeset -g name=value`
form cannot be steered into declaring something else.

**Returns:** `0` on success; `Z_ERR_INPUT` on an illegal name.

#### `z::set::unset_var`

```
z::set::unset_var <name>
```

Remove a parameter. Returns `Z_ERR_INPUT` on an empty name,
`Z_ERR_NOTFOUND` when it is not declared, `Z_ERR_PERM` when it is
readonly, and `Z_ERR_GENERAL` if the unset itself fails.

#### `z::set::unset_func`

```
z::set::unset_func <name>
```

Remove a function definition. Returns `Z_ERR_INPUT` on an empty name,
`Z_ERR_NOTFOUND` when no such function exists, `Z_ERR_GENERAL` if
`unfunction` fails.

#### `z::set::alias` / `z::set::unalias`

```
z::set::alias   <name> <value>
z::set::unalias <name>
```

Define or remove an alias. The name is rejected if it contains whitespace
or `=`. The registration is read back and verified.

**Returns:** `Z_ERR_INPUT` on bad arguments, `Z_ERR_NOTFOUND` when
unaliasing a missing name, `Z_ERR_GENERAL` if the alias did not take or
the removal failed.

#### `z::set::path::add`

```
z::set::path::add <dir> [prepend|append]
```

Add a directory to `$path`, absolutising it first and defaulting to
`append`. Re-hashes the command table so the change takes effect
immediately. Idempotent: an entry already present is logged once and
skipped. Compared literally, not as a glob.

**Returns:** `Z_ERR_INPUT` on bad arguments; `Z_ERR_NOTFOUND` when the
directory does not exist (it is not added).

```zsh
z::set::path::add "$HOME/.local/bin" prepend
z::set::var APP_ENV production
z::set::export APP_ENV production
```

---

## 10. Effects — `z::do::`

Invocation, sourcing, command execution, and the heuristic scanner that
guards it. Only `z::do::run_async` sets `REPLY`; the rest report through
their exit status and pass through the status of whatever they ran.

#### `z::do::call`

```
z::do::call <func> [args ...]
```

Invoke a shell function by name and return its exit status unchanged.
Returns `Z_ERR_INPUT` on an empty name and `Z_ERR_NOTFOUND` when no such
function exists. Under a debug log level the call is wrapped in a zlog
context and benchmark; the context is always removed, even on a non-zero
status.

#### `z::do::source`

```
z::do::source [--global] <file> [args ...]
```

Source a file and return its exit status. Without `--global` the file is
sourced under `emulate -L zsh`, so option changes it makes do not leak
into the caller; `--global` runs it in the caller's own option state,
which is what a file defining shell configuration needs.

**Returns:** `Z_ERR_INPUT` or `Z_ERR_NOTFOUND` from path resolution;
otherwise the sourced file's status.

```zsh
z::do::source "$HOME/.config/myapp/lib.zsh"
z::do::source --global "$HOME/.zshenv"
```

#### `z::do::scan`

```
z::do::scan <command-string>
```

Scan a command string for the dangerous patterns `z::do::run` refuses.
Returns `Z_ERR_INPUT` when empty, `1` when a pattern matched, `0`
otherwise.

A clean result is **not** a certificate that the string is safe to
execute — the name claims only "I looked".

#### `z::do::run`

```
z::do::run <command-string> [timeout-seconds]
```

Execute a command string in a fresh `zsh -o pipefail -c` subshell and
return its exit status. The timeout defaults to 30 seconds, is capped at
3600, and `0` disables it. With no timeout binary available (`timeout` on
Linux, `gtimeout` on macOS) the command still runs, unbounded, and that
is noted once. A timeout surfaces as exit status `124`.

**Returns:** `Z_ERR_INPUT` on an empty command or a bad timeout,
`Z_ERR_PERM` when the metacharacter gate rejects the string, `1` when the
pattern scan does, otherwise the command's status.

The interface is string-in, so the string is parsed a second time by the
subshell — the gate and the scan are what stand between the caller and
that reparse. An argv interface would remove the attack class outright;
the string form is kept for the tool-init call sites in `z::do::hook`.

A bare `<tool> init <shell>` invocation of a known integration tool
(starship, mise, zoxide, …) skips both the metacharacter gate and the
pattern scan. Every token must be a plain word — chaining, redirection,
and command substitution are rejected.

```zsh
z::do::run "ls -la /tmp" 10
z::do::run "jq -e . < data.json"
```

#### `z::do::run_async`

```
z::do::run_async <command-string> [callback-func]
```

Launch a command in the background through `z::do::run` and record its
PID. Sets `REPLY` to the PID.

**Returns:** `0` on launch. `Z_ERR_INPUT` on an empty command.
`Z_ERR_GENERAL` when 50 live jobs are already outstanding — call
`z::do::wait` first.

`<callback-func>` is invoked with the exit status and captured output
**inside the child**, so anything it assigns dies with that subshell and
can never reach the parent.

#### `z::do::wait`

```
z::do::wait
```

Block until every job started by `z::do::run_async` has finished. Returns
the status of the last job that failed, or `0` if all succeeded. Status
`127` is ignored because it means the job was already reaped.

```zsh
z::do::run_async "sleep 2 && echo done"
z::do::wait
```

#### `z::do::hook`

```
z::do::hook <tool-name> [subcommand] [shell-arg]
```

Initialise a shell integration tool (starship, mise, zoxide, …) from a
cached copy of its `<tool> <subcommand> <shell>` output, regenerating the
cache when it is missing or stale. Defaults are `init` and `zsh`.

An absent tool is not an error and returns `0`. `Z_ERR_GENERAL` means the
tool produced output that could neither be sourced nor evaluated.

The output of a known binary is evaluated unscanned, unlike the strings
`z::do::run` accepts. The cache directory is `0700` and writes are atomic
because everything in it is executed. Cache files live under
`${XDG_CACHE_HOME:-$HOME/.cache}/zsh/hooks/`.

```zsh
z::do::hook starship
z::do::hook mise
z::do::hook zoxide init zsh
```

---

## 11. Dependencies

`zlog` must already be sourced, or the load aborts with a fatal message
on stderr. Loading is idempotent (`_Z_BASE_LOADED`).

```zsh
source /path/to/zcore/zcore.zsh
# or:
source ./zlog
source ./zbase
```
