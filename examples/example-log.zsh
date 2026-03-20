#!/usr/bin/env zsh
source $ZDOTDIR/v3/z3.zsh || {
  echo "Failed to load z.zsh"
  exit 1
}

# 1. Standard Logging
z::log::info "Starting backup job..."
z::log::warn "Low disk space detected on /vol/backup (15% remaining)"

# 2. Progress Bar Integration
files_to_process=50
z::log::info "Processing $files_to_process assets..."

for ((i = 1; i <= files_to_process; i++)); do
  # Simulate work
  sleep 0.02
  # Update progress bar (automatically throttled by Z for performance)
  z::ui::progress::show "$i" "$files_to_process" "assets archived"
done

# 3. Toggling Debug Mode dynamically
z::log::debug "This message will NOT appear (default level is info)"

z::log::info "Enabling verbose debug mode for complex operation..."
z::log::enable_debug

z::log::debug "Connecting to remote storage endpoint: s3://bucket-name"
z::log::debug "Authentication token: xy78***********"

# Simulate an error
if ! false; then
  z::log::error "Connection failed to remote storage"
  # z::runtime::die "Cannot continue without storage" 10
else
  z::log::info "Backup complete."
fi
