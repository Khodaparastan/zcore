# zcore documentation

This documentation covers zcore as both an application framework and a
maintained source project. Start with the [project README](../README.md) for
installation, positioning, and a runnable tour; use this page to find the
right level of detail for your task.

## Learn the framework

| Goal | Read |
| :--- | :--- |
| Install zcore and build a first script | [README: Install](../README.md#install) and [Five-minute tour](../README.md#five-minute-tour) |
| Decide which modules to load | [README: Choose the right layer](../README.md#choose-the-right-layer) |
| Understand process scope, dependencies, and optional integrations | [Architecture](architecture.md) |
| Use `REPLY`, `reply`, status codes, and namespaces correctly | [Conventions](conventions.md#return-channel-reply-reply-reply2) |
| Find an exact function signature or edge case | [API reference](#api-reference) |
| Run or extend the test suite | [Architecture: Tests](architecture.md#tests) |
| Change a generated module safely | [Conventions: Split-source layout](conventions.md#split-source-layout) |

## Concept guides

### [Architecture](architecture.md)

The runtime model: strict prerequisites, optional cross-module integrations,
loader behavior, process-local state, generated sources, testing boundaries,
versioning, and public API scope.

### [Conventions](conventions.md)

The coding contract: scalar and array result channels, shared errors,
verb-root naming, internal visibility, sibling-file resolution, source banners,
function documentation, and test organization.

## API reference

| Module | Best for | Major capabilities | Availability |
| :--- | :--- | :--- | :--- |
| [`zlog`](api/zlog.md) | Observable scripts and services | Structured fields, contexts, formats, files, rotation, buffering, throttling, timing | Core module; async delivery is experimental |
| [`zbase`](api/zbase.md) | Disciplined shell foundations | Predicates, guards, path/time queries, state changes, execution, hooks | Requires `zlog` |
| [`ui`](api/ui.md) | Interactive CLIs that also run in CI | Terminal capabilities, dimensions, formatting, boxes, progress tracks, spinner | Uses cache/config when `z` is present |
| [`zkv`](api/zkv.md) | Structured process-local state | Scalar and collection types, TTL, transactions, persistence, locks, watchers | Requires `zlog` and `zbase` |
| [`zbus`](api/zbus.md) | Decoupled in-process components | Priority and wildcard events, safe/async modes, history, stats, channels | Requires `zkv`; state is process scoped |
| [`z`](api/z.md) | Integrated application runtime | Cache, typed config, platform and signal services, diagnostics, event adapters | Event namespace is conditional on `zbus` |

## Core contracts at a glance

- **Loading:** source [`zcore.zsh`](../zcore.zsh) for the complete stack. For
  subsets, follow the canonical [load order](architecture.md#load-order).
- **Results:** read `REPLY`, `reply`, or `REPLY2` immediately after a function
  that documents one of those channels. Some APIs intentionally print to
  stdout instead.
- **Errors:** shared status constants are the `Z_ERR_*` values exported by
  `zbase`; module-specific status codes remain with their defining module.
- **State:** stores, subscriptions, caches, and most diagnostics live in the
  current Zsh process. Forked or async work receives a copy, not shared state.
- **Visibility:** public application functions use `zlog::*` or documented
  `z::*` namespaces. Underscore-prefixed functions and variables are private.
- **Conditional APIs:** `z::event::*` is bound only when `zbus` is loaded
  before `z`; experimental surfaces are identified by their module reference.

## Source of truth

API pages describe supported caller behavior. The source doc block immediately
above each function is authoritative for its exact arguments, result channel,
status codes, and side effects. When changing behavior, update source docs,
this reference, and tests together.
