#!/usr/bin/env zsh

################################################################################
# Z KV STORE DEMO
################################################################################

# Source the main z framework
source "$(dirname "$0")/z.zsh"

print "\n========================================="
print "Z KV STORE COMPREHENSIVE DEMO"
print "=========================================\n"

################################################################################
# DEMO 1: Basic Operations
################################################################################

print "DEMO 1: Basic CRUD Operations\n"
print "------------------------------"

# Set values
z::kv::set "app.name" "MyAwesomeApp"
z::kv::set "app.version" "1.0.0"
z::kv::set "app.author" "John Doe"

# Get values
print "App Name:    $(z::kv::get app.name)"
print "Version:     $(z::kv::get app.version)"
print "Author:      $(z::kv::get app.author)"

# Check existence
if z::kv::exists "app.name"; then
  print "✓ Key 'app.name' exists"
fi

# Delete
z::kv::del "app.author"
if ! z::kv::exists "app.author"; then
  print "✓ Key 'app.author' deleted successfully"
fi

print ""

################################################################################
# DEMO 2: Namespaced Keys (Dot Notation)
################################################################################

print "DEMO 2: Namespaced Keys\n"
print "-----------------------"

# User settings
z::kv::set "user.john.email" "john@example.com"
z::kv::set "user.john.theme" "dark"
z::kv::set "user.john.language" "en"

z::kv::set "user.jane.email" "jane@example.com"
z::kv::set "user.jane.theme" "light"
z::kv::set "user.jane.language" "es"

# Database config
z::kv::set "db.host" "localhost"
z::kv::set "db.port" "5432"
z::kv::set "db.name" "myapp"

print "All user keys:"
z::kv::keys "user.*" | while read key; do
  print "  $key = $(z::kv::get $key)"
done

print "\nAll db keys:"
z::kv::keys "db.*" | while read key; do
  print "  $key = $(z::kv::get $key)"
done

print ""

################################################################################
# DEMO 3: Type-Safe Operations
################################################################################

print "DEMO 3: Type-Safe Operations\n"
print "----------------------------"

# Integer operations
z::kv::set_int "counter" 0
print "Initial counter: $(z::kv::get_int counter)"

z::kv::incr "counter"
print "After incr:      $(z::kv::get_int counter)"

z::kv::incr "counter" 5
print "After incr 5:    $(z::kv::get_int counter)"

z::kv::decr "counter" 2
print "After decr 2:    $(z::kv::get_int counter)"

# Boolean operations
z::kv::set_bool "feature.new_ui" true
z::kv::set_bool "feature.beta" false

if z::kv::get_bool "feature.new_ui"; then
  print "✓ New UI feature is enabled"
else
  print "✗ New UI feature is disabled"
fi

if z::kv::get_bool "feature.beta"; then
  print "✓ Beta feature is enabled"
else
  print "✗ Beta feature is disabled"
fi

# Array operations
z::kv::set_array "tags" "zsh" "shell" "framework" "awesome"
print "\nTags stored as array"

local -a tags
z::kv::get_array "tags" tags
print "Retrieved tags: ${(j:, :)tags}"

print ""

################################################################################
# DEMO 4: TTL (Time To Live)
################################################################################

print "DEMO 4: TTL (Expiration)\n"
print "------------------------"

# Set with TTL
z::kv::set "session.abc123" "user_data" --ttl 5
print "Session created with 5 second TTL"

print "TTL remaining: $(z::kv::ttl session.abc123) seconds"

if z::kv::exists "session.abc123"; then
  print "✓ Session exists: $(z::kv::get session.abc123)"
fi

print "Waiting 3 seconds..."
sleep 3

print "TTL remaining: $(z::kv::ttl session.abc123) seconds"

print "Waiting 3 more seconds..."
sleep 3

if z::kv::exists "session.abc123"; then
  print "✓ Session still exists"
else
  print "✗ Session expired (as expected)"
fi

print ""

################################################################################
# DEMO 5: Persistence (Save/Load)
################################################################################

print "DEMO 5: Persistence\n"
print "-------------------"

# Set some data
z::kv::set "persist.test1" "value1"
z::kv::set "persist.test2" "value2"
z::kv::set "persist.test3" "value3"

# Save to file
local db_file="/tmp/z_demo.db"
z::kv::save "$db_file"
print "✓ Saved to $db_file"

# Clear data
z::kv::clear "persist.*"
print "✓ Cleared all persist.* keys"

if ! z::kv::exists "persist.test1"; then
  print "✓ Confirmed: persist.test1 no longer exists"
fi

# Load from file
z::kv::load "$db_file"
print "✓ Loaded from $db_file"

if z::kv::exists "persist.test1"; then
  print "✓ Restored: persist.test1 = $(z::kv::get persist.test1)"
fi

print ""

################################################################################
# DEMO 6: Watch Patterns (Event Integration)
################################################################################

print "DEMO 6: Watch Patterns\n"
print "----------------------"

# Define watch handler
config_changed_handler() {
  local key="$1"
  local value="$2"
  local operation="$3"
  print "  🔔 Config changed: $key = $value [$operation]"
}

# Register watcher
z::kv::watch "config.*" config_changed_handler
print "Watching all config.* keys\n"

# Make changes (will trigger handler)
print "Setting config values:"
z::kv::set "config.timeout" "30"
z::kv::set "config.retries" "3"
z::kv::set "config.debug" "true"

print "\nDeleting config value:"
z::kv::del "config.debug"

# Unwatch
z::kv::unwatch "config.*" config_changed_handler
print "\n✓ Stopped watching config.*"

print ""

################################################################################
# DEMO 7: Bulk Operations
################################################################################

print "DEMO 7: Bulk Operations\n"
print "-----------------------"

# Multiple set
z::kv::mset \
  "bulk.key1" "value1" \
  "bulk.key2" "value2" \
  "bulk.key3" "value3" \
  "bulk.key4" "value4"

print "Set 4 keys with mset"

# Multiple get
print "\nRetrieving with mget:"
z::kv::mget "bulk.key1" "bulk.key2" "bulk.key3" "bulk.key4" | \
  nl -w2 -s'. '

# Clear pattern
z::kv::clear "bulk.*"
print "\n✓ Cleared all bulk.* keys"

print ""

################################################################################
# DEMO 8: Transactions
################################################################################

print "DEMO 8: Transactions\n"
print "--------------------"

# Set initial values
z::kv::set "account.balance" "1000"
z::kv::set "account.transactions" "0"

print "Initial balance: $(z::kv::get account.balance)"
print "Initial transactions: $(z::kv::get account.transactions)"

# Start transaction
z::kv::begin
print "\n✓ Transaction started"

# Make changes
z::kv::set "account.balance" "500"
z::kv::incr "account.transactions"
print "  Updated balance to 500"
print "  Incremented transactions"

# Simulate error and rollback
print "\n⚠️  Error occurred! Rolling back..."
z::kv::rollback

print "After rollback:"
print "  Balance: $(z::kv::get account.balance)"
print "  Transactions: $(z::kv::get account.transactions)"

# Try again with commit
z::kv::begin
z::kv::set "account.balance" "750"
z::kv::incr "account.transactions"
z::kv::commit
print "\n✓ Transaction committed"

print "After commit:"
print "  Balance: $(z::kv::get account.balance)"
print "  Transactions: $(z::kv::get account.transactions)"

print ""

################################################################################
# DEMO 9: Integration with Events & Logging
################################################################################

print "DEMO 9: Integration with Events & Logging\n"
print "------------------------------------------"

# Handler that updates KV store
user_login_handler() {
  local username="$1"

  z::kv::incr "stats.logins.total"
  z::kv::incr "stats.logins.${username}"
  z::kv::set "user.${username}.last_login" "$(date +%s)"

  local total=$(z::kv::get "stats.logins.total")
  local user_logins=$(z::kv::get "stats.logins.${username}")

  z::log::info "User $username logged in (total: $total, user: $user_logins)"
}

# Register event handler
z::event::on "user:login" user_login_handler

# Simulate logins
print "Simulating user logins:\n"
z::event::emit "user:login" "alice"
z::event::emit "user:login" "bob"
z::event::emit "user:login" "alice"
z::event::emit "user:login" "charlie"
z::event::emit "user:login" "alice"

print "\nLogin statistics:"
print "  Total logins: $(z::kv::get stats.logins.total)"
print "  Alice: $(z::kv::get stats.logins.alice)"
print "  Bob: $(z::kv::get stats.logins.bob)"
print "  Charlie: $(z::kv::get stats.logins.charlie)"

print ""

################################################################################
# DEMO 10: Real-World Use Case - Feature Flags
################################################################################

print "DEMO 10: Feature Flags System\n"
print "------------------------------"

# Initialize feature flags
z::kv::set_bool "features.new_dashboard" true
z::kv::set_bool "features.dark_mode" true
z::kv::set_bool "features.beta_api" false
z::kv::set_bool "features.experimental_search" false

# Helper function
is_feature_enabled() {
  z::kv::get_bool "features.$1" 2>/dev/null
}

# Check features
print "Feature Status:"
if is_feature_enabled "new_dashboard"; then
  print "  ✓ New Dashboard: ENABLED"
else
  print "  ✗ New Dashboard: DISABLED"
fi

if is_feature_enabled "dark_mode"; then
  print "  ✓ Dark Mode: ENABLED"
else
  print "  ✗ Dark Mode: DISABLED"
fi

if is_feature_enabled "beta_api"; then
  print "  ✓ Beta API: ENABLED"
else
  print "  ✗ Beta API: DISABLED"
fi

if is_feature_enabled "experimental_search"; then
  print "  ✓ Experimental Search: ENABLED"
else
  print "  ✗ Experimental Search: DISABLED"
fi

# Toggle feature
print "\nToggling dark_mode..."
z::kv::set_bool "features.dark_mode" false

if is_feature_enabled "dark_mode"; then
  print "  ✓ Dark Mode: ENABLED"
else
  print "  ✗ Dark Mode: DISABLED"
fi

print ""

################################################################################
# DEMO 11: Real-World Use Case - Configuration Management
################################################################################

print "DEMO 11: Configuration Management\n"
print "----------------------------------"

# Load configuration
z::kv::set "config.app.name" "ProductionApp"
z::kv::set "config.app.environment" "production"
z::kv::set "config.app.debug" "false"

z::kv::set "config.server.host" "0.0.0.0"
z::kv::set "config.server.port" "8080"
z::kv::set "config.server.workers" "4"

z::kv::set "config.database.host" "db.example.com"
z::kv::set "config.database.port" "5432"
z::kv::set "config.database.name" "production_db"
z::kv::set "config.database.pool_size" "20"

# Display configuration
print "Application Configuration:\n"

print "App Settings:"
z::kv::keys "config.app.*" | while read key; do
  local short_key="${key#config.app.}"
  print "  ${short_key}: $(z::kv::get $key)"
done

print "\nServer Settings:"
z::kv::keys "config.server.*" | while read key; do
  local short_key="${key#config.server.}"
  print "  ${short_key}: $(z::kv::get $key)"
done

print "\nDatabase Settings:"
z::kv::keys "config.database.*" | while read key; do
  local short_key="${key#config.database.}"
  print "  ${short_key}: $(z::kv::get $key)"
done

# Watch for config changes
config_reload_handler() {
  local key="$1"
  local value="$2"
  z::log::warn "Configuration changed: $key = $value (reload required)"
}

z::kv::watch "config.*" config_reload_handler

print "\n✓ Watching for configuration changes"

print ""

################################################################################
# DEMO 12: Real-World Use Case - Caching
################################################################################

print "DEMO 12: Caching System\n"
print "-----------------------"

# Simulate expensive operation
expensive_database_query() {
  local user_id="$1"
  sleep 0.5  # Simulate delay
  echo "User data for ID $user_id from database"
}

get_user_cached() {
  local user_id="$1"
  local cache_key="cache.user.${user_id}"

  if z::kv::exists "$cache_key"; then
    print "  [CACHE HIT] User $user_id"
    z::kv::get "$cache_key"
    return 0
  else
    print "  [CACHE MISS] User $user_id - fetching from database..."
    local data=$(expensive_database_query "$user_id")
    z::kv::set "$cache_key" "$data" --ttl 60
    print "$data"
    return 0
  fi
}

# Test caching
print "First request (cache miss):"
get_user_cached "123"

print "\nSecond request (cache hit):"
get_user_cached "123"

print "\nThird request (cache hit):"
get_user_cached "123"

print ""
################################################################################
# DEMO 13: Real-World Use Case - Rate Limiting
################################################################################

print "DEMO 13: Rate Limiting\n"
print "----------------------"

# Rate limiter
check_rate_limit() {
  local user="$1"
  local limit=3
  local window=10  # seconds

  local key="ratelimit.${user}"
  local count_key="${key}.count"
  local window_key="${key}.window"

  # Check if window expired
  if ! z::kv::exists "$window_key"; then
    # New window
    z::kv::set_int "$count_key" 0
    z::kv::set "$window_key" "active" --ttl "$window"
  fi

  local count=$(z::kv::get_int "$count_key")

  if (( count >= limit )); then
    local ttl=$(z::kv::ttl "$window_key")
    print "  ⛔ Rate limit exceeded for $user (retry in ${ttl}s)"
    return 1
  else
    z::kv::incr "$count_key"
    (( count += 1 ))
    print "  ✓ Request allowed for $user ($count/$limit)"
    return 0
  fi
}

# Test rate limiting
print "Testing rate limiter (3 requests per 10 seconds):\n"

for i in {1..5}; do
  print "Request $i:"
  check_rate_limit "user_alice"
  sleep 0.5
done

print ""

################################################################################
# DEMO 14: Statistics & Introspection
################################################################################

print "DEMO 14: Statistics & Introspection\n"
print "-----------------------------------"

# Show statistics
z::kv::stats

# Show all keys
print "\nAll Keys:"
z::kv::keys | head -20 | while read key; do
  print "  - $key"
done

local total=$(z::kv::size)
if (( total > 20 )); then
  print "  ... and $((total - 20)) more"
fi

print ""

################################################################################
# DEMO 15: Export/Import
################################################################################

print "DEMO 15: Export/Import\n"
print "----------------------"

# Export data
local export_file="/tmp/z_export.txt"
z::kv::export > "$export_file"
print "✓ Exported data to $export_file"

print "\nFirst 10 lines of export:"
head -15 "$export_file"

print ""

################################################################################
# DEMO 16: Auto-Persistence
################################################################################

print "DEMO 16: Auto-Persistence\n"
print "-------------------------"

# Enable auto-persistence
local persist_file="/tmp/z_autopersist.db"
z::kv::enable_persist "$persist_file"
print "✓ Auto-persistence enabled: $persist_file"

# Make changes (automatically saved)
z::kv::set "autopersist.test1" "value1"
z::kv::set "autopersist.test2" "value2"
print "✓ Made changes (automatically persisted)"

# Verify file exists
if [[ -f $persist_file ]]; then
  print "✓ Persist file exists and is up-to-date"
  print "  File size: $(wc -c < $persist_file) bytes"
fi

z::kv::disable_persist
print "✓ Auto-persistence disabled"

print ""

################################################################################
# FINAL SUMMARY
################################################################################

print "========================================="
print "DEMO COMPLETED"
print "=========================================\n"

print "Summary:"
print "--------"
print "✓ Basic CRUD operations"
print "✓ Namespaced keys (dot notation)"
print "✓ Type-safe operations (int, bool, array)"
print "✓ TTL (Time To Live) expiration"
print "✓ Persistence (save/load)"
print "✓ Watch patterns (event integration)"
print "✓ Bulk operations (mset, mget, clear)"
print "✓ Transactions (begin, commit, rollback)"
print "✓ Event & Logging integration"
print "✓ Feature flags system"
print "✓ Configuration management"
print "✓ Caching system"
print "✓ Rate limiting"
print "✓ Statistics & introspection"
print "✓ Export/Import"
print "✓ Auto-persistence"

print "\nFinal Statistics:"
z::kv::stats

print "\n========================================="
print "All demos completed successfully! 🎉"
print "=========================================\n"
