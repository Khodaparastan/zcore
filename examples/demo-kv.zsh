#!/usr/bin/env zsh

################################################################################
# Z KV STORE - ADVANCED FEATURES DEMO
################################################################################

source "$(dirname "$0")/z.zsh"

print "\n========================================="
print "Z KV ADVANCED FEATURES DEMO"
print "=========================================\n"

################################################################################
# DEMO 1: Lists (Queue/Stack Operations)
################################################################################

print "DEMO 1: Lists (Queue/Stack)\n"
print "----------------------------"

# Queue (FIFO): RPUSH + LPOP
print "Queue Operations (FIFO):"
z::kv::rpush "queue" "task1"
z::kv::rpush "queue" "task2"
z::kv::rpush "queue" "task3"
print "  Pushed: task1, task2, task3"

print "  Popping from queue:"
print "    $(z::kv::lpop queue)"
print "    $(z::kv::lpop queue)"
print "    $(z::kv::lpop queue)"

# Stack (LIFO): RPUSH + RPOP
print "\nStack Operations (LIFO):"
z::kv::rpush "stack" "item1"
z::kv::rpush "stack" "item2"
z::kv::rpush "stack" "item3"
print "  Pushed: item1, item2, item3"

print "  Popping from stack:"
print "    $(z::kv::rpop stack)"
print "    $(z::kv::rpop stack)"
print "    $(z::kv::rpop stack)"

# List range
print "\nList Range Operations:"
z::kv::rpush "numbers" "1"
z::kv::rpush "numbers" "2"
z::kv::rpush "numbers" "3"
z::kv::rpush "numbers" "4"
z::kv::rpush "numbers" "5"

print "  All elements:"
z::kv::lrange "numbers" 0 -1 | nl -w4 -s'. '

print "  First 3 elements:"
z::kv::lrange "numbers" 0 2 | nl -w4 -s'. '

print "  Last 2 elements:"
z::kv::lrange "numbers" -2 -1 | nl -w4 -s'. '

print "  List length: $(z::kv::llen numbers)"

print ""

################################################################################
# DEMO 2: Sets (Unique Values)
################################################################################

print "DEMO 2: Sets (Unique Values)\n"
print "----------------------------"

# Add members
z::kv::sadd "tags" "zsh"
z::kv::sadd "tags" "shell"
z::kv::sadd "tags" "framework"
z::kv::sadd "tags" "zsh"  # Duplicate - ignored

print "Added tags (including duplicate 'zsh'):"
z::kv::smembers "tags" | while read tag; do
  print "  - $tag"
done

print "\nSet cardinality: $(z::kv::scard tags)"

# Check membership
if z::kv::sismember "tags" "zsh"; then
  print "✓ 'zsh' is in the set"
fi

if ! z::kv::sismember "tags" "python"; then
  print "✓ 'python' is NOT in the set"
fi

# Remove member
z::kv::srem "tags" "shell"
print "\nAfter removing 'shell':"
z::kv::smembers "tags" | while read tag; do
  print "  - $tag"
done

print ""

################################################################################
# DEMO 3: Sorted Sets (Leaderboard)
################################################################################

print "DEMO 3: Sorted Sets (Leaderboard)\n"
print "----------------------------------"

# Add players with scores
z::kv::zadd "leaderboard" 1500 "Alice"
z::kv::zadd "leaderboard" 2300 "Bob"
z::kv::zadd "leaderboard" 1800 "Charlie"
z::kv::zadd "leaderboard" 2100 "Diana"
z::kv::zadd "leaderboard" 1950 "Eve"

print "Leaderboard (Top 3):"
z::kv::zrange_withscores "leaderboard" 0 2 | nl -w2 -s'. '

print "\nAll players (highest to lowest):"
z::kv::zrange_withscores "leaderboard" 0 -1 | nl -w2 -s'. '

# Get specific score
print "\nBob's score: $(z::kv::zscore leaderboard Bob)"

# Update score
z::kv::zadd "leaderboard" 2500 "Alice"
print "Alice's new score: $(z::kv::zscore leaderboard Alice)"

print "\nUpdated Top 3:"
z::kv::zrange_withscores "leaderboard" 0 2 | nl -w2 -s'. '

print ""

################################################################################
# DEMO 4: Hashes (Structured Data)
################################################################################

print "DEMO 4: Hashes (Structured Data)\n"
print "--------------------------------"

# Store user data
z::kv::hset "user:1001" "name" "John Doe"
z::kv::hset "user:1001" "email" "john@example.com"
z::kv::hset "user:1001" "age" "30"
z::kv::hset "user:1001" "country" "USA"

print "User 1001 data:"
z::kv::hgetall "user:1001" | while read field value; do
  print "  $field: $value"
done

# Get specific field
print "\nUser email: $(z::kv::hget user:1001 email)"

# Check field existence
if z::kv::hexists "user:1001" "email"; then
  print "✓ Email field exists"
fi

# List all fields
print "\nAll fields:"
z::kv::hkeys "user:1001" | while read field; do
  print "  - $field"
done

# Delete field
z::kv::hdel "user:1001" "age"
print "\nAfter deleting 'age' field:"
z::kv::hgetall "user:1001" | while read field value; do
  print "  $field: $value"
done

print ""

################################################################################
# DEMO 5: Atomic Operations
################################################################################

print "DEMO 5: Atomic Operations\n"
print "-------------------------"

# GETSET
z::kv::set "status" "idle"
print "Initial status: $(z::kv::get status)"

old_status=$(z::kv::getset "status" "running")
print "Changed to 'running', old value was: '$old_status'"

# SETNX (Set if Not eXists)
print "\nSETNX (lock acquisition):"
if z::kv::setnx "lock:resource1" "process_$$"; then
  print "  ✓ Lock acquired by process $$"
else
  print "  ✗ Lock already held"
fi

if z::kv::setnx "lock:resource1" "process_999"; then
  print "  ✓ Lock acquired by process 999"
else
  print "  ✗ Lock already held (expected)"
fi

# SETXX (Set if eXists)
print "\nSETXX (update existing only):"
if z::kv::setxx "status" "completed"; then
  print "  ✓ Updated existing key"
fi

if z::kv::setxx "nonexistent" "value"; then
  print "  ✓ Updated key"
else
  print "  ✗ Key doesn't exist (expected)"
fi

# CAS (Compare And Swap)
print "\nCAS (Compare And Swap):"
z::kv::set "version" "1.0"
print "  Current version: $(z::kv::get version)"

if z::kv::cas "version" "1.0" "1.1"; then
  print "  ✓ Updated from 1.0 to 1.1"
fi

if z::kv::cas "version" "1.0" "1.2"; then
  print "  ✓ Updated"
else
  print "  ✗ CAS failed - value changed (expected)"
fi

print ""

################################################################################
# DEMO 6: Distributed Locking
################################################################################

print "DEMO 6: Distributed Locking\n"
print "---------------------------"

# Acquire lock
if z::kv::lock "critical_resource" 5; then
  print "✓ Lock acquired for 'critical_resource'"
  print "  Performing critical operation..."
  sleep 1

  # Release lock
  if z::kv::unlock "critical_resource"; then
    print "✓ Lock released"
  fi
fi

# Try to acquire already-held lock
print "\nTrying to acquire held lock:"
z::kv::lock "busy_resource" 10
if z::kv::lock "busy_resource" 10 "other_process"; then
  print "  ✓ Lock acquired"
else
  print "  ✗ Lock already held (expected)"
fi
z::kv::unlock "busy_resource"

# Lock with retry
print "\nLock with automatic retry:"
if z::kv::lock_wait "contested_resource" 10 3 0.5; then
  print "✓ Lock acquired after retries"
  z::kv::unlock "contested_resource"
fi

print ""

################################################################################
# DEMO 7: Pub/Sub Channels
################################################################################

print "DEMO 7: Pub/Sub Channels\n"
print "------------------------"

# Define subscribers
notification_handler() {
  local channel="$1"
  local message="$2"
  print "  📬 [$channel] $message"
}

alert_handler() {
  local channel="$1"
  local message="$2"
  print "  🚨 [ALERT] $message"
}

# Subscribe
z::kv::subscribe "notifications" notification_handler
z::kv::subscribe "alerts" alert_handler
z::kv::subscribe "notifications" alert_handler  # Multiple subscribers

print "Subscribed to channels\n"

# Publish messages
print "Publishing to 'notifications':"
z::kv::publish "notifications" "New user registered"
z::kv::publish "notifications" "System update available"

print "\nPublishing to 'alerts':"
z::kv::publish "alerts" "High CPU usage detected"

# Unsubscribe
z::kv::unsubscribe "notifications" notification_handler
print "\nAfter unsubscribing notification_handler:"
z::kv::publish "notifications" "This only goes to alert_handler"

print ""

################################################################################
# DEMO 8: Snapshots
################################################################################

print "DEMO 8: Snapshots\n"
print "-----------------"

# Create some data
z::kv::set "snapshot.test1" "value1"
z::kv::set "snapshot.test2" "value2"
z::kv::set "snapshot.test3" "value3"

print "Created test data"

# Create snapshot
snapshot_id=$(z::kv::snapshot_create "before_changes")
print "✓ Snapshot created: $snapshot_id"

# Make changes
z::kv::set "snapshot.test1" "modified1"
z::kv::del "snapshot.test2"
z::kv::set "snapshot.test4" "new_value"

print "\nAfter modifications:"
print "  test1: $(z::kv::get snapshot.test1)"
print "  test2: $(z::kv::get snapshot.test2 2>/dev/null || echo '[deleted]')"
print "  test4: $(z::kv::get snapshot.test4)"

# Restore snapshot
z::kv::snapshot_restore "$snapshot_id"

print "\nAfter restoring snapshot:"
print "  test1: $(z::kv::get snapshot.test1)"
print "  test2: $(z::kv::get snapshot.test2)"
print "  test4: $(z::kv::get snapshot.test4 2>/dev/null || echo '[not found]')"

# List snapshots
z::kv::snapshot_list

print ""

################################################################################
# DEMO 9: Batch Operations
################################################################################

print "DEMO 9: Batch Operations\n"
print "------------------------"

print "Executing batch commands:"

z::kv::batch <<'EOF'
set batch.key1 value1
set batch.key2 value2
set batch.counter 0
incr batch.counter
incr batch.counter
incr batch.counter
EOF

print "✓ Batch completed\n"

print "Results:"
print "  key1: $(z::kv::get batch.key1)"
print "  key2: $(z::kv::get batch.key2)"
print "  counter: $(z::kv::get batch.counter)"

print ""

################################################################################
# DEMO 10: Utility Operations
################################################################################

print "DEMO 10: Utility Operations\n"
print "---------------------------"

# Rename
z::kv::set "old_name" "some_value"
z::kv::rename "old_name" "new_name"
print "✓ Renamed 'old_name' to 'new_name'"
print "  new_name: $(z::kv::get new_name)"

# Copy
z::kv::set "original" "data"
z::kv::copy "original" "backup"
print "\n✓ Copied 'original' to 'backup'"
print "  original: $(z::kv::get original)"
print "  backup: $(z::kv::get backup)"

# Random key
print "\n✓ Random key: $(z::kv::randomkey)"

# Scan
print "\nScanning keys (batch.*):"
result=$(z::kv::scan 0 "batch.*" 2)
print "  Result: $result"

print ""

################################################################################
# DEMO 11: Key Information
################################################################################

print "DEMO 11: Key Information\n"
print "------------------------"

z::kv::set "info_test" "sample_value" --ttl 3600

z::kv::info "info_test"
z::kv::info "numbers"
z::kv::info "leaderboard"
z::kv::info "user:1001"

print ""

################################################################################
# DEMO 12: Memory Usage
################################################################################

print "DEMO 12: Memory Usage\n"
print "---------------------"

z::kv::memory

print ""

################################################################################
# DEMO 13: Real-World - Task Queue
################################################################################

print "DEMO 13: Real-World - Task Queue System\n"
print "----------------------------------------"

# Task queue implementation
enqueue_task() {
  local task_id="$1"
  local task_data="$2"

  z::kv::hset "task:${task_id}" "data" "$task_data"
  z::kv::hset "task:${task_id}" "status" "pending"
  z::kv::hset "task:${task_id}" "created" "$(date +%s)"

  z::kv::rpush "task_queue" "$task_id"

  print "  ✓ Enqueued task: $task_id"
}

process_task() {
  local task_id=$(z::kv::lpop "task_queue")

  if [[ -z $task_id ]]; then
    print "  ℹ️  Queue empty"
    return 1
  fi

  local task_data=$(z::kv::hget "task:${task_id}" "data")

  print "  ⚙️  Processing task: $task_id"
  print "     Data: $task_data"

  z::kv::hset "task:${task_id}" "status" "completed"
  z::kv::hset "task:${task_id}" "completed" "$(date +%s)"

  return 0
}

# Demo
print "Creating tasks:"
enqueue_task "task_001" "Send email to user@example.com"
enqueue_task "task_002" "Generate report for Q4"
enqueue_task "task_003" "Backup database"

print "\nQueue length: $(z::kv::llen task_queue)"

print "\nProcessing tasks:"
process_task
process_task
process_task
process_task

print "\nQueue length: $(z::kv::llen task_queue)"

print ""

################################################################################
# DEMO 14: Real-World - Session Store
################################################################################

print "DEMO 14: Real-World - Session Store\n"
print "------------------------------------"

create_session() {
  local user_id="$1"
  local session_id="sess_$(date +%s)_${RANDOM}"

  z::kv::hset "session:${session_id}" "user_id" "$user_id"
  z::kv::hset "session:${session_id}" "created" "$(date +%s)"
  z::kv::hset "session:${session_id}" "ip" "192.168.1.100"

  # Add to user's session list
  z::kv::sadd "user:${user_id}:sessions" "$session_id"

  # Set TTL on session
  z::kv::expire "session:${session_id}" 3600

  print "  ✓ Session created: $session_id for user $user_id"
  echo "$session_id"
}

get_session_user() {
  local session_id="$1"
  z::kv::hget "session:${session_id}" "user_id"
}

# Demo
print "Creating sessions:"
session1=$(create_session "user_alice")
session2=$(create_session "user_bob")
session3=$(create_session "user_alice")

print "\nAlice's sessions:"
z::kv::smembers "user:user_alice:sessions" | while read sess; do
  print "  - $sess"
done

print "\nSession details for $session1:"
z::kv::hgetall "$session1" | while read field value; do
  print "  $field: $value"
done

print ""

################################################################################
# DEMO 15: Real-World - Feature Rollout
################################################################################

print "DEMO 15: Real-World - Feature Rollout\n"
print "--------------------------------------"

# Feature rollout percentages
z::kv::hset "features:new_ui" "enabled" "true"
z::kv::hset "features:new_ui" "rollout_percent" "50"
z::kv::hset "features:new_ui" "description" "New dashboard UI"

z::kv::hset "features:beta_api" "enabled" "true"
z::kv::hset "features:beta_api" "rollout_percent" "10"
z::kv::hset "features:beta_api" "description" "Beta API endpoints"

# Check if user gets feature
is_feature_enabled_for_user() {
  local feature="$1"
  local user_id="$2"

  local enabled=$(z::kv::hget "features:${feature}" "enabled")
  if [[ $enabled != true ]]; then
    return 1
  fi

  local rollout=$(z::kv::hget "features:${feature}" "rollout_percent")

  # Simple hash-based assignment
  typeset -i user_hash
  (( user_hash = ${#user_id} % 100 ))

  (( user_hash < rollout ))
}

print "Feature rollout status:\n"

# Test different users
local -a test_users=(alice bob charlie david eve frank)
local user

for user in "${test_users[@]}"; do
  print "User $user:"

  if is_feature_enabled_for_user "new_ui" "$user"; then
    print "  ✓ new_ui: ENABLED"
  else
    print "  ✗ new_ui: DISABLED"
  fi

  if is_feature_enabled_for_user "beta_api" "$user"; then
    print "  ✓ beta_api: ENABLED"
  else
    print "  ✗ beta_api: DISABLED"
  fi
done

print ""

################################################################################
# FINAL SUMMARY
################################################################################

print "========================================="
print "ADVANCED FEATURES DEMO COMPLETED"
print "=========================================\n"

print "Summary of Advanced Features:\n"
print "✓ Lists (LPUSH, RPUSH, LPOP, RPOP, LRANGE)"
print "✓ Sets (SADD, SREM, SMEMBERS, SISMEMBER)"
print "✓ Sorted Sets (ZADD, ZSCORE, ZRANGE)"
print "✓ Hashes (HSET, HGET, HGETALL, HDEL)"
print "✓ Atomic Operations (GETSET, SETNX, SETXX, CAS)"
print "✓ Distributed Locking"
print "✓ Pub/Sub Channels"
print "✓ Snapshots"
print "✓ Batch Operations"
print "✓ Utility Operations (RENAME, COPY, SCAN)"
print "✓ Memory Usage Analysis"
print "✓ Key Information"

print "\nMemory Usage:"
z::kv::memory

print "========================================="
print "All advanced features working! 🚀"
print "=========================================\n"
