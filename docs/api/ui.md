# ui API Reference

> Complete reference for terminal UI primitives in `ui`.
> Public API: `z::ui::*`, `z::progress::*`, `z::util::*`.
> Private API: `__z::progress::*` — do not call directly.

---

## API Reference — `z::ui` / `z::progress` / `z::util`

---

### Table of Contents

1. [Namespace Overview](#1-namespace-overview)
2. [z::ui](#2-zui)
   - [z::ui::width](#zui-width)
   - [z::ui::height](#zui-height)
   - [z::ui::clear_line](#zui-clear_line)
   - [z::ui::clear](#zui-clear)
3. [z::progress](#3-zprogress)
   - [z::progress::show](#zprogress-show)
   - [z::progress::clear](#zprogress-clear)
   - [z::progress::enable](#zprogress-enable)
   - [z::progress::disable](#zprogress-disable)
   - [z::progress::spinner](#zprogress-spinner)
4. [z::util](#4-zutil)
   - [z::util::comma](#zutil-comma)
5. [Internal / Private](#5-internal--private)
   - [__z::progress::should_show](#zprogress-should_show)
6. [Dependencies](#6-dependencies)
7. [Exit Code Reference](#7-exit-code-reference)

---

## 1. Namespace Overview

| Namespace | Responsibility |
| :--- | :--- |
| `z::ui::*` | Terminal introspection and raw screen control |
| `z::progress::*` | Progress bar rendering, spinner, and visibility control |
| `z::util::*` | General-purpose formatting utilities |
| `__z::progress::*` | Private throttle, bar geometry, theming — internal use only |

All public functions begin with `emulate -L zsh`, enforcing strict Zsh emulation in a local scope. Terminal dimension queries (`z::ui::width`, `z::ui::height`) and number formatting (`z::util::comma`) print results to **stdout**. Progress bars, spinners, and line clearing write to **stderr**.

---

## 2. `z::ui`

---

### `z::ui::width` {#zui-width}

Returns the current terminal column width as a plain integer.

**Signature**

```zsh
z::ui::width
```

**Arguments** — none

**Output** — stdout

Prints a single integer representing the terminal width in columns.

**Return Codes**

| Code | Meaning |
| :--- | :--- |
| `0` | Width resolved and printed (from cache, `$COLUMNS`, or `tput`) |

**Resolution Order**

| Priority | Source | Condition |
| :---: | :--- | :--- |
| 1 | `z::cache` (`ui:term_width`) | Cache hit with TTL ≤ 1 s |
| 2 | `$COLUMNS` | Set and matches `<->` (pure integer) |
| 3 | `tput cols` | `tput` is in `$PATH` and returns a valid integer |
| 4 | Hardcoded default `80` | All above fail |

**Caching**

Result is written to the framework cache under the key `ui:term_width` with a TTL of **1 second**. Subsequent calls within that window skip all detection and return the cached value immediately.

**Example**

```zsh
local width
width=$(z::ui::width)
# width → 220
```

---

### `z::ui::height` {#zui-height}

Returns the current terminal row height as a plain integer.

**Signature**

```zsh
z::ui::height
```

**Arguments** — none

**Output** — stdout

Prints a single integer representing the terminal height in rows.

**Return Codes**

| Code | Meaning |
| :--- | :--- |
| `0` | Height resolved and printed |

**Resolution Order**

| Priority | Source | Condition |
| :---: | :--- | :--- |
| 1 | `$LINES` | Set and matches `<->` (pure integer) |
| 2 | `tput lines` | `tput` is in `$PATH` and returns a valid integer |
| 3 | Hardcoded default `24` | All above fail |

> **Note:** Unlike `z::ui::width`, height is **not cached**. Each call performs a fresh resolution. This is intentional — terminal height changes are less frequent and height is queried far less often than width.

**Example**

```zsh
local height
height=$(z::ui::height)
# height → 54
```

---

### `z::ui::clear_line` {#zui-clear_line}

Erases the current terminal line on stderr and optionally emits a newline.

**Signature**

```zsh
z::ui::clear_line [-f|--force] [-n|--no-newline] [--]
```

**Arguments**

| Flag | Long Form | Description |
| :--- | :--- | :--- |
| `-f` | `--force` | Emit the escape sequence even when stderr is not a TTY |
| `-n` | `--no-newline` | Suppress the trailing `\n` after the erase sequence |
| `--` | | End of option parsing |

**Output** — stderr

Emits `\r\e[K` (carriage return + erase-to-end-of-line), followed by `\n` unless `-n` is passed.

**Return Codes**

| Code | Meaning |
| :--- | :--- |
| `0` | Sequence emitted, or skipped because stderr is not a TTY (non-force mode) |
| `1` | Unrecognised argument passed |

**Behaviour**

When `--force` is **not** set and stderr is not an interactive terminal (`[[ ! -t 2 ]]`), the function exits silently with `0` — making it safe to call unconditionally in scripts that may run non-interactively.

**Examples**

```zsh
# Erase line and move to next line (default)
z::ui::clear_line

# Erase line, stay on same line (used by spinner/progress overwrite loops)
z::ui::clear_line --no-newline

# Force erase even when stderr is redirected
z::ui::clear_line --force --no-newline
```

---

### `z::ui::clear` {#zui-clear}

Clears the entire terminal screen.

**Signature**

```zsh
z::ui::clear
```

**Arguments** — none

**Output** — stdout (via `clear`)

**Return Codes**

| Code | Meaning |
| :--- | :--- |
| `0` | Always |

**Behaviour**

Calls the system `clear` command only when stdout is an interactive terminal (`[[ -t 1 ]]`). No-ops silently in non-interactive contexts (pipes, subshells, CI).

---

## 3. `z::progress`

---

### `z::progress::show` {#zprogress-show}

Renders a progress bar to stderr for a given `current / total` position.

**Signature**

```zsh
z::progress::show <current> <total> [label] [flags...]
```

**Arguments**

| Position | Name | Type | Required | Default | Description |
| :---: | :--- | :--- | :---: | :--- | :--- |
| `$1` | `current` | integer | ✓ | — | Items processed so far |
| `$2` | `total` | integer | ✓ | — | Total item count |
| `$3` | `label` | string | ✗ | `items` | Unit label shown in wide-terminal format |
| `$4+` | flags | — | ✗ | — | See flag table below |

**Flags**

| Flag | Description |
| :--- | :--- |
| `--newline` | Commit the bar to its own line (use when logs follow) |
| `--active` | Mark the next item as in-progress (discrete mode pulse) |
| `--fail` | Mark the current discrete cell as failed (`✗`) |
| `--skip` | Mark the current discrete cell as skipped (`◌`) |
| `--since <stamp>` | Show elapsed time / ETA from `EPOCHREALTIME` or epoch seconds |
| `--detail <text>` | Sub-label appended on wide terminals |

**Output** — stderr

Emits one of two formats depending on terminal width. Each update is preceded by `\r\e[K` to erase and redraw on the **current line** (in-place overwrite). By default, a trailing `\n` is emitted only when `current == total`. Pass `--newline` to emit `\n` after every update — required when log lines or other stderr output will follow before the next `show` call.

*Wide terminal* (`term_width > 70`):

```
▸ keybindings │ ⟨●●●●●●◉○○○○○○⟩ │  50% │ 6/12
```

Each glyph is **one item** when `total ≤ 24` (e.g. 12-module shell init):

| Glyph | Meaning |
| :---: | :--- |
| `●` | Completed |
| `◉` / `◎` | In progress (`--active`; alternates on each render) |
| `○` | Pending |

Pass `--active` **before** work starts so the label names the item loading and the frontier cell pulses:

```zsh
z::progress::show "$done" "$total" "$module" --active   # before source
# ... load module ...
z::progress::show "$total" "$total" "ready"             # final green bar
```

For large workloads (`total > 24`), a continuous gradient bar with leading-edge `╸`:

```
▸ records │ ⟨━━━━━━━━━▓╸────────────────────────────────⟩ │  21% │ 42/200
```

*Narrow terminal* (`term_width ≤ 70`):

```
▸  50% ⟨●●●●●●◉○○○○○○⟩ 6/12
```

When zlog colors are initialized and `NO_COLOR` is unset:

| Element | Color |
| :--- | :--- |
| `⟨` `⟩` frame, `│` separators | Dim |
| `●` done / `━` fill | Bright cyan |
| `◉` active | Bold bright yellow |
| `○` pending / `─` track | Bright black |
| `▓` gradient edge, `╸` head | Bright cyan / bold white |
| Percent & counts | Bold white / dim meta |
| 100% complete | Bright green throughout |

Without color support, the same layout renders without ANSI codes.

**Bar Geometry**

Bar width scales with terminal size (8–48 inner cells, plus `⟨⟩` frame). Reserved space includes label, `│` separators, percent, and counts:

| Terminal Width | Reserved Columns | Inner Bar Width |
| :---: | :---: | :---: |
| `> 100` | 44 | `term_width − 44` (capped at 48) |
| `> 70` | 38 | `term_width − 38` (capped at 48) |
| `≤ 70` | 28 | `term_width − 28` (capped at 48) |

Minimum inner width is **8** cells.

**Render modes**

| Condition | Style | Meaning |
| :--- | :--- | :--- |
| `total ≤ 24` | **Discrete** | `●` done, `◉`/`◎` active (`--active`), `○` pending — one glyph per item |
| `total > 24` | **Continuous** | `━` fill, `▓` gradient edge, `╸` head, `─` track |

Continuous position: `pos = ⌊current × segments / total⌋`; fill is `━…▓` with `╸` at the leading edge until complete.

**Return Codes**

| Code | Meaning |
| :--- | :--- |
| `0` | Bar rendered, intentionally skipped (see guards below), or completed with final newline |
| `1` | Non-integer arguments, or `current`/`total` out of valid range |

**Validation:** `current` and `total` must be integer strings. `total` must be `> 0`, and `current` must satisfy `0 ≤ current ≤ total`.

**Render Guard Conditions** — returns `0` without output when any of the following are true:

| Condition | Reason |
| :--- | :--- |
| stderr is not a TTY | Safe for non-interactive use |
| `show_progress` config is `"false"` | Explicitly disabled by caller |
| `__z::progress::should_show` returns `1` | Throttle interval not reached |

Progress output is **independent of `z::log::set_level`** — a quiet `error` console can still show bars when `show_progress` is `"true"`.

**Config Keys Read**

| Key | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `show_progress` | string | `true` | Master on/off switch (`"true"` / `"false"` string comparison) |
| `progress_update_interval` | integer | `10` | Throttle interval (delegated to `__z::progress::should_show`) |
| `progress_style` | string | `classic` | Bar style: `classic`, `minimal`, or `blocks` |

**Examples**

```zsh
# Basic usage — label defaults to "items"
z::progress::show 42 200

# Custom label
z::progress::show 1500 10000 "records"

# Shell init — show active item before each module loads
local -i done=0
for module in "${modules[@]}"; do
  z::progress::show "$done" "${#modules[@]}" "$module" --active
  source_module "$module"
  (( done++ ))
done
z::progress::show "${#modules[@]}" "${#modules[@]}" "ready"

# Typical loop — show after work; gate on config when optional
local i show_progress=0
if z::config::get show_progress 2>/dev/null && [[ $REPLY == true ]]; then
  show_progress=1
fi
for (( i = 1; i <= total; i++ )); do
  process_item "$i"   # may log to stderr
  if (( show_progress )); then
    # --newline when info/debug logging interleaves; omit for in-place redraw.
    if (( ${_zlog_config[level]:-2} >= _ZLOG_LEVEL_INFO )); then
      z::progress::show "$i" "$total" "files" --newline
    else
      z::progress::show "$i" "$total" "files"
    fi
  fi
done
```

---

### `z::progress::clear` {#zprogress-clear}

Erases the progress bar line from stderr without advancing to a new line. No-op when `show_progress` is `"false"`.

**Signature**

```zsh
z::progress::clear
```

**Arguments** — none

**Output** — stderr (via `z::ui::clear_line --no-newline`)

**Return Codes**

| Code | Meaning |
| :--- | :--- |
| `0` | Always |

**Usage Pattern**

Call immediately after a progress loop completes to leave the terminal clean before printing a final status message:

```zsh
for (( i = 1; i <= total; i++ )); do
  z::progress::show "$i" "$total"
done
z::progress::clear
print "Done."
```

---

### `z::progress::enable` {#zprogress-enable}

Sets the `show_progress` config key to `true`, re-enabling progress output.

**Signature**

```zsh
z::progress::enable
```

**Arguments** — none

**Return Codes**

| Code | Meaning |
| :--- | :--- |
| `0` | Config key set |

---

### `z::progress::disable` {#zprogress-disable}

Sets the `show_progress` config key to `false`, suppressing all progress output.

**Signature**

```zsh
z::progress::disable
```

**Arguments** — none

**Return Codes**

| Code | Meaning |
| :--- | :--- |
| `0` | Config key set |

**Example**

```zsh
z::progress::disable
run_batch_silently
z::progress::enable
```

---

### `z::progress::spinner` {#zprogress-spinner}

Advances and renders a single braille-dot spinner frame to stderr.

**Signature**

```zsh
z::progress::spinner [message]
```

**Arguments**

| Position | Name | Type | Required | Default | Description |
| :---: | :--- | :--- | :---: | :--- | :--- |
| `$1` | `message` | string | ✗ | `Working...` | Text displayed to the right of the spinner glyph |

**Output** — stderr

Emits `\r\e[K<frame> <message>` — overwrites the current line without advancing. The caller is responsible for clearing the line when the operation completes.

**Frame Sequence**

```
⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏  (10 frames, wraps)
```

**State**

Frame position is tracked in the global integer `_z_progress_spinner_idx`. The index wraps via modulo on each call — no external state management is required.

**Return Codes**

| Code | Meaning |
| :--- | :--- |
| `0` | Frame rendered, or skipped (non-TTY / progress disabled) |

**Render Guard Conditions**

| Condition | Behaviour |
| :--- | :--- |
| stderr is not a TTY | Silent no-op, returns `0` |
| `show_progress` is `"false"` | Silent no-op, returns `0` |

**Example**

```zsh
# Drive the spinner from a polling loop
while is_task_running; do
  z::progress::spinner "Waiting for cluster..."
  sleep 0.1
done
z::progress::clear
```

> **Note:** The spinner does **not** manage its own loop or timing. The caller controls cadence via `sleep` or event polling. This is intentional — it keeps the function composable with any async pattern.

---

## 4. `z::util`

---

### `z::util::comma` {#zutil-comma}

Formats an integer with thousands-separator commas.

**Signature**

```zsh
z::util::comma [number]
```

Uses `emulate -L zsh` and `setopt localoptions typeset_silent`.

**Arguments**

| Position | Name | Type | Required | Default | Description |
| :---: | :--- | :--- | :---: | :--- | :--- |
| `$1` | `number` | integer string | ✗ | `0` | The number to format |

**Output** — stdout

Prints the formatted number as a string.

**Return Codes**

| Code | Meaning |
| :--- | :--- |
| `0` | Always |

**Behaviour**

| Input | Output |
| :--- | :--- |
| `999` | `999` |
| `1000` | `1,000` |
| `1234567` | `1,234,567` |
| `-9876543` | `-9,876,543` |
| `abc` | `abc` *(non-integer passthrough)* |
| *(empty)* | `0` |

- Negative numbers: the sign is stripped, the absolute value is formatted, and the sign is re-prepended.
- Non-integer input is passed through unchanged — the function never errors on bad input.
- Uses base-10 forced parsing (`10#`) internally, but the input is treated as a plain string — no arithmetic overflow risk.

**Algorithm**

The integer string is walked left-to-right in chunks of 3, with the leading chunk sized as \(\text{len} \bmod 3\) (or 3 when evenly divisible). Commas are inserted between chunks during concatenation.

**Examples**

```zsh
z::util::comma 1000000   # → 1,000,000
z::util::comma -42500    # → -42,500
z::util::comma 42        # → 42
z::util::comma           # → 0
z::util::comma "n/a"     # → n/a
```

---

## 5. Internal / Private

---

### `__z::progress::should_show` {#zprogress-should_show}

Throttle gate — determines whether a progress update should be rendered for a given `current / total` pair.

> ⚠️ **Private.** Do not call this function directly. It is an implementation detail of `z::progress::show`.

**Signature**

```zsh
__z::progress::should_show <current> <total>
```

**Arguments**

| Position | Name | Type | Required |
| :---: | :--- | :--- | :---: |
| `$1` | `current` | integer | ✓ |
| `$2` | `total` | integer | ✓ |

**Return Codes**

| Code | Meaning |
| :--- | :--- |
| `0` | Caller **should** render a progress update |
| `1` | Caller **should skip** this update |

**Throttle Tiers**

| Total Range | Render Condition |
| :--- | :--- |
| Any | Always render when `current == 1` or `current == total` |
| `≤ 15` | Render every item |
| `16 – 50` | Render every 5th item (`current % 5 == 0`) |
| `> 50` | Render every `interval`-th item, or when within `interval` of the end |

**Config Keys Read**

| Key | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `progress_update_interval` | integer | `10` | Render interval for large totals; clamped to minimum of `1` |

---

## 6. Dependencies

| Dependency | Type | Used By | Notes |
| :--- | :--- | :--- | :--- |
| `zlog` | Module | `z::progress::show` | Must be loaded first; `z::log::debug` used only for invalid-input diagnostics |
| `z::cache::get` / `z::cache::set` | Internal module | `z::ui::width` | Key `ui:term_width`, TTL 1 s |
| `z::config::get` / `z::config::set` | Internal module | `z::progress::*`, `__z::progress::*` | Keys: `show_progress`, `progress_update_interval`, `progress_style`. **`z::config::get` sets `$REPLY`** — do not use `$(z::config::get …)` |
| `_zlog_colors` | `zlog` | `__z::progress::theme` | Optional ANSI styling when `__z::log::init_colors` has run; respects `NO_COLOR` |
| `z::log::debug` | `zlog` | `z::progress::show` | Emits debug messages on invalid input (respects log level; does not gate bar output) |
| `_z_progress_spinner_idx` | Global integer | `z::progress::spinner` | Persists across calls; declared with `typeset -gi` |
| `tput` | External binary | `z::ui::width`, `z::ui::height` | Optional; queried via `$+commands[tput]` |
| `clear` | External binary | `z::ui::clear` | Standard POSIX utility |

**Source order** (when loading standalone, outside the framework `init`):

```zsh
source ./zlog    # optional; only needed if z::log::debug diagnostics are desired
source ./ui      # or via framework init
```

---

## 7. Exit Code Reference

| Code | Meaning | Functions |
| :---: | :--- | :--- |
| `0` | Success or intentional no-op | All functions |
| `1` | Invalid argument type, unrecognised flag, or out-of-range value | `z::ui::clear_line`, `z::progress::show`, `__z::progress::should_show` |
