#!/usr/bin/env zsh
#
# Keybindings Module
# Configures Zsh Line Editor (ZLE) keybindings for vi mode.
#

# ==============================================================================
# MAIN INITIALIZATION
# ==============================================================================

###
# Public entry point to set up all custom keybindings.
###
z::mod::keybindings::init()
{
  emulate -L zsh
  z::runtime::check_interrupted \
    || return $?
  z::log::info "Initializing keybindings..."

  bindkey -v
  typeset -gxi KEYTIMEOUT=1

  # --- Universal Bindings (emacs-like, available in insert mode) ---
  bindkey '^A' beginning-of-line
  bindkey '^E' end-of-line
  bindkey '^K' kill-line
  bindkey '^U' kill-whole-line
  bindkey '^W' backward-kill-word
  bindkey '^?' backward-delete-char
  bindkey '^H' backward-delete-char
  bindkey '^[[3~' delete-char

  # --- Word Navigation ---
  bindkey '^[[1;5C' forward-word
  bindkey '^[[1;5D' backward-word
  bindkey '^[f' forward-word
  bindkey '^[b' backward-word

  # --- Completion ---
  bindkey '^I' expand-or-complete
  bindkey '^[[Z' reverse-menu-complete

  # --- Vi Mode History Navigation ---
  bindkey -M vicmd 'k' up-line-or-search
  bindkey -M vicmd 'j' down-line-or-search
  bindkey -M vicmd '/' history-incremental-search-forward
  bindkey -M viins '^P' up-line-or-search
  bindkey -M viins '^N' down-line-or-search

  # --- Conditionally bind zsh-navigation-tools widgets ---
  autoload -Uz znt-history-widget znt-cd-widget znt-kill-widget 2> /dev/null \
    || true

  # CORRECTED SYNTAX: Associative array keys should not be in brackets.
  local -A znt_bindings=(
    znt-history-widget
    '^R'
    znt-cd-widget
    '^G'
    znt-kill-widget
    '^Q'
  )

  local widget key
  for widget key in "${(@kv)znt_bindings}"; do
    if whence -w "$widget" > /dev/null 2>&1; then
      zle -N "$widget"
      bindkey "$key" "$widget"
      z::log::debug "Bound znt widget '$widget' to '$key'"
    fi
  done

  z::log::info "Keybindings initialized successfully."
}

# Auto-initialize the module when it is sourced.
if z::func::exists "z::mod::keybindings::init"; then
  z::mod::keybindings::init
fi
