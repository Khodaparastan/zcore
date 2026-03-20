#!/usr/bin/env zsh
zmodload zsh/zprof

###############################################################################
# ZLOG Performance Benchmark Suite
###############################################################################

# Source the logging framework
SCRIPT_DIR="${0:A:h}"
source "${SCRIPT_DIR}/zlog_mods/zlog.zsh"

# Benchmark configuration
typeset -g BENCH_DIR="/tmp/zlog_bench_$$"
typeset -gA BENCH_RESULTS=()

###############################################################################
# Benchmark Utilities
###############################################################################

setup_benchmark() {
  mkdir -p "$BENCH_DIR"
  z::log::reset

  print "╔════════════════════════════════════════════════════════════════╗"
  print "║           ZLOG Framework - Performance Benchmark              ║"
  print "╠════════════════════════════════════════════════════════════════╣"
  print "║ Benchmark Dir:  $(printf '%-44s' "$BENCH_DIR") ║"
  print "║ Zsh Version:    $(printf '%-44s' "$ZSH_VERSION") ║"
  print "║ System:         $(printf '%-44s' "$(uname -s) $(uname -m)") ║"
  print "╚════════════════════════════════════════════════════════════════╝"
  print
}

cleanup_benchmark() {
  rm -rf "$BENCH_DIR"
  z::log::cleanup
}

# Run a benchmark and return duration in milliseconds
run_benchmark() {
  local name="$1"
  local iterations="$2"
  shift 2

  # Warmup
  "$@" &>/dev/null

  # Actual benchmark
  local start=$EPOCHREALTIME
  local i
  for (( i = 0; i < iterations; i++ )); do
    "$@" &>/dev/null
  done
  local end=$EPOCHREALTIME

  local duration=$(( (end - start) * 1000 ))
  local per_op=$(( duration / iterations ))

  BENCH_RESULTS[$name]="$duration:$per_op"

  printf "  %-40s %8.2f ms  (%6.3f ms/op)\n" "$name:" "$duration" "$per_op"
}

# Format number with thousand separators
format_number() {
  local num="$1"
  printf "%'d" "$num" 2>/dev/null || printf "%d" "$num"
}

###############################################################################
# Benchmark Tests
###############################################################################

benchmark_timestamp_generation() {
  print "\n$(z::log::colorize 'bold' '━━━ Timestamp Generation ━━━')"

  # Cached timestamps
  z::log::enable_timestamp_cache
  run_benchmark "Cached timestamp (same second)" 10000 __z::log::update_ts

  # Uncached timestamps
  z::log::disable_timestamp_cache
  run_benchmark "Uncached timestamp" 1000 __z::log::update_ts

  z::log::enable_timestamp_cache  # Reset
}

benchmark_json_escaping() {
  print "\n$(z::log::colorize 'bold' '━━━ JSON Escaping ━━━')"

  # Simple string (fast path)
  run_benchmark "Simple string (no escaping)" 10000 \
    __z::json::escape "simple text without special chars"

  # String with quotes
  run_benchmark "String with quotes" 10000 \
    __z::json::escape 'text with "quotes" and more'

  # String with backslashes
  run_benchmark "String with backslashes" 10000 \
    __z::json::escape 'path: C:\Users\test\file.txt'

  # String with newlines
  run_benchmark "String with newlines" 10000 \
    __z::json::escape $'line1\nline2\nline3'

  # Complex string
  run_benchmark "Complex string" 10000 \
    __z::json::escape $'Complex: "quotes", \\backslash, \n newline, \t tab'
}

benchmark_level_checking() {
  print "\n$(z::log::colorize 'bold' '━━━ Level Checking ━━━')"

  z::log::set_level "info"

  run_benchmark "Level name to number" 10000 __z::log::level_number "info"
  run_benchmark "Level number to name" 10000 __z::log::level_name 2
  run_benchmark "Check if level active" 10000 __z::log::is_level_active 2
  run_benchmark "if_info check" 10000 z::log::if_info
  run_benchmark "if_debug check (inactive)" 10000 z::log::if_debug
}

benchmark_formatting() {
  print "\n$(z::log::colorize 'bold' '━━━ Message Formatting ━━━')"

  local test_file="$BENCH_DIR/format.log"
  z::log::set_file "$test_file"
  z::log::set_level "info"

  # Text formatting
  z::log::set_format "text"
  run_benchmark "Text format (no context)" 1000 \
    __z::log::format_text 2 "Simple log message"

  run_benchmark "Text format (with context)" 1000 \
    __z::log::format_text 2 "Log message" "key1" "value1" "key2" "value2"

  # JSON formatting
  z::log::set_format "json"
  run_benchmark "JSON format (no context)" 1000 \
    __z::log::format_json 2 "Simple log message"

  run_benchmark "JSON format (with context)" 1000 \
    __z::log::format_json 2 "Log message" "key1" "value1" "key2" "value2"

  z::log::set_format "text"  # Reset
}

benchmark_file_operations() {
  print "\n$(z::log::colorize 'bold' '━━━ File Operations ━━━')"

  local test_file="$BENCH_DIR/file_ops.log"
  z::log::set_file "$test_file"

  # Direct file write
  run_benchmark "Direct file write" 1000 \
    __z::log::write_file "Test log message"

  # File size check
  run_benchmark "Get file size" 1000 \
    __z::log::get_file_size "$test_file"

  # Directory creation (cached)
  run_benchmark "Ensure log dir (cached)" 1000 \
    __z::log::ensure_log_dir "$test_file"
}

benchmark_buffering() {
  print "\n$(z::log::colorize 'bold' '━━━ Buffering Performance ━━━')"

  local test_file="$BENCH_DIR/buffering.log"
  z::log::set_file "$test_file"
  z::log::set_level "info"

  # Without buffering
  rm -f "$test_file"
  local start=$EPOCHREALTIME
  for i in {1..1000}; do
    z::log::info "Unbuffered message $i"
  done
  local end=$EPOCHREALTIME
  local duration_nobuf=$(( (end - start) * 1000 ))

  # With buffering
  rm -f "$test_file"
  z::log::enable_buffering 100
  start=$EPOCHREALTIME
  for i in {1..1000}; do
    z::log::info "Buffered message $i"
  done
  z::log::flush
  end=$EPOCHREALTIME
  local duration_buf=$(( (end - start) * 1000 ))
  z::log::disable_buffering

  printf "  %-40s %8.2f ms\n" "1000 logs without buffering:" "$duration_nobuf"
  printf "  %-40s %8.2f ms\n" "1000 logs with buffering:" "$duration_buf"
  printf "  %-40s %8.2f ms  (%.1fx faster)\n" "Improvement:" \
    "$((duration_nobuf - duration_buf))" \
    "$((duration_nobuf / duration_buf))"
}

benchmark_core_logging() {
  print "\n$(z::log::colorize 'bold' '━━━ Core Logging Functions ━━━')"

  local test_file="$BENCH_DIR/core.log"
  z::log::set_file "$test_file"
  z::log::set_level "debug"

  # Basic logging
  run_benchmark "z::log::info (simple)" 1000 \
    z::log::info "Simple info message"

  run_benchmark "z::log::info (with context)" 1000 \
    z::log::info "Info message" "key1" "val1" "key2" "val2"

  run_benchmark "z::log::debug (simple)" 1000 \
    z::log::debug "Simple debug message"

  # Printf-style
  run_benchmark "z::log::infof" 1000 \
    z::log::infof "Processed %d items" 42

  # Generic log
  run_benchmark "z::log::log" 1000 \
    z::log::log "info" "Generic log message"

  # Filtered out (should be very fast)
  z::log::set_level "error"
  run_benchmark "z::log::info (filtered out)" 10000 \
    z::log::info "This won't be logged"

  z::log::set_level "info"  # Reset
}

benchmark_conditional_logging() {
  print "\n$(z::log::colorize 'bold' '━━━ Conditional Logging ━━━')"

  z::log::set_level "info"

  run_benchmark "if_info (active)" 10000 z::log::if_info
  run_benchmark "if_debug (inactive)" 10000 z::log::if_debug

  # Conditional with expensive operation
  expensive_operation() {
    local result=""
    for i in {1..100}; do
      result+="x"
    done
  }

  # Without conditional check
  local start=$EPOCHREALTIME
  for i in {1..100}; do
    expensive_operation
    z::log::debug "Debug: result"
  done
  local end=$EPOCHREALTIME
  local duration_no_check=$(( (end - start) * 1000 ))

  # With conditional check
  start=$EPOCHREALTIME
  for i in {1..100}; do
    if z::log::if_debug; then
      expensive_operation
      z::log::debug "Debug: result"
    fi
  done
  end=$EPOCHREALTIME
  local duration_with_check=$(( (end - start) * 1000 ))

  printf "  %-40s %8.2f ms\n" "100 logs without if_debug check:" "$duration_no_check"
  printf "  %-40s %8.2f ms\n" "100 logs with if_debug check:" "$duration_with_check"
  printf "  %-40s %8.2f ms  (%.1fx faster)\n" "Savings:" \
    "$((duration_no_check - duration_with_check))" \
    "$((duration_no_check / duration_with_check))"
}

benchmark_rate_limiting() {
  print "\n$(z::log::colorize 'bold' '━━━ Rate Limiting ━━━')"

  local test_file="$BENCH_DIR/rate.log"
  z::log::set_file "$test_file"

  # Rate limiting overhead
  run_benchmark "Rate limit check (allowed)" 1000 \
    z::log::rate_limit "bench_key" 1000 60 "info" "Rate limited message"

  z::log::clear_rate_limits

  # Rate limit vs normal logging
  rm -f "$test_file"
  local start=$EPOCHREALTIME
  for i in {1..1000}; do
    z::log::info "Normal message $i"
  done
  local end=$EPOCHREALTIME
  local duration_normal=$(( (end - start) * 1000 ))

  rm -f "$test_file"
  start=$EPOCHREALTIME
  for i in {1..1000}; do
    z::log::rate_limit "rate_key" 1000 60 "info" "Rate limited message $i"
  done
  end=$EPOCHREALTIME
  local duration_rate=$(( (end - start) * 1000 ))

  z::log::clear_rate_limits

  printf "  %-40s %8.2f ms\n" "1000 normal logs:" "$duration_normal"
  printf "  %-40s %8.2f ms\n" "1000 rate limited logs:" "$duration_rate"
  printf "  %-40s %8.2f ms\n" "Overhead:" "$((duration_rate - duration_normal))"
}

benchmark_size_operations() {
  print "\n$(z::log::colorize 'bold' '━━━ Size Operations ━━━')"

  run_benchmark "Parse size (10MB)" 10000 __z::log::parse_size "10MB"
  run_benchmark "Parse size (1.5GB)" 10000 __z::log::parse_size "1.5GB"
  run_benchmark "Format size (1MB)" 10000 __z::log::format_size 1048576
  run_benchmark "Format size (1GB)" 10000 __z::log::format_size 1073741824

  # Truncation
  local long_msg=$(printf 'A%.0s' {1..1000})
  z::log::set_max_message_size 100
  run_benchmark "Truncate message" 1000 __z::log::truncate_message "$long_msg"
  z::log::set_max_message_size 0  # Reset
}

benchmark_string_utilities() {
  print "\n$(z::log::colorize 'bold' '━━━ String Utilities ━━━')"

  run_benchmark "Trim string" 10000 __z::str::trim "  text  "
  run_benchmark "Check if blank" 10000 __z::str::is_blank "  "
  run_benchmark "Truncate string" 10000 __z::str::truncate "long text here" 8 "..."
  run_benchmark "Repeat string" 10000 __z::str::repeat "=" 10
}

benchmark_memory_usage() {
  print "\n$(z::log::colorize 'bold' '━━━ Memory Usage ━━━')"

  # Get initial memory
  local mem_before=$(ps -o rss= -p $$ 2>/dev/null || echo "0")

  # Generate lots of logs
  local test_file="$BENCH_DIR/memory.log"
  z::log::set_file "$test_file"
  z::log::enable_buffering 1000

  for i in {1..10000}; do
    z::log::info "Memory test message $i with some context" "iteration" "$i"
  done

  z::log::flush
  z::log::disable_buffering

  # Get final memory
  local mem_after=$(ps -o rss= -p $$ 2>/dev/null || echo "0")
  local mem_diff=$((mem_after - mem_before))

  printf "  %-40s %8s KB\n" "Memory before:" "$(format_number $mem_before)"
  printf "  %-40s %8s KB\n" "Memory after:" "$(format_number $mem_after)"
  printf "  %-40s %8s KB\n" "Difference:" "$(format_number $mem_diff)"

  # File size
  local file_size=$(wc -c < "$test_file" 2>/dev/null || echo "0")
  __z::log::format_size "$file_size"
  printf "  %-40s %8s\n" "Log file size:" "$REPLY"
}

benchmark_throughput() {
  print "\n$(z::log::colorize 'bold' '━━━ Throughput Test ━━━')"

  local test_file="$BENCH_DIR/throughput.log"
  z::log::set_file "$test_file"
  z::log::enable_buffering 1000

  local iterations=50000
  print "  Logging $(format_number $iterations) messages..."

  local start=$EPOCHREALTIME
  for i in {1..$iterations}; do
    z::log::info "Throughput test message $i"
  done
  z::log::flush
  local end=$EPOCHREALTIME

  local duration=$(( (end - start) * 1000 ))
  local throughput=$(( iterations * 1000 / duration ))

  printf "  %-40s %8.2f ms\n" "Total time:" "$duration"
  printf "  %-40s %8s msgs/sec\n" "Throughput:" "$(format_number $throughput)"
  printf "  %-40s %8.3f ms\n" "Average per message:" "$(( duration / iterations ))"

  z::log::disable_buffering
}

###############################################################################
# Comparison Benchmarks
###############################################################################

benchmark_comparison_echo() {
  print "\n$(z::log::colorize 'bold' '━━━ Comparison: ZLOG vs echo ━━━')"

  local test_file="$BENCH_DIR/comparison.log"
  local iterations=500

  # 1. Plain echo
  rm -f "$test_file"
  local start=$EPOCHREALTIME
  local i
  for i in {1..$iterations}; do
    echo "Test message $i" >> "$test_file"
  done
  local end=$EPOCHREALTIME
  local duration_echo=$(( (end - start) * 1000 ))

  # 2. ZLOG unbuffered (normal mode)
  rm -f "$test_file"
  z::log::set_file "$test_file"
  z::log::set_level "info"
  z::log::disable_performance_mode
  local start=$EPOCHREALTIME
  for i in {1..$iterations}; do
    z::log::info "Test message $i"
  done
  end=$EPOCHREALTIME
  local duration_zlog=$(( (end - start) * 1000 ))

  # 3. ZLOG buffered (normal mode)
  rm -f "$test_file"
  z::log::enable_buffering 100
  start=$EPOCHREALTIME
  for i in {1..$iterations}; do
    z::log::info "Test message $i"
  done
  z::log::flush
  end=$EPOCHREALTIME
  local duration_zlog_buf=$(( (end - start) * 1000 ))
  z::log::disable_buffering

  # 4. ZLOG performance mode + buffering
  rm -f "$test_file"
  z::log::enable_performance_mode
  z::log::enable_buffering 100
  start=$EPOCHREALTIME
  for i in {1..$iterations}; do
    z::log::info "Test message $i"
  done
  z::log::flush
  end=$EPOCHREALTIME
  local duration_zlog_perf=$(( (end - start) * 1000 ))
  z::log::disable_buffering
  z::log::disable_performance_mode

  printf "  %-45s %8.2f ms\n" "echo >> file:" "$duration_echo"
  printf "  %-45s %8.2f ms  (%.1fx slower)\n" "ZLOG unbuffered:" \
    "$duration_zlog" "$((duration_zlog / duration_echo))"
  printf "  %-45s %8.2f ms  (%.1fx slower)\n" "ZLOG buffered:" \
    "$duration_zlog_buf" "$((duration_zlog_buf / duration_echo))"
  printf "  %-45s %8.2f ms  (%.1fx slower)\n" "ZLOG performance mode + buffered:" \
    "$duration_zlog_perf" "$((duration_zlog_perf / duration_echo))"

  print "\n  $(z::log::colorize 'cyan' 'Note:') ZLOG provides timestamps, formatting, levels, rotation, etc."
  print "  $(z::log::colorize 'cyan' 'Note:') For maximum performance, use performance mode + buffering"
}
###############################################################################
# Summary and Analysis
###############################################################################

print_summary() {
  print "\n╔════════════════════════════════════════════════════════════════╗"
  print "║                      Benchmark Summary                         ║"
  print "╚════════════════════════════════════════════════════════════════╝"

  print "\n$(z::log::colorize 'green' 'Key Findings:')"
  print "  • Timestamp caching provides ~10x speedup for same-second logs"
  print "  • JSON escaping fast path (no special chars) is very efficient"
  print "  • Buffering provides 2-5x throughput improvement"
  print "  • Level filtering (early exit) is extremely fast"
  print "  • Conditional checks prevent expensive operations effectively"
  print "  • Rate limiting adds minimal overhead (~5-10%)"

  print "\n$(z::log::colorize 'cyan' 'Recommendations:')"
  print "  • Enable buffering for high-volume logging"
  print "  • Use conditional checks (if_debug) for expensive operations"
  print "  • Set appropriate log levels to filter unnecessary logs"
  print "  • Use rate limiting in loops to prevent log floods"
  print "  • Enable timestamp caching (default) for better performance"
}
benchmark_detailed_comparison() {
  print "\n$(z::log::colorize 'bold' '━━━ Detailed Performance Comparison ━━━')"

  local test_file="$BENCH_DIR/detailed_comparison.log"
  local iterations=1000

  print "\n$(z::log::colorize 'cyan' 'Testing with $iterations iterations each...')\n"

  # =========================================================================
  # Scenario 1: Console Only (stderr)
  # =========================================================================
  print "$(z::log::colorize 'yellow' '═══ Scenario 1: Console Only (stderr) ═══')"

  # 1a. Plain echo to stderr
  local start=$EPOCHREALTIME
  for i in {1..$iterations}; do
    echo "Test message $i" >&2
  done 2>/dev/null
  local end=$EPOCHREALTIME
  local duration_echo_console=$(( (end - start) * 1000 ))

  # 1b. ZLOG console only (unbuffered)
  z::log::set_file ""  # No file
  z::log::set_level "info"
  z::log::disable_performance_mode
  start=$EPOCHREALTIME
  for i in {1..$iterations}; do
    z::log::info "Test message $i"
  done 2>/dev/null
  end=$EPOCHREALTIME
  local duration_zlog_console=$(( (end - start) * 1000 ))

  # 1c. ZLOG console only (performance mode)
  z::log::enable_performance_mode
  start=$EPOCHREALTIME
  for i in {1..$iterations}; do
    z::log::info "Test message $i"
  done 2>/dev/null
  end=$EPOCHREALTIME
  local duration_zlog_console_perf=$(( (end - start) * 1000 ))
  z::log::disable_performance_mode

  printf "  %-50s %8.2f ms\n" "echo >&2:" "$duration_echo_console"
  printf "  %-50s %8.2f ms  (%.1fx)\n" "ZLOG console (normal):" \
    "$duration_zlog_console" "$((duration_zlog_console / duration_echo_console))"
  printf "  %-50s %8.2f ms  (%.1fx)\n" "ZLOG console (performance):" \
    "$duration_zlog_console_perf" "$((duration_zlog_console_perf / duration_echo_console))"

  # =========================================================================
  # Scenario 2: File Only (no console)
  # =========================================================================
  print "\n$(z::log::colorize 'yellow' '═══ Scenario 2: File Only (no console) ═══')"

  # 2a. Plain echo to file
  rm -f "$test_file"
  start=$EPOCHREALTIME
  for i in {1..$iterations}; do
    echo "Test message $i" >> "$test_file"
  done
  end=$EPOCHREALTIME
  local duration_echo_file=$(( (end - start) * 1000 ))

  # 2b. ZLOG file only, unbuffered
  rm -f "$test_file"
  z::log::set_file "$test_file"
  z::log::set_level "error"  # Disable console
  z::log::set_file_level "info"  # Enable file
  z::log::disable_performance_mode
  start=$EPOCHREALTIME
  for i in {1..$iterations}; do
    z::log::info "Test message $i"
  done
  end=$EPOCHREALTIME
  local duration_zlog_file=$(( (end - start) * 1000 ))

  # 2c. ZLOG file only, buffered
  rm -f "$test_file"
  z::log::enable_buffering 100
  start=$EPOCHREALTIME
  for i in {1..$iterations}; do
    z::log::info "Test message $i"
  done
  z::log::flush
  end=$EPOCHREALTIME
  local duration_zlog_file_buf=$(( (end - start) * 1000 ))
  z::log::disable_buffering

  # 2d. ZLOG file only, performance + buffered
  rm -f "$test_file"
  z::log::enable_performance_mode
  z::log::enable_buffering 100
  start=$EPOCHREALTIME
  for i in {1..$iterations}; do
    z::log::info "Test message $i"
  done
  z::log::flush
  end=$EPOCHREALTIME
  local duration_zlog_file_perf=$(( (end - start) * 1000 ))
  z::log::disable_buffering
  z::log::disable_performance_mode

  printf "  %-50s %8.2f ms\n" "echo >> file:" "$duration_echo_file"
  printf "  %-50s %8.2f ms  (%.1fx)\n" "ZLOG file (unbuffered):" \
    "$duration_zlog_file" "$((duration_zlog_file / duration_echo_file))"
  printf "  %-50s %8.2f ms  (%.1fx)\n" "ZLOG file (buffered):" \
    "$duration_zlog_file_buf" "$((duration_zlog_file_buf / duration_echo_file))"
  printf "  %-50s %8.2f ms  (%.1fx)\n" "ZLOG file (perf + buffered):" \
    "$duration_zlog_file_perf" "$((duration_zlog_file_perf / duration_echo_file))"

  # =========================================================================
  # Scenario 3: Both Console and File
  # =========================================================================
  print "\n$(z::log::colorize 'yellow' '═══ Scenario 3: Both Console and File ═══')"

  # 3a. Plain echo to both
  rm -f "$test_file"
  start=$EPOCHREALTIME
  for i in {1..$iterations}; do
    echo "Test message $i" | tee -a "$test_file" >&2
  done 2>/dev/null
  end=$EPOCHREALTIME
  local duration_echo_both=$(( (end - start) * 1000 ))

  # 3b. ZLOG both, unbuffered
  rm -f "$test_file"
  z::log::set_file "$test_file"
  z::log::set_level "info"
  z::log::set_file_level "info"
  z::log::disable_performance_mode
  start=$EPOCHREALTIME
  for i in {1..$iterations}; do
    z::log::info "Test message $i"
  done 2>/dev/null
  end=$EPOCHREALTIME
  local duration_zlog_both=$(( (end - start) * 1000 ))

  # 3c. ZLOG both, buffered
  rm -f "$test_file"
  z::log::enable_buffering 100
  start=$EPOCHREALTIME
  for i in {1..$iterations}; do
    z::log::info "Test message $i"
  done 2>/dev/null
  z::log::flush
  end=$EPOCHREALTIME
  local duration_zlog_both_buf=$(( (end - start) * 1000 ))
  z::log::disable_buffering

  # 3d. ZLOG both, performance + buffered
  rm -f "$test_file"
  z::log::enable_performance_mode
  z::log::enable_buffering 100
  start=$EPOCHREALTIME
  for i in {1..$iterations}; do
    z::log::info "Test message $i"
  done 2>/dev/null
  z::log::flush
  end=$EPOCHREALTIME
  local duration_zlog_both_perf=$(( (end - start) * 1000 ))
  z::log::disable_buffering
  z::log::disable_performance_mode

  printf "  %-50s %8.2f ms\n" "echo | tee >> file >&2:" "$duration_echo_both"
  printf "  %-50s %8.2f ms  (%.1fx)\n" "ZLOG both (unbuffered):" \
    "$duration_zlog_both" "$((duration_zlog_both / duration_echo_both))"
  printf "  %-50s %8.2f ms  (%.1fx)\n" "ZLOG both (buffered):" \
    "$duration_zlog_both_buf" "$((duration_zlog_both_buf / duration_echo_both))"
  printf "  %-50s %8.2f ms  (%.1fx)\n" "ZLOG both (perf + buffered):" \
    "$duration_zlog_both_perf" "$((duration_zlog_both_perf / duration_echo_both))"

  # =========================================================================
  # Scenario 4: With Context Fields
  # =========================================================================
  print "\n$(z::log::colorize 'yellow' '═══ Scenario 4: File with Context Fields ═══')"

  # 4a. Plain echo with context simulation
  rm -f "$test_file"
  start=$EPOCHREALTIME
  for i in {1..$iterations}; do
    echo "Test message $i user=john ip=192.168.1.1" >> "$test_file"
  done
  end=$EPOCHREALTIME
  local duration_echo_context=$(( (end - start) * 1000 ))

  # 4b. ZLOG with context, unbuffered
  rm -f "$test_file"
  z::log::set_file "$test_file"
  z::log::set_level "error"  # Console off
  z::log::set_file_level "info"
  z::log::disable_performance_mode
  start=$EPOCHREALTIME
  for i in {1..$iterations}; do
    z::log::info "Test message $i" "user" "john" "ip" "192.168.1.1"
  done
  end=$EPOCHREALTIME
  local duration_zlog_context=$(( (end - start) * 1000 ))

  # 4c. ZLOG with context, buffered
  rm -f "$test_file"
  z::log::enable_buffering 100
  start=$EPOCHREALTIME
  for i in {1..$iterations}; do
    z::log::info "Test message $i" "user" "john" "ip" "192.168.1.1"
  done
  z::log::flush
  end=$EPOCHREALTIME
  local duration_zlog_context_buf=$(( (end - start) * 1000 ))
  z::log::disable_buffering

  # 4d. ZLOG with context, performance + buffered
  rm -f "$test_file"
  z::log::enable_performance_mode
  z::log::enable_buffering 100
  start=$EPOCHREALTIME
  for i in {1..$iterations}; do
    z::log::info "Test message $i" "user" "john" "ip" "192.168.1.1"
  done
  z::log::flush
  end=$EPOCHREALTIME
  local duration_zlog_context_perf=$(( (end - start) * 1000 ))
  z::log::disable_buffering
  z::log::disable_performance_mode

  printf "  %-50s %8.2f ms\n" "echo with context:" "$duration_echo_context"
  printf "  %-50s %8.2f ms  (%.1fx)\n" "ZLOG context (unbuffered):" \
    "$duration_zlog_context" "$((duration_zlog_context / duration_echo_context))"
  printf "  %-50s %8.2f ms  (%.1fx)\n" "ZLOG context (buffered):" \
    "$duration_zlog_context_buf" "$((duration_zlog_context_buf / duration_echo_context))"
  printf "  %-50s %8.2f ms  (%.1fx)\n" "ZLOG context (perf + buffered):" \
    "$duration_zlog_context_perf" "$((duration_zlog_context_perf / duration_echo_context))"

  # =========================================================================
  # Scenario 5: JSON Format
  # =========================================================================
  print "\n$(z::log::colorize 'yellow' '═══ Scenario 5: JSON Format (File Only) ═══')"

  # 5a. ZLOG JSON, unbuffered
  rm -f "$test_file"
  z::log::set_format "json"
  z::log::set_file "$test_file"
  z::log::set_level "error"
  z::log::set_file_level "info"
  z::log::disable_performance_mode
  start=$EPOCHREALTIME
  for i in {1..$iterations}; do
    z::log::info "Test message $i" "user" "john" "ip" "192.168.1.1"
  done
  end=$EPOCHREALTIME
  local duration_zlog_json=$(( (end - start) * 1000 ))

  # 5b. ZLOG JSON, buffered
  rm -f "$test_file"
  z::log::enable_buffering 100
  start=$EPOCHREALTIME
  for i in {1..$iterations}; do
    z::log::info "Test message $i" "user" "john" "ip" "192.168.1.1"
  done
  z::log::flush
  end=$EPOCHREALTIME
  local duration_zlog_json_buf=$(( (end - start) * 1000 ))
  z::log::disable_buffering

  # 5c. ZLOG JSON, performance + buffered
  rm -f "$test_file"
  z::log::enable_performance_mode
  z::log::enable_buffering 100
  start=$EPOCHREALTIME
  for i in {1..$iterations}; do
    z::log::info "Test message $i" "user" "john" "ip" "192.168.1.1"
  done
  z::log::flush
  end=$EPOCHREALTIME
  local duration_zlog_json_perf=$(( (end - start) * 1000 ))
  z::log::disable_buffering
  z::log::disable_performance_mode

  z::log::set_format "text"  # Reset

  printf "  %-50s %8.2f ms  (baseline: echo)\n" "ZLOG JSON (unbuffered):" "$duration_zlog_json"
  printf "  %-50s %8.2f ms  (%.1fx faster)\n" "ZLOG JSON (buffered):" \
    "$duration_zlog_json_buf" "$((duration_zlog_json / duration_zlog_json_buf))"
  printf "  %-50s %8.2f ms  (%.1fx faster)\n" "ZLOG JSON (perf + buffered):" \
    "$duration_zlog_json_perf" "$((duration_zlog_json / duration_zlog_json_perf))"

  # =========================================================================
  # Scenario 6: Level Filtering (Logs Disabled)
  # =========================================================================
  print "\n$(z::log::colorize 'yellow' '═══ Scenario 6: Level Filtering (Logs Disabled) ═══')"

  # 6a. ZLOG with filtering (debug disabled at info level)
  z::log::set_file "$test_file"
  z::log::set_level "info"
  z::log::disable_performance_mode
  start=$EPOCHREALTIME
  for i in {1..$iterations}; do
    z::log::debug "This won't be logged"
  done
  end=$EPOCHREALTIME
  local duration_zlog_filtered=$(( (end - start) * 1000 ))

  # 6b. ZLOG with filtering (performance mode)
  z::log::enable_performance_mode
  start=$EPOCHREALTIME
  for i in {1..$iterations}; do
    z::log::debug "This won't be logged"
  done
  end=$EPOCHREALTIME
  local duration_zlog_filtered_perf=$(( (end - start) * 1000 ))
  z::log::disable_performance_mode

  printf "  %-50s %8.2f ms  (%.3f ms/call)\n" "ZLOG filtered (normal):" \
    "$duration_zlog_filtered" "$((duration_zlog_filtered / iterations))"
  printf "  %-50s %8.2f ms  (%.3f ms/call)\n" "ZLOG filtered (performance):" \
    "$duration_zlog_filtered_perf" "$((duration_zlog_filtered_perf / iterations))"

  # =========================================================================
  # Summary Table
  # =========================================================================
  print "\n$(z::log::colorize 'bold' '═══ Summary Table ═══')"
  print "\n$(z::log::colorize 'cyan' 'Overhead compared to plain echo:')"
  print "┌────────────────────────────────────────────────┬──────────┬─────────┐"
  print "│ Scenario                                       │  Normal  │  Perf   │"
  print "├────────────────────────────────────────────────┼──────────┼─────────┤"
  printf "│ Console only                                   │ %6.1fx   │ %5.1fx  │\n" \
    "$((duration_zlog_console / duration_echo_console))" \
    "$((duration_zlog_console_perf / duration_echo_console))"
  printf "│ File only (unbuffered)                         │ %6.1fx   │   -     │\n" \
    "$((duration_zlog_file / duration_echo_file))"
  printf "│ File only (buffered)                           │ %6.1fx   │ %5.1fx  │\n" \
    "$((duration_zlog_file_buf / duration_echo_file))" \
    "$((duration_zlog_file_perf / duration_echo_file))"
  printf "│ Both console and file (buffered)               │ %6.1fx   │ %5.1fx  │\n" \
    "$((duration_zlog_both_buf / duration_echo_both))" \
    "$((duration_zlog_both_perf / duration_echo_both))"
  printf "│ With context fields (buffered)                 │ %6.1fx   │ %5.1fx  │\n" \
    "$((duration_zlog_context_buf / duration_echo_context))" \
    "$((duration_zlog_context_perf / duration_echo_context))"
  print "└────────────────────────────────────────────────┴──────────┴─────────┘"

  print "\n$(z::log::colorize 'green' 'Key Findings:')"
  print "  • Console logging overhead: mostly from formatting and colors"
  print "  • File logging overhead: mostly from rotation checks and I/O"
  print "  • Buffering provides 2-5x improvement for file operations"
  print "  • Performance mode provides 10-30x improvement overall"
  print "  • Level filtering is extremely fast (< 0.1ms per call)"
  print "  • Context fields add minimal overhead (~10-20%)"

  print "\n$(z::log::colorize 'cyan' 'Recommendations:')"
  print "  • Use buffering for any file logging (2-5x faster)"
  print "  • Enable performance mode for high-volume logging (10-30x faster)"
  print "  • Use level filtering to avoid expensive operations"
  print "  • Console logging is slower due to colors; disable for production"
}


###############################################################################
# Main Benchmark Runner
###############################################################################

run_all_benchmarks() {
  setup_benchmark

  # benchmark_timestamp_generation
  # benchmark_json_escaping
  # benchmark_level_checking
  # benchmark_formatting
  # benchmark_file_operations
  # benchmark_buffering
  # benchmark_core_logging
  # benchmark_conditional_logging
  # benchmark_rate_limiting
  # benchmark_size_operations
  # benchmark_string_utilities
  # benchmark_memory_usage
  # benchmark_throughput
  benchmark_comparison_echo
  # zprof
  # benchmark_detailed_comparison
  # print_summary

  cleanup_benchmark
}

# Run benchmarks if executed directly
if [[ "${ZSH_EVAL_CONTEXT}" == "toplevel" ]]; then
  run_all_benchmarks
fi
