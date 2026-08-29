# zcore Architecture

## Overview

zcore is a layered Zsh framework. Each layer depends only on layers below it. The public API (`z::namespace::*` functions) is stable; internal helpers use `_z::namespace::*` or `_module_*` prefixes.

```
┌─────────────────────────────────────────┐
│  z          integration (cache, config) │
├─────────────────────────────────────────┤
│  zbus       event bus, pub/sub          │
├─────────────────────────────────────────┤
│  zkv        in-memory KV + structures   │
├─────────────────────────────────────────┤
│  zbase      validation, probes, I/O     │
├─────────────────────────────────────────┤
│  zlog       structured logging          │
└─────────────────────────────────────────┘
```

## Source layout (`lib/`)

| Module | Loader | Parts |
|--------|--------|-------|
| **zlog** | `lib/zlog/zlog.zsh` | See [docs/api/zlog.md](api/zlog.md) — `init`, `_globals`, `_util`, `_levels`, `_engine`, `format`, `fields`, then public modules: `log`, `printf`, `guards`, `control`, `ratelimit`, `context`, `benchmark`, `timestamp`, `stats`, `config`, `rotation`, `buffer`, `async`, `perf`, `color`, `debug`, `cleanup` |
| **zbase** | `lib/zbase/zbase.zsh` | `constants`, `time`, `opt`, `validate`, `probe`, `cmd`, `func`, `var`, `env`, `exec`, `file` |
| **zkv** | `lib/zkv/zkv.zsh` | `core`, `ttl`, `tx`, `lock`, `watch`, `persist`, `batch`, `types/{string,list,set,zset,hash}` |
| **zbus** | `lib/zbus/zbus.zsh` | `core`, `wildcard`, `history`, `stats`, `async`, `safe`, `dispatch`, `channel` |
| **z** | `lib/z/z.zsh` | `header`, `debug`, `cache`, `sys`, `config`, `help`, `event`, `init` |

## Load order

Always source in this order:

1. `zlog`
2. `zbase` (requires zlog)
3. `zkv` (requires zlog + zbase)
4. `zbus` (requires zlog + zbase + zkv v4+)
5. `z` (requires zlog + zbase + zkv)

## Thin loader pattern

Each module loader:

1. Guards against double-sourcing with a readonly flag (`_ZLOG_LOADED`, `_ZBASE_LOADED`, …).
2. Resolves its directory via `${0:A:h}`.
3. Sources part files in dependency order.
4. Sets the loaded flag.

Root wrappers (`z`, `zbase`, …) delegate to `lib/*/loader.zsh` for backward compatibility.

## zlog layout

File names mirror [docs/api/zlog.md](api/zlog.md) sections. Prefix `_` marks private implementation.

| File | API § | Responsibility |
|------|-------|----------------|
| `init.zsh` | — | Bootstrap, constants, state hashes |
| `_globals.zsh` | — | Perf globals, fast-path flags |
| `_util.zsh` | — | Private sysinfo, string, size helpers |
| `_levels.zsh` | — | Private level conversion |
| `_engine.zsh` | — | Private logging engine |
| `format.zsh` / `fields.zsh` | — | Private formatters |
| `log.zsh` | §2 | Core logging |
| `printf.zsh` | §3 | Printf-style logging |
| `guards.zsh` | §4 | Level guards |
| `control.zsh` | §5 | with_level, silent, always |
| `ratelimit.zsh` | §6 | once, rate_limit |
| `context.zsh` | §7 | Context loggers |
| `benchmark.zsh` | §8 | Benchmarking |
| `timestamp.zsh` | §9 | Timestamp utilities |
| `config.zsh` | §10 | Configuration |
| `rotation.zsh` | §11 | File rotation |
| `buffer.zsh` | §12 | Buffering |
| `async.zsh` | §13 | Async logging |
| `perf.zsh` | §14 | Performance mode |
| `color.zsh` | §15 | Color system |
| `stats.zsh` | §16 | Statistics & diagnostics |
| `cleanup.zsh` | §17 | Cleanup & resource management |
| `debug.zsh` | §18 | Internal debug mode |

Rebuild from canonical source: `python3 scripts/rebuild_zlog.py`

## Bundled distribution

`bin/zbundle` concatenates part files (skipping loaders) into `dist/` single-file modules suitable for drop-in deployment. Bundles preserve the same public API as the modular layout.

## Tests

```
tests/
  harness/ztest.zsh     Test framework
  unit/{zlog,zbase,zkv,zbus}/test_*.zsh
  integration/test_*.zsh
  run_tests.zsh
```

Tests source `lib/` loaders directly, not root wrappers.

## Versioning

Single source of truth: `VERSION` at repo root. Bundles and install targets read this file.

## Internal vs public API

- **Public:** `zlog::*`, `z::ensure::*`, `z::is::*`, `z::get::*`, `z::kv::*`, `z::bus::*`, `z::cache::*`, etc.
- **Private:** `_z::kv::*`, `_z::bus::*`, `__zlog::*`, `_zkv_*` helpers.

Do not call private functions from application code; they may change without notice.
