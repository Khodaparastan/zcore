#!/usr/bin/env zsh

################################################################################
# EXAMPLE 1: Basic Event Handling
################################################################################

# Define handler functions
my_plugin_loaded_handler() {
  local plugin_name="$1"
  z::log::info "Plugin loaded: $plugin_name"
}

my_app_start_handler() {
  z::log::info "Application starting..."
}

# Register handlers
z::event::on "plugin:loaded" my_plugin_loaded_handler
z::event::on "app:start" my_app_start_handler

# Emit events
z::event::emit "app:start"
z::event::emit "plugin:loaded" "git-helper"

################################################################################
# EXAMPLE 2: Priority-Based Handlers
################################################################################

high_priority_handler() {
  print "HIGH: This runs first"
}

low_priority_handler() {
  print "LOW: This runs last"
}

normal_priority_handler() {
  print "NORMAL: This runs in the middle"
}

z::event::on "test:priority" high_priority_handler --priority 100
z::event::on "test:priority" low_priority_handler --priority 25
z::event::on "test:priority" normal_priority_handler --priority 50

z::event::emit "test:priority"

################################################################################
# EXAMPLE 3: One-Time Handlers
################################################################################

init_once_handler() {
  print "This only runs once!"
}

z::event::once "app:ready" init_once_handler

z::event::emit "app:ready"  # Handler runs
z::event::emit "app:ready"  # Handler does NOT run

################################################################################
# EXAMPLE 4: Wildcard Event Matching
################################################################################

catch_all_plugin_events() {
  local event_name="$1"
  shift
  z::log::info "Plugin event caught: $event_name with args: $*"
}

z::event::on "plugin:*" catch_all_plugin_events

z::event::emit "plugin:loaded" "vim-plugin"
z::event::emit "plugin:unloaded" "vim-plugin"
z::event::emit "plugin:error" "broken-plugin" "error message"

################################################################################
# EXAMPLE 5: Async Events
################################################################################

heavy_processing_handler() {
  sleep 2
  print "Heavy processing complete"
}

z::event::on "data:process" heavy_processing_handler

# Non-blocking
z::event::emit_async "data:process"
print "This prints immediately"

################################################################################
# EXAMPLE 6: Event Introspection
################################################################################

# List all handlers
z::event::list

# List handlers for specific pattern
z::event::list "plugin:*"

# Show statistics
z::event::stats

# Show history
z::event::history 10

################################################################################
# EXAMPLE 7: Removing Handlers
################################################################################

# Remove specific handler
z::event::off "plugin:loaded" my_plugin_loaded_handler

# Remove all handlers for an event
z::event::off "plugin:loaded"

# Remove handler from all events
z::event::off "*" catch_all_plugin_events

################################################################################
# EXAMPLE 8: Configuration
################################################################################

# Increase history size
z::event::configure max_history 500

# Disable history
z::event::configure enable_history false

# Get config value
max=$(z::event::get_config max_history)
print "Max history: $max"

################################################################################
# EXAMPLE 9: Real-World Plugin System Integration
################################################################################

# Plugin lifecycle events
plugin_lifecycle_monitor() {
  local event="$1"
  local plugin="$2"

  case "$event" in
    plugin:discovered)
      print "📦 Discovered: $plugin"
      ;;
    plugin:loaded)
      print "✅ Loaded: $plugin"
      ;;
    plugin:enabled)
      print "🟢 Enabled: $plugin"
      ;;
    plugin:disabled)
      print "🔴 Disabled: $plugin"
      ;;
    plugin:failed)
      print "❌ Failed: $plugin"
      ;;
  esac
}

z::event::on "plugin:*" plugin_lifecycle_monitor --priority 100

# Emit lifecycle events
z::event::emit "plugin:discovered" "my-plugin"
z::event::emit "plugin:loaded" "my-plugin"
z::event::emit "plugin:enabled" "my-plugin"

################################################################################
# EXAMPLE 10: Error Handling
################################################################################

failing_handler() {
  print "This handler will fail"
  return 1
}

successful_handler() {
  print "This handler succeeds"
  return 0
}

z::event::on "test:error" failing_handler
z::event::on "test:error" successful_handler

# Both handlers run, failure is isolated
z::event::emit "test:error"

# Check stats to see failures
z::event::stats "test:error"
