#!/usr/bin/env zsh
#
# ==============================================================================
# Zcore Test Suite (Production-Ready)
#
# Usage:
#   1. Save the library as `../zcore.zsh` relative to this script.
#   2. Run: ./run.zsh
#      Optional: VERBOSE=1 ./run.zsh (to enable debug logs from the library)
# ==============================================================================

emulate -L zsh
setopt typeset_silent

# Ensure we are in the script's directory
cd "${0:h}" || exit 1

# Source the library to be tested
if [[ ! -f ../lib/core.zsh ]]; then
    print -r -- "FATAL: Library not found at ../zcore.zsh" >&2
    exit 1
fi
source ../lib/core.zsh

# Honor VERBOSE=1 to increase library logging (optional)
if [[ -n ${VERBOSE:-} ]]; then
    z::log::enable_debug
fi

# --- Test Harness ---

typeset -gi _test_count=0
typeset -gi _fail_count=0
typeset -gi _skip_count=0
typeset -g  _test_temp_dir
typeset -g  _orig_PATH="${PATH}"
typeset -g  _orig_COLUMNS="${COLUMNS:-}"
typeset -g  _orig_perf="${_zcore_config[performance_mode]}"
typeset -g  _orig_show_progress="${_zcore_config[show_progress]}"

# Helpers for standardized output
_green() {
    if [[ -n ${_zcore_colors[green]} ]]; then
        print -n -- "${_zcore_colors[green]}$1${_zcore_colors[reset]}"
    else
        print -n -- "$1"
    fi
}
_red() {
    if [[ -n ${_zcore_colors[red]} ]]; then
        print -n -- "${_zcore_colors[red]}$1${_zcore_colors[reset]}"
    else
        print -n -- "$1"
    fi
}
_yellow() {
    if [[ -n ${_zcore_colors[yellow]} ]]; then
        print -n -- "${_zcore_colors[yellow]}$1${_zcore_colors[reset]}"
    else
        print -n -- "$1"
    fi
}

_assert_success() {
    # capture rc BEFORE any commands in the helper
    local -i rc=$?
    emulate -L zsh
    setopt typeset_silent
    (( _test_count++ ))
    if (( rc == 0 )); then
        _green "✔"; print -r -- " Pass: $1"
    else
        (( _fail_count++ ))
        _red "✖"; print -r -- " Fail: $1 (Expected exit 0, got $rc)"
    fi
    return $rc
}

_assert_fail() {
    # capture rc BEFORE any commands in the helper
    local -i rc=$?
    emulate -L zsh
    setopt typeset_silent
    (( _test_count++ ))
    if (( rc != 0 )); then
        _green "✔"; print -r -- " Pass: $1"
        return 0
    else
        (( _fail_count++ ))
        _red "✖"; print -r -- " Fail: $1 (Expected non-zero exit, got 0)"
        return 1
    fi
}

_assert_rc() {
    emulate -L zsh
    setopt typeset_silent
    local -i expected="$1" rc="$2"
    local msg="$3"
    (( _test_count++ ))
    if (( rc == expected )); then
        _green "✔"; print -r -- " Pass: $msg"
        return 0
    else
        (( _fail_count++ ))
        _red "✖"; print -r -- " Fail: $msg"
        print -r -- "  Expected rc: $expected"
        print -r -- "  Actual rc:   $rc"
        return 1
    fi
}

_assert_equal() {
    emulate -L zsh
    setopt typeset_silent
    local expected="$1" actual="$2" msg="$3"
    (( _test_count++ ))
    if [[ "$expected" == "$actual" ]]; then
        _green "✔"; print -r -- " Pass: $msg"
        return 0
    else
        (( _fail_count++ ))
        _red "✖"; print -r -- " Fail: $msg"
        print -r -- "  Expected: '$expected'"
        print -r -- "  Actual:   '$actual'"
        return 1
    fi
}

# Literal substring contains (needle treated literally, not as a pattern)
_assert_contains() {
    emulate -L zsh
    setopt typeset_silent
    local haystack="$1" needle="$2" msg="$3"
    (( _test_count++ ))
    # Backslash-escape and then evaluate as pattern to neutralize glob metachars
    local escaped="${(b)needle}"
    local -i pos
    pos=${haystack[(i)$~escaped]}
    if (( pos <= ${#haystack} )); then
        _green "✔"; print -r -- " Pass: $msg"
        return 0
    else
        (( _fail_count++ ))
        _red "✖"; print -r -- " Fail: $msg"
        print -r -- "  Expected string to contain: '$needle'"
        print -r -- "  Actual string: '$haystack'"
        return 1
    fi
}

# Regex match using zsh's [[ str =~ ERE ]]
_assert_matches() {
    emulate -L zsh
    setopt typeset_silent
    local str="$1" ere="$2" msg="$3"
    (( _test_count++ ))
    local -i match_result=0
    print -r -- "$str" | command grep -E -q -- "$ere" >/dev/null 2>&1 || match_result=1
    if (( match_result == 0 )); then
        _green "✔"; print -r -- " Pass: $msg"
        return 0
    else
        (( _fail_count++ ))
        _red "✖"; print -r -- " Fail: $msg"
        print -r -- "  ERE: $ere"
        print -r -- "  String: $str"
        return 1
    fi
}

_assert_skip() {
    emulate -L zsh
    setopt typeset_silent
    (( _skip_count++ ))
    _yellow "↷"; print -r -- " Skip: $1"
    return 0
}

_setup() {
    emulate -L zsh
    setopt typeset_silent
    _test_temp_dir=$(mktemp -d)
    # normalize env knobs for predictable tests
    _zcore_config[performance_mode]=false
    _zcore_config[show_progress]=true
}

_teardown() {
    emulate -L zsh
    setopt typeset_silent
    # restore critical env
    export PATH="$_orig_PATH"
    if [[ -n "$_orig_COLUMNS" ]]; then
        export COLUMNS="$_orig_COLUMNS"
    else
        unset -v COLUMNS
    fi
    _zcore_config[performance_mode]="${_orig_perf}"
    _zcore_config[show_progress]="${_orig_show_progress}"
    [[ -n "$_test_temp_dir" && -d "$_test_temp_dir" ]] && rm -rf -- "$_test_temp_dir"
    # Clean up filesystem test artifacts if they exist
    [[ -d "$HOME/zcore_test_dir" ]] && rm -rf -- "$HOME/zcore_test_dir"
}

trap _teardown EXIT

# --- Test Cases ---

run_core_framework_tests() {
    emulate -L zsh
    setopt typeset_silent
    printf '\n'
    print -r -- "--- Testing Core Framework & Logging ---"

    # Test logging level switch
    local -i initial_level=$_zcore_verbose_level
    z::log::enable_debug
    _assert_equal "${_zcore_config[log_debug]}" "${_zcore_verbose_level}" "z::log::enable_debug sets debug level"
    _zcore_verbose_level=$initial_level

    # z::config::set validation
    z::config::set 'log_warn' 1
    _assert_success "z::config::set accepts valid int key/value"
    z::config::set 'nonexistent_key' 'some_value'
    _assert_fail "z::config::set rejects unknown key"
    z::config::set 'show_progress' true
    _assert_success "z::config::set accepts boolean"
    z::config::set 'show_progress' maybe
    _assert_fail "z::config::set rejects invalid boolean"

    # log engine prints timestamps and level tags
    local output
    output=$(z::log::info "test message" 2>&1)
    _assert_contains "$output" "[info]" "z::log::info contains [info]"
    _assert_contains "$output" "test message" "z::log::info contains message"

    # die() should return (not exit) when sourced
    # Test this by creating a test script that sources the library
    local test_script="${_test_temp_dir}/die_test.zsh"
    cat > "$test_script" << 'EOF'
#!/usr/bin/env zsh
source ../zcore.zsh
z::runtime::die "expected-failure" 9
echo "This should not print"
EOF
    chmod +x "$test_script"
    "$test_script" >/dev/null 2>&1
    local die_rc=$?
    _assert_rc 9 $die_rc "z::runtime::die returns code when sourced"
}

run_command_and_alias_tests() {
    emulate -L zsh
    setopt typeset_silent
    printf '\n'
    print -r -- "--- Testing Command, Alias & PATH Handling ---"

    # alias define and execution
    z::alias::define "testalias" "echo hello"
    _assert_success "z::alias::define succeeds"
    local alias_exec_output
    alias_exec_output=$(testalias)
    _assert_equal "hello" "$alias_exec_output" "Alias executes"
    unalias testalias 2>/dev/null

    z::alias::define "invalid name" "value"
    _assert_fail "z::alias::define fails for invalid name"

    # alias name extraction (private)
    local name
    name=$(z::alias::_extract_name "nocorrect sudo -u root env FOO=1 echo hi")
    _assert_equal "echo" "$name" "z::alias::_extract_name parses command correctly"

    # PATH add/duplicates
    local original_path="$PATH"
    local test_dir="${_test_temp_dir}/bin"
    mkdir -p -- "$test_dir"
    local resolved_test_dir
    resolved_test_dir=$(z::path::resolve "$test_dir")

    z::path::add "$test_dir" "prepend"
    _assert_success "z::path::add succeeds"
    _assert_equal "${resolved_test_dir}:${original_path}" "$PATH" "z::path::add prepends"
    z::path::add "$test_dir" "append"
    _assert_success "z::path::add no-op on duplicate"
    _assert_equal "${resolved_test_dir}:${original_path}" "$PATH" "No duplicates added"

    export PATH="$original_path"
}

run_exec_engine_tests() {
    emulate -L zsh
    setopt typeset_silent
    printf '\n'
    print -r -- "--- Testing Safe Execution & Scanners ---"

    # Simple run captures stdout and returns 0
    local out rc
    out=$(z::exec::run "echo 'safe exec'")
    rc=$?
    _assert_rc 0 $rc "z::exec::run returns 0"
    _assert_equal "safe exec" "$out" "z::exec::run captures stdout"

    # pipefail behavior: false | true should be non-zero
    z::exec::run "false | true" >/dev/null
    _assert_fail "z::exec::run propagates pipeline failure (pipefail)"

    # Dangerous patterns blocked
    z::exec::run "rm -rf /" >/dev/null 2>&1
    _assert_fail "Scanner blocks dangerous rm -rf /"
    z::exec::run "dd if=/dev/zero of=/dev/rdisk0 bs=1 count=1" >/dev/null 2>&1
    _assert_fail "Scanner blocks dd to raw device (macOS rdisk*)"
    z::exec::run "mkfs.ext4 /dev/sda" >/dev/null 2>&1
    _assert_fail "Scanner blocks mkfs on device"
    z::exec::run "chmod 0777 /" >/dev/null 2>&1
    _assert_fail "Scanner blocks chmod 0777 /"
    z::exec::run "killall -9 something" >/dev/null 2>&1
    _assert_fail "Scanner blocks kill -9"
    z::exec::run "userdel -r bob" >/dev/null 2>&1
    _assert_fail "Scanner blocks userdel -r"
    z::exec::run "groupdel admins" >/dev/null 2>&1
    _assert_fail "Scanner blocks groupdel"
    z::exec::run ":(){ :|:&; : }" >/dev/null 2>&1
    _assert_fail "Scanner blocks fork-bomb pattern"

    # init command detection (private helper via scan bypass for init commands)
    local init1="eval \"$(starship init zsh)\""
    local init2="env FOO=1 zoxide init zsh"
    z::exec::_is_init_cmd "$init1"
    _assert_success "init-cmd detection matches starship init"
    z::exec::_is_init_cmd "$init2"
    _assert_success "init-cmd detection matches zoxide init"

    # z::exec::eval: trusted eval path (force_current_shell=true)
    z::exec::eval "X_TEST_VAR=ok" 5 true
    _assert_success "z::exec::eval executes in current shell when forced"
    _assert_equal "ok" "${X_TEST_VAR-}" "eval affected current shell"
    unset -v X_TEST_VAR

    # package install detection shouldn't skip scan in run(), but eval-side check exists
    z::exec::eval "pip uninstall foo" 5 false
    _assert_success "z::exec::eval allows benign uninstall"

    # timeout behavior (conditional)
    local have_timeout_cmd=0
    if (( $+commands[timeout] )) || (( $+commands[gtimeout] )); then
        have_timeout_cmd=1
    fi
    if (( have_timeout_cmd )); then
        z::exec::run "sleep 2" 1 >/dev/null 2>&1
        rc=$?
        _assert_rc 124 $rc "z::exec::run returns 124 on timeout"
    else
        _assert_skip "timeout/gtimeout not available; skipping timeout test"
    fi
}

run_filesystem_tests() {
    emulate -L zsh
    setopt typeset_silent
    printf '\n'
    print -r -- "--- Testing Filesystem & Sourcing ---"

    # Tilde expansion and resolve
    local test_path="~/zcore_test_dir/file.txt"
    local expected_path="$HOME/zcore_test_dir/file.txt"
    mkdir -p -- "$HOME/zcore_test_dir"
    : >| "$expected_path"
    local resolved_tilde_path resolved_expected_path
    resolved_tilde_path=$(z::path::resolve "$test_path")
    resolved_expected_path=$(z::path::resolve "$expected_path")
    _assert_equal "$resolved_expected_path" "$resolved_tilde_path" "resolve expands ~"

    # Relative path normalization via :A
    local reldir="${_test_temp_dir}/sub"
    mkdir -p -- "$reldir"
    pushd "$_test_temp_dir" >/dev/null
    local abs_from_rel
    abs_from_rel=$(z::path::resolve "sub")
    popd >/dev/null
    _assert_contains "$abs_from_rel" "$_test_temp_dir/sub" "resolve handles relative paths"

    # Symlink resolution
    local target="${_test_temp_dir}/target"
    local link="${_test_temp_dir}/link"
    : >| "$target"
    ln -sf "$target" "$link"
    local resolved_link
    resolved_link=$(z::path::resolve "$link")
    # On macOS, /var/folders is a symlink to /private/var/folders, so we need to be flexible
    if [[ "$resolved_link" == "$target" ]] || [[ "$resolved_link" == "/private$target" ]]; then
        _green "✔"; print -r -- " Pass: resolve follows symlinks (when readlink available)"
    else
        (( _fail_count++ ))
        _red "✖"; print -r -- " Fail: resolve follows symlinks (when readlink available)"
        print -r -- "  Expected: '$target' or '/private$target'"
        print -r -- "  Actual:   '$resolved_link'"
    fi
    (( _test_count++ ))

    # Sourcing (normal mode)
    local test_file="${_test_temp_dir}/test.sh"
    print -r -- 'export SOURCED_VAR="success"' >| "$test_file"
    z::path::source "$test_file"
    _assert_success "path::source sources existing file"
    _assert_equal "success" "${SOURCED_VAR-}" "sourced variable set"
    unset -v SOURCED_VAR

    # Sourcing (perf mode true: skip heavy normalization but still source)
    _zcore_config[performance_mode]=true
    z::path::source "$test_file"
    _assert_success "path::source works in performance mode"
    _zcore_config[performance_mode]=false

    z::path::source "/nonexistent/file"
    _assert_fail "path::source fails for non-existent file"
}

run_introspection_and_cache_tests() {
    emulate -L zsh
    setopt typeset_silent
    printf '\n'
    print -r -- "--- Testing Introspection, Caching & State ---"

    # Command lookup
    z::cmd::exists "ls"
    _assert_success "cmd::exists finds 'ls'"
    z::cmd::exists "commandthatdoesnotexist12345"
    _assert_fail "cmd::exists does not find bogus command"

    # Function lookup
    z::func::exists "z::log::info"
    _assert_success "func::exists finds 'z::log::info'"
    z::func::exists "functionthatdoesnotexist12345"
    _assert_fail "func::exists does not find bogus function"

    # func::call existing and missing
    z::func::call "z::log::info" "hello" >/dev/null
    _assert_success "func::call executes existing function"
    z::func::call "missing_function_zzz" >/dev/null 2>&1
    _assert_fail "func::call warns and fails for missing function"

    # Variable unset
    TEST_VAR="hello"
    z::var::unset "TEST_VAR"
    _assert_success "var::unset succeeds"
    local -i var_exists=${+parameters[TEST_VAR]}
    _assert_equal "0" "$var_exists" "variable is unset"

    # Function unset + cache sync
    test_func_tmp() { echo "x"; }
    z::func::unset "test_func_tmp"
    _assert_success "func::unset succeeds"
    z::func::exists "test_func_tmp"
    _assert_fail "function is unset"

    # Cache purge behavior (reduce cache size and overflow)
    local -i old_max=${_zcore_config[cache_max_size]}
    _zcore_config[cache_max_size]=5
    local i
    for i in {1..12}; do
        z::func::exists "zcore_dummy_func_$i" >/dev/null
        z::cmd::exists "zcore_dummy_cmd_$i" >/dev/null
    done
    # After purge, size must be <= max
    _assert_equal "$((_func_cache_size <= _zcore_config[cache_max_size] ? 1 : 0))" "1" "function cache size <= max"
    _assert_equal "$((_cmd_cache_size  <= _zcore_config[cache_max_size] ? 1 : 0))" "1" "command cache size <= max"
    _zcore_config[cache_max_size]=$old_max
}

run_ui_tests() {
    emulate -L zsh
    setopt typeset_silent
    printf '\n'
    print -r -- "--- Testing UI (term width, progress logic, comma) ---"

    # term width uses COLUMNS when valid; cache works
    local w1 w2
    COLUMNS=123
    w1=$(z::ui::term::width)
    _assert_equal "123" "$w1" "term::width uses COLUMNS"
    COLUMNS=123
    w2=$(z::ui::term::width)
    _assert_equal "$w1" "$w2" "term::width cached until COLUMNS changes"
    COLUMNS=80
    w2=$(z::ui::term::width)
    _assert_equal "80" "$w2" "term::width updates when COLUMNS changes"

    # progress _should_show logic
    z::ui::progress::_should_show 1 10
    _assert_success "_should_show shows at start"
    z::ui::progress::_should_show 10 10
    _assert_success "_should_show shows at end"
    z::ui::progress::_should_show 3 9
    _assert_fail "_should_show hides non-interval for small totals"

    # comma formatting
    _assert_equal "1,234,567" "$(z::util::comma 1234567)" "comma formats large ints"
    _assert_equal "-1,234"    "$(z::util::comma -1234)"  "comma preserves sign"

    # Toggle progress config (visual not asserted due to no TTY)
    local -i before="${_zcore_verbose_level}"
    z::log::toggle_progress
    _assert_success "toggle_progress toggles without error"
    _zcore_verbose_level=$before
}

run_interrupt_tests() {
    emulate -L zsh
    setopt typeset_silent
    printf '\n'
    print -r -- "--- Testing Interrupt Handling ---"

    # Ensure interrupted flag starts clear
    _zcore_config_interrupted=0
    # Send INT to current shell; trap should handle gracefully
    kill -INT $$
    sleep 0.1  # allow trap to run
    _assert_equal "1" "$_zcore_config_interrupted" "handle_interrupt sets interrupted flag"

    # check_interrupted returns configured exit code
    z::runtime::check_interrupted >/dev/null 2>&1
    _assert_rc ${_zcore_config[exit_interrupted]} $? "check_interrupted returns exit_interrupted"
    _zcore_config_interrupted=0
}

# --- Main Execution ---

_setup
print -r -- "Starting Zcore test suite..."
run_core_framework_tests
run_command_and_alias_tests
run_exec_engine_tests
run_filesystem_tests
run_introspection_and_cache_tests
run_ui_tests
run_interrupt_tests

printf '\n'
print -r -- "--- Test Summary ---"
if (( _fail_count == 0 )); then
    if (( _skip_count > 0 )); then
        _green "All $_test_count tests passed"; print -r -- ", $_skip_count skipped."
    else
        _green "All $_test_count tests passed!"; print -r -- ""
    fi
    exit 0
else
    _red "$_fail_count out of $_test_count tests failed"; print -r -- ", $_skip_count skipped."
    exit 1
fi
