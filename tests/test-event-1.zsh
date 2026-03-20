#!/usr/bin/env zsh

# Source the main zcore framework
source "$(dirname "$0")/zcore.zsh"

################################################################################
# TEST 1: Basic Registration
################################################################################
test_basic_registration() {
  print "Test: Basic registration..."

  test_handler() { print "Handler called"; }

  z::event::on "test:basic" test_handler
  z::event::emit "test:basic"

  z::event::off "test:basic"
  print "✓ Passed\n"
}

################################################################################
# TEST 2: Priority Ordering
################################################################################

# Define handlers OUTSIDE the test function to avoid redefinition issues
_handler_priority_a() {
  _test_order+=(A)
  print "Handler A executed (priority 10)"
}

_handler_priority_b() {
  _test_order+=(B)
  print "Handler B executed (priority 50)"
}

_handler_priority_c() {
  _test_order+=(C)
  print "Handler C executed (priority 100)"
}

test_priority_ordering() {
  print "Test: Priority ordering..."

  # Use global array to track order
  typeset -ga _test_order
  _test_order=()

  # Register with different priorities
  z::event::on "test:priority" _handler_priority_a --priority 10
  z::event::on "test:priority" _handler_priority_b --priority 50
  z::event::on "test:priority" _handler_priority_c --priority 100

  # Emit event
  z::event::emit "test:priority"

  # Check order (highest priority first: C=100, B=50, A=10)
  print "Execution order: ${(j:,:)_test_order}"

  if [[ ${_test_order[1]} == C && ${_test_order[2]} == B && ${_test_order[3]} == A ]]; then
    print "✓ Passed\n"
  else
    print "✗ Failed: Expected C,B,A got ${(j:,:)_test_order}\n"
  fi

  # Cleanup
  z::event::off "test:priority"
  unset _test_order
}

################################################################################
# TEST 3: Once Handler
################################################################################
test_once_handler() {
  print "Test: Once handler..."

  typeset -gi _test_count
  _test_count=0

  _once_handler() {
    (( _test_count += 1 ))
    print "Once handler called (count: $_test_count)"
  }

  z::event::once "test:once" _once_handler

  print "First emit:"
  z::event::emit "test:once"

  print "Second emit:"
  z::event::emit "test:once"

  if (( _test_count == 1 )); then
    print "✓ Passed\n"
  else
    print "✗ Failed: Expected 1 call, got $_test_count\n"
  fi

  unset _test_count
}

################################################################################
# TEST 4: Wildcard Matching
################################################################################
test_wildcard_matching() {
  print "Test: Wildcard matching..."

  typeset -gi _wildcard_count
  _wildcard_count=0

  _wildcard_handler() {
    local event_arg="${1:-no-arg}"
    (( _wildcard_count += 1 ))
    print "Wildcard handler called (count: $_wildcard_count, event: $event_arg)"
  }

  z::event::on "test:wild:*" _wildcard_handler

  print "Emitting test:wild:one"
  z::event::emit "test:wild:one" "arg1"

  print "Emitting test:wild:two"
  z::event::emit "test:wild:two" "arg2"

  print "Emitting test:other (should not match)"
  z::event::emit "test:other" "arg3"

  if (( _wildcard_count == 2 )); then
    print "✓ Passed\n"
  else
    print "✗ Failed: Expected 2 calls, got $_wildcard_count\n"
  fi

  z::event::off "test:wild:*"
  unset _wildcard_count
}

################################################################################
# TEST 5: Multiple Handlers Same Event
################################################################################
test_multiple_handlers_same_event() {
  print "Test: Multiple handlers on same event..."

  typeset -ga _multi_results
  _multi_results=()

  _multi_handler_1() {
    _multi_results+=(handler1)
    print "Handler 1 executed"
  }

  _multi_handler_2() {
    _multi_results+=(handler2)
    print "Handler 2 executed"
  }

  _multi_handler_3() {
    _multi_results+=(handler3)
    print "Handler 3 executed"
  }

  z::event::on "test:multi" _multi_handler_1
  z::event::on "test:multi" _multi_handler_2
  z::event::on "test:multi" _multi_handler_3

  z::event::emit "test:multi"

  if (( ${#_multi_results} == 3 )); then
    print "✓ Passed (${#_multi_results} handlers executed)\n"
  else
    print "✗ Failed: Expected 3 handlers, got ${#_multi_results}\n"
  fi

  z::event::off "test:multi"
  unset _multi_results
}

################################################################################
# TEST 6: Handler with Arguments
################################################################################
test_handler_with_arguments() {
  print "Test: Handler with arguments..."

  typeset -g _received_arg1 _received_arg2

  _arg_handler() {
    _received_arg1="${1:-}"
    _received_arg2="${2:-}"
    print "Received: arg1='$_received_arg1', arg2='$_received_arg2'"
  }

  z::event::on "test:args" _arg_handler
  z::event::emit "test:args" "hello" "world"

  if [[ $_received_arg1 == "hello" && $_received_arg2 == "world" ]]; then
    print "✓ Passed\n"
  else
    print "✗ Failed: Expected 'hello world', got '$_received_arg1 $_received_arg2'\n"
  fi

  z::event::off "test:args"
  unset _received_arg1 _received_arg2
}

################################################################################
# TEST 7: Handler Removal
################################################################################
test_handler_removal() {
  print "Test: Handler removal..."

  typeset -gi _removal_count
  _removal_count=0

  _removal_handler() {
    (( _removal_count += 1 ))
    print "Removal handler called (count: $_removal_count)"
  }

  z::event::on "test:removal" _removal_handler
  print "Before removal:"
  z::event::emit "test:removal"

  local count_before=$_removal_count

  z::event::off "test:removal" _removal_handler
  print "After removal:"
  z::event::emit "test:removal"

  local count_after=$_removal_count

  if (( count_before == 1 && count_after == 1 )); then
    print "✓ Passed (handler removed successfully)\n"
  else
    print "✗ Failed: Before=$count_before, After=$count_after\n"
  fi

  unset _removal_count
}

################################################################################
# TEST 8: Error Handling
################################################################################
test_error_handling() {
  print "Test: Error handling in handlers..."

  typeset -gi _error_handler_called _success_handler_called
  _error_handler_called=0
  _success_handler_called=0

  _failing_handler() {
    (( _error_handler_called = 1 ))
    print "Failing handler called"
    return 1
  }

  _success_handler() {
    (( _success_handler_called = 1 ))
    print "Success handler called"
    return 0
  }

  z::event::on "test:error" _failing_handler
  z::event::on "test:error" _success_handler

  z::event::emit "test:error"

  if (( _error_handler_called == 1 && _success_handler_called == 1 )); then
    print "✓ Passed (both handlers executed despite failure)\n"
  else
    print "✗ Failed: error=$_error_handler_called, success=$_success_handler_called\n"
  fi

  z::event::off "test:error"
  unset _error_handler_called _success_handler_called
}

################################################################################
# TEST 9: Event with No Handlers
################################################################################
test_event_with_no_handlers() {
  print "Test: Event with no handlers..."

  # Should not error, just return 0
  if z::event::emit "test:nonexistent"; then
    print "✓ Passed (no error on unhandled event)\n"
  else
    print "✗ Failed: Error occurred\n"
  fi
}

################################################################################
# TEST 10: Remove All Handlers for Event
################################################################################
test_remove_all_handlers() {
  print "Test: Remove all handlers for event..."

  typeset -gi _count_a _count_b
  _count_a=0
  _count_b=0

  _handler_all_a() { (( _count_a += 1 )); }
  _handler_all_b() { (( _count_b += 1 )); }

  z::event::on "test:remove_all" _handler_all_a
  z::event::on "test:remove_all" _handler_all_b

  z::event::emit "test:remove_all"

  local before_a=$_count_a
  local before_b=$_count_b

  # Remove all handlers (no specific handler name)
  z::event::off "test:remove_all"

  z::event::emit "test:remove_all"

  if (( before_a == 1 && before_b == 1 && _count_a == 1 && _count_b == 1 )); then
    print "✓ Passed (all handlers removed)\n"
  else
    print "✗ Failed: before_a=$before_a, before_b=$before_b, after_a=$_count_a, after_b=$_count_b\n"
  fi

  unset _count_a _count_b
}

################################################################################
# RUN ALL TESTS
################################################################################

print "\n========================================="
print "ZCORE EVENT SYSTEM TEST SUITE"
print "=========================================\n"

# Reset event system before tests
z::event::reset

# Run all tests
test_basic_registration
test_priority_ordering
test_once_handler
test_wildcard_matching
test_multiple_handlers_same_event
test_handler_with_arguments
test_handler_removal
test_error_handling
test_event_with_no_handlers
test_remove_all_handlers

print "========================================="
print "TEST SUITE COMPLETED"
print "=========================================\n"

# Show comprehensive results
print "Event Statistics:"
print "-----------------"
z::event::stats

print "\nEvent History (last 15):"
print "-------------------------"
z::event::history 15

print "\nRegistered Handlers:"
print "--------------------"
z::event::list

print "\n========================================="
print "END OF TEST SUITE"
print "=========================================\n"
