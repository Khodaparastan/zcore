# zcore

**A batteries-included runtime toolkit for serious Zsh programs.**

zcore brings structured logging, contract-driven shell primitives, adaptive
terminal UI, a Redis-inspired in-memory data store, event dispatch, caching,
typed configuration, and platform services into one sourceable framework. It
is designed for installers, developer tools, automation, and long-lived
interactive shells that need more structure than a collection of helpers.

**Framework 0.6.0** · **Zsh 5.9** · **macOS and Linux** · **MIT**

> zcore is a shell-process runtime, not a daemon. Stores, subscriptions,
> caches, and handler state belong to the current Zsh process. Explicit dump
> and load APIs provide persistence where it is needed.

## What you get

| Capability | Highlights |
| :--- | :--- |
| **Structured logging** | Levels, text/JSON output, context fields, buffering, rotation, rate limiting, timing, and experimental async delivery |
| **Contract-driven primitives** | Silent predicates, logging guards, path and time queries, safe state mutation, command execution, hooks, and async jobs |
| **Terminal UI** | TTY/color/Unicode detection, dimensions and resize handling, formatting, boxes, progress bars, named tracks, and spinners with ASCII fallbacks |
| **In-memory data** | Strings, typed scalars, lists, sets, sorted sets, hashes, TTL, transactions, watchers, snapshots, locks, scans, batching, and file persistence |
| **Events and pub/sub** | Priorities, one-shot and wildcard handlers, synchronous/safe/async dispatch, watchdog timeouts, channels, ring-buffer history, and statistics |
| **Runtime integration** | TTL cache and memoization, typed configuration, platform detection, signal handling, profiling, assertions, diagnostics, and event wrappers |

Each layer remains useful on its own. Source the complete stack with one
loader, or load only the modules your script needs.

## Design principles

- **Names communicate behavior.** In `zbase`, `z::is::*` is a silent
  predicate, `z::ensure::*` is a logging guard, and `z::get::*` returns a
  value. Call sites reveal their contract without opening the implementation.
- **Results do not require a subprocess.** Scalar and array results normally
  arrive in `REPLY` and `reply`; hot-path helpers avoid command substitution
  unless stdout is explicitly part of their API.
- **Logging does not steal application results.** Emit-path `zlog` functions
  preserve the caller's `REPLY` and `reply` values.
- **Optional integrations stay optional.** The UI can measure a terminal
  without the cache, and the `z` layer only exposes event wrappers when the
  bus is present.
- **Build artifacts cannot silently drift.** Split sources are canonical;
  linting, installation, and integration tests reject stale bundles.
- **Non-interactive output is safe.** Renderers write to stderr and suppress
  dynamic terminal output when stderr is not a TTY.

## Install

Clone with the logging submodule, then install under `~/.local`:

```sh
git clone --recurse-submodules https://github.com/Khodaparastan/zcore zcore
cd zcore
make install
```

```zsh
source ~/.local/share/zcore/zcore.zsh
```

`PREFIX` changes the installation prefix; uninstall removes only the files
written by the install target.

```sh
PREFIX=/opt/zcore make install
make uninstall
```

To use a checkout directly:

```zsh
source /path/to/zcore/zcore.zsh
```

The loader resolves modules relative to itself, sources them in dependency
order, and is safe to source repeatedly. See the canonical
[load-order reference](docs/architecture.md#load-order) when loading a subset.

## Five-minute tour

```zsh
#!/usr/bin/env zsh

source /path/to/zcore/zcore.zsh
zlog::setup "-" info text

on_job_queued() {
  local event="$1" job_id="$2"
  zlog::info "job queued" event "$event" job_id "$job_id"
}

# Typed, process-local data with TTL and collection operations.
z::kv::open app
z::kv::set app current_user alice --ttl 300
z::kv::rpush app jobs index-docs
z::kv::zadd app scores 10 alice
z::kv::zadd app scores 5 bob

# Priority-aware events; handlers receive the event name as argument one.
z::bus::on "job.queued" on_job_queued --priority $ZBUS_PRIORITY_HIGH
z::bus::emit "job.queued" index-docs

# Collection results use the global array channel.
z::kv::zrange app scores 0 -1
print -r -- "ranking: ${reply[*]}"       # bob alice

# Integration services build on the lower layers.
z::config::set request_timeout 60
find_project_root() { git rev-parse --show-toplevel }
project_root=$(z::cache::memoize project-root 30 find_project_root)
```

Read `REPLY` (scalar), `reply` (array), or `REPLY2` (documented secondary
detail) immediately after a call. A function's reference entry states which
channel it writes. Functions whose contract is stdout, such as terminal
formatters and cache reads, are documented explicitly.

## Modules

Modules have independent versions and compatibility boundaries. The root
[`VERSION`](VERSION) tracks the integrated framework release.

| Module | Responsibility | Depth | Reference |
| :--- | :--- | :--- | :--- |
| [`zlog`](lib/zsh-log) | Structured logging | Contexts, formats, files, rotation, buffering, throttling, timing | [API](docs/api/zlog.md) |
| [`zbase`](zbase) | Foundational contracts | Predicates, guards, queries, mutation, execution, hooks | [API](docs/api/zbase.md) |
| [`ui`](ui) | Terminal presentation | Capabilities, dimensions, formatting, progress, tracks, spinner | [API](docs/api/ui.md) |
| [`zkv`](zkv) | In-memory data engine | Five collection types, TTL, transactions, persistence, observers | [API](docs/api/zkv.md) |
| [`zbus`](zbus) | Event coordination | Priority/wildcard dispatch, isolation, history, stats, channels | [API](docs/api/zbus.md) |
| [`z`](z) | Integration services | Cache, config, system, event, debug, and help namespaces | [API](docs/api/z.md) |

### Runtime model

| Property | What it means for callers |
| :--- | :--- |
| **Process scoped** | Mutations made in a subshell do not update the parent shell's store or bus |
| **Explicit persistence** | `zkv` snapshots and dump/load APIs move selected state to disk; ordinary stores remain in memory |
| **Synchronous by default** | Normal bus handlers run in the caller and can intentionally mutate its shell state |
| **Isolation on demand** | Safe dispatch forks handlers behind a timeout watchdog; async dispatch backgrounds the full emission |
| **Global result channels** | Consume documented results before another framework call overwrites them |
| **TTY-aware rendering** | Progress output is suitable for interactive stderr and becomes a no-op in pipelines by default |

## Choose the right layer

- Use **`zbase`** in small scripts that need validation, path handling, and
  disciplined command execution without the higher-level runtime.
- Add **`ui`** for interactive CLIs and installers that must also behave well
  in CI and redirected output.
- Add **`zkv`** when related shell state needs types, expiry, transactions,
  observation, or persistence rather than loose global variables.
- Add **`zbus`** when components should communicate without directly calling
  one another, or when handler priority, isolation, and history are valuable.
- Use the full loader when you want **`z`** to connect caching, configuration,
  events, diagnostics, and platform behavior into one runtime.

## Documentation

| Start here | Use it for |
| :--- | :--- |
| [Documentation guide](docs/README.md) | Task-oriented map of concepts and references |
| [Architecture](docs/architecture.md) | Dependency model, loading, optional integrations, source layout, and tests |
| [Conventions](docs/conventions.md) | Return channels, errors, naming, source standards, and contribution rules |
| [API reference](docs/README.md#api-reference) | Complete per-module function contracts |

## Development

```sh
make help
make bundle                 # assemble split modules from lib/<module>/
make bundle-check           # detect generated-file drift
make test                   # all unit and integration suites
make test-unit
make test-integration
make test-module M=zkv
make lint                   # syntax, bundle, and source-comment checks
make lint-style
```

Every suite declares and loads its own dependencies, so focused runs are
first-class:

```sh
zsh tests/unit/zkv/test_zkv_tx.zsh
zsh tests/unit/zkv/test_zkv_tx.zsh 'test_*rollback*'
zsh tests/run_tests.zsh zkv zbus -t 'test_*timeout*'
```

### Editing generated modules

The root [`z`](z) file is generated from the ordered parts in [`lib/z/`](lib/z).
Edit a part, test it through the development loader, and regenerate the bundle:

```sh
$EDITOR lib/z/cache.zsh
zsh tests/unit/z/test_z_core.zsh
make bundle
make lint
```

`make lint` and `make install` fail when the generated root module differs
from its canonical parts. [`zlog`](zlog) is likewise not edited at the root:
it is a symlink to the independently maintained `lib/zsh-log` submodule.

## Repository layout

```text
zcore.zsh               Full-stack loader
zbase ui zkv zbus       Directly sourceable modules
z                       Generated integration module; do not edit directly
zlog                    Symlink to the logging submodule
lib/z/                  Canonical integration-module parts and manifest
bin/                    Bundle and source-documentation tooling
tests/unit/             Suites grouped by module
tests/integration/      Loader and generated-artifact coverage
tests/ztest             Minimal project test framework
docs/                   Architecture, conventions, and API references
```

## Compatibility and scope

Public module namespaces are the supported application surface; underscore-
prefixed helpers and state are internal. Some APIs are conditional by design:
`z::event::*` exists only when `zbus` is available before `z` initializes,
and asynchronous logging is currently experimental. Consult each API page for
module-specific contracts and caveats before depending on those surfaces.
