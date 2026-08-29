# zcore Conventions

Conventions shared across all zcore modules. Follow these when adding or extending APIs.

## Return channel: `REPLY`, `reply`, `REPLY2`

Public functions that produce values use global return channels (documented in zbase):

| Variable | Type | Usage |
|----------|------|-------|
| `REPLY` | scalar | Primary result; reset to `""` on entry |
| `reply` | array | List results; reset to `()` on entry |
| `REPLY2` | scalar | Secondary detail when documented |

**Rules:**

- Read return values immediately after the call, before calling another zcore function.
- Functions that return nothing (pure predicates, setters) do not touch these globals.
- On error, `REPLY` is reset to `""` or the documented default.

## Error codes

Defined in `zbase` (v3 verb-root namespace):

| Constant | Value | Meaning |
|----------|-------|---------|
| `Z_ERR_GENERAL` | 1 | Unspecified failure |
| `Z_ERR_INPUT` | 2 | Bad argument or state |
| `Z_ERR_NOTFOUND` | 3 | Missing resource |
| `Z_ERR_PERM` | 4 | Denied / locked |

Module-specific codes (e.g. `ZCORE_ERROR_TIMEOUT=124` in `z`) live in the module that defines them.

## Verb-root namespace (zbase v3)

Public zbase APIs use verb roots that encode return-channel contracts:

| Root | Contract |
|------|----------|
| `z::is::` | Silent predicate — branch on `$?`, never sets REPLY |
| `z::ensure::` | Guard — returns code, logs on failure, never sets REPLY |
| `z::get::` | Value query — always sets `REPLY` (or `reply=` for lists) |
| `z::set::` | State mutator — status only, never sets REPLY |
| `z::do::` | Effects (run, source, call) — sets REPLY only where documented |

## Naming

| Pattern | Visibility | Example |
|---------|------------|---------|
| `z::ns::name` | Public API | `z::kv::get` |
| `_z::ns::name` | Module-private | `_z::kv::epoch` |
| `_module_*` / `__zlog::*` | Internal | `_zkv_handles`, `__zlog::engine` |

Namespaces use lowercase segments separated by `::`. Use verbs for actions (`get`, `set`, `emit`), nouns for accessors.

## Idempotent load guard

Every module loader starts with:

```zsh
(( ${+_MODULE_LOADED} )) && return 0
local _dir="${0:A:h}"
# ... source parts ...
typeset -gr _MODULE_LOADED=1
```

Part files must **not** re-run guards or re-define the loaded flag.

## `${0:A:h}` idiom

Resolve the directory containing the current file:

```zsh
local _dir="${0:A:h}"
source "${_dir}/core.zsh"
```

Use this in loaders so modules work regardless of install path or symlink location.

## `z::result` pattern

Functions that can fail return a shell exit code and optionally populate `REPLY`/`REPLY2`:

```zsh
z::kv::get handle key || return $?
# use $REPLY
```

Callers should check `$?` before reading globals.

## Binary-safe encoding (zkv / zbus)

Field and record separators from zbase:

- `Z_SEP` (`\x01`) — field delimiter
- `Z_RECSEP` (`\x02`) — record delimiter
- `Z_ESC` (`\x03`) — escape prefix

Values containing these bytes must be encoded via `_z::kv::encode_value` / decoded on read.

## Logging

- Use `zlog::{error,warn,info,debug}` with structured key-value pairs.
- Module load may use `zlog::once` to avoid duplicate startup noise.
- Tests typically call `zlog::set_level error`.

## Testing

- Test functions: `test_*`, discovered by `ztest::run`.
- Hooks: `test_setup`, `test_teardown` (per test); `test_setup_all`, `test_teardown_all` (per run).
- Assertions: `ztest::assert::eq`, `ztest::assert::returns`, etc.
- Each test file runs in a subshell to isolate globals.

## Style

- `emulate -L zsh` at the start of public functions.
- Prefer `setopt extendedglob warncreateglobal typesetsilent` where the module already uses it.
- Match surrounding code: minimal comments, no drive-by refactors.
