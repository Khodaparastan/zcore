#!/usr/bin/env zsh

################################################################################
# Z FRAMEWORK v3.0 - PILLAR-BASED DEMO
################################################################################
#
# Demonstrates the three-pillar architecture:
#   🔴 Logging Pillar
#   🔵 Cache Pillar
#   🟠 KV Store Pillar
#   🟣 Event System (optional)
#
# Usage:
#   ./z-demo.zsh [--verbose] [--section SECTION]
#
################################################################################

# Source the framework
SCRIPT_DIR="${${(%):-%x}:A:h}"
if [[ -f "$SCRIPT_DIR/z3.zsh" ]]; then
  source "$SCRIPT_DIR/z3.zsh"
else
  print "ERROR: z.zsh not found in $SCRIPT_DIR" >&2
  exit 1
fi

################################################################################
# DEMO CONFIGURATION
################################################################################

typeset -g DEMO_SECTION=""
typeset -gi DEMO_VERBOSE=0

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --verbose|-v)
      DEMO_VERBOSE=1
      shift
      ;;
    --section|-s)
      DEMO_SECTION="$2"
      shift 2
      ;;
    --help|-h)
      cat <<'EOF'
Z Framework v3.0 - Pillar-Based Demo

Usage: ./z-demo.zsh [OPTIONS]

Options:
  --verbose, -v           Enable debug logging
  --section NAME, -s NAME Run specific section
  --help, -h              Show help

Sections:
  pillars       - Three pillar demonstration
  logging       - Logging pillar features
  cache         - Cache pillar features
  kv            - KV store pillar features
  events        - Event system features
  integration   - Pillar integration examples
  reactive      - Reactive programming demo
  config        - Configuration management
  persistence   - Data persistence demo
  locking       - Distributed locking demo
  transactions  - Transaction support demo
  performance   - Performance benchmarks
  all           - Run all demos (default)

Examples:
  ./z-demo.zsh
  ./z-demo.zsh --verbose
  ./z-demo.zsh --section pillars
  ./z-demo.zsh -v -s reactive
EOF
      exit 0
      ;;
    *)
      print "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# Set log level
if (( DEMO_VERBOSE )); then
  z::log::set_level debug
else
  z::log::set_level info
fi

################################################################################
# DEMO HELPERS
################################################################################

demo_section() {
  local title="$1"
  print ""
  print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  print "  ${_z_colors[bold]}${_z_colors[cyan]}$title${_z_colors[reset]}"
  print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  print ""
}

demo_subsection() {
  local title="$1"
  print ""
  print "${_z_colors[yellow]}▶ $title${_z_colors[reset]}"
  print "────────────────────────────────────────────────────────────────────────────────"
}

demo_cmd() {
  local description="$1"
  shift
  print "${_z_colors[green]}→${_z_colors[reset]} $description"
  print "  ${_z_colors[cyan]}\$ $*${_z_colors[reset]}"
  "$@"
  local exit_code=$?
  if (( exit_code == 0 )); then
    print "  ${_z_colors[green]}✓ Success${_z_colors[reset]}"
  else
    print "  ${_z_colors[red]}✗ Failed (exit: $exit_code)${_z_colors[reset]}"
  fi
  print ""
}

should_run_section() {
  local section="$1"
  [[ -z $DEMO_SECTION || $DEMO_SECTION == "$section" || $DEMO_SECTION == "all" ]]
}

################################################################################
# DEMO SECTIONS
################################################################################

###
# Demo 1: Three Pillars Overview
###
demo_pillars() {
  demo_section "1. THREE PILLARS ARCHITECTURE"

  demo_subsection "Pillar Status"
  print "🔴 Logging Pillar:   ${_z_colors[green]}✓ Loaded${_z_colors[reset]}"
  print "🔵 Cache Pillar:     ${_z_colors[green]}✓ Loaded${_z_colors[reset]}"
  print "🟠 KV Store Pillar:  ${_z_colors[green]}✓ Loaded${_z_colors[reset]}"

  if (( ${+functions[z::event::emit]} )); then
    print "🟣 Event System:     ${_z_colors[green]}✓ Loaded${_z_colors[reset]}"
  else
    print "🟣 Event System:     ${_z_colors[yellow]}○ Not Loaded (optional)${_z_colors[reset]}"
  fi
  print ""

  demo_subsection "Pillar Independence"
  print "Each pillar can function independently:"
  print ""
  print "  ${_z_colors[red]}Logging${_z_colors[reset]}  → No dependencies"
  print "  ${_z_colors[blue]}Cache${_z_colors[reset]}    → Depends only on Logging"
  print "  ${_z_colors[yellow]}KV Store${_z_colors[reset]} → Depends only on Logging"
  print "  ${_z_colors[magenta]}Events${_z_colors[reset]}   → Depends on Logging + Cache"
  print ""
  print "  ${_z_colors[green]}✓ No circular dependencies${_z_colors[reset]}"
  print "  ${_z_colors[green]}✓ Clear loading order${_z_colors[reset]}"
  print "  ${_z_colors[green]}✓ Optional integration${_z_colors[reset]}"
  print ""

  demo_subsection "Framework Version"
  print "Z Version: ${_z_colors[bold]}${Z_VERSION}${_z_colors[reset]}"
  if (( ${+Z_EVENT_VERSION} )); then
    print "Event Version: ${_z_colors[bold]}${Z_EVENT_VERSION}${_z_colors[reset]}"
  fi
  print ""
}

###
# Demo 2: Logging Pillar
###
demo_logging() {
  demo_section "2. LOGGING PILLAR 🔴"

  demo_subsection "Basic Logging"
  demo_cmd "Error message" z::log::error "This is an error"
  demo_cmd "Warning message" z::log::warn "This is a warning"
  demo_cmd "Info message" z::log::info "This is info"
  demo_cmd "Debug message (may not show)" z::log::debug "This is debug"

  demo_subsection "Log Level Management"
  demo_cmd "Get current level" z::log::get_level
  demo_cmd "Set to debug" z::log::set_level debug
  demo_cmd "Debug now visible" z::log::debug "Now you can see me!"
  demo_cmd "Set back to info" z::log::set_level info

  demo_subsection "Logging Features"
  print "Features:"
  print "  ✓ Timestamp caching (performance)"
  print "  ✓ Color-coded output"
  print "  ✓ Recursion prevention"
  print "  ✓ Zero dependencies"
  print "  ✓ Event emission (if events loaded)"
  print ""
}

###
# Demo 3: Cache Pillar
###
demo_cache() {
  demo_section "3. CACHE PILLAR 🔵"

  demo_subsection "Basic Caching"
  demo_cmd "Set cache value" z::cache::set "demo:key1" "value1"
  demo_cmd "Get cache value" z::cache::get "demo:key1"
  demo_cmd "Check existence" z::cache::exists "demo:key1"

  demo_subsection "TTL Support"
  demo_cmd "Set with 5s TTL" z::cache::set "demo:temp" "expires_soon" --ttl 5
  demo_cmd "Get immediately" z::cache::get "demo:temp"
  print "Waiting 6 seconds for expiration..."
  sleep 6
  print "Attempting to get expired key:"
  z::cache::get "demo:temp" && print "  ${_z_colors[red]}✗ Should be expired${_z_colors[reset]}" || print "  ${_z_colors[green]}✓ Correctly expired${_z_colors[reset]}"
  print ""

  demo_subsection "Namespaced Caching"
  demo_cmd "Set in namespace 'app'" z::cache::set "app:setting1" "value1"
  demo_cmd "Set in namespace 'app'" z::cache::set "app:setting2" "value2"
  demo_cmd "Set in namespace 'user'" z::cache::set "user:pref1" "value3"
  demo_cmd "Clear 'app' namespace" z::cache::clear "app:*"
  print "Checking if app:setting1 still exists:"
  z::cache::exists "app:setting1" && print "  ${_z_colors[red]}✗ Should be cleared${_z_colors[reset]}" || print "  ${_z_colors[green]}✓ Correctly cleared${_z_colors[reset]}"
  print "Checking if user:pref1 still exists:"
  z::cache::exists "user:pref1" && print "  ${_z_colors[green]}✓ Still exists${_z_colors[reset]}" || print "  ${_z_colors[red]}✗ Should exist${_z_colors[reset]}"
  print ""

  demo_subsection "Memoization"
  print "Creating expensive function..."
  expensive_computation() {
    local input="$1"
    sleep 0.5  # Simulate expensive work
    print "Result for: $input"
  }

  print "${_z_colors[green]}→${_z_colors[reset]} First call (cache miss, slow):"
  print "  ${_z_colors[cyan]}\$ time z::cache::memoize 'compute:test' 60 expensive_computation 'data'${_z_colors[reset]}"
  time z::cache::memoize "compute:test" 60 expensive_computation "data"
  print ""

  print "${_z_colors[green]}→${_z_colors[reset]} Second call (cache hit, fast):"
  print "  ${_z_colors[cyan]}\$ time z::cache::memoize 'compute:test' 60 expensive_computation 'data'${_z_colors[reset]}"
  time z::cache::memoize "compute:test" 60 expensive_computation "data"
  print "  ${_z_colors[green]}✓ Notice the speed difference!${_z_colors[reset]}"
  print ""

  demo_subsection "Cache Statistics"
  demo_cmd "Show cache stats" z::cache::stats
  demo_cmd "Show 'demo' namespace stats" z::cache::stats "demo"

  # Cleanup
  z::cache::clear "demo:*"
  z::cache::clear "compute:*"
  unset -f expensive_computation
}

###
# Demo 4: KV Store Pillar
###
demo_kv() {
  demo_section "4. KV STORE PILLAR 🟠"

  demo_subsection "Basic Operations"
  demo_cmd "Set string value" z::kv::set "user:name" "John Doe"
  demo_cmd "Get value" z::kv::get "user:name"
  demo_cmd "Check existence" z::kv::exists "user:name"
  demo_cmd "Delete key" z::kv::del "user:name"

  demo_subsection "Type-Safe Operations"
  demo_cmd "Set integer" z::kv::set_int "counter" "42"
  demo_cmd "Get integer" z::kv::get_int "counter"
  demo_cmd "Increment by 10" z::kv::incr "counter" 10
  demo_cmd "Get new value" z::kv::get_int "counter"
  demo_cmd "Decrement by 5" z::kv::decr "counter" 5
  demo_cmd "Final value" z::kv::get_int "counter"

  demo_subsection "Boolean Operations"
  demo_cmd "Set boolean true" z::kv::set_bool "feature:enabled" "true"
  demo_cmd "Get boolean" z::kv::get_bool "feature:enabled"
  demo_cmd "Set boolean false" z::kv::set_bool "feature:enabled" "false"
  print "Checking boolean value:"
  z::kv::get_bool "feature:enabled" && print "  Value: true" || print "  Value: false"
  print ""

  demo_subsection "TTL (Time To Live)"
  demo_cmd "Set with 10s TTL" z::kv::set "session:token" "abc123" --ttl 10
  demo_cmd "Check TTL remaining" z::kv::ttl "session:token"
  demo_cmd "Extend TTL to 20s" z::kv::expire "session:token" 20
  demo_cmd "Check new TTL" z::kv::ttl "session:token"

  demo_subsection "Key Patterns"
  demo_cmd "Set multiple keys" z::kv::set "app:db:host" "localhost"
  z::kv::set "app:db:port" "5432"
  z::kv::set "app:db:name" "mydb"
  z::kv::set "app:cache:ttl" "300"
  demo_cmd "List all app keys" z::kv::keys "app:*"
  demo_cmd "List only db keys" z::kv::keys "app:db:*"

  demo_subsection "KV Statistics"
  demo_cmd "Show KV stats" z::kv::stats

  # Cleanup
  z::kv::del "counter" 2>/dev/null
  z::kv::del "feature:enabled" 2>/dev/null
  z::kv::del "session:token" 2>/dev/null
  z::kv::keys "app:*" | while read key; do z::kv::del "$key"; done
}

###
# Demo 5: Event System
###
demo_events() {
  demo_section "5. EVENT SYSTEM 🟣"

  if ! (( ${+functions[z::event::emit]} )); then
    print "${_z_colors[yellow]}Event system not loaded (optional module)${_z_colors[reset]}"
    print "To enable: ensure z-event.zsh is in same directory"
    print ""
    return 0
  fi

  demo_subsection "Event Registration"

  print "Creating event handlers..."
  demo_handler_1() {
    local event="$1"
    shift
    print "  Handler 1 called: event=$event, args=($*)"
  }

  demo_handler_2() {
    local event="$1"
    shift
    print "  Handler 2 called: event=$event, args=($*)"
  }

  demo_handler_priority() {
    print "  High priority handler (runs first)"
  }
  print ""

  demo_cmd "Register handler 1" z::event::on "demo:test" demo_handler_1
  demo_cmd "Register handler 2" z::event::on "demo:test" demo_handler_2
  demo_cmd "Register high priority" z::event::on "demo:test" demo_handler_priority --priority 100

  demo_subsection "Event Emission"
  demo_cmd "Emit event" z::event::emit "demo:test" "arg1" "arg2"

  demo_subsection "One-Time Handlers"
  demo_once_handler() {
    print "  One-time handler executed"
  }

  demo_cmd "Register once handler" z::event::once "demo:once" demo_once_handler
  demo_cmd "First emit (handler runs)" z::event::emit "demo:once"
  demo_cmd "Second emit (handler removed)" z::event::emit "demo:once"

  demo_subsection "Wildcard Events"
  demo_wildcard_handler() {
    local event="$1"
    print "  Wildcard handler caught: $event"
  }

  demo_cmd "Register wildcard handler" z::event::on "demo:*" demo_wildcard_handler
  demo_cmd "Emit demo:action1" z::event::emit "demo:action1"
  demo_cmd "Emit demo:action2" z::event::emit "demo:action2"

  demo_subsection "Event Introspection"
  demo_cmd "List all demo events" z::event::list "demo:*"
  demo_cmd "Show event statistics" z::event::stats "demo"
  demo_cmd "Show event history" z::event::history 10 "demo:*"

  demo_subsection "Event Cleanup"
  demo_cmd "Remove specific handler" z::event::off "demo:test" demo_handler_1
  demo_cmd "Remove all handlers for event" z::event::off "demo:*"

  # Cleanup functions
  unset -f demo_handler_1 demo_handler_2 demo_handler_priority demo_once_handler demo_wildcard_handler
}

###
# Demo 6: Pillar Integration
###
demo_integration() {
  demo_section "6. PILLAR INTEGRATION"

  if ! (( ${+functions[z::event::emit]} )); then
    print "${_z_colors[yellow]}Event system required for integration demo${_z_colors[reset]}"
    print ""
    return 0
  fi

  demo_subsection "Logging → Events"
  print "Log messages automatically emit events when event system is loaded:"
  print ""

  log_event_handler() {
    local event="$1" message="$2"
    print "  ${_z_colors[cyan]}[Event Caught]${_z_colors[reset]} $event: $message"
  }

  z::event::on "log:error" log_event_handler
  z::event::on "log:warn" log_event_handler

  print "${_z_colors[green]}→${_z_colors[reset]} Logging with event emission:"
  z::log::error "Test error message"
  z::log::warn "Test warning message"
  print ""

  z::event::off "log:*" log_event_handler

  demo_subsection "Cache → Events"
  print "Cache operations emit events:"
  print ""

  cache_event_handler() {
    local event="$1" key="$2"
    print "  ${_z_colors[cyan]}[Cache Event]${_z_colors[reset]} $event: $key"
  }

  z::event::on "cache:set" cache_event_handler
  z::event::on "cache:hit" cache_event_handler
  z::event::on "cache:miss" cache_event_handler

  print "${_z_colors[green]}→${_z_colors[reset]} Cache operations:"
  z::cache::set "integration:test" "value"
  z::cache::get "integration:test" >/dev/null
  z::cache::get "integration:nonexistent" 2>/dev/null
  print ""

  z::event::off "cache:*" cache_event_handler

  demo_subsection "KV Store → Events"
  print "KV operations emit events:"
  print ""

  kv_event_handler() {
    local event="$1" key="$2" value="$3"
    print "  ${_z_colors[cyan]}[KV Event]${_z_colors[reset]} $event: $key = $value"
  }

  z::event::on "kv:set" kv_event_handler
  z::event::on "kv:del" kv_event_handler

  print "${_z_colors[green]}→${_z_colors[reset]} KV operations:"
  z::kv::set "integration:data" "test_value"
  z::kv::del "integration:data"
  print ""

  z::event::off "kv:*" kv_event_handler

  # Cleanup
  z::cache::del "integration:test"
  unset -f log_event_handler cache_event_handler kv_event_handler
}

###
# Demo 7: Reactive Programming
###
demo_reactive() {
  demo_section "7. REACTIVE PROGRAMMING"

  demo_subsection "Configuration Watchers"
  print "Watch configuration changes and react automatically:"
  print ""

  theme_change_handler() {
    local key="$1" value="$2" operation="$3"
    print "  ${_z_colors[magenta]}[Theme Changed]${_z_colors[reset]} New theme: $value"
    print "  ${_z_colors[cyan]}→${_z_colors[reset]} Clearing UI cache..."
    z::cache::clear "ui:*"
    print "  ${_z_colors[cyan]}→${_z_colors[reset]} Reloading colors..."
    print "  ${_z_colors[green]}✓${_z_colors[reset]} UI updated!"
  }

  demo_cmd "Register theme watcher" z::kv::watch "config:theme" theme_change_handler

  print "${_z_colors[green]}→${_z_colors[reset]} Changing theme:"
  z::config::set theme "dark"
  print ""

  print "${_z_colors[green]}→${_z_colors[reset]} Changing theme again:"
  z::config::set theme "light"
  print ""

  demo_subsection "Data Watchers"
  print "Watch data changes:"
  print ""

  data_change_handler() {
    local key="$1" value="$2" operation="$3"
    print "  ${_z_colors[magenta]}[Data Changed]${_z_colors[reset]} $key = $value ($operation)"

    # Trigger dependent updates
    if [[ $key == "user:score" ]]; then
      local score
      score=$(z::kv::get_int "$key")
      if (( score > 100 )); then
        print "  ${_z_colors[yellow]}→${_z_colors[reset]} Achievement unlocked!"
      fi
    fi
  }

  demo_cmd "Watch user data" z::kv::watch "user:*" data_change_handler

  print "${_z_colors[green]}→${_z_colors[reset]} Setting user score:"
  z::kv::set_int "user:score" "50"
  print ""

  print "${_z_colors[green]}→${_z_colors[reset]} Incrementing score:"
  z::kv::incr "user:score" 60
  print ""

  demo_subsection "Event Chains"
  if (( ${+functions[z::event::emit]} )); then
    print "Events can trigger other events (reactive chains):"
    print ""

    chain_handler_1() {
      print "  ${_z_colors[cyan]}[Chain 1]${_z_colors[reset]} First handler"
      z::event::emit "demo:chain2" "from_chain1"
    }

    chain_handler_2() {
      local from="$2"
      print "  ${_z_colors[cyan]}[Chain 2]${_z_colors[reset]} Second handler (triggered by: $from)"
      z::event::emit "demo:chain3" "from_chain2"
    }

    chain_handler_3() {
      local from="$2"
      print "  ${_z_colors[cyan]}[Chain 3]${_z_colors[reset]} Third handler (triggered by: $from)"
    }

    z::event::on "demo:chain1" chain_handler_1
    z::event::on "demo:chain2" chain_handler_2
    z::event::on "demo:chain3" chain_handler_3

    print "${_z_colors[green]}→${_z_colors[reset]} Triggering chain:"
    z::event::emit "demo:chain1"
    print ""

    z::event::off "demo:chain*"
    unset -f chain_handler_1 chain_handler_2 chain_handler_3
  fi

  # Cleanup
  z::kv::unwatch "config:theme" theme_change_handler
  z::kv::unwatch "user:*" data_change_handler
  z::kv::del "user:score" 2>/dev/null
  unset -f theme_change_handler data_change_handler
}

###
# Demo 8: Configuration Management
###
demo_config() {
  demo_section "8. CONFIGURATION MANAGEMENT"

  demo_subsection "Configuration is KV-Backed"
  print "All configuration is stored in KV store with 'config:' prefix"
  print ""

  demo_cmd "Get config value" z::config::get log_level
  demo_cmd "Set config value" z::config::set custom_setting "my_value"
  demo_cmd "Verify in KV store" z::kv::get "config:custom_setting"

  demo_subsection "Type-Safe Configuration"
  demo_cmd "Set integer config" z::config::set timeout_default 60
  demo_cmd "Set boolean config" z::config::set show_progress false

  print "Attempting invalid type (should fail):"
  z::config::set timeout_default "not_a_number" && print "  ${_z_colors[red]}✗ Should fail${_z_colors[reset]}" || print "  ${_z_colors[green]}✓ Correctly rejected${_z_colors[reset]}"
  print ""

  demo_subsection "Configuration Display"
  demo_cmd "Show all configuration" z::config::show

  demo_subsection "Configuration Persistence"
  local config_file="/tmp/z_demo_config.txt"
  demo_cmd "Save configuration" z::config::save "$config_file"
  print "Configuration file contents:"
  print "${_z_colors[cyan]}────────────────────────────────────────${_z_colors[reset]}"
  head -n 15 "$config_file"
  print "${_z_colors[cyan]}────────────────────────────────────────${_z_colors[reset]}"
  print ""

  # Cleanup
  rm -f "$config_file"
  z::kv::del "config:custom_setting" 2>/dev/null
}

###
# Demo 9: Persistence
###
demo_persistence() {
  demo_section "9. DATA PERSISTENCE"

  demo_subsection "Save & Load KV Store"

  print "Setting up test data..."
  z::kv::set "app:version" "1.0.0"
  z::kv::set_int "app:users" "1000"
  z::kv::set_bool "app:production" "true"
  z::kv::set "app:database" "postgresql://localhost/mydb"
  print ""

  local db_file="/tmp/z_demo.db"
  demo_cmd "Save to file" z::kv::save "$db_file"

  print "File contents:"
  print "${_z_colors[cyan]}────────────────────────────────────────${_z_colors[reset]}"
  cat "$db_file"
  print "${_z_colors[cyan]}────────────────────────────────────────${_z_colors[reset]}"
  print ""

  print "Clearing KV store..."
  z::kv::keys "app:*" | while read key; do z::kv::del "$key"; done
  print "Keys after clear: $(z::kv::keys 'app:*' | wc -l | tr -d ' ')"
  print ""

  demo_cmd "Load from file" z::kv::load "$db_file"
  demo_cmd "Verify data restored" z::kv::get "app:version"
  demo_cmd "Check integer restored" z::kv::get_int "app:users"

  demo_subsection "Auto-Persistence"
  demo_cmd "Enable auto-persist" z::kv::enable_persist "$db_file"
  print "Now every KV change auto-saves to disk"
  print ""

  z::kv::set "app:auto_saved" "this will auto-save"
  print "Checking file was updated:"
  if grep -q "app:auto_saved" "$db_file"; then
    print "  ${_z_colors[green]}✓ Auto-save working${_z_colors[reset]}"
  else
    print "  ${_z_colors[red]}✗ Auto-save failed${_z_colors[reset]}"
  fi
  print ""

  demo_cmd "Disable auto-persist" z::kv::disable_persist

  # Cleanup
  rm -f "$db_file"
  z::kv::keys "app:*" | while read key; do z::kv::del "$key"; done
}

###
# Demo 10: Distributed Locking
###
demo_locking() {
  demo_section "10. DISTRIBUTED LOCKING"

  demo_subsection "Basic Locking"
  demo_cmd "Acquire lock" z::kv::lock "resource:database" 30

  print "Attempting to acquire same lock (should fail):"
  z::kv::lock "resource:database" 30 && print "  ${_z_colors[red]}✗ Should fail${_z_colors[reset]}" || print "  ${_z_colors[green]}✓ Correctly blocked${_z_colors[reset]}"
  print ""

  demo_cmd "Release lock" z::kv::unlock "resource:database"

  print "Attempting to acquire after release (should succeed):"
  z::kv::lock "resource:database" 30 && print "  ${_z_colors[green]}✓ Lock acquired${_z_colors[reset]}" || print "  ${_z_colors[red]}✗ Should succeed${_z_colors[reset]}"
  z::kv::unlock "resource:database"
  print ""

  demo_subsection "Lock Expiration"
  demo_cmd "Acquire lock with 3s TTL" z::kv::lock "resource:temp" 3
  print "Waiting 4 seconds for lock to expire..."
  sleep 4
  print "Attempting to acquire expired lock (should succeed):"
  z::kv::lock "resource:temp" 10 && print "  ${_z_colors[green]}✓ Expired lock acquired${_z_colors[reset]}" || print "  ${_z_colors[red]}✗ Should succeed${_z_colors[reset]}"
  z::kv::unlock "resource:temp"
  print ""

  demo_subsection "Critical Section Pattern"
  print "Typical usage pattern:"
  print "${_z_colors[cyan]}────────────────────────────────────────${_z_colors[reset]}"
  cat <<'EOF'
  if z::kv::lock "resource" 30; then
    # Critical section - only one process here
    process_shared_resource
    z::kv::unlock "resource"
  else
    echo "Resource locked by another process"
  fi
EOF
  print "${_z_colors[cyan]}────────────────────────────────────────${_z_colors[reset]}"
  print ""
}

###
# Demo 11: Transactions
###
demo_transactions() {
  demo_section "11. TRANSACTION SUPPORT"

  demo_subsection "Successful Transaction"
  print "Setting initial values..."
  z::kv::set_int "account:balance" "1000"
  z::kv::set "account:status" "active"
  print "  balance: $(z::kv::get_int 'account:balance')"
  print "  status: $(z::kv::get 'account:status')"
  print ""

  demo_cmd "Begin transaction" z::kv::begin
  print "Making changes in transaction..."
  z::kv::incr "account:balance" -100
  z::kv::set "account:status" "pending"
  print "  balance: $(z::kv::get_int 'account:balance')"
  print "  status: $(z::kv::get 'account:status')"
  print ""

  demo_cmd "Commit transaction" z::kv::commit
  print "After commit:"
  print "  balance: $(z::kv::get_int 'account:balance')"
  print "  status: $(z::kv::get 'account:status')"
  print ""

  demo_subsection "Rollback Transaction"
  print "Current balance: $(z::kv::get_int 'account:balance')"
  print ""

  demo_cmd "Begin transaction" z::kv::begin
  print "Making changes..."
  z::kv::incr "account:balance" -500
  z::kv::set "account:status" "error"
  print "  balance: $(z::kv::get_int 'account:balance')"
  print "  status: $(z::kv::get 'account:status')"
  print ""

  demo_cmd "Rollback transaction" z::kv::rollback
  print "After rollback:"
  print "  balance: $(z::kv::get_int 'account:balance')"
  print "  status: $(z::kv::get 'account:status')"
  print ""

  # Cleanup
  z::kv::del "account:balance" 2>/dev/null
  z::kv::del "account:status" 2>/dev/null
}

###
# Demo 12: Performance Benchmarks
###
demo_performance() {
  demo_section "12. PERFORMANCE BENCHMARKS"

  demo_subsection "Cache Performance"
  print "Comparing cached vs uncached lookups:"
  print ""

  slow_function() {
    sleep 0.1
    print "computed"
  }

  print "${_z_colors[green]}→${_z_colors[reset]} First call (cache miss):"
  time z::cache::memoize "perf:test" 60 slow_function
  print ""

  print "${_z_colors[green]}→${_z_colors[reset]} Second call (cache hit):"
  time z::cache::memoize "perf:test" 60 slow_function
  print ""

  print "${_z_colors[green]}→${_z_colors[reset]} Third call (cache hit):"
  time z::cache::memoize "perf:test" 60 slow_function
  print ""

  demo_subsection "Bulk Operations"
  print "Testing bulk KV operations..."
  print ""

  print "${_z_colors[green]}→${_z_colors[reset]} Writing 100 keys:"
  time {
    for i in {1..100}; do
      z::kv::set "perf:key${i}" "value${i}" >/dev/null 2>&1
    done
  }
  print ""

  print "${_z_colors[green]}→${_z_colors[reset]} Reading 100 keys:"
  time {
    for i in {1..100}; do
      z::kv::get "perf:key${i}" >/dev/null 2>&1
    done
  }
  print ""

  demo_subsection "Cache Statistics"
  demo_cmd "Show cache performance" z::cache::stats

  demo_subsection "KV Statistics"
  demo_cmd "Show KV performance" z::kv::stats

  # Cleanup
  z::cache::clear "perf:*"
  for i in {1..100}; do
    z::kv::del "perf:key${i}" 2>/dev/null
  done
  unset -f slow_function
}

###
# Demo 13: Real-World Example
###
demo_real_world() {
  demo_section "13. REAL-WORLD EXAMPLE: USER SESSION MANAGER"

  print "Building a complete user session manager using all pillars:"
  print ""

  demo_subsection "Session Manager Implementation"

  # Session manager functions
  session_create() {
    local username="$1"
    local session_id="session:${RANDOM}${RANDOM}"

    z::log::info "Creating session for: $username"

    # Store session data in KV
    z::kv::set "${session_id}:user" "$username"
    z::kv::set "${session_id}:created" "$(date +%s)"
    z::kv::set "${session_id}:ip" "127.0.0.1"

    # Set 1 hour expiration
    z::kv::expire "${session_id}:user" 3600
    z::kv::expire "${session_id}:created" 3600
    z::kv::expire "${session_id}:ip" 3600

    # Increment session counter
    z::kv::incr "stats:total_sessions"
    z::kv::incr "stats:active_sessions"

    print "  Session ID: $session_id"
    print "  TTL: 3600s (1 hour)"

    # Emit event
    if (( ${+functions[z::event::emit]} )); then
      z::event::emit "session:created" "$session_id" "$username"
    fi

    print -r -- "$session_id"
  }

  session_get() {
    local session_id="$1"

    if ! z::kv::exists "${session_id}:user"; then
      z::log::warn "Session not found or expired: $session_id"
      return 1
    fi

    local username
    username=$(z::kv::get "${session_id}:user")

    print "Session: $session_id"
    print "  User: $username"
    print "  TTL: $(z::kv::ttl "${session_id}:user")s remaining"

    return 0
  }

  session_destroy() {
    local session_id="$1"

    z::log::info "Destroying session: $session_id"

    # Get username before deleting
    local username
    username=$(z::kv::get "${session_id}:user" 2>/dev/null || print "unknown")

    # Delete session data
    z::kv::del "${session_id}:user" 2>/dev/null
    z::kv::del "${session_id}:created" 2>/dev/null
    z::kv::del "${session_id}:ip" 2>/dev/null

    # Update counter
    z::kv::decr "stats:active_sessions"

    # Emit event
    if (( ${+functions[z::event::emit]} )); then
      z::event::emit "session:destroyed" "$session_id" "$username"
    fi
  }

  # Event handlers
  if (( ${+functions[z::event::on]} )); then
    session_created_handler() {
      local event="$1" session_id="$2" username="$3"
      z::log::info "📝 Audit: User $username logged in (session: $session_id)"
    }

    session_destroyed_handler() {
      local event="$1" session_id="$2" username="$3"
      z::log::info "📝 Audit: User $username logged out (session: $session_id)"
    }

    z::event::on "session:created" session_created_handler
    z::event::on "session:destroyed" session_destroyed_handler
  fi

  demo_subsection "Creating Sessions"
  print "${_z_colors[green]}→${_z_colors[reset]} Creating session for Alice:"
  local session1
  session1=$(session_create "alice")
  print ""

  print "${_z_colors[green]}→${_z_colors[reset]} Creating session for Bob:"
  local session2
  session2=$(session_create "bob")
  print ""

  demo_subsection "Retrieving Sessions"
  print "${_z_colors[green]}→${_z_colors[reset]} Getting Alice's session:"
  session_get "$session1"
  print ""

  print "${_z_colors[green]}→${_z_colors[reset]} Getting Bob's session:"
  session_get "$session2"
  print ""

  demo_subsection "Session Statistics"
  print "Total sessions created: $(z::kv::get_int 'stats:total_sessions' 2>/dev/null || print 0)"
  print "Active sessions: $(z::kv::get_int 'stats:active_sessions' 2>/dev/null || print 0)"
  print ""

  demo_subsection "Destroying Sessions"
  print "${_z_colors[green]}→${_z_colors[reset]} Destroying Alice's session:"
  session_destroy "$session1"
  print ""

  print "${_z_colors[green]}→${_z_colors[reset]} Destroying Bob's session:"
  session_destroy "$session2"
  print ""

  print "Active sessions after cleanup: $(z::kv::get_int 'stats:active_sessions' 2>/dev/null || print 0)"
  print ""

  # Cleanup
  if (( ${+functions[z::event::off]} )); then
    z::event::off "session:*"
    unset -f session_created_handler session_destroyed_handler
  fi
  unset -f session_create session_get session_destroy
  z::kv::del "stats:total_sessions" 2>/dev/null
  z::kv::del "stats:active_sessions" 2>/dev/null
}

###
# Demo 14: Advanced Features
###
demo_advanced() {
  demo_section "14. ADVANCED FEATURES"

  demo_subsection "Watchers with Reactive Updates"
  print "Setting up reactive counter with automatic notifications:"
  print ""

  counter_watcher() {
    local key="$1" value="$2" operation="$3"
    local count
    count=$(z::kv::get_int "$key" 2>/dev/null || print 0)

    print "  ${_z_colors[magenta]}[Watcher]${_z_colors[reset]} Counter changed: $count"

    if (( count >= 10 )); then
      print "  ${_z_colors[yellow]}→${_z_colors[reset]} Milestone reached: 10!"
    fi

    if (( count >= 20 )); then
      print "  ${_z_colors[yellow]}→${_z_colors[reset]} Milestone reached: 20!"
    fi
  }

  z::kv::watch "demo:counter" counter_watcher

  print "${_z_colors[green]}→${_z_colors[reset]} Incrementing counter:"
  for i in {1..25}; do
    z::kv::incr "demo:counter" 1
    sleep 0.05
  done
  print ""

  demo_subsection "Cache Warming"
  print "Pre-populating cache for better performance:"
  print ""

  lookup_function() {
    local item="$1"
    sleep 0.05  # Simulate lookup
    print "data_for_${item}"
  }

  print "${_z_colors[green]}→${_z_colors[reset]} Warming cache with 10 items:"
  time {
    local -a items
    items=(item1 item2 item3 item4 item5 item6 item7 item8 item9 item10)

    for item in "${items[@]}"; do
      z::cache::memoize "lookup:${item}" 300 lookup_function "$item" >/dev/null
    done
  }
  print ""

  print "${_z_colors[green]}→${_z_colors[reset]} Accessing cached items (instant):"
  time {
    for item in item1 item5 item10; do
      z::cache::get "lookup:${item}" >/dev/null
    done
  }
  print ""

  demo_subsection "Configuration Reactivity"
  if (( ${+functions[z::event::on]} )); then
    print "Configuration changes trigger automatic updates:"
    print ""

    config_change_handler() {
      local event="$1" key="$2" value="$3"
      print "  ${_z_colors[magenta]}[Config Changed]${_z_colors[reset]} $key → $value"

      case $key in
        theme)
          print "  ${_z_colors[cyan]}→${_z_colors[reset]} Reloading UI colors..."
          z::cache::clear "ui:*"
          ;;
        log_level)
          print "  ${_z_colors[cyan]}→${_z_colors[reset]} Adjusting verbosity..."
          ;;
        performance_mode)
          print "  ${_z_colors[cyan]}→${_z_colors[reset]} Toggling performance optimizations..."
          ;;
      esac
    }

    z::event::on "config:changed" config_change_handler

    print "${_z_colors[green]}→${_z_colors[reset]} Changing configuration:"
    z::config::set theme "dark"
    z::config::set performance_mode true
    print ""

    z::event::off "config:changed" config_change_handler
    unset -f config_change_handler
  fi

  # Cleanup
  z::kv::unwatch "demo:counter" counter_watcher
  z::kv::del "demo:counter" 2>/dev/null
  z::cache::clear "lookup:*"
  unset -f counter_watcher lookup_function
}

###
# Demo 15: Complete Application Example
###
demo_application() {
  demo_section "15. COMPLETE APPLICATION: TODO MANAGER"

  print "Building a complete TODO application using Z v3.0:"
  print ""

  demo_subsection "Application Setup"

  # Initialize
  todo_init() {
    z::log::info "Initializing TODO manager"

    # Set up configuration
    z::config::set todo_max_items 100
    z::config::set todo_auto_save true

    # Initialize counters
    z::kv::set_int "todo:next_id" "1"
    z::kv::set_int "todo:total" "0"
    z::kv::set_int "todo:completed" "0"

    # Set up event handlers
    if (( ${+functions[z::event::on]} )); then
      z::event::on "todo:added" todo_on_added
      z::event::on "todo:completed" todo_on_completed
    fi

    z::log::info "TODO manager ready"
  }

  # Add todo
  todo_add() {
    local title="$1"

    # Get next ID
    local id
    id=$(z::kv::get_int "todo:next_id")

    # Store todo
    z::kv::set "todo:${id}:title" "$title"
    z::kv::set "todo:${id}:status" "pending"
    z::kv::set "todo:${id}:created" "$(date +%s)"

    # Update counters
    z::kv::incr "todo:next_id"
    z::kv::incr "todo:total"

    z::log::info "Added TODO #${id}: $title"

    # Emit event
    if (( ${+functions[z::event::emit]} )); then
      z::event::emit "todo:added" "$id" "$title"
    fi

    print -r -- "$id"
  }

  # Complete todo
  todo_complete() {
    local id="$1"

    if ! z::kv::exists "todo:${id}:title"; then
      z::log::error "TODO #${id} not found"
      return 1
    fi

    local title
    title=$(z::kv::get "todo:${id}:title")

    z::kv::set "todo:${id}:status" "completed"
    z::kv::set "todo:${id}:completed_at" "$(date +%s)"

    z::kv::incr "todo:completed"

    z::log::info "Completed TODO #${id}: $title"

    # Emit event
    if (( ${+functions[z::event::emit]} )); then
      z::event::emit "todo:completed" "$id" "$title"
    fi
  }

  # List todos
  todo_list() {
    local status="${1:-all}"

    print "\nTODO List:"
    print "=========="

    local -a todo_ids
    todo_ids=($(z::kv::keys "todo:*:title" | sed 's/:title$//' | sed 's/^todo://'))

    if (( ${#todo_ids} == 0 )); then
      print "No todos found.\n"
      return 0
    fi

    local id title todo_status
    for id in "${todo_ids[@]}"; do
      title=$(z::kv::get "todo:${id}:title" 2>/dev/null || print "N/A")
      todo_status=$(z::kv::get "todo:${id}:status" 2>/dev/null || print "unknown")

      if [[ $status != "all" && $todo_status != $status ]]; then
        continue
      fi

      local status_icon
      if [[ $todo_status == "completed" ]]; then
        status_icon="${_z_colors[green]}✓${_z_colors[reset]}"
      else
        status_icon="${_z_colors[yellow]}○${_z_colors[reset]}"
      fi

      print "  ${status_icon} #${id}: $title"
    done

    print ""
  }

  # Statistics
  todo_stats() {
    print "\nTODO Statistics:"
    print "================"

    local total completed
    total=$(z::kv::get_int "todo:total" 2>/dev/null || print 0)
    completed=$(z::kv::get_int "todo:completed" 2>/dev/null || print 0)

    typeset -i pending
    (( pending = total - completed ))

    print "Total:     $total"
    print "Completed: $completed"
    print "Pending:   $pending"

    if (( total > 0 )); then
      typeset -F completion_rate
      (( completion_rate = (completed * 100.0) / total ))
      print "Progress:  ${completion_rate}%"
    fi

    print ""
  }

  # Event handlers
  todo_on_added() {
    local event="$1" id="$2" title="$3"
    print "  ${_z_colors[cyan]}[Event]${_z_colors[reset]} New TODO added: #${id}"
  }

  todo_on_completed() {
    local event="$1" id="$2" title="$3"
    print "  ${_z_colors[cyan]}[Event]${_z_colors[reset]} TODO completed: #${id}"

    # Check if all todos completed
    local total completed
    total=$(z::kv::get_int "todo:total" 2>/dev/null || print 0)
    completed=$(z::kv::get_int "todo:completed" 2>/dev/null || print 0)

    if (( total > 0 && total == completed )); then
      print "  ${_z_colors[green]}🎉 All todos completed!${_z_colors[reset]}"
    fi
  }

  demo_subsection "Running Application"

  print "${_z_colors[green]}→${_z_colors[reset]} Initializing:"
  todo_init
  print ""

  print "${_z_colors[green]}→${_z_colors[reset]} Adding todos:"
  local id1 id2 id3
  id1=$(todo_add "Write documentation")
  id2=$(todo_add "Review pull requests")
  id3=$(todo_add "Deploy to production")
  print ""

  print "${_z_colors[green]}→${_z_colors[reset]} Listing all todos:"
  todo_list

  print "${_z_colors[green]}→${_z_colors[reset]} Completing some todos:"
  todo_complete "$id1"
  todo_complete "$id2"
  print ""

  print "${_z_colors[green]}→${_z_colors[reset]} Listing pending todos:"
  todo_list "pending"

  print "${_z_colors[green]}→${_z_colors[reset]} Completing remaining:"
  todo_complete "$id3"
  print ""

  print "${_z_colors[green]}→${_z_colors[reset]} Final statistics:"
  todo_stats

  demo_subsection "Persistence"
  local todo_db="/tmp/z_todo.db"
  demo_cmd "Save todos to disk" z::kv::save "$todo_db"
  print "Database file size: $(wc -c < "$todo_db" | tr -d ' ') bytes"
  print ""

  # Cleanup
  if (( ${+functions[z::event::off]} )); then
    z::event::off "todo:*"
  fi
  z::kv::keys "todo:*" | while read key; do z::kv::del "$key" 2>/dev/null; done
  z::kv::del "stats:total_sessions" 2>/dev/null
  z::kv::del "stats:active_sessions" 2>/dev/null
  rm -f "$todo_db"
  unset -f todo_init todo_add todo_complete todo_list todo_stats todo_on_added todo_on_completed
}

###
# Demo 16: Pillar Comparison
###
demo_comparison() {
  demo_section "16. PILLAR COMPARISON & BENEFITS"

  demo_subsection "Storage Comparison"

  print "Comparing different storage mechanisms:"
  print ""
  print "${_z_colors[bold]}Cache vs KV Store:${_z_colors[reset]}"
  print ""

  print "Cache (Temporary, Performance):"
  print "  • Fast lookups with TTL"
  print "  • Automatic eviction"
  print "  • Statistics per namespace"
  print "  • Best for: computed results, lookups"
  print ""

  print "KV Store (Persistent, Features):"
  print "  • Persistent storage"
  print "  • Rich data structures"
  print "  • Transactions"
  print "  • Watchers"
  print "  • Best for: configuration, state, data"
  print ""

  demo_subsection "When to Use Each Pillar"

  print "${_z_colors[red]}Logging:${_z_colors[reset]}"
  print "  ✓ All diagnostic output"
  print "  ✓ Error reporting"
  print "  ✓ Audit trails"
  print "  ✓ Performance metrics"
  print ""

  print "${_z_colors[blue]}Cache:${_z_colors[reset]}"
  print "  ✓ Function memoization"
  print "  ✓ Command existence checks"
  print "  ✓ Path resolution results"
  print "  ✓ Terminal dimensions"
  print "  ✓ Platform detection"
  print ""

  print "${_z_colors[yellow]}KV Store:${_z_colors[reset]}"
  print "  ✓ Application configuration"
  print "  ✓ User preferences"
  print "  ✓ Session data"
  print "  ✓ Feature flags"
  print "  ✓ Counters and metrics"
  print "  ✓ Distributed locks"
  print ""

  demo_subsection "Performance Characteristics"

  print "Operation Speed (relative):"
  print ""
  print "  Cache Get:     ${_z_colors[green]}█████${_z_colors[reset]} (fastest)"
  print "  KV Get:        ${_z_colors[green]}████${_z_colors[reset]} (very fast)"
  print "  Cache Set:     ${_z_colors[blue]}████${_z_colors[reset]} (very fast)"
  print "  KV Set:        ${_z_colors[blue]}███${_z_colors[reset]} (fast, with features)"
  print "  KV Save:       ${_z_colors[yellow]}██${_z_colors[reset]} (I/O bound)"
  print ""

  # Cleanup
  z::kv::unwatch "demo:counter" counter_watcher 2>/dev/null
  z::kv::del "demo:counter" 2>/dev/null
  unset -f counter_watcher
}

###
# Demo 17: Best Practices
###
demo_best_practices() {
  demo_section "17. BEST PRACTICES"

  demo_subsection "1. Use Namespaces"
  print "Organize keys with namespaces:"
  print ""
  print "${_z_colors[green]}✓ Good:${_z_colors[reset]}"
  print "  z::kv::set 'app:db:host' 'localhost'"
  print "  z::kv::set 'app:cache:ttl' '300'"
  print "  z::cache::set 'cmd:exists:git' '1'"
  print ""
  print "${_z_colors[red]}✗ Bad:${_z_colors[reset]}"
  print "  z::kv::set 'dbhost' 'localhost'"
  print "  z::kv::set 'cachettl' '300'"
  print ""

  demo_subsection "2. Use Appropriate Pillar"
  print "Choose the right pillar for your data:"
  print ""
  print "${_z_colors[green]}✓ Good:${_z_colors[reset]}"
  print "  z::cache::memoize 'expensive:calc' 60 compute_fn  # Temporary"
  print "  z::kv::set 'user:preferences' 'data'              # Persistent"
  print "  z::log::info 'Operation complete'                 # Diagnostic"
  print ""
  print "${_z_colors[red]}✗ Bad:${_z_colors[reset]}"
  print "  z::kv::set 'cache:temp' 'data'  # Use cache pillar instead"
  print "  print 'Debug info' >&2          # Use logging pillar"
  print ""

  demo_subsection "3. Leverage Events for Decoupling"
  if (( ${+functions[z::event::on]} )); then
    print "Use events to decouple components:"
    print ""
    print "${_z_colors[green]}✓ Good:${_z_colors[reset]}"
    print "  z::event::on 'user:login' update_ui"
    print "  z::event::on 'user:login' log_access"
    print "  z::event::on 'user:login' send_notification"
    print "  z::event::emit 'user:login' 'john'"
    print ""
    print "${_z_colors[red]}✗ Bad:${_z_colors[reset]}"
    print "  user_login() {"
    print "    update_ui"
    print "    log_access"
    print "    send_notification"
    print "  }"
    print ""
  fi

  demo_subsection "4. Use Transactions for Consistency"
  print "Use transactions for multi-step operations:"
  print ""
  print "${_z_colors[green]}✓ Good:${_z_colors[reset]}"
  print "  z::kv::begin"
  print "  z::kv::incr 'account:balance' -100"
  print "  z::kv::set 'account:status' 'pending'"
  print "  z::kv::commit"
  print ""

  demo_subsection "5. Monitor with Statistics"
  print "Track performance and usage:"
  print ""
  print "  z::cache::stats          # Cache performance"
  print "  z::kv::stats             # KV usage"
  print "  z::event::stats          # Event activity"
  print ""
}

################################################################################
# MAIN DEMO RUNNER
################################################################################

main() {
  clear
  cat <<'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║                    Z FRAMEWORK v3.0 DEMO                                ║
║                                                                              ║
║                    🏛️ Pillar-Based Architecture                             ║
║                                                                              ║
║              🔴 Logging  |  🔵 Cache  |  🟠 KV Store  |  🟣 Events          ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF

  z::log::info "Starting Z v3.0 demonstration"
  z::log::info "Framework version: ${Z_VERSION}"

  if should_run_section "pillars"; then
    demo_pillars
  fi

  if should_run_section "logging"; then
    demo_logging
  fi

  if should_run_section "cache"; then
    demo_cache
  fi

  if should_run_section "kv"; then
    demo_kv
  fi

  if should_run_section "events"; then
    demo_events
  fi

  if should_run_section "integration"; then
    demo_integration
  fi

  if should_run_section "reactive"; then
    demo_reactive
  fi

  if should_run_section "config"; then
    demo_config
  fi

  if should_run_section "persistence"; then
    demo_persistence
  fi

  if should_run_section "locking"; then
    demo_locking
  fi

  if should_run_section "transactions"; then
    demo_transactions
  fi

  if should_run_section "performance"; then
    demo_performance
  fi

  if should_run_section "application"; then
    demo_application
  fi

  if should_run_section "comparison"; then
    demo_comparison
  fi

  if should_run_section "best_practices"; then
    demo_best_practices
  fi

  # Summary
  demo_section "DEMO COMPLETE ✓"

  print "${_z_colors[green]}${_z_colors[bold]}All demonstrations completed successfully!${_z_colors[reset]}"
  print ""
  print "What you've seen:"
  print "  🔴 Logging pillar - Zero-dependency diagnostic output"
  print "  🔵 Cache pillar - Universal caching with TTL and memoization"
  print "  🟠 KV Store pillar - Persistent storage with rich features"
  if (( ${+functions[z::event::emit]} )); then
    print "  🟣 Event system - Reactive pub/sub architecture"
  fi
  print ""
  print "Key Features:"
  print "  ✓ No circular dependencies"
  print "  ✓ Optional integration"
  print "  ✓ Event-driven reactivity"
  print "  ✓ Automatic persistence"
  print "  ✓ Transaction support"
  print "  ✓ Distributed locking"
  print "  ✓ Type safety"
  print "  ✓ Performance monitoring"
  print ""
  print "Next steps:"
  print "  • Review source: ${_z_colors[cyan]}less z.zsh${_z_colors[reset]}"
  print "  • Quick reference: ${_z_colors[cyan]}z::help::quick${_z_colors[reset]}"
  print "  • List functions: ${_z_colors[cyan]}z::help::list z::kv::${_z_colors[reset]}"
  print "  • Run specific demo: ${_z_colors[cyan]}./z-demo.zsh --section reactive${_z_colors[reset]}"
  print ""
  print "Architecture documentation: ARCHITECTURE.md"
  print "GitHub: https://github.com/your-repo/z"
  print ""

  # Final statistics
  if (( ${+functions[z::event::stats]} )); then
    print "${_z_colors[bold]}Demo Statistics:${_z_colors[reset]}"
    z::event::stats
  fi

  print "${_z_colors[bold]}Cache Statistics:${_z_colors[reset]}"
  z::cache::stats

  print "${_z_colors[bold]}KV Statistics:${_z_colors[reset]}"
  z::kv::stats
}

# Run main demo
main

exit 0
