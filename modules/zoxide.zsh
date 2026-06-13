#!/usr/bin/env zsh
#
# Zoxide Integration Module
# Initializes zoxide (smarter cd command) using the standard hook pattern.
#

z::exec::from_hook "zoxide" || true
