#!/usr/bin/env zsh
#
# Zoxide Integration Module
# Initializes zoxide (smarter cd command) using the standard hook pattern.
#

__z::mod::zoxide::init() {
  emulate -L zsh
  z::exec::from_hook "zoxide" || true
}

if z::probe::func "__z::mod::zoxide::init"; then
  __z::mod::zoxide::init
fi
