#!/usr/bin/env zsh

source "$(dirname "$0")/zcore.zsh"

print "=== TESTING ID GENERATION DIRECTLY ==="

print "\nInitial counter value: $_zcore_event_handler_id"
print "Counter type: $(typeset -p _zcore_event_handler_id 2>/dev/null || print 'undefined')"

print "\n--- Calling _generate_id directly 3 times ---"

id1=$(z::event::_generate_id)
print "ID 1: $id1"
print "Counter after ID 1: $_zcore_event_handler_id"

id2=$(z::event::_generate_id)
print "ID 2: $id2"
print "Counter after ID 2: $_zcore_event_handler_id"

id3=$(z::event::_generate_id)
print "ID 3: $id3"
print "Counter after ID 3: $_zcore_event_handler_id"

print "\n=== END TEST ==="
