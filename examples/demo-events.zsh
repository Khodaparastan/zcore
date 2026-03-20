#!/usr/bin/env zsh

# Source the main z framework
source "$(dirname "$0")/z.zsh"

print "\n========================================="
print "Z EVENT SYSTEM DEMO"
print "=========================================\n"

################################################################################
# DEMO 1: Plugin Lifecycle Events
################################################################################

print "DEMO 1: Plugin Lifecycle Events\n"

plugin_discovered_logger() {
  local plugin="${1:-unknown}"
  print "📦 Discovered plugin: $plugin"
}

plugin_loaded_logger() {
  local plugin="${1:-unknown}"
  print "✅ Loaded plugin: $plugin"
}

plugin_enabled_logger() {
  local plugin="${1:-unknown}"
  print "🟢 Enabled plugin: $plugin"
}

plugin_disabled_logger() {
  local plugin="${1:-unknown}"
  print "🔴 Disabled plugin: $plugin"
}

plugin_failed_logger() {
  local plugin="${1:-unknown}"
  print "❌ Failed plugin: $plugin"
}

# Register specific handlers for each event
z::event::on "plugin:discovered" plugin_discovered_logger --priority 100
z::event::on "plugin:loaded" plugin_loaded_logger --priority 100
z::event::on "plugin:enabled" plugin_enabled_logger --priority 100
z::event::on "plugin:disabled" plugin_disabled_logger --priority 100
z::event::on "plugin:failed" plugin_failed_logger --priority 100

# Simulate plugin lifecycle
z::event::emit "plugin:discovered" "git-helper"
z::event::emit "plugin:loaded" "git-helper"
z::event::emit "plugin:enabled" "git-helper"

print ""

################################################################################
# DEMO 2: Application Startup Sequence
################################################################################

print "DEMO 2: Application Startup Sequence\n"

app_init_config() {
  print "  [1/4] Loading configuration..."
  sleep 0.2
}

app_init_database() {
  print "  [2/4] Connecting to database..."
  sleep 0.2
}

app_init_plugins() {
  print "  [3/4] Initializing plugins..."
  sleep 0.2
}

app_init_complete() {
  print "  [4/4] Application ready!"
}

# Register startup handlers with priorities
z::event::on "app:startup" app_init_config --priority 100
z::event::on "app:startup" app_init_database --priority 75
z::event::on "app:startup" app_init_plugins --priority 50
z::event::on "app:startup" app_init_complete --priority 25

print "Starting application..."
z::event::emit "app:startup"

print ""

################################################################################
# DEMO 3: User Authentication Flow
################################################################################

print "DEMO 3: User Authentication Flow\n"

auth_validate() {
  local username="${1:-anonymous}"
  print "  → Validating credentials for: $username"
}

auth_log() {
  local username="${1:-anonymous}"
  print "  → Logging authentication attempt: $username"
}

auth_notify() {
  local username="${1:-anonymous}"
  print "  → Sending notification: Welcome $username!"
}

z::event::on "user:login" auth_validate --priority 100
z::event::on "user:login" auth_log --priority 50
z::event::on "user:login" auth_notify --priority 25

print "User login event:"
z::event::emit "user:login" "john_doe"

print ""

################################################################################
# DEMO 4: One-Time Initialization
################################################################################

print "DEMO 4: One-Time Initialization\n"

first_run_setup() {
  print "  → Running first-time setup..."
  print "  → Creating config directory..."
  print "  → Generating default settings..."
}

z::event::once "app:first_run" first_run_setup

print "First application start:"
z::event::emit "app:first_run"

print "\nSecond application start (setup should not run):"
z::event::emit "app:first_run"

print ""

################################################################################
# DEMO 5: Error Handling and Recovery
################################################################################

print "DEMO 5: Error Handling and Recovery\n"

risky_operation() {
  print "  → Attempting risky operation..."
  return 1  # Simulate failure
}

error_recovery() {
  print "  → Error recovery handler executed"
  print "  → System remains stable"
}

z::event::on "system:operation" risky_operation --priority 100
z::event::on "system:operation" error_recovery --priority 50

print "Executing operation with error handling:"
z::event::emit "system:operation"

print ""

################################################################################
# DEMO 6: Real-Time Monitoring
################################################################################

print "DEMO 6: Real-Time Monitoring\n"

monitor_cpu() {
  local usage="${1:-0}"
  if (( usage > 80 )); then
    print "  ⚠️  CPU usage high: ${usage}%"
  else
    print "  ✓ CPU usage normal: ${usage}%"
  fi
}

monitor_memory() {
  local usage="${1:-0}"
  if (( usage > 80 )); then
    print "  ⚠️  Memory usage high: ${usage}%"
  else
    print "  ✓ Memory usage normal: ${usage}%"
  fi
}

z::event::on "system:metrics" monitor_cpu
z::event::on "system:metrics" monitor_memory

print "System metrics check 1:"
z::event::emit "system:metrics" 45

print "\nSystem metrics check 2:"
z::event::emit "system:metrics" 85

print ""

################################################################################
# DEMO 7: Multiple Arguments
################################################################################

print "DEMO 7: Multiple Arguments\n"

file_processor() {
  local filename="${1:-unknown}"
  local size="${2:-0}"
  local type="${3:-unknown}"

  print "  → Processing file: $filename"
  print "    Size: $size bytes"
  print "    Type: $type"
}

z::event::on "file:process" file_processor

z::event::emit "file:process" "document.pdf" "1048576" "application/pdf"

print ""

################################################################################
# DEMO 8: Wildcard Events
################################################################################

print "DEMO 8: Wildcard Event Matching\n"

catch_all_logger() {
  local data="${1:-no-data}"
  print "  → Caught data event: $data"
}

z::event::on "data:*" catch_all_logger

z::event::emit "data:received" "payload-1"
z::event::emit "data:processed" "payload-2"
z::event::emit "data:saved" "payload-3"

print ""

################################################################################
# DEMO 9: Event Chaining
################################################################################

print "DEMO 9: Event Chaining\n"

step1_handler() {
  print "  → Step 1: Fetch data"
  z::event::emit "workflow:step2" "data-from-step1"
}

step2_handler() {
  local data="${1:-}"
  print "  → Step 2: Process data ($data)"
  z::event::emit "workflow:step3" "processed-data"
}

step3_handler() {
  local data="${1:-}"
  print "  → Step 3: Save data ($data)"
  print "  ✓ Workflow complete!"
}

z::event::on "workflow:step1" step1_handler
z::event::on "workflow:step2" step2_handler
z::event::on "workflow:step3" step3_handler

print "Starting workflow:"
z::event::emit "workflow:step1"

print ""

################################################################################
# DEMO 10: Async Events (Non-Blocking)
################################################################################

print "DEMO 10: Async Events (Non-Blocking)\n"

heavy_processing() {
  print "  → Background: Starting heavy computation..."
  sleep 1
  print "  → Background: Computation complete!"
}

z::event::on "data:heavy_process" heavy_processing

print "Triggering async event..."
z::event::emit_async "data:heavy_process"
print "Main thread continues immediately!"
print "Doing other work..."
sleep 0.5
print "Still doing work..."
sleep 0.7
print "Waiting for background task to complete..."

print ""

################################################################################
# SHOW RESULTS
################################################################################

print "========================================="
print "DEMO RESULTS"
print "=========================================\n"

print "Event Statistics:"
z::event::stats

print "\nEvent History (last 15):"
z::event::history 15

print "\nRegistered Handlers:"
z::event::list

print "\n========================================="
print "DEMO COMPLETED"
print "=========================================\n"
