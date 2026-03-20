#!/usr/bin/env zsh

###
# Comprehensive test and demonstration script for z::alias::* module
# Tests all public API functions with various scenarios
#
# Usage: ./test_alias_module.zsh
###

# Color output helpers
autoload -U colors && colors
export ZCORE_TEST_MODE=1
source zcore_v2.zsh
print_header() {
  print "\n${fg_bold[cyan]}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${reset_color}"
  print "${fg_bold[cyan]}$1${reset_color}"
  print "${fg_bold[cyan]}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${reset_color}"
}

print_section() {
  print "\n${fg_bold[yellow]}▶ $1${reset_color}"
}

print_success() {
  print "  ${fg_bold[green]}✓${reset_color} $1"
}

print_error() {
  print "  ${fg_bold[red]}✗${reset_color} $1"
}

print_info() {
  print "  ${fg[blue]}ℹ${reset_color} $1"
}

print_command() {
  print "  ${fg[magenta]}\$${reset_color} $1"
}

# Test counters
typeset -i total_tests=0 passed_tests=0 failed_tests=0

run_test() {
  local test_name="$1"
  shift
  (( total_tests += 1 ))

  # Execute the command and capture return code
  local ret
  "$@" &>/dev/null
  ret=$?

  if (( ret == 0 )); then
    (( passed_tests += 1 ))
    print_success "$test_name"
    return 0
  else
    (( failed_tests += 1 ))
    print_error "$test_name"
    return 1
  fi
}


run_test_output() {
  local test_name="$1"
  local expected="$2"
  shift 2
  (( total_tests += 1 ))

  local output
  output=$("$@" 2>&1)

  if [[ $output == *"$expected"* ]]; then
    (( passed_tests += 1 ))
    print_success "$test_name"
    return 0
  else
    (( failed_tests += 1 ))
    print_error "$test_name (expected: '$expected', got: '$output')"
    return 1
  fi
}

# Cleanup function
cleanup() {
  print_section "Cleaning up test artifacts"

  # Remove test aliases
  z::alias::clear --type all &>/dev/null

  # Remove test named directories
  z::alias::dir::unset test_projects &>/dev/null
  z::alias::dir::unset test_config &>/dev/null
  z::alias::dir::unset test_tmp &>/dev/null

  # Remove test files
  rm -f /tmp/test_aliases.txt &>/dev/null
  rm -f /tmp/test_aliases_import.txt &>/dev/null

  # Clear persistence
  z::alias::persist::clear &>/dev/null

  print_success "Cleanup complete"
}

# Trap to ensure cleanup on exit
trap cleanup EXIT INT TERM

###############################################################################
# START TESTS
###############################################################################

print_header "Z::ALIAS MODULE - COMPREHENSIVE TEST & DEMONSTRATION"
print_info "Testing all public API functions with various scenarios"

###############################################################################
# TEST: z::opt::* (Option Parsing)
###############################################################################

print_header "1. OPTION PARSING (z::opt::*)"

print_section "Testing z::opt::get"
test_opt_get() {
  local -A opts
  opts=(-t regular --verbose 1)
  local result
  result=$(z::opt::get opts 't' 'type' 'default')
  [[ $result == "regular" ]]
}
run_test "Get short option value" test_opt_get

test_opt_get_long() {
  local -A opts
  opts=(--type global)
  local result
  result=$(z::opt::get opts 't' 'type' 'default')
  [[ $result == "global" ]]
}
run_test "Get long option value" test_opt_get_long

test_opt_get_default() {
  local -A opts
  local result
  result=$(z::opt::get opts 't' 'type' 'default')
  [[ $result == "default" ]]
}
run_test "Get default when option missing" test_opt_get_default

print_section "Testing z::opt::has"
test_opt_has() {
  local -A opts
  opts=(-f 1 --force 1)
  z::opt::has opts 'f' 'force'
}
run_test "Check option exists (short)" test_opt_has

test_opt_has_missing() {
  local -A opts
  ! z::opt::has opts 'f' 'force'
}
run_test "Check option missing" test_opt_has_missing

print_section "Testing z::opt::parse::force"
test_parse_force() {
  local -A opts
  opts=(-f 1)
  local result
  result=$(z::opt::parse::force opts)
  (( result == 1 ))
}
run_test "Parse force flag present" test_parse_force

test_parse_force_absent() {
  local -A opts
  local result
  result=$(z::opt::parse::force opts)
  (( result == 0 ))
}
run_test "Parse force flag absent" test_parse_force_absent

###############################################################################
# TEST: z::validate::* (Validation)
###############################################################################
print_header "2. VALIDATION (z::validate::*)"

print_section "Testing z::validate::identifier"
run_test "Valid identifier (alphanumeric)" z::validate::identifier "my_alias_123"
run_test "Valid identifier (with hyphen)" z::validate::identifier "my-alias"

# Negative tests need wrapper functions
test_invalid_identifier_empty() { ! z::validate::identifier ""; }
test_invalid_identifier_special() { ! z::validate::identifier "my@alias"; }
run_test "Invalid identifier (empty)" test_invalid_identifier_empty
run_test "Invalid identifier (special chars)" test_invalid_identifier_special

print_section "Testing z::validate::nonempty"
run_test "Non-empty string" z::validate::nonempty "value"
test_empty_string_fails() { ! z::validate::nonempty ""; }
run_test "Empty string fails" test_empty_string_fails

print_section "Testing z::validate::integer"
run_test "Valid positive integer" z::validate::integer "123"
run_test "Valid negative integer" z::validate::integer "-456"
test_invalid_integer_letters() { ! z::validate::integer "abc"; }
test_invalid_integer_float() { ! z::validate::integer "12.34"; }
run_test "Invalid integer (letters)" test_invalid_integer_letters
run_test "Invalid integer (float)" test_invalid_integer_float

print_section "Testing z::validate::integer::range"
run_test "Integer in range" z::validate::integer::range "50" 0 100
test_integer_below_range() { ! z::validate::integer::range "-5" 0 100; }
test_integer_above_range() { ! z::validate::integer::range "150" 0 100; }
run_test "Integer below range" test_integer_below_range
run_test "Integer above range" test_integer_above_range

print_section "Testing z::validate::enum"
run_test "Valid enum value" z::validate::enum "regular|global|suffix" "global"
test_invalid_enum() { ! z::validate::enum "regular|global|suffix" "invalid"; }
run_test "Invalid enum value" test_invalid_enum

print_section "Testing z::validate::boolean"
run_test "Boolean: 1" z::validate::boolean "1"
run_test "Boolean: 0" z::validate::boolean "0"
run_test "Boolean: true" z::validate::boolean "true"
run_test "Boolean: false" z::validate::boolean "false"
run_test "Boolean: yes" z::validate::boolean "yes"
run_test "Boolean: no" z::validate::boolean "no"
test_invalid_boolean() { ! z::validate::boolean "maybe"; }
run_test "Invalid boolean" test_invalid_boolean
###############################################################################
# TEST: z::probe::* (Existence Checks)
###############################################################################

print_header "3. EXISTENCE CHECKS (z::probe::*)"
test_invalid_command() {! z::probe::cmd "nonexistent_command_xyz"}
print_section "Testing z::probe::cmd"
run_test "Command exists (ls)" z::probe::cmd "ls"
run_test "Command exists (zsh)" z::probe::cmd "zsh"
run_test "Command not exists" test_invalid_command


print_section "Testing z::probe::func"
# Create a test function
test_function() { : }
run_test "Function exists" z::probe::func "test_function"
test_none_exist_func() { ! z::probe::func "nonexistent_function_xyz"; }
run_test "Function not exists" test_none_exist_func

print_section "Testing z::probe::builtin"
run_test "Builtin exists (cd)" z::probe::builtin "cd"
run_test "Builtin exists (echo)" z::probe::builtin "echo"
test_none_exist_builtin() { ! z::probe::builtin "notabuiltin"; }
run_test "Builtin not exists" test_none_exist_builtin

print_section "Testing z::probe::var"
TEST_VAR="value"
run_test "Variable exists" z::probe::var "TEST_VAR"
test_none_exist_var() { ! z::probe::var "NONEXISTENT_VAR_XYZ"; }
run_test "Variable not exists" test_none_exist_var

print_section "Testing z::probe::path"
run_test "Path exists (file)" z::probe::path "/etc/hosts" "file"
run_test "Path exists (dir)" z::probe::path "/tmp" "dir"
run_test "Path exists (any)" z::probe::path "/etc" "any"
test_none_exist_path() { ! z::probe::path "/nonexistent/path/xyz"; }
run_test "Path not exists" test_none_exist_path

print_section "Testing z::probe::path::readable"
run_test "Path readable" z::probe::path::readable "/etc/hosts"
test_none_readable_path() { ! z::probe::path::readable "/nonexistent"; }
run_test "Path not readable" test_none_readable_path

print_section "Testing z::probe::module"
run_test "Module exists (git)" z::probe::module "git"
run_test "Module exists (cd builtin)" z::probe::module "cd"

###############################################################################
# TEST: z::alias::* (Alias Management)
###############################################################################

print_header "4. ALIAS MANAGEMENT (z::alias::*)"

print_section "Testing z::alias::set (regular aliases)"
print_command "z::alias::set ll 'ls -lah'"
run_test "Create regular alias" z::alias::set ll 'ls -lah'
run_test "Alias exists after creation" z::probe::alias ll

print_command "z::alias::set la 'ls -A'"
run_test "Create another regular alias" z::alias::set la 'ls -A'

print_section "Testing z::alias::set (global aliases)"
print_command "z::alias::set G 'grep' --global"
run_test "Create global alias" z::alias::set G 'grep' --global
run_test "Global alias exists" z::probe::alias G --type global

print_command "z::alias::set L 'less' --global"
run_test "Create another global alias" z::alias::set L 'less' --global

print_section "Testing z::alias::set (suffix aliases)"
print_command "z::alias::set pdf 'zathura' --suffix"
run_test "Create suffix alias" z::alias::set pdf 'zathura' --suffix
run_test "Suffix alias exists" z::probe::alias pdf --type suffix

print_section "Testing z::alias::get"
print_command "z::alias::get ll"
run_test_output "Get regular alias value" "ls -lah" z::alias::get ll

print_command "z::alias::get G --type global"
run_test_output "Get global alias value" "grep" z::alias::get G --type global

print_section "Testing alias overwrite protection"
print_command "z::alias::set ll 'ls -la' (without --force)"
run_test "Overwrite fails without force" ! z::alias::set ll 'ls -la'

print_command "z::alias::set ll 'ls -la' --force"
run_test "Overwrite succeeds with force" z::alias::set ll 'ls -la' --force
run_test_output "Alias value updated" "ls -la" z::alias::get ll

print_section "Testing z::alias::list"
print_command "z::alias::list"
print_info "Listing all aliases:"
z::alias::list 2>/dev/null | head -5

print_command "z::alias::list 'l*'"
print_info "Listing aliases matching 'l*':"
z::alias::list 'l*' 2>/dev/null

print_command "z::alias::list --type global"
print_info "Listing global aliases:"
z::alias::list --type global 2>/dev/null

print_section "Testing z::alias::info"
print_command "z::alias::info ll"
print_info "Alias information:"
z::alias::info ll 2>/dev/null

print_section "Testing z::alias::stats"
print_command "z::alias::stats"
print_info "Alias statistics:"
z::alias::stats 2>/dev/null

print_section "Testing z::alias::export"
print_command "z::alias::export /tmp/test_aliases.txt"
run_test "Export aliases to file" z::alias::export /tmp/test_aliases.txt
run_test "Export file exists" test -f /tmp/test_aliases.txt
print_info "Exported aliases (first 5 lines):"
head -5 /tmp/test_aliases.txt 2>/dev/null

print_section "Testing z::alias::import"
# Create import test file
cat > /tmp/test_aliases_import.txt <<'EOF'
# Test import file
test_alias1=echo "test 1"
test_alias2=echo "test 2"
global:test_global=echo "global"
suffix:txt=cat
EOF

print_command "z::alias::import /tmp/test_aliases_import.txt --force"
run_test "Import aliases from file" z::alias::import /tmp/test_aliases_import.txt --force
run_test "Imported regular alias exists" z::probe::alias test_alias1
run_test "Imported global alias exists" z::probe::alias test_global --type global
run_test "Imported suffix alias exists" z::probe::alias txt --type suffix

print_section "Testing z::alias::unset"
print_command "z::alias::unset test_alias1"
run_test "Unset regular alias" z::alias::unset test_alias1
run_test "Alias removed" ! z::probe::alias test_alias1

print_command "z::alias::unset test_global --type global"
run_test "Unset global alias" z::alias::unset test_global --type global
run_test "Global alias removed" ! z::probe::alias test_global --type global

print_section "Testing z::alias::clear"
print_command "z::alias::clear --type suffix"
run_test "Clear suffix aliases" z::alias::clear --type suffix
run_test "Suffix aliases cleared" ! z::probe::alias pdf --type suffix

###############################################################################
# TEST: z::alias::dir::* (Named Directories)
###############################################################################

print_header "5. NAMED DIRECTORIES (z::alias::dir::*)"

print_section "Testing z::alias::dir::set"
print_command "z::alias::dir::set test_projects ~/projects"
run_test "Create named directory" z::alias::dir::set test_projects ~/projects
run_test "Named directory exists" z::probe::dir test_projects

print_command "z::alias::dir::set test_config ~/.config"
run_test "Create another named directory" z::alias::dir::set test_config ~/.config

print_command "z::alias::dir::set test_tmp /tmp"
run_test "Create named directory (existing path)" z::alias::dir::set test_tmp /tmp

print_section "Testing z::alias::dir::get"
print_command "z::alias::dir::get test_tmp"
run_test_output "Get named directory path" "/tmp" z::alias::dir::get test_tmp

print_section "Testing z::alias::dir::list"
print_command "z::alias::dir::list"
print_info "Listing named directories:"
z::alias::dir::list 2>/dev/null

print_command "z::alias::dir::list 'test_*'"
print_info "Listing named directories matching 'test_*':"
z::alias::dir::list 'test_*' 2>/dev/null

print_section "Testing named directory overwrite protection"
print_command "z::alias::dir::set test_tmp /var/tmp (without --force)"
run_test "Overwrite fails without force" ! z::alias::dir::set test_tmp /var/tmp

print_command "z::alias::dir::set test_tmp /var/tmp --force"
run_test "Overwrite succeeds with force" z::alias::dir::set test_tmp /var/tmp --force

print_section "Testing z::alias::dir::unset"
print_command "z::alias::dir::unset test_projects"
run_test "Unset named directory" z::alias::dir::unset test_projects
run_test "Named directory removed" ! z::probe::dir test_projects

###############################################################################
# TEST: z::alias::persist::* (Persistence)
###############################################################################

print_header "6. PERSISTENCE (z::alias::persist::*)"

print_section "Setting up test aliases for persistence"
z::alias::set persist_test1 'echo test1' &>/dev/null
z::alias::set persist_test2 'echo test2' --global &>/dev/null
z::alias::dir::set persist_dir /tmp &>/dev/null
print_success "Test aliases created"

print_section "Testing z::alias::persist::save"
print_command "z::alias::persist::save"
run_test "Save aliases to storage" z::alias::persist::save

print_section "Testing z::alias::persist::enable"
print_command "z::alias::persist::enable"
run_test "Enable persistence" z::alias::persist::enable

print_command "z::alias::persist::enable --auto"
run_test "Enable auto-persistence" z::alias::persist::enable --auto

print_section "Testing z::alias::persist::disable"
print_command "z::alias::persist::disable"
run_test "Disable persistence" z::alias::persist::disable

print_section "Simulating session restart"
print_info "Clearing current aliases..."
z::alias::unset persist_test1 &>/dev/null
z::alias::unset persist_test2 --type global &>/dev/null
z::alias::dir::unset persist_dir &>/dev/null
print_success "Aliases cleared"

print_section "Testing z::alias::persist::load"
print_command "z::alias::persist::load --force"
run_test "Load aliases from storage" z::alias::persist::load --force
run_test "Regular alias restored" z::probe::alias persist_test1
run_test "Global alias restored" z::probe::alias persist_test2 --type global
run_test "Named directory restored" z::probe::dir persist_dir

print_section "Testing file-based persistence"
print_command "z::alias::persist::save /tmp/test_persist.db"
run_test "Save to file" z::alias::persist::save /tmp/test_persist.db
run_test "Persistence file exists" test -f /tmp/test_persist.db

# Clear again
z::alias::clear --type all &>/dev/null

print_command "z::alias::persist::load /tmp/test_persist.db --force"
run_test "Load from file" z::alias::persist::load /tmp/test_persist.db --force
run_test "Aliases restored from file" z::probe::alias persist_test1

print_section "Testing z::alias::persist::clear"
print_command "z::alias::persist::clear"
run_test "Clear persistent storage" z::alias::persist::clear

# Clean up persistence file
rm -f /tmp/test_persist.db &>/dev/null

###############################################################################
# TEST: Edge Cases and Error Handling
###############################################################################

print_header "7. EDGE CASES & ERROR HANDLING"

print_section "Testing invalid inputs"
run_test "Empty alias name fails" ! z::alias::set '' 'value'
run_test "Empty alias value fails" ! z::alias::set 'name' ''
run_test "Invalid alias name (special chars)" ! z::alias::set 'my@alias' 'value'
run_test "Invalid alias type" ! z::alias::get 'test' --type invalid
run_test "Get non-existent alias fails" ! z::alias::get nonexistent_alias_xyz
run_test "Unset non-existent alias fails" ! z::alias::unset nonexistent_alias_xyz

print_section "Testing named directory edge cases"
run_test "Empty directory name fails" ! z::alias::dir::set '' '/tmp'
run_test "Empty directory path fails" ! z::alias::dir::set 'name' ''
run_test "Get non-existent directory fails" ! z::alias::dir::get nonexistent_dir_xyz
run_test "Unset non-existent directory fails" ! z::alias::dir::unset nonexistent_dir_xyz

print_section "Testing import edge cases"
run_test "Import non-existent file fails" ! z::alias::import /nonexistent/file.txt

# Create malformed import file
cat > /tmp/test_malformed.txt <<'EOF'
# Valid line
valid_alias=echo "valid"
# Invalid lines
invalid line without equals
=no_name
name_only=
EOF

print_command "z::alias::import /tmp/test_malformed.txt --force"
print_info "Importing file with malformed lines (should handle gracefully)"
z::alias::import /tmp/test_malformed.txt --force 2>/dev/null
run_test "Valid alias imported despite errors" z::probe::alias valid_alias

rm -f /tmp/test_malformed.txt &>/dev/null

###############################################################################
# TEST: Integration Scenarios
###############################################################################

print_header "8. INTEGRATION SCENARIOS"

print_section "Scenario: Developer workflow"
print_info "Setting up development environment aliases..."

print_command "z::alias::set gst 'git status'"
z::alias::set gst 'git status' &>/dev/null

print_command "z::alias::set gco 'git checkout'"
z::alias::set gco 'git checkout' &>/dev/null

print_command "z::alias::set gp 'git push'"
z::alias::set gp 'git push' &>/dev/null

print_command "z::alias::dir::set proj ~/projects"
z::alias::dir::set proj ~/projects &>/dev/null

print_command "z::alias::persist::save"
z::alias::persist::save &>/dev/null

print_success "Development environment configured"

print_section "Scenario: Exporting for team sharing"
print_command "z::alias::export /tmp/team_aliases.txt"
z::alias::export /tmp/team_aliases.txt &>/dev/null
print_success "Aliases exported for team"
print_info "Team members can import with: z::alias::import /tmp/team_aliases.txt"

print_section "Scenario: Cleaning up old aliases"
print_command "z::alias::list 'g*'"
print_info "Found git-related aliases:"
z::alias::list 'g*' 2>/dev/null | head -3

print_command "z::alias::clear --type regular"
print_info "Clearing regular aliases (keeping global/suffix)..."
z::alias::clear --type regular &>/dev/null
print_success "Regular aliases cleared"

###############################################################################
# TEST: Cache Performance
###############################################################################

print_header "9. CACHE PERFORMANCE"

print_section "Testing probe cache"
print_command "z::probe::cache::stats"
print_info "Cache statistics:"
z::probe::cache::stats 2>/dev/null

print_section "Cache hit performance test"
print_info "Testing 100 repeated command existence checks..."
typeset -i i
typeset -F start_time end_time elapsed
start_time=$SECONDS
for (( i = 0; i < 100; i++ )); do
  z::probe::cmd ls &>/dev/null
done
end_time=$SECONDS
elapsed=$((end_time - start_time))
print_success "100 cached checks completed in ${elapsed}s"

print_command "z::probe::cache::clear"
z::probe::cache::clear &>/dev/null
print_success "Cache cleared"

###############################################################################
# FINAL RESULTS
###############################################################################

print_header "TEST RESULTS SUMMARY"

typeset -i pass_rate
if (( total_tests > 0 )); then
  (( pass_rate = (passed_tests * 100) / total_tests ))
else
  (( pass_rate = 0 ))
fi

print ""
print "  Total Tests:  ${fg_bold[cyan]}${total_tests}${reset_color}"
print "  Passed:       ${fg_bold[green]}${passed_tests}${reset_color}"
print "  Failed:       ${fg_bold[red]}${failed_tests}${reset_color}"
print "  Pass Rate:    ${fg_bold[yellow]}${pass_rate}%${reset_color}"
print ""

if (( failed_tests == 0 )); then
  print "${fg_bold[green]}🎉 ALL TESTS PASSED! 🎉${reset_color}"
  exit 0
else
  print "${fg_bold[red]}⚠️  SOME TESTS FAILED ⚠️${reset_color}"
  exit 1
fi
