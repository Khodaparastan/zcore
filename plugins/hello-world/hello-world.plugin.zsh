#!/usr/bin/env zsh

# Entry point
hello_world_init()
{
  z::log::info "Hello World plugin initialized!"
  return 0
}

# Public API
hello::greet()
{
  local name="${1:-World}"
  print "Hello, $name!"
  return 0
}
