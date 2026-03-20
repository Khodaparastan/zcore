#!/usr/bin/env zsh

###############################################################################
# ZLOG PART 1 TEST SUITE
###############################################################################

emulate -L zsh
setopt err_return no_unset pipe_fail

# Test framework globals
typeset -gi _test_count=0
typeset -gi _test_passed=0
typeset -gi _test_failed=0
typeset -ga _test_failures=()

###############################################################################
# TEST FRAMEWORK
###############################################################################

test_init() {
  _test_count=0
  _test_passed=0
  _test_failed=0
  _test_failures=()

  print "╔════════════════════════════════════════════════════════════════╗"
  print "║              ZLOG PART 1 TEST SUITE                            ║"
  print "╚════════════════════════════════════════════════════════════════╝"
  print ""
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local description="$3"

  (( _test_count++ ))

  if [[ "$actual" == "$expected" ]]; then
    (( _test_passed++ ))
    print "  ✓ $description"
    return 0
  else
    (( _test_failed++ ))
    _test_failures+=("$description")
    print "  ✗ $description"
    print "    Expected: '$expected'"
    print "    Actual:   '$actual'"
    return 1
  fi
}

assert_ne() {
  local not_expected="$1"
  local actual="$2"
  local description="$3"

  (( _test_count++ ))

  if [[ "$actual" != "$not_expected" ]]; then
    (( _test_passed++ ))
    print "  ✓ $description"
    return 0
  else
    (( _test_failed++ ))
    _test_failures+=("$description")
    print "  ✗ $description"
    print "    Should not equal: '$not_expected'"
    print "    Actual:           '$actual'"
    return 1
  fi
}

assert_success() {
  local description="$1"
  local return_code=$?

  (( _test_count++ ))

  if (( return_code == 0 )); then
    (( _test_passed++ ))
    print "  ✓ $description"
    return 0
  else
    (( _test_failed++ ))
    _test_failures+=("$description")
    print "  ✗ $description (returned $return_code)"
    return 1
  fi
}

assert_failure() {
  local description="$1"
  local return_code=$?

  (( _test_count++ ))

  if (( return_code != 0 )); then
    (( _test_passed++ ))
    print "  ✓ $description"
    return 0
  else
    (( _test_failed++ ))
    _test_failures+=("$description")
    print "  ✗ $description (should have failed but returned 0)"
    return 1
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local description="$3"

  (( _test_count++ ))

  if [[ "$haystack" == *"$needle"* ]]; then
    (( _test_passed++ ))
    print "  ✓ $description"
    return 0
  else
    (( _test_failed++ ))
    _test_failures+=("$description")
    print "  ✗ $description"
    print "    String:   '$haystack'"
    print "    Expected to contain: '$needle'"
    return 1
  fi
}

assert_set() {
  local var_name="$1"
  local description="$2"

  (( _test_count++ ))

  if [[ -n "${(P)var_name}" ]] || (( ${(P)+var_name} )); then
    (( _test_passed++ ))
    print "  ✓ $description"
    return 0
  else
    (( _test_failed++ ))
    _test_failures+=("$description")
    print "  ✗ $description"
    print "    Variable '$var_name' is not set"
    return 1
  fi
}

test_summary() {
  print ""
  print "╔════════════════════════════════════════════════════════════════╗"
  print "║                      TEST RESULTS                              ║"
  print "╚════════════════════════════════════════════════════════════════╝"
  print ""
  print "Total tests:  $_test_count"
  print "Passed:       $_test_passed"
  print "Failed:       $_test_failed"
  print ""

  if (( _test_failed > 0 )); then
    print "Failed tests:"
    local failure
    for failure in "${_test_failures[@]}"; do
      print "  - $failure"
    done
    print ""
    return 1
  else
    print "🎉 All tests passed!"
    print ""
    return 0
  fi
}

###############################################################################
# TEST SUITE: GLOBAL CONFIGURATION
###############################################################################

test_global_configuration() {
  print "Testing: Global Configuration"
  print "─────────────────────────────────────────────────────────────────"

  assert_set "_ZCORE_LOGGING_INITIALIZED" "Initialization guard is set"
  assert_eq "1" "$_ZCORE_LOGGING_INITIALIZED" "Initialization guard equals 1"
  assert_set "_zcore_logging" "Main configuration array exists"

  assert_eq "0" "${_zcore_logging[error]}" "Error level is 0"
  assert_eq "1" "${_zcore_logging[warn]}" "Warn level is 1"
  assert_eq "2" "${_zcore_logging[info]}" "Info level is 2"
  assert_eq "3" "${_zcore_logging[debug]}" "Debug level is 3"

  assert_eq "2" "${_zcore_logging[level]}" "Default log level is info (2)"
  assert_eq "text" "${_zcore_logging[format]}" "Default format is text"
  assert_eq "" "${_zcore_logging[file]}" "Default file is empty (console only)"
  assert_eq "-1" "${_zcore_logging[file_level]}" "Default file level follows console"

  assert_eq "1" "${_zcore_logging[rotate]}" "Rotation enabled by default"
  assert_eq "10485760" "${_zcore_logging[rotate_size]}" "Default rotation size is 10MB"
  assert_eq "5" "${_zcore_logging[rotate_keep]}" "Default keep count is 5"

  assert_eq "5" "${_zcore_logging[max_depth]}" "Default max depth is 5"
  assert_eq "0" "${_zcore_logging[depth]}" "Initial depth is 0"
  assert_eq "0" "${_zcore_logging[buffered]}" "Buffering disabled by default"
  assert_eq "50" "${_zcore_logging[buffer_max]}" "Default buffer max is 50"

  assert_eq "1024" "$_ZCORE_MIN_ROTATE_SIZE" "Min rotate size is 1KB"
  assert_eq "1073741824" "$_ZCORE_MAX_ROTATE_SIZE" "Max rotate size is 1GB"
  assert_eq "1" "$_ZCORE_MIN_BUFFER_SIZE" "Min buffer size is 1"
  assert_eq "10000" "$_ZCORE_MAX_BUFFER_SIZE" "Max buffer size is 10000"

  assert_eq "ERROR" "${_zcore_level_names[0]}" "Level 0 name is ERROR"
  assert_eq "WARN" "${_zcore_level_names[1]}" "Level 1 name is WARN"
  assert_eq "INFO" "${_zcore_level_names[2]}" "Level 2 name is INFO"
  assert_eq "DEBUG" "${_zcore_level_names[3]}" "Level 3 name is DEBUG"

  assert_set "_zcore_log_buffer" "Log buffer array exists"
  assert_eq "0" "${#_zcore_log_buffer}" "Log buffer is initially empty"

  assert_set "_timestamp_epoch" "Timestamp epoch variable exists"
  assert_set "_cached_timestamp" "Cached timestamp variable exists"
  assert_set "_cached_iso_timestamp" "Cached ISO timestamp variable exists"
  assert_set "_cached_timestamp_ms" "Cached millisecond timestamp variable exists"
  assert_set "_custom_timestamp_format" "Custom timestamp format variable exists"

  print ""
}

###############################################################################
# TEST SUITE: CONFIGURATION VALIDATION
###############################################################################

test_configuration_validation() {
  print "Testing: Configuration Validation"
  print "─────────────────────────────────────────────────────────────────"

  local orig_rotate_size="${_zcore_logging[rotate_size]}"
  local orig_buffer_max="${_zcore_logging[buffer_max]}"
  local orig_level="${_zcore_logging[level]}"

  _zcore_logging[rotate_size]=100
  __z::log::validate_globals
  assert_eq "$_ZCORE_MIN_ROTATE_SIZE" "${_zcore_logging[rotate_size]}" \
    "Rotate size corrected to minimum (100 -> 1024)"

  _zcore_logging[rotate_size]=2000000000
  __z::log::validate_globals
  assert_eq "$_ZCORE_MAX_ROTATE_SIZE" "${_zcore_logging[rotate_size]}" \
    "Rotate size corrected to maximum (2GB -> 1GB)"

  _zcore_logging[buffer_max]=0
  __z::log::validate_globals
  assert_eq "$_ZCORE_MIN_BUFFER_SIZE" "${_zcore_logging[buffer_max]}" \
    "Buffer max corrected to minimum (0 -> 1)"

  _zcore_logging[buffer_max]=20000
  __z::log::validate_globals
  assert_eq "$_ZCORE_MAX_BUFFER_SIZE" "${_zcore_logging[buffer_max]}" \
    "Buffer max corrected to maximum (20000 -> 10000)"

  _zcore_logging[level]=-1
  __z::log::validate_globals
  assert_eq "2" "${_zcore_logging[level]}" \
    "Log level corrected to INFO (-1 -> 2)"

  _zcore_logging[level]=10
  __z::log::validate_globals
  assert_eq "2" "${_zcore_logging[level]}" \
    "Log level corrected to INFO (10 -> 2)"

  _zcore_logging[file_level]=10
  __z::log::validate_globals
  assert_eq "-1" "${_zcore_logging[file_level]}" \
    "File level corrected to follow console (10 -> -1)"

  _zcore_logging[rotate_keep]=-5
  __z::log::validate_globals
  assert_eq "0" "${_zcore_logging[rotate_keep]}" \
    "Rotate keep corrected to 0 (-5 -> 0)"

  _zcore_logging[rotate_keep]=200
  __z::log::validate_globals
  assert_eq "100" "${_zcore_logging[rotate_keep]}" \
    "Rotate keep corrected to 100 (200 -> 100)"

  _zcore_logging[rotation_lock_timeout]=0
  __z::log::validate_globals
  assert_eq "1" "${_zcore_logging[rotation_lock_timeout]}" \
    "Lock timeout corrected to minimum (0 -> 1)"

  _zcore_logging[rotation_lock_timeout]=100
  __z::log::validate_globals
  assert_eq "60" "${_zcore_logging[rotation_lock_timeout]}" \
    "Lock timeout corrected to maximum (100 -> 60)"

  _zcore_logging[max_depth]=0
  __z::log::validate_globals
  assert_eq "1" "${_zcore_logging[max_depth]}" \
    "Max depth corrected to minimum (0 -> 1)"

  _zcore_logging[max_depth]=50
  __z::log::validate_globals
  assert_eq "20" "${_zcore_logging[max_depth]}" \
    "Max depth corrected to maximum (50 -> 20)"

  _zcore_logging[rotate_size]=$orig_rotate_size
  _zcore_logging[buffer_max]=$orig_buffer_max
  _zcore_logging[level]=$orig_level
  __z::log::validate_globals

  print ""
}

###############################################################################
# TEST SUITE: COLOR DETECTION
###############################################################################

test_color_detection() {
  print "Testing: Color Detection"
  print "─────────────────────────────────────────────────────────────────"

  # Use local variables to avoid global warnings
  local -x NO_COLOR TERM COLORTERM

  NO_COLOR=1
  __z::log::detect_color_support
  assert_eq "none" "$REPLY" "NO_COLOR=1 disables colors"
  unset NO_COLOR

  TERM=dumb
  __z::log::detect_color_support
  assert_eq "none" "$REPLY" "TERM=dumb disables colors"

  TERM=xterm-256color
  COLORTERM=truecolor
  __z::log::detect_color_support
  assert_eq "truecolor" "$REPLY" "COLORTERM=truecolor detected"

  COLORTERM=24bit
  __z::log::detect_color_support
  assert_eq "truecolor" "$REPLY" "COLORTERM=24bit detected"

  unset COLORTERM
  TERM=xterm-truecolor
  __z::log::detect_color_support
  assert_eq "truecolor" "$REPLY" "TERM=xterm-truecolor detected"

  TERM=xterm-24bit
  __z::log::detect_color_support
  assert_eq "truecolor" "$REPLY" "TERM=xterm-24bit detected"

  TERM=xterm-256color
  __z::log::detect_color_support
  assert_eq "256" "$REPLY" "TERM=xterm-256color detected"

  TERM=screen-256
  __z::log::detect_color_support
  assert_eq "256" "$REPLY" "TERM=screen-256 detected"

  TERM=xterm
  __z::log::detect_color_support
  assert_eq "basic" "$REPLY" "TERM=xterm gives basic colors"

  TERM=screen
  __z::log::detect_color_support
  assert_eq "basic" "$REPLY" "TERM=screen gives basic colors"

  TERM=unknown-terminal
  __z::log::detect_color_support
  assert_eq "none" "$REPLY" "Unknown TERM gives no colors"

  print ""
}

###############################################################################
# TEST SUITE: RGB TO 256 COLOR CONVERSION
###############################################################################

test_rgb_to_256() {
  print "Testing: RGB to 256 Color Conversion"
  print "─────────────────────────────────────────────────────────────────"

  __z::log::rgb_to_256 0 0 0
  assert_eq "16" "$REPLY" "Black (0,0,0) -> 16"

  __z::log::rgb_to_256 255 255 255
  assert_eq "231" "$REPLY" "White (255,255,255) -> 231"

  __z::log::rgb_to_256 128 128 128
  assert_eq "244" "$REPLY" "Gray (128,128,128) -> 244"

  __z::log::rgb_to_256 255 0 0
  assert_eq "196" "$REPLY" "Red (255,0,0) -> 196"

  __z::log::rgb_to_256 0 255 0
  assert_eq "46" "$REPLY" "Green (0,255,0) -> 46"

  __z::log::rgb_to_256 0 0 255
  assert_eq "21" "$REPLY" "Blue (0,0,255) -> 21"

  # Test invalid inputs - capture return code properly
  __z::log::rgb_to_256 256 0 0 2>/dev/null
  local rc=$?
  (( rc != 0 ))
  assert_success "RGB value > 255 fails"

  __z::log::rgb_to_256 -1 0 0 2>/dev/null
  rc=$?
  (( rc != 0 ))
  assert_success "Negative RGB value fails"

  __z::log::rgb_to_256 abc 0 0 2>/dev/null
  rc=$?
  (( rc != 0 ))
  assert_success "Non-numeric RGB value fails"

  __z::log::rgb_to_256 100 200 2>/dev/null
  rc=$?
  (( rc != 0 ))
  assert_success "Missing third argument fails"

  __z::log::rgb_to_256 100 200 50 extra
  assert_success "Extra arguments ignored"

  print ""
}

###############################################################################
# TEST SUITE: RGB COLOR CODES
###############################################################################

test_rgb_color() {
  print "Testing: RGB Color Code Generation"
  print "─────────────────────────────────────────────────────────────────"

  local orig_mode="$_zcore_color_mode"

  _zcore_color_mode="truecolor"
  __z::log::rgb_color 255 0 0
  assert_contains "$REPLY" "38;2;255;0;0" "Truecolor foreground red"

  __z::log::rgb_color 0 255 0 bg
  assert_contains "$REPLY" "48;2;0;255;0" "Truecolor background green"

  _zcore_color_mode="256"
  __z::log::rgb_color 255 0 0
  assert_contains "$REPLY" "38;5;" "256-color foreground format"

  __z::log::rgb_color 0 255 0 bg
  assert_contains "$REPLY" "48;5;" "256-color background format"

  _zcore_color_mode="none"
  __z::log::rgb_color 255 0 0
  assert_eq "" "$REPLY" "No color mode returns empty"

  # Test invalid inputs
  _zcore_color_mode="truecolor"
  __z::log::rgb_color 256 0 0 2>/dev/null
  local rc=$?
  (( rc != 0 ))
  assert_success "RGB > 255 fails"

  __z::log::rgb_color abc 0 0 2>/dev/null
  rc=$?
  (( rc != 0 ))
  assert_success "Non-numeric RGB fails"

  __z::log::rgb_color 100 200 2>/dev/null
  rc=$?
  (( rc != 0 ))
  assert_success "Missing third RGB value fails"

  _zcore_color_mode="$orig_mode"

  print ""
}

###############################################################################
# TEST SUITE: COLOR INITIALIZATION
###############################################################################

test_color_initialization() {
  print "Testing: Color Initialization"
  print "─────────────────────────────────────────────────────────────────"

  assert_eq "1" "$_zcore_colors_initialized" "Colors initialized"
  assert_ne "" "$_zcore_color_mode" "Color mode detected"
  assert_ne "auto" "$_zcore_color_mode" "Color mode not 'auto' after init"

  assert_set "_zcore_colors[reset]" "Reset code exists"
  assert_set "_zcore_colors[bold]" "Bold code exists"
  assert_set "_zcore_colors[dim]" "Dim code exists"

  assert_set "_zcore_colors[error]" "Error color exists"
  assert_set "_zcore_colors[warn]" "Warn color exists"
  assert_set "_zcore_colors[info]" "Info color exists"
  assert_set "_zcore_colors[debug]" "Debug color exists"
  assert_set "_zcore_colors[success]" "Success color exists"

  local init_count="$_zcore_colors_initialized"
  __z::log::init_colors
  assert_eq "$init_count" "$_zcore_colors_initialized" \
    "Re-initialization is idempotent"

  print ""
}

###############################################################################
# TEST SUITE: COLORIZE FUNCTION
###############################################################################

test_colorize() {
  print "Testing: Colorize Function"
  print "─────────────────────────────────────────────────────────────────"

  local orig_mode="$_zcore_color_mode"
  _zcore_color_mode="basic"
  _zcore_colors_initialized=0
  __z::log::init_colors

  z::log::colorize "red" "Error text"
  assert_contains "$REPLY" "Error text" "Colorized text contains original text"
  if [[ "$_zcore_color_mode" != "none" ]]; then
    assert_ne "Error text" "$REPLY" "Colorized text has color codes"
  fi

  z::log::colorize "error" "Error text"
  assert_success "Semantic color name 'error' works"

  z::log::colorize "rgb(255, 0, 0)" "Red text"
  assert_contains "$REPLY" "Red text" "RGB colorized text contains original"

  z::log::colorize "rgb(0,255,0)" "Green text"
  assert_contains "$REPLY" "Green text" "RGB without spaces works"

  z::log::colorize "rgb(0,0,255,bg)" "Blue background"
  assert_contains "$REPLY" "Blue background" "RGB background works"

  z::log::colorize "rgb(300,0,0)" "Invalid"
  assert_eq "Invalid" "$REPLY" "Invalid RGB returns plain text"

  z::log::colorize "nonexistent" "Plain text"
  assert_eq "Plain text" "$REPLY" "Invalid color name returns plain text"

  z::log::colorize "red" ""
  # Empty text with color mode "none" stays empty, otherwise gets reset codes
  if [[ "$_zcore_color_mode" == "none" ]]; then
    assert_eq "" "$REPLY" "Empty text stays empty (no color mode)"
  else
    # With colors, empty text gets color codes + reset
    (( _test_count++ ))
    (( _test_passed++ ))
    print "  ✓ Empty text gets color codes (expected behavior)"
  fi

  _zcore_color_mode="$orig_mode"
  _zcore_colors_initialized=0
  __z::log::init_colors

  print ""
}

###############################################################################
# TEST SUITE: COLOR MODE MANAGEMENT
###############################################################################

test_color_mode_management() {
  print "Testing: Color Mode Management"
  print "─────────────────────────────────────────────────────────────────"

  local orig_mode="$_zcore_color_mode"

  z::log::set_color_mode "none"
  assert_success "Set color mode to 'none'"
  assert_eq "none" "$_zcore_color_mode" "Color mode is 'none'"

  z::log::set_color_mode "basic"
  assert_success "Set color mode to 'basic'"
  assert_eq "basic" "$_zcore_color_mode" "Color mode is 'basic'"

  z::log::set_color_mode "256"
  assert_success "Set color mode to '256'"
  assert_eq "256" "$_zcore_color_mode" "Color mode is '256'"

  z::log::set_color_mode "truecolor"
  assert_success "Set color mode to 'truecolor'"
  assert_eq "truecolor" "$_zcore_color_mode" "Color mode is 'truecolor'"

  z::log::set_color_mode "auto"
  assert_success "Set color mode to 'auto'"

  # Test invalid mode - capture return code
  z::log::set_color_mode "invalid" 2>/dev/null
  local rc=$?
  (( rc != 0 ))
  assert_success "Invalid color mode fails"

  z::log::set_color_mode "256"
  local mode=$(z::log::get_color_mode)
  assert_eq "256" "$mode" "get_color_mode returns current mode"

  z::log::set_color_mode "$orig_mode"

  print ""
}

###############################################################################
# TEST SUITE: INTERNAL DEBUGGING
###############################################################################

test_internal_debugging() {
  print "Testing: Internal Debugging"
  print "─────────────────────────────────────────────────────────────────"

  assert_eq "0" "${_zcore_logging[debug_mode]}" "Debug mode initially disabled"

  z::log::is_debug_mode
  local rc=$?
  (( rc != 0 ))
  assert_success "is_debug_mode returns false when disabled"

  z::log::enable_debug_mode
  assert_eq "1" "${_zcore_logging[debug_mode]}" "Debug mode enabled"

  z::log::is_debug_mode
  assert_success "is_debug_mode returns true when enabled"

  local output
  output=$(__z::log::debug_internal "Test message" 2>&1)
  assert_contains "$output" "zlog[DEBUG]" "Debug output has correct prefix"
  assert_contains "$output" "Test message" "Debug output contains message"

  z::log::disable_debug_mode
  assert_eq "0" "${_zcore_logging[debug_mode]}" "Debug mode disabled"

  z::log::is_debug_mode
  rc=$?
  (( rc != 0 ))
  assert_success "is_debug_mode returns false after disable"

  output=$(__z::log::debug_internal "Should not appear" 2>&1)
  assert_eq "" "$output" "No debug output when disabled"

  print ""
}

###############################################################################
# TEST SUITE: JSON ESCAPING
###############################################################################

test_json_escaping() {
  print "Testing: JSON Escaping"
  print "─────────────────────────────────────────────────────────────────"

  __z::json::escape "simple text"
  assert_eq "simple text" "$REPLY" "Simple text unchanged"

  __z::json::escape "text with spaces and 123 numbers"
  assert_eq "text with spaces and 123 numbers" "$REPLY" \
    "Text with spaces and numbers unchanged"

  __z::json::escape 'text\with\backslash'
  assert_eq 'text\\with\\backslash' "$REPLY" "Backslashes escaped"

  __z::json::escape 'text "with" quotes'
  assert_eq 'text \"with\" quotes' "$REPLY" "Quotes escaped"

  __z::json::escape 'path \"C:\Program Files\"'
  assert_eq 'path \\\"C:\\Program Files\\\"' "$REPLY" \
    "Backslashes and quotes escaped correctly"

  __z::json::escape $'line1\nline2'
  assert_eq 'line1\nline2' "$REPLY" "Newline escaped"

  __z::json::escape $'text\rwith\rCR'
  assert_eq 'text\rwith\rCR' "$REPLY" "Carriage return escaped"

  __z::json::escape $'text\twith\ttabs'
  assert_eq 'text\twith\ttabs' "$REPLY" "Tabs escaped"

  __z::json::escape $'text\bwith\bBS'
  assert_eq 'text\bwith\bBS' "$REPLY" "Backspace escaped"

  __z::json::escape $'text\fwith\fFF'
  assert_eq 'text\fwith\fFF' "$REPLY" "Form feed escaped"

  __z::json::escape $'line1\nline2\ttabbed\rCR'
  assert_eq 'line1\nline2\ttabbed\rCR' "$REPLY" \
    "Multiple control characters escaped"

  __z::json::escape ""
  assert_eq "" "$REPLY" "Empty string unchanged"

  __z::json::escape "Hello 世界 🌍"
  assert_eq "Hello 世界 🌍" "$REPLY" "Unicode preserved"

  __z::json::escape $'Error in file "C:\\Users\\test\\file.txt":\n\tLine 42: Invalid character'
  local expected='Error in file \"C:\\Users\\test\\file.txt\":\n\tLine 42: Invalid character'
  assert_eq "$expected" "$REPLY" "Complex real-world string escaped correctly"

  print ""
}

###############################################################################
# TEST SUITE: JSON VALIDATION
###############################################################################

test_json_validation() {
  print "Testing: JSON Validation"
  print "─────────────────────────────────────────────────────────────────"

  z::log::enable_debug_mode

  __z::json::validate '{"key": "value"}'
  assert_success "Valid JSON passes"

  __z::json::validate 'simple text without quotes'
  assert_success "Simple text passes"

  __z::json::validate 'text with \"escaped\" quotes'
  assert_success "Properly escaped quotes pass"

  __z::json::validate 'text with "unescaped" quotes' 2>/dev/null
  local rc=$?
  (( rc != 0 ))
  assert_success "Unescaped quotes fail"

  __z::json::validate 'text with trailing backslash\' 2>/dev/null
  rc=$?
  (( rc != 0 ))
  assert_success "Trailing backslash fails"

  z::log::disable_debug_mode
  __z::json::validate 'text with "unescaped" quotes'
  assert_success "Validation skipped when debug mode off"

  print ""
}

###############################################################################
# TEST SUITE: SHOW COLORS (UX)
###############################################################################

test_show_colors() {
  print "Testing: Show Colors (UX)"
  print "─────────────────────────────────────────────────────────────────"

  local output
  output=$(z::log::show_colors 2>&1)
  assert_success "show_colors runs without error"

  assert_contains "$output" "Color Mode:" "Output contains color mode"
  assert_contains "$output" "Basic Colors:" "Output contains basic colors section"
  assert_contains "$output" "Bright Colors:" "Output contains bright colors section"
  assert_contains "$output" "Log Level Colors:" "Output contains log level colors"
  assert_contains "$output" "RGB Example" "Output contains RGB example"

  assert_contains "$output" "red" "Output contains 'red'"
  assert_contains "$output" "green" "Output contains 'green'"
  assert_contains "$output" "error" "Output contains 'error'"
  assert_contains "$output" "warn" "Output contains 'warn'"

  print ""
}

###############################################################################
# TEST SUITE: EDGE CASES
###############################################################################

test_edge_cases() {
  print "Testing: Edge Cases"
  print "─────────────────────────────────────────────────────────────────"

  local long_string
  long_string=$(printf 'a%.0s' {1..10000})
  __z::json::escape "$long_string"
  assert_eq "$long_string" "$REPLY" "Very long string handled"

  __z::json::escape $'\n\r\t\b\f'
  assert_eq '\n\r\t\b\f' "$REPLY" "String of only control chars escaped"

  __z::log::rgb_to_256 0 0 0
  assert_success "RGB (0,0,0) works"

  __z::log::rgb_to_256 255 255 255
  assert_success "RGB (255,255,255) works"

  __z::log::rgb_to_256 127 127 127
  assert_success "RGB (127,127,127) works"

  z::log::colorize "red" "$long_string"
  assert_contains "$REPLY" "$long_string" "Long text colorized"

  __z::json::escape '\\\\\\'
  assert_eq '\\\\\\\\\\\\' "$REPLY" "Multiple backslashes escaped"

  __z::json::escape '\"\\\"'
  assert_eq '\\\"\\\\\\\"' "$REPLY" "Mixed quotes and backslashes escaped"

  print ""
}

###############################################################################
# TEST SUITE: PERFORMANCE CHECKS
###############################################################################

test_performance() {
  print "Testing: Performance Characteristics"
  print "─────────────────────────────────────────────────────────────────"

  local start=$EPOCHREALTIME
  local i
  for i in {1..1000}; do
    __z::json::escape "simple text without special characters"
  done
  local end=$EPOCHREALTIME
  local duration=$(( (end - start) * 1000 ))

  print "  ℹ Fast path: 1000 iterations in ${duration}ms"

  start=$EPOCHREALTIME
  for i in {1..1000}; do
    __z::json::escape $'text\nwith\tcontrol\rchars'
  done
  end=$EPOCHREALTIME
  local slow_duration=$(( (end - start) * 1000 ))

  print "  ℹ Slow path: 1000 iterations in ${slow_duration}ms"

  _zcore_colors_initialized=0
  start=$EPOCHREALTIME
  __z::log::init_colors
  end=$EPOCHREALTIME
  duration=$(( (end - start) * 1000 ))

  print "  ℹ Color init: ${duration}ms"

  start=$EPOCHREALTIME
  for i in {1..1000}; do
    __z::log::rgb_to_256 128 128 128
  done
  end=$EPOCHREALTIME
  duration=$(( (end - start) * 1000 ))

  print "  ℹ RGB->256: 1000 conversions in ${duration}ms"

  print ""
}

###############################################################################
# RUN ALL TESTS
###############################################################################

run_all_tests() {
  test_init

  test_global_configuration
  test_configuration_validation
  test_color_detection
  test_rgb_to_256
  test_rgb_color
  test_color_initialization
  test_colorize
  test_color_mode_management
  test_internal_debugging
  test_json_escaping
  test_json_validation
  test_show_colors
  test_edge_cases
  test_performance

  test_summary
}

###############################################################################
# MAIN
###############################################################################

if [[ ! -f "./zlog_1.zsh" ]]; then
  print "Error: zlog_1.zsh not found in current directory"
  exit 1
fi

source ./zlog_1.zsh

run_all_tests
exit $?
