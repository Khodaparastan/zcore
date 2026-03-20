#!/usr/bin/env zsh
source ./z.zsh

# Enable debug to see cache operations in standard error
z::log::enable_debug

z::log::info "--- DEMO: Normal Cache Usage ---"
# First call: performs actual lookup, caches result (exit code 0 or 1)
z::cmd::exists "git" && z::log::info "Git found (uncached)"
# Second call: returns immediately from memory
z::cmd::exists "git" && z::log::info "Git found (cached hit)"

z::log::info "\n--- DEMO: Forcing LRU Eviction ---"
# Artificially lower cache size to 5 entries to force rapid eviction
z::config::set cache_max_size 10

# Define 7 commands to overflow the 5-slot cache
cmds=(ls grep cat sed awk tar curl wget python node ruby bun ssh)

# Loop twice to show caching and eviction
for i in {1..2}; do
    z::log::info "--- Loop $i ---"
    for cmd in $cmds; do
        # Watch STDERR. You will see "Cleaned command cache..." 
        # when the cache exceeds 5 items.
        z::cmd::exists "$cmd"
    done
done