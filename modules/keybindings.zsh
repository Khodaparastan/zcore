#!/usr/bin/env zsh
#
# Keybindings Module
# Configures Zsh Line Editor (ZLE) keybindings for vi mode with full CSI u support.
#

# ==============================================================================
# CUSTOM ZLE WIDGETS
# ==============================================================================

# Accept line and execute immediately (alias for clarity in bindings)
z::zle::accept-and-execute() { zle accept-line; }
zle -N z::zle::accept-and-execute

# Clear screen but keep current line/prompt
z::zle::clear-screen-soft() {
  zle clear-screen
  zle reset-prompt
}
zle -N z::zle::clear-screen-soft

# Kill the buffer and copy it to the system clipboard if possible
z::zle::kill-line-to-clipboard() {
  emulate -L zsh
  local cmd
  for cmd in pbcopy 'xclip -selection clipboard' wl-copy; do
    (( ${+commands[${cmd%% *}]} )) || continue
    print -rn -- "$BUFFER" | eval "$cmd"
    break
  done
  zle kill-whole-line
}
zle -N z::zle::kill-line-to-clipboard

# Accept current line and pushd to the second token if it's a directory
z::zle::accept-and-infer-next() {
  local dir="${${(z)BUFFER}[2]}"
  [[ -d "$dir" ]] && pushd -q "$dir"
  zle accept-line
}
zle -N z::zle::accept-and-infer-next

autoload -Uz edit-command-line accept-and-hold
zle -N edit-command-line
zle -N accept-and-hold

# ==============================================================================
# MAIN INITIALIZATION
# ==============================================================================

__z::mod::keybindings::init() {
  emulate -L zsh

  z::log::info "Initializing keybindings with full CSI u support..."

  bindkey -v
  typeset -gi KEYTIMEOUT=1

  # ── Basic editing (emacs-style, available everywhere) ───────────────────
  bindkey '^A' beginning-of-line
  bindkey '^E' end-of-line
  bindkey '^K' kill-line
  bindkey '^U' kill-whole-line
  bindkey '^W' backward-kill-word
  bindkey '^Y' yank

  # ── Backspace / delete ──────────────────────────────────────────────────
  bindkey '^?'        backward-delete-char       # Backspace
  bindkey '^H'        backward-delete-char       # Ctrl+H
  bindkey '^[[3~'     delete-char                # Delete
  bindkey '^[[127;2u' backward-delete-char       # Shift+Backspace (CSI u)
  bindkey '^[[3;2~'   delete-char                # Shift+Delete
  bindkey '^[[127;5u' backward-kill-word         # Ctrl+Backspace (CSI u)
  bindkey '^[[3;5~'   kill-word                  # Ctrl+Delete

  # ── Interrupt (must beat vi-mode self-insert and CSI-u motion binds) ───
  bindkey -M viins '^C' send-break
  bindkey -M vicmd '^C' send-break
  bindkey -M viins '^[[67;5u' send-break  # CSI-u Ctrl+C
  bindkey -M vicmd '^[[67;5u' send-break
  bindkey '^[[67;5u' send-break

  # ── Word navigation ─────────────────────────────────────────────────────
  bindkey '^[[1;5C'  forward-word                # Ctrl+Right
  bindkey '^[[1;5D'  backward-word               # Ctrl+Left
  bindkey '^[f'      forward-word                # Alt+F
  bindkey '^[b'      backward-word               # Alt+B
  bindkey '^[[66;5u' backward-word               # Ctrl+B as motion (CSI u)
  bindkey '^[[1;2C'  forward-word                # Shift+Right
  bindkey '^[[1;2D'  backward-word               # Shift+Left

  # ── Line navigation ─────────────────────────────────────────────────────
  bindkey '^[[H'  beginning-of-line              # Home
  bindkey '^[[F'  end-of-line                    # End
  bindkey '^[[1~' beginning-of-line
  bindkey '^[[4~' end-of-line

  # ── Completion ──────────────────────────────────────────────────────────
  bindkey '^I'       expand-or-complete          # Tab
  bindkey '^[[Z'     reverse-menu-complete       # Shift+Tab
  bindkey '^[[9;2u'  reverse-menu-complete       # Shift+Tab (CSI u)

  # ── History ─────────────────────────────────────────────────────────────
  bindkey '^P'    up-line-or-search
  bindkey '^N'    down-line-or-search
  bindkey '^[[A'  up-line-or-search
  bindkey '^[[B'  down-line-or-search

  # ── Accept / execute ────────────────────────────────────────────────────
  bindkey '^M' accept-line                       # Enter
  bindkey '^J' accept-line                       # Ctrl+J
  bindkey '^[[13;2u' accept-and-hold             # Shift+Enter (CSI u)
  bindkey '^[[13;5u' z::zle::accept-and-execute  # Ctrl+Enter (CSI u)

  # ── Screen / clear ──────────────────────────────────────────────────────
  bindkey '^L' z::zle::clear-screen-soft

  # ── Advanced editing (CSI u exclusive) ──────────────────────────────────
  bindkey '^[[59;5u' edit-command-line           # Ctrl+;
  bindkey '^[[44;5u' undo                        # Ctrl+,
  bindkey '^[[46;5u' redo                        # Ctrl+.
  bindkey '^[[47;5u' undo                        # Ctrl+/
  bindkey '^[[75;6u' z::zle::kill-line-to-clipboard  # Ctrl+Shift+K
  bindkey '^[.'      insert-last-word            # Alt+.

  # ── Special functions ───────────────────────────────────────────────────
  bindkey '^@' set-mark-command
  bindkey '^ ' set-mark-command
  bindkey '^X^E' edit-command-line
  bindkey '^X^U' undo

  z::log::info "Keybindings initialized successfully (CSI u enabled)."
}

if z::probe::func "__z::mod::keybindings::init"; then
  __z::mod::keybindings::init
fi
