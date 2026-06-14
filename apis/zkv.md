# zkv API Reference

> Complete reference for all public-facing functions and constants in `zkv`.
> Every symbol prefixed `z::kv::` or `ZKV_` is part of the stable public API.
> Symbols prefixed `_z::kv::` or `_zkv_` are private internals — do not call or
> depend on them directly.

---

## Table of Contents

1. [Quick Start](#1-quick-start)
2. [Constants](#2-constants)
3. [Store Lifecycle](#3-store-lifecycle)
4. [Core String KV](#4-core-string-kv)
5. [Typed Accessors](#5-typed-accessors)
6. [Numeric Helpers](#6-numeric-helpers)
7. [TTL Management](#7-ttl-management)
8. [Multi-Key Operations](#8-multi-key-operations)
9. [Conditional Operations](#9-conditional-operations)
10. [Transactions](#10-transactions)
11. [Persistence](#11-persistence)
12. [Locks](#12-locks)
13. [Watchers](#13-watchers)
14. [Lists](#14-lists)
15. [Sets](#15-sets)
16. [Sorted Sets](#16-sorted-sets)
17. [Hashes](#17-hashes)
18. [Snapshots](#18-snapshots)
19. [Batch Commands](#19-batch-commands)
20. [Rename & Copy](#20-rename--copy)
21. [Scan & Random](#21-scan--random)
22. [Configuration](#22-configuration)
23. [Performance Mode](#23-performance-mode)
24. [Diagnostics](#24-diagnostics)
25. [Persist File Format](#25-persist-file-format)
26. [Dependencies](#26-dependencies)

---

## Conventions

| Convention | Meaning |
|---|---|
| `handle` | Store name passed to `z::kv::open`. Must be a valid identifier (`a-z`, `0-9`, `_`, `-`) |
| `key` | User key. Allowed chars: `a-z A-Z 0-9 . _ : / -`. Max length configurable (default `256`) |
| `REPLY` | Primary scalar result channel |
| `reply` | Array result channel (lists of keys, members, scan pages, etc.) |
| `REPLY2` | Secondary scalar; used by `z::kv::get` for the stored type name |
| Returns `0` | Success; non-zero on validation failure or error |
| `ZBASE_ERROR_*` | Named error codes from `zbase` (required dependency) |
| `_z::kv::*` | Private internal function — not part of the public API |
| `_zkv_*` | Private internal variable — not part of the public API |

### Result Convention

Read `REPLY`, `reply`, and `REPLY2` **immediately** after each call. Subsequent
`z::kv::*` calls may overwrite them.

### Structure Types

Every key has exactly one structure. Mixing operations across structures on the
same key returns `ZBASE_ERROR_PERMISSION`.

| Structure | Metadata type | Storage |
|---|---|---|
| String | `string`, `int`, `bool`, `array` | Scalar value in the string store |
| List | `list` | Ordered, encoded delimited string |
| Set | `set` | Unordered unique members |
| Sorted set | `zset` | Members with float scores |
| Hash | `hash` | Field → value map |

After `z::kv::del`, a key may be reused with any structure.

### Error Codes

| Constant | Typical zkv usage |
|---|---|
| `ZBASE_ERROR_INVALID_INPUT` | Bad handle/key/value, malformed arguments |
| `ZBASE_ERROR_NOT_FOUND` | Unknown handle, missing key, absent snapshot |
| `ZBASE_ERROR_PERMISSION` | Type collision, `setnx` on existing key, lock held, CAS mismatch, duplicate set member |
| `ZBASE_ERROR_GENERAL` | Save/load failure, batch rollback, epoch unavailable |

---

## 1. Quick Start

```zsh
#!/usr/bin/env zsh

# zlog and zbase must be sourced first
source ./zlog
source ./zbase
source ./zkv

# ── Open a store ───────────────────────────────────────────────
z::kv::open myapp --auto-persist "$HOME/.cache/myapp.kv"
# REPLY → "myapp" (the handle name)

# ── Strings ────────────────────────────────────────────────────
z::kv::set myapp "user:alice" "Alice" --ttl 3600
z::kv::get myapp "user:alice"
local name="$REPLY"          # → Alice
local type="$REPLY2"         # → string

z::kv::set_int myapp "counter" "0"
z::kv::incr myapp "counter"  # REPLY → 1

# ── Lists ──────────────────────────────────────────────────────
z::kv::lpush myapp "queue" "job-1"
z::kv::lpush myapp "queue" "job-2"
z::kv::rpop myapp "queue"    # REPLY → "job-1" (FIFO)

# ── Sets & hashes ──────────────────────────────────────────────
z::kv::sadd myapp "tags" "zsh"
z::kv::hset myapp "session:abc" "user" "alice"
z::kv::hget myapp "session:abc" "user"  # REPLY → alice

# ── Transactions ───────────────────────────────────────────────
z::kv::tx myapp _apply_changes   # begin → callback → commit/rollback

# ── Persistence ──────────────────────────────────────────────
z::kv::save myapp "/tmp/backup.kv"
z::kv::close myapp              # auto-flushes if --auto-persist was set
```

---

## 2. Constants

| Constant | Value | Description |
|---|---|---|
| `ZKV_VERSION` | `4` | Module version integer |
| `ZKV_PERSIST_FORMAT_VERSION` | `4` | On-disk dump format version |

Both are declared `typeset -gri` (global, readonly integer).

`zkv` uses `Z_SEP`, `Z_RECSEP`, and `Z_ESC` from `zbase` internally for
binary-safe encoding. Callers do not need to interact with these directly.

---

## 3. Store Lifecycle

### `z::kv::open`

Open (or re-open) a named in-memory store. Sets `$REPLY` to the handle name.

```
z::kv::open <name> [options...]
```

| Option | Type | Default | Description |
|---|---|---|---|
| `--max-key-length` | int | `256` | Maximum key length (1–1048576) |
| `--max-value-length` | int | `65536` | Maximum scalar value length (1–1073741824) |
| `--max-snapshots` | int | `10` | Snapshot cap before oldest is evicted (1–1000) |
| `--enable-ttl` | `0`\|`1` | `1` | Enable TTL expiry checks |
| `--persist-debounce` | int | `1` | Auto-persist debounce window in seconds (0–86400) |
| `--auto-persist` | path | — | Enable auto-persistence to the given file |

**Returns:** `0` on success. Sets `$REPLY` to `<name>`.
`ZBASE_ERROR_INVALID_INPUT` on bad name or options.
`ZBASE_ERROR_GENERAL` if `--auto-persist` path setup fails.

**Notes:**

- Opening an already-open handle is a no-op (returns `0`)
- `--auto-persist` calls `z::kv::enable_persist` after initialization

**Example:**

```zsh
z::kv::open cache --max-value-length 131072 --enable-ttl 1
z::kv::open sessions --auto-persist "$HOME/.cache/sessions.kv" --persist-debounce 5
local handle="$REPLY"
```

---

### `z::kv::close`

Flush pending auto-persist writes, free all per-store state, and unregister the handle.

```
z::kv::close <handle>
```

**Returns:** `0` on success. `ZBASE_ERROR_NOT_FOUND` if handle is unknown.

**Notes:**

- If `auto_persist` is enabled, calls `z::kv::flush` before teardown
- All snapshots, watchers, locks, and transaction state for the handle are destroyed

---

### `z::kv::list_handles`

List all currently open store handles.

```
z::kv::list_handles
```

**Returns:** `0` always. Sets `$reply` to the handle names. Prints a summary table to stdout.

---

## 4. Core String KV

### `z::kv::set`

Store a scalar string value.

```
z::kv::set <handle> <key> <value> [--ttl <seconds>] [--type <type>]
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `handle` | string | required | Open store handle |
| `key` | string | required | Key name |
| `value` | string | required | Value to store |
| `--ttl` | int | none | Expire after N seconds |
| `--type` | string | `string` | Metadata type: `string`, `int`, `bool`, `array` |

**Returns:** `0` on success.
`ZBASE_ERROR_INVALID_INPUT` if value exceeds `max_value_length` or type is non-scalar.
`ZBASE_ERROR_PERMISSION` on structure type collision.

**Notes:**

- Inside a transaction, writes are buffered until `commit` or `rollback`
- Outside transactions, fires watchers and may trigger auto-persist
- In performance mode, validation and side effects are bypassed (see [Performance Mode](#23-performance-mode))

**Examples:**

```zsh
z::kv::set myapp "config:theme" "dark"
z::kv::set myapp "token:xyz" "secret" --ttl 300
z::kv::set myapp "count" "42" --type int
```

---

### `z::kv::get`

Retrieve a value. Sets `$REPLY` to the value and `$REPLY2` to the metadata type.

```
z::kv::get <handle> <key>
```

**Returns:** `0` on success.
`ZBASE_ERROR_NOT_FOUND` if the key is absent or expired.

**Example:**

```zsh
z::kv::get myapp "config:theme"
local theme="$REPLY"    # → dark
local vtype="$REPLY2"   # → string
```

---

### `z::kv::del`

Delete a key and all associated data across every structure map.

```
z::kv::del <handle> <key>
```

**Returns:** `0` on success.
`ZBASE_ERROR_NOT_FOUND` if the key does not exist (non-transactional path).

---

### `z::kv::exists`

Predicate: returns `0` if the key exists and has not expired, `1` otherwise.

```
z::kv::exists <handle> <key>
```

---

### `z::kv::keys`

List all live (non-expired) keys, optionally filtered by glob pattern.

```
z::kv::keys <handle> [<glob-pattern>]
```

**Returns:** `0` always. Sets `$reply` to matching key names (default pattern: `*`).

**Example:**

```zsh
z::kv::keys myapp "user:*"
local -a user_keys=("${reply[@]}")
```

---

## 5. Typed Accessors

### `z::kv::set_int` / `z::kv::get_int`

Store or retrieve an integer-validated scalar (`--type int`).

```
z::kv::set_int <handle> <key> <value>
z::kv::get_int <handle> <key>
```

`get_int` sets `$REPLY` to the integer string.
`ZBASE_ERROR_INVALID_INPUT` if the stored value is not a valid integer.

---

### `z::kv::set_bool` / `z::kv::get_bool`

Store or retrieve a boolean. Truthy inputs (`true`, `1`, `yes`, `on`) are
canonicalized to `"true"`; all other valid booleans to `"false"`.

```
z::kv::set_bool <handle> <key> <value>
z::kv::get_bool <handle> <key>
```

`get_bool` always sets `$REPLY` to `"true"` or `"false"`.

---

### `z::kv::set_array` / `z::kv::get_array`

Store or retrieve an array of elements encoded as a single delimited string.

```
z::kv::set_array <handle> <key> <element> [<element> ...]
z::kv::get_array <handle> <key> <output-var>
```

`set_array` accepts one or more elements.
`get_array` decodes into the caller-supplied array variable name.

**Example:**

```zsh
z::kv::set_array myapp "roles" "admin" "editor" "viewer"
local -a roles
z::kv::get_array myapp "roles" roles
# roles → (admin editor viewer)
```

---

## 6. Numeric Helpers

### `z::kv::incr`

Atomically increment a numeric key. Creates the key at `0` if absent.
Preserves any active TTL. Sets `$REPLY` to the new value.

```
z::kv::incr <handle> <key> [<amount>]
```

Default `amount` is `1`.

---

### `z::kv::decr`

Decrement by delegating to `z::kv::incr` with a negated amount.

```
z::kv::decr <handle> <key> [<amount>]
```

---

### `z::kv::append`

Append a suffix to a string key, preserving TTL. Creates the key if absent.

```
z::kv::append <handle> <key> <suffix>
```

---

## 7. TTL Management

TTL applies to all structure types (strings, lists, sets, zsets, hashes).

### `z::kv::ttl`

Get remaining TTL in seconds. Sets `$REPLY` using Redis conventions:

| `$REPLY` | Meaning |
|---|---|
| `-2` | Key does not exist |
| `-1` | Key exists, no expiry |
| `0` | Expired (or expiring this second) |
| `> 0` | Seconds remaining |

```
z::kv::ttl <handle> <key>
```

**Returns:** `0` always (including for missing keys, where `$REPLY` is `-2`).

---

### `z::kv::expire`

Set or remove TTL on an existing key.

```
z::kv::expire <handle> <key> <ttl-seconds>
```

| `ttl-seconds` | Effect |
|---|---|
| `> 0` | Expire after N seconds from now |
| `≤ 0` | Remove expiry (make persistent) |

**Returns:** `ZBASE_ERROR_NOT_FOUND` if the key does not exist.

---

### `z::kv::persist`

Remove TTL from a key (make it permanent). Thin wrapper around `expire` with `ttl=0`.

```
z::kv::persist <handle> <key>
```

---

## 8. Multi-Key Operations

### `z::kv::mset`

Set multiple key-value pairs. Requires an even argument count after the handle.

```
z::kv::mset <handle> <key> <value> [<key> <value> ...]
```

---

### `z::kv::mget`

Get multiple keys. Sets `$reply` to values in request order.
Missing or expired keys produce an empty string in the corresponding slot.

```
z::kv::mget <handle> <key> [<key> ...]
```

**Example:**

```zsh
z::kv::mget myapp "a" "b" "missing"
# reply → (value_a value_b "")
```

---

### `z::kv::clear`

Delete all keys matching an optional glob pattern (default: `*`).

```
z::kv::clear <handle> [<glob-pattern>]
```

---

## 9. Conditional Operations

### `z::kv::getset`

Atomically replace a value and return the old one via `$REPLY`.
Preserves TTL. Old value is `""` if the key did not exist.

```
z::kv::getset <handle> <key> <new-value>
```

---

### `z::kv::setnx`

Set only if the key does **not** exist (SET if Not eXists).

```
z::kv::setnx <handle> <key> <value>
```

**Returns:** `ZBASE_ERROR_PERMISSION` if the key already exists.

---

### `z::kv::setxx`

Set only if the key **does** exist (SET if eXists).

```
z::kv::setxx <handle> <key> <value>
```

**Returns:** `ZBASE_ERROR_NOT_FOUND` if the key is absent.

---

### `z::kv::cas`

Compare-And-Swap: set `<new-value>` only when the current value equals `<expected>`.

```
z::kv::cas <handle> <key> <expected> <new-value>
```

**Returns:** `ZBASE_ERROR_PERMISSION` on mismatch.
An absent key is treated as having current value `""`.

---

## 10. Transactions

All writes inside a transaction are buffered. Reads merge the live store with
the transaction buffer. Watchers fire once at commit time. Nested transactions
are not supported.

### `z::kv::begin`

```
z::kv::begin <handle>
```

**Returns:** `ZBASE_ERROR_PERMISSION` if a transaction is already active.

---

### `z::kv::commit`

Apply all buffered writes to the live store.

```
z::kv::commit <handle>
```

**Returns:** `0` if committed, or if called outside a transaction (no-op with warning).

---

### `z::kv::rollback`

Discard all buffered writes.

```
z::kv::rollback <handle>
```

**Returns:** `0` always (no-op with warning if no transaction is active).

---

### `z::kv::tx`

Convenience wrapper: `begin` → call callback → `commit` on success or `rollback` on non-zero return.

```
z::kv::tx <handle> <callback> [<args> ...]
```

The callback is invoked as: `callback <handle> <args...>`

**Returns:** Exit code of the callback if it failed (after rollback), or `0` on commit.

**Example:**

```zsh
_apply_session() {
  local h="$1"
  z::kv::set "$h" "session:1" "data"
  z::kv::hset "$h" "meta:1" "user" "alice"
  return 0
}

z::kv::tx myapp _apply_session
```

---

## 11. Persistence

### `z::kv::save`

Serialize the entire store to a file using atomic write (temp file + rename).
Expired keys are skipped.

```
z::kv::save <handle> <file>
```

**Returns:** `ZBASE_ERROR_PERMISSION` if the parent directory is not writable.
`ZBASE_ERROR_GENERAL` on write or rename failure.

---

### `z::kv::load`

Load a dump file into an open store.

```
z::kv::load <handle> <file> [--clear]
```

| Flag | Effect |
|---|---|
| `--clear` | Wipe the store before loading |

**Returns:** `ZBASE_ERROR_NOT_FOUND` if the file is unreadable.
`ZBASE_ERROR_GENERAL` if the format version is unreadable or newer than supported.

**Notes:**

- `auto_persist` is suppressed during bulk load to avoid per-key disk writes
- Dump files with `version` greater than `ZKV_PERSIST_FORMAT_VERSION` are rejected

---

### `z::kv::flush`

Save to the configured `persist_file` only if the dirty flag is set.

```
z::kv::flush <handle>
```

No-ops when auto-persist is disabled, no file is configured, or the store is clean.

---

### `z::kv::enable_persist` / `z::kv::disable_persist`

Enable or disable debounced auto-persistence.

```
z::kv::enable_persist <handle> <file>
z::kv::disable_persist <handle>
```

`enable_persist` validates that the file path is writable (creates parent dirs are
not automatic — the path or its parent must exist and be writable).

---

## 12. Locks

Named locks with TTL-based expiry. Expired locks are silently taken over.

### `z::kv::lock`

```
z::kv::lock <handle> <lock-name> [<ttl>] [<owner>]
```

| Parameter | Default | Description |
|---|---|---|
| `ttl` | `10` | Lock expiry in seconds |
| `owner` | `""` | Owner identifier stored with the lock |

**Returns:** `ZBASE_ERROR_PERMISSION` if the lock is held and not expired.

---

### `z::kv::unlock`

```
z::kv::unlock <handle> <lock-name> [<owner>]
```

**Returns:** `ZBASE_ERROR_NOT_FOUND` if lock absent.
`ZBASE_ERROR_PERMISSION` if `owner` does not match the recorded owner.

---

### `z::kv::lock_wait`

Retry `z::kv::lock` with backoff.

```
z::kv::lock_wait <handle> <lock-name> [<ttl>] [<attempts>] [<interval>] [<owner>]
```

| Parameter | Default | Description |
|---|---|---|
| `attempts` | `3` | Maximum acquisition attempts |
| `interval` | `1` | Seconds between attempts (supports fractional values) |

Uses `zselect` for sub-second sleep when `zsh/zselect` is available; falls back to `sleep`.

**Returns:** `ZBASE_ERROR_PERMISSION` if all attempts fail.

---

## 13. Watchers

### `z::kv::watch`

Register a handler to be called when keys matching a glob pattern are modified.

```
z::kv::watch <handle> <glob-pattern> <handler-function>
```

**Handler signature:**

```
handler <handle> <key> <value> <op>
```

| `op` value | Trigger |
|---|---|
| `set` | String write |
| `del` | Key deleted |
| `lpush`, `rpush` | List mutation |
| `sadd` | Set add |
| `zadd` | Sorted set add |
| `hset` | Hash field set |
| `lupdate`, `supdate`, `zupdate`, `hupdate` | Collection committed in transaction |
| `rename_from`, `rename_to`, `copy` | Key rename/copy |

**Returns:** `ZBASE_ERROR_NOT_FOUND` if the handler function is not defined.

**Notes:**

- Multiple handlers per pattern are supported
- Watchers are deferred during transactions and fire at commit
- Handler errors are rate-limited to avoid log spam

---

### `z::kv::unwatch`

Remove watcher(s) for a pattern.

```
z::kv::unwatch <handle> <glob-pattern> [<handler-function>]
```

Omit `handler-function` to remove all handlers for the pattern.

---

## 14. Lists

Ordered collections. Indices are 0-based; negative indices count from the end.

| Function | Description | Result |
|---|---|---|
| `z::kv::lpush <handle> <key> <value>` | Prepend element | — |
| `z::kv::rpush <handle> <key> <value>` | Append element | — |
| `z::kv::lpop <handle> <key>` | Remove first element | `$REPLY` |
| `z::kv::rpop <handle> <key>` | Remove last element | `$REPLY` |
| `z::kv::lrange <handle> <key> [<start>] [<stop>]` | Slice (default `0`..`-1`) | `$reply` |
| `z::kv::llen <handle> <key>` | Element count | `$REPLY` |
| `z::kv::lindex <handle> <key> [<index>]` | Element at index (default `0`) | `$REPLY` |
| `z::kv::lset <handle> <key> <index> <value>` | Replace element at index | — |

**Returns:** `ZBASE_ERROR_NOT_FOUND` for pop/index on empty or missing lists.
`ZBASE_ERROR_PERMISSION` on type collision.
`ZBASE_ERROR_INVALID_INPUT` for out-of-range `lset` index.

**Example:**

```zsh
z::kv::lpush myapp "jobs" "third"
z::kv::lpush myapp "jobs" "second"
z::kv::lpush myapp "jobs" "first"
z::kv::rpop myapp "jobs"   # REPLY → first  (FIFO dequeue)
```

---

## 15. Sets

Unordered collections of unique members (case-sensitive).

| Function | Description | Result |
|---|---|---|
| `z::kv::sadd <handle> <key> <value>` | Add member | — |
| `z::kv::srem <handle> <key> <value>` | Remove member | — |
| `z::kv::sismember <handle> <key> <value>` | Membership test | `0` = member, `1` = not |
| `z::kv::smembers <handle> <key>` | All members | `$reply` |
| `z::kv::scard <handle> <key>` | Member count | `$REPLY` |
| `z::kv::sunion <handle> <key> [<key> ...]` | Union | `$reply` |
| `z::kv::sinter <handle> <key> [<key> ...]` | Intersection | `$reply` |
| `z::kv::sdiff <handle> <key> [<key> ...]` | First set minus others | `$reply` |

**Returns:** `ZBASE_ERROR_PERMISSION` if `sadd` member already exists.
`ZBASE_ERROR_NOT_FOUND` if `srem` member or set not found.

---

## 16. Sorted Sets

Members with float scores. Score range: `-999999999999.999999` .. `+999999999999.999999`.
Scores are stored with 6 decimal places of precision.

| Function | Description | Result |
|---|---|---|
| `z::kv::zadd <handle> <key> <score> <member>` | Add or update member | — |
| `z::kv::zscore <handle> <key> <member>` | Get member score | `$REPLY` |
| `z::kv::zrank <handle> <key> <member> [<reverse>]` | 0-based rank by score | `$REPLY` |
| `z::kv::zrange <handle> <key> [<start>] [<stop>] [--rev]` | Members by rank | `$reply` |
| `z::kv::zrange_withscores <handle> <key> [<start>] [<stop>] [--rev]` | Members + scores interleaved | `$reply` |
| `z::kv::zrangebyscore <handle> <key> <min> <max>` | Members in score range (inclusive) | `$reply` |
| `z::kv::zrem <handle> <key> <member>` | Remove member | — |
| `z::kv::zcard <handle> <key>` | Member count | `$REPLY` |

Pass `--rev` as the last argument to `zrange` / `zrange_withscores` for descending order.

**Example:**

```zsh
z::kv::zadd myapp "leaderboard" 100 "alice"
z::kv::zadd myapp "leaderboard" 250 "bob"
z::kv::zrange myapp "leaderboard" 0 -1
# reply → (alice bob)

z::kv::zrange_withscores myapp "leaderboard" 0 -1 --rev
# reply → (bob 250.000000 alice 100.000000)
```

---

## 17. Hashes

Field → value maps stored under a single key.

| Function | Description | Result |
|---|---|---|
| `z::kv::hset <handle> <key> <field> <value>` | Set one field | — |
| `z::kv::hmset <handle> <key> <field> <value> [...]` | Set multiple fields (even count) | — |
| `z::kv::hget <handle> <key> <field>` | Get one field | `$REPLY` |
| `z::kv::hgetall <handle> <key>` | All fields (interleaved) | `$reply` |
| `z::kv::hdel <handle> <key> <field>` | Delete one field | — |
| `z::kv::hexists <handle> <key> <field>` | Field exists? | `0` / `1` |
| `z::kv::hkeys <handle> <key>` | Field names | `$reply` |
| `z::kv::hvals <handle> <key>` | Field values | `$reply` |
| `z::kv::hlen <handle> <key>` | Field count | `$REPLY` |
| `z::kv::hincrby <handle> <key> <field> [<amount>]` | Increment integer field | `$REPLY` |

`hgetall` returns interleaved pairs: `( field1 val1 field2 val2 ... )`, sorted by field name.

**Example:**

```zsh
z::kv::hmset myapp "user:1" name "Alice" email "alice@example.com"
z::kv::hget myapp "user:1" name     # REPLY → Alice
z::kv::hincrby myapp "user:1" logins
```

---

## 18. Snapshots

Point-in-time copies of the entire store. Capped by `max_snapshots`; oldest is
evicted when the cap is reached.

### `z::kv::snapshot_create`

```
z::kv::snapshot_create <handle> [<label>]
```

**Returns:** `0` on success. Sets `$REPLY` to the snapshot ID (e.g. `snap_3`).

---

### `z::kv::snapshot_restore`

Replace the live store with a snapshot's data.

```
z::kv::snapshot_restore <handle> <snapshot-id>
```

**Returns:** `ZBASE_ERROR_NOT_FOUND` if snapshot ID is unknown.

---

### `z::kv::snapshot_list`

Print a formatted table of all snapshots (sorted by creation time).

```
z::kv::snapshot_list <handle>
```

---

### `z::kv::snapshot_delete`

Delete a snapshot and free its storage.

```
z::kv::snapshot_delete <handle> <snapshot-id>
```

---

## 19. Batch Commands

### `z::kv::batch`

Read a command script from stdin and execute each line inside a single transaction.
Rolls back on any command failure.

```
z::kv::batch <handle> <<'EOF'
set key1 value1
lpush mylist item
hset myhash field val
EOF
```

**Supported commands** (one per line, shell-quoted):

| Command | Arguments |
|---|---|
| `set` | `<key> <value>` |
| `del` | `<key>` |
| `incr` / `decr` | `<key> [<amount>]` |
| `expire` / `persist` | `<key> [<ttl>]` |
| `hset` / `hdel` | `<key> <field> [<value>]` |
| `lpush` / `rpush` | `<key> <value>` |
| `sadd` / `srem` | `<key> <value>` |
| `zadd` | `<key> <score> <member>` |
| `zrem` | `<key> <member>` |

Lines starting with `#` and blank lines are ignored.

**Returns:** `ZBASE_ERROR_GENERAL` if any command failed (transaction rolled back).

---

## 20. Rename & Copy

### `z::kv::rename`

Rename a key, replacing any existing destination key. No-op if old and new are equal.

```
z::kv::rename <handle> <old-key> <new-key>
```

Copies all structure data and TTL. Fires `rename_from` / `rename_to` watchers.

---

### `z::kv::copy`

Copy source key to destination, replacing any existing destination key.

```
z::kv::copy <handle> <src-key> <dst-key>
```

Source key is preserved. Fires a `copy` watcher on the destination.

---

## 21. Scan & Random

### `z::kv::randomkey`

Return a uniformly random live key via `$REPLY`.

```
z::kv::randomkey <handle>
```

**Returns:** `ZBASE_ERROR_NOT_FOUND` if the store has no live keys.

---

### `z::kv::scan`

Cursor-based key iteration over live keys in sorted order.

```
z::kv::scan <handle> [<cursor>] [<pattern>] [<count>]
```

| Parameter | Default | Description |
|---|---|---|
| `cursor` | `0` | Start position (`0` = beginning) |
| `pattern` | `*` | Glob filter |
| `count` | `10` | Page size |

**Returns:** `0` on success.
Sets `$REPLY` to the **next cursor** (`0` = iteration complete).
Sets `$reply` to the current page of keys.

**Example:**

```zsh
typeset -i cursor=0
while true; do
  z::kv::scan myapp "$cursor" "user:*" 50
  cursor="$REPLY"
  process_keys "${reply[@]}"
  (( cursor == 0 )) && break
done
```

---

## 22. Configuration

Per-store defaults are set at `open` time and may be changed at runtime.

| Key | Type | Default | Description |
|---|---|---|---|
| `max_key_length` | int | `256` | Maximum key length |
| `max_value_length` | int | `65536` | Maximum scalar value length |
| `max_snapshots` | int | `10` | Snapshot cap |
| `enable_ttl` | `0`\|`1` | `1` | TTL expiry enabled |
| `auto_persist` | `0`\|`1` | `0` | Auto-persist enabled |
| `persist_file` | string | `""` | Auto-persist target path |
| `persist_debounce` | int | `1` | Debounce interval (seconds) |

### `z::kv::config`

Update a single configuration key at runtime.

```
z::kv::config <handle> <key> <value>
```

**Returns:** `ZBASE_ERROR_NOT_FOUND` for unknown config keys.
`ZBASE_ERROR_INVALID_INPUT` / `ZBASE_ERROR_PERMISSION` on validation failure.

---

## 23. Performance Mode

### `z::kv::enable_performance_mode`

Bypass validation, TTL checks, watchers, and auto-persist for direct `z::kv::set`
writes. Intended for bulk-load hot paths.

```
z::kv::enable_performance_mode <handle>
```

**Trade-offs:**

- Only affects `z::kv::set` — all other operations retain full checks
- No key/value length validation
- No watcher dispatch or auto-persist side effects
- Type metadata is still written (`string`)

---

### `z::kv::disable_performance_mode`

Restore full `z::kv::set` behaviour.

```
z::kv::disable_performance_mode <handle>
```

**Example:**

```zsh
z::kv::enable_performance_mode myapp
for line in "${data[@]}"; do
  z::kv::set myapp "${line%%:*}" "${line#*:}"
done
z::kv::disable_performance_mode myapp
z::kv::save myapp "/tmp/bulk.kv"
```

---

## 24. Diagnostics

| Function | Output | Description |
|---|---|---|
| `z::kv::stats <handle>` | stdout table | Operation counters, key counts, config summary |
| `z::kv::size <handle>` | `$REPLY` | Count of live (non-expired) keys |
| `z::kv::memory <handle>` | stdout table | Approximate byte usage per structure |
| `z::kv::info <handle> <key>` | stdout table | Structure, type, TTL, size/length for one key |
| `z::kv::export <handle>` | stdout dump | Human-readable export of all live keys |
| `z::kv::reset_stats <handle>` | — | Zero all operation counters |

### Stats Counters

| Counter | Incremented by |
|---|---|
| `reads` | Every `get` attempt |
| `hits` | Successful `get` |
| `misses` | Failed `get` (not found / expired) |
| `writes` | Successful `set` and structure mutations |
| `deletes` | Successful `del` |
| `expired` | Keys reaped by TTL check |

---

## 25. Persist File Format

Version `4` text format. Header comments followed by one record per line.

```
# zkv store dump
# handle:  myapp
# created: 2026-06-14 12:00:00
# version: 4

M|<encoded-key>|<type>|<ttl-remaining>
S|<encoded-key>|<type>|<ttl-remaining>|<encoded-value>
L|<encoded-key>|<ttl-remaining>|<encoded-list>
T|<encoded-key>|<ttl-remaining>|<encoded-set>
Z|<encoded-key>|<ttl-remaining>|<encoded-zset>
H|<encoded-composite-key>|<encoded-value>
```

| Record | Meaning |
|---|---|
| `M` | Metadata (type + TTL) for a key |
| `S` | Scalar string value |
| `L` | List (encoded delimited elements) |
| `T` | Set (encoded delimited members) |
| `Z` | Sorted set (encoded packed entries) |
| `H` | Hash field (composite encoded key + value) |

All keys and values are escaped via the internal encoder (handles newlines,
backslashes, pipes, and `Z_SEP` / `Z_RECSEP` / `Z_ESC` bytes safely).

Dump files with `version` greater than `ZKV_PERSIST_FORMAT_VERSION` are rejected.

---

## 26. Dependencies

| Dependency | Required | Used for |
|---|---|---|
| `zlog` | Yes | All `z::log::*` calls (must be sourced first) |
| `zbase` | Yes | `z::validate::*`, `z::probe::*`, `Z_SEP`/`Z_RECSEP`/`Z_ESC`, `ZBASE_ERROR_*` |
| `zsh/datetime` | Optional | `$EPOCHSECONDS` for TTL (falls back to `z::log::get_timestamp epoch`) |
| `zsh/zselect` | Optional | Sub-second sleep in `z::kv::lock_wait` (falls back to `sleep`) |

**Source order:**

```zsh
source ./zlog
source ./zbase
source ./zkv
```

---

## Function & Constant Index

| Symbol | Category | Description |
|---|---|---|
| `ZKV_VERSION` | Constants | Module version (`4`) |
| `ZKV_PERSIST_FORMAT_VERSION` | Constants | On-disk format version (`4`) |
| `z::kv::open` | Lifecycle | Open a named store |
| `z::kv::close` | Lifecycle | Close and free a store |
| `z::kv::list_handles` | Lifecycle | List open handles |
| `z::kv::set` | Strings | Store scalar value |
| `z::kv::get` | Strings | Retrieve value + type |
| `z::kv::del` | Strings | Delete key |
| `z::kv::exists` | Strings | Key exists predicate |
| `z::kv::keys` | Strings | List keys by glob |
| `z::kv::set_int` | Typed | Store integer |
| `z::kv::get_int` | Typed | Retrieve integer |
| `z::kv::set_bool` | Typed | Store boolean |
| `z::kv::get_bool` | Typed | Retrieve boolean |
| `z::kv::set_array` | Typed | Store encoded array |
| `z::kv::get_array` | Typed | Decode into array variable |
| `z::kv::incr` | Numeric | Atomic increment |
| `z::kv::decr` | Numeric | Atomic decrement |
| `z::kv::append` | Numeric | Append to string |
| `z::kv::ttl` | TTL | Get remaining TTL |
| `z::kv::expire` | TTL | Set/remove TTL |
| `z::kv::persist` | TTL | Remove TTL permanently |
| `z::kv::mset` | Multi-key | Set multiple pairs |
| `z::kv::mget` | Multi-key | Get multiple keys |
| `z::kv::clear` | Multi-key | Delete keys by glob |
| `z::kv::getset` | Conditional | Replace and return old |
| `z::kv::setnx` | Conditional | Set if not exists |
| `z::kv::setxx` | Conditional | Set if exists |
| `z::kv::cas` | Conditional | Compare-and-swap |
| `z::kv::begin` | Transactions | Start transaction |
| `z::kv::commit` | Transactions | Apply buffered writes |
| `z::kv::rollback` | Transactions | Discard buffered writes |
| `z::kv::tx` | Transactions | Transaction wrapper |
| `z::kv::save` | Persistence | Atomic save to file |
| `z::kv::load` | Persistence | Load from file |
| `z::kv::flush` | Persistence | Save if dirty |
| `z::kv::enable_persist` | Persistence | Enable auto-persist |
| `z::kv::disable_persist` | Persistence | Disable auto-persist |
| `z::kv::lock` | Locks | Acquire named lock |
| `z::kv::unlock` | Locks | Release named lock |
| `z::kv::lock_wait` | Locks | Retry lock acquisition |
| `z::kv::watch` | Watchers | Register change handler |
| `z::kv::unwatch` | Watchers | Remove change handler |
| `z::kv::lpush` | Lists | Prepend element |
| `z::kv::rpush` | Lists | Append element |
| `z::kv::lpop` | Lists | Remove first element |
| `z::kv::rpop` | Lists | Remove last element |
| `z::kv::lrange` | Lists | Slice list |
| `z::kv::llen` | Lists | List length |
| `z::kv::lindex` | Lists | Element at index |
| `z::kv::lset` | Lists | Replace at index |
| `z::kv::sadd` | Sets | Add member |
| `z::kv::srem` | Sets | Remove member |
| `z::kv::sismember` | Sets | Membership test |
| `z::kv::smembers` | Sets | All members |
| `z::kv::scard` | Sets | Member count |
| `z::kv::sunion` | Sets | Union |
| `z::kv::sinter` | Sets | Intersection |
| `z::kv::sdiff` | Sets | Difference |
| `z::kv::zadd` | Zsets | Add/update scored member |
| `z::kv::zscore` | Zsets | Get member score |
| `z::kv::zrank` | Zsets | Get member rank |
| `z::kv::zrange` | Zsets | Members by rank |
| `z::kv::zrange_withscores` | Zsets | Members + scores |
| `z::kv::zrangebyscore` | Zsets | Members by score range |
| `z::kv::zrem` | Zsets | Remove member |
| `z::kv::zcard` | Zsets | Member count |
| `z::kv::hset` | Hashes | Set field |
| `z::kv::hmset` | Hashes | Set multiple fields |
| `z::kv::hget` | Hashes | Get field |
| `z::kv::hgetall` | Hashes | All fields + values |
| `z::kv::hdel` | Hashes | Delete field |
| `z::kv::hexists` | Hashes | Field exists predicate |
| `z::kv::hkeys` | Hashes | Field names |
| `z::kv::hvals` | Hashes | Field values |
| `z::kv::hlen` | Hashes | Field count |
| `z::kv::hincrby` | Hashes | Increment integer field |
| `z::kv::snapshot_create` | Snapshots | Create point-in-time copy |
| `z::kv::snapshot_restore` | Snapshots | Restore from snapshot |
| `z::kv::snapshot_list` | Snapshots | List snapshots |
| `z::kv::snapshot_delete` | Snapshots | Delete snapshot |
| `z::kv::batch` | Batch | Execute stdin command script |
| `z::kv::rename` | Key ops | Rename key |
| `z::kv::copy` | Key ops | Copy key |
| `z::kv::randomkey` | Key ops | Random live key |
| `z::kv::scan` | Key ops | Cursor-based key scan |
| `z::kv::config` | Config | Update store configuration |
| `z::kv::enable_performance_mode` | Perf | Fast-path bulk set |
| `z::kv::disable_performance_mode` | Perf | Restore normal set |
| `z::kv::stats` | Diagnostics | Print operation statistics |
| `z::kv::size` | Diagnostics | Live key count |
| `z::kv::memory` | Diagnostics | Approximate memory usage |
| `z::kv::info` | Diagnostics | Single-key introspection |
| `z::kv::export` | Diagnostics | Human-readable dump |
| `z::kv::reset_stats` | Diagnostics | Zero stat counters |
