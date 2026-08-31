#!/usr/bin/env zsh
# =============================================================================
# test_ui_dimensions.zsh — Terminal size resolution and the optional cache
# =============================================================================
# Description:  docs/api/ui.md promises the resolution order cache → $COLUMNS
#               → tput → 80. A non-interactive zsh sets COLUMNS=0, and 0
#               satisfies the <-> integer pattern, so an unqualified numeric
#               test accepted it as a real width: every script and pipeline
#               got a width of 0 and the tput and 80 fallbacks were
#               unreachable.
#
#               Every case runs in a clean child shell through
#               ztest::child_prelude, because the condition being tested is a
#               property of a non-interactive shell — simulating it by
#               assigning COLUMNS in the runner's own process would not
#               reproduce it faithfully.
#
#               The cache cases cover the other half: z::cache::* comes from
#               the z module, which loads after ui, so ui treats it as an
#               optional dependency. It must be used when present, skipped
#               cleanly when absent, and never produce a "command not found".
#
# Usage:        zsh tests/run_tests.zsh ui
#               zsh tests/unit/ui/test_ui_dimensions.zsh    # standalone
#
# Covers:       z::ui::width, z::ui::height, z::ui::watch_resize, z::ui::box
#
# Requires:     tests/bootstrap.zsh — for ZCORE_ROOT and ztest::child_prelude.
#               ui is not loaded in-process: every case runs a child shell.
# =============================================================================

source "${0:A:h}/../../bootstrap.zsh"

# _ui_child <module> ... -- <script>
# Run <script> in a clean non-interactive child shell with the named modules
# loaded, and set REPLY to its stdout and REPLY2 to its stderr.
_ui_child() {
  local -a modules
  while (( $# )) && [[ $1 != "--" ]]; do
    modules+=( "$1" )
    shift
  done
  shift   # drop the --

  local script="$1"
  local errfile
  errfile="$(mktemp "${TMPDIR:-/tmp}/ztest-ui.XXXXXX")" || return 1

  ztest::child_prelude "${modules[@]}" || return 1

  REPLY="$(zsh -f -c "
    $REPLY
    $script
  " 2>"$errfile")"
  REPLY2="$(<"$errfile")"

  rm -f -- "$errfile"
  return 0
}


# -----------------------------------------------------------------------------
# The documented fallback
# -----------------------------------------------------------------------------

test_ui_width_falls_back_to_80_in_a_script() {
  _ui_child ui -- 'print -r -- "[${COLUMNS:-unset}] $(z::ui::width)"'
  ztest::assert::eq "[0] 80" "$REPLY" "COLUMNS=0 must not be taken as a width"
}

test_ui_height_falls_back_to_24_in_a_script() {
  _ui_child ui -- 'print -r -- "[${LINES:-unset}] $(z::ui::height)"'
  ztest::assert::eq "[0] 24" "$REPLY"
}

test_ui_dimensions_are_silent_without_the_z_module() {
  _ui_child ui -- 'z::ui::width >/dev/null; z::ui::height >/dev/null'
  ztest::assert::eq "" "$REPLY2" "no diagnostic for the absent cache"
  ztest::assert::not_contains "$REPLY2" "command not found"
}


# -----------------------------------------------------------------------------
# Explicit values and rejected ones
# -----------------------------------------------------------------------------

test_ui_width_honours_a_valid_columns() {
  _ui_child ui -- 'COLUMNS=120; z::ui::width'
  ztest::assert::eq "120" "$REPLY"
}

test_ui_height_honours_a_valid_lines() {
  _ui_child ui -- 'LINES=48; z::ui::height'
  ztest::assert::eq "48" "$REPLY"
}

test_ui_width_rejects_a_non_integer_columns() {
  _ui_child ui -- 'COLUMNS=abc; z::ui::width'
  ztest::assert::eq "80" "$REPLY"

  _ui_child ui -- 'COLUMNS=-5; z::ui::width'
  ztest::assert::eq "80" "$REPLY" "a negative width is not a width"
}

# With no tput on PATH the chain has to land on the hardcoded default rather
# than on whatever the failed command substitution left behind.
test_ui_width_falls_back_when_tput_is_absent() {
  _ui_child ui -- 'PATH=""; hash -r; COLUMNS=0; z::ui::width'
  ztest::assert::eq "80" "$REPLY"

  _ui_child ui -- 'PATH=""; hash -r; LINES=0; z::ui::height'
  ztest::assert::eq "24" "$REPLY"
}


# -----------------------------------------------------------------------------
# The optional z::cache dependency
# -----------------------------------------------------------------------------

# Loading ui on its own must leave the cache genuinely absent — this is the
# condition the old 2>/dev/null was hiding.
test_ui_cache_is_absent_when_only_ui_is_loaded() {
  _ui_child ui -- 'print -r -- "${+functions[z::cache::get]}"'
  ztest::assert::eq "0" "$REPLY"
}

# And with the full stack the memoisation has to actually populate, rather
# than failing silently as it did before. z::ui::width prints to stdout, so it
# is called directly here: a $(...) capture would run it in a subshell and the
# cache write would not survive.
test_ui_width_populates_the_cache_when_z_is_loaded() {
  _ui_child ui z -- '
    z::ui::width >/dev/null
    z::probe::cache "ui:term_width" && print -r -- "cached" || print -r -- "missing"
  '
  ztest::assert::eq "cached" "$REPLY"
}

test_ui_cached_width_matches_the_measured_one() {
  _ui_child ui z -- '
    COLUMNS=132
    z::ui::width >/dev/null
    z::ui::width
  '
  ztest::assert::eq "132" "$REPLY" "the cached read returns the same value"
}

# emulate -L zsh enables LOCAL_TRAPS, which used to discard this handler the
# moment watch_resize returned, so the cache was never invalidated on resize.
test_ui_watch_resize_installs_a_lasting_trap() {
  _ui_child ui z -- '
    z::ui::watch_resize
    print -r -- "${+functions[TRAPWINCH]}"
  '
  ztest::assert::eq "1" "$REPLY" "the trap must outlive watch_resize"
}

test_ui_watch_resize_invalidates_the_cached_width() {
  _ui_child ui z -- '
    z::ui::width >/dev/null
    z::ui::watch_resize
    TRAPWINCH
    z::probe::cache "ui:term_width" && print -r -- "stale" || print -r -- "invalidated"
  '
  ztest::assert::eq "invalidated" "$REPLY"
}

test_ui_watch_resize_leaves_an_existing_trap_alone() {
  _ui_child ui z -- '
    TRAPWINCH() { print -r -- "mine" }
    z::ui::watch_resize
    TRAPWINCH
  '
  ztest::assert::eq "mine" "$REPLY"
}


# -----------------------------------------------------------------------------
# A consumer of the dimensions
# -----------------------------------------------------------------------------

# z::ui::box auto-sizes from z::ui::width and clamps its inner width to a
# minimum of 10, so at width 0 it truncated "hello world" to "hell…orld".
test_ui_box_renders_full_width_content() {
  _ui_child ui -- 'z::ui::box "Title" 0 "hello world" 2>&1'
  ztest::assert::contains "$REPLY" "hello world"
  ztest::assert::not_contains "$REPLY" "…"
}

# Standalone execution; under the runner ztest::run is called by the runner.
(( ${ZTEST_RUNNER:-0} )) || ztest::run "${1:-test_*}"
