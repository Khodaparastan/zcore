# zcore

A modular Zsh framework: structured logging, validation/probes, in-memory KV store, event bus, and integration layer.

**Version:** see [VERSION](../VERSION) (currently 2.1.0)

## Quick start

```zsh
# From a checkout — source in dependency order:
source /path/to/zcore/zlog
source /path/to/zcore/zbase
source /path/to/zcore/zkv    # optional for zbus
source /path/to/zcore/zbus   # optional
source /path/to/zcore/z      # integration layer
```

Root-level `z`, `zbase`, `zkv`, `zbus`, `zlog` are thin wrappers that source `lib/`.

## Layout

```
lib/          Source modules (split by namespace)
bin/zbundle   Build single-file dist/ bundles
dist/         Generated bundles (gitignored): zlog, zbase, zkv, zbus, z, z-framework
tests/        Unit + integration tests
docs/         Architecture, conventions, API reference
```

## Development

```sh
make test       # run all tests
make lint       # zsh -n syntax check
make bundle     # build dist/
make install    # install to ~/.local/share/zcore
```

See [docs/architecture.md](architecture.md) and [docs/conventions.md](conventions.md).
