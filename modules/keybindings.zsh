#!/usr/bin/env zsh
#
# Keybindings Module
# Configures Zsh Line Editor (ZLE) keybindings for vi mode with full CSI u support.
#
# ==============================================================================
# CUSTOM ZLE WIDGETS
# ==============================================================================

# Accept line and execute immediately
z::zle::accept-and-execute() {
  zle accept-line
}
zle -N z::zle::accept-and-execute

# Accept line and keep in buffer (for editing)
z::zle::accept-and-hold() {
  BUFFER="$BUFFER"
  zle accept-line
}
zle -N z::zle::accept-and-hold

# Clear screen but keep current line
z::zle::clear-screen-soft() {
  zle clear-screen
  zle reset-prompt
}
zle -N z::zle::clear-screen-soft

# Kill line and yank to clipboard (if available)
z::zle::kill-line-to-clipboard() {
  if (( $+commands[pbcopy] )); then
    echo -n "$BUFFER" | pbcopy
  elif (( $+commands[xclip] )); then
    echo -n "$BUFFER" | xclip -selection clipboard
  elif (( $+commands[wl-copy] )); then
    echo -n "$BUFFER" | wl-copy
  fi
  zle kill-whole-line
}
zle -N z::zle::kill-line-to-clipboard

# Accept line and add to directory stack
z::zle::accept-and-infer-next() {
  local dir="${${(z)BUFFER}[2]}"
  [[ -d "$dir" ]] && pushd -q "$dir"
  zle accept-line
}
zle -N z::zle::accept-and-infer-next

autoload -Uz edit-command-line
zle -N edit-command-line

# ==============================================================================
# MAIN INITIALIZATION
# ==============================================================================

__z::mod::keybindings::init()
{
  emulate -L zsh
  
  z::log::info "Initializing keybindings with full CSI u support..."

  # Enable vi mode
  bindkey -v
  typeset -gi KEYTIMEOUT=1

  # ==============================================================================
  # BASIC EDITING (Emacs-style, available everywhere)
  # ==============================================================================
  bindkey '^A' beginning-of-line
  bindkey '^E' end-of-line
  bindkey '^K' kill-line
  bindkey '^U' kill-whole-line
  bindkey '^W' backward-kill-word
  bindkey '^Y' yank

  # ==============================================================================
  # BACKSPACE / DELETE
  # ==============================================================================
  bindkey '^?' backward-delete-char              # Backspace
  bindkey '^H' backward-delete-char              # Ctrl+H
  bindkey '^[[3~' delete-char                    # Delete
  bindkey '^[[127;2u' backward-delete-char       # Shift+Backspace (CSI u)
  bindkey '^[[3;2~' delete-char                  # Shift+Delete
  bindkey '^[[127;5u' backward-kill-word         # Ctrl+Backspace (CSI u)
  bindkey '^[[3;5~' kill-word                    # Ctrl+Delete

  # ==============================================================================
  # WORD NAVIGATION (Standard + CSI u enhanced)
  # ==============================================================================
  # Standard sequences
  bindkey '^[[1;5C' forward-word                 # Ctrl+Right
  bindkey '^[[1;5D' backward-word                # Ctrl+Left
  bindkey '^[f' forward-word                     # Alt+F
  bindkey '^[b' backward-word                    # Alt+B

  # CSI u enhanced (more reliable in WezTerm)
  bindkey '^[[67;5u' forward-word                # Ctrl+C (as motion)
  bindkey '^[[66;5u' backward-word               # Ctrl+B (as motion)

  # Shift+Arrow for selection-style movement (prepare for visual mode)
  bindkey '^[[1;2C' forward-word                 # Shift+Right
  bindkey '^[[1;2D' backward-word                # Shift+Left

  # ==============================================================================
  # LINE NAVIGATION
  # ==============================================================================
  bindkey '^[[H' beginning-of-line               # Home
  bindkey '^[[F' end-of-line                     # End
  bindkey '^[[1~' beginning-of-line              # Home (alternate)
  bindkey '^[[4~' end-of-line                    # End (alternate)

  # ==============================================================================
  # COMPLETION
  # ==============================================================================
  bindkey '^I' expand-or-complete                # Tab
  bindkey '^[[Z' reverse-menu-complete           # Shift+Tab
  bindkey '^[[9;2u' reverse-menu-complete        # Shift+Tab (CSI u)

  # ==============================================================================
  # HISTORY (Standard + CSI u enhanced)
  # ==============================================================================
  bindkey '^P' up-line-or-search                 # Ctrl+P
  bindkey '^N' down-line-or-search               # Ctrl+N
  bindkey '^[[A' up-line-or-search               # Up arrow
  bindkey '^[[B' down-line-or-search             # Down arrow

  # Vi mode history in command mode
  # bindkey -M vicmd 'k' up-line-or-search
  # bindkey -M vicmd 'j' down-line-or-search
  # bindkey -M vicmd '/' history-incremental-search-forward
  # bindkey -M vicmd '?' history-incremental-search-backward

  # ==============================================================================
  # ACCEPT / EXECUTE (CSI u enhanced)
  # ==============================================================================
  bindkey '^M' accept-line                       # Enter
  bindkey '^J' accept-line                       # Ctrl+J
  bindkey '^[[13;2u' z::zle::accept-and-hold     # Shift+Enter (CSI u)
  bindkey '^[[13;5u' z::zle::accept-and-execute  # Ctrl+Enter (CSI u)

  # ==============================================================================
  # SCREEN / CLEAR
  # ==============================================================================
  bindkey '^L' z::zle::clear-screen-soft         # Ctrl+L

  # ==============================================================================
  # ADVANCED EDITING (CSI u exclusive)
  # ==============================================================================
  # Ctrl+; - Edit command in $EDITOR
  bindkey '^[[59;5u' edit-command-line

  # Ctrl+, - Undo
  bindkey '^[[44;5u' undo

  # Ctrl+. - Redo
  bindkey '^[[46;5u' redo

  # Ctrl+/ - Undo (alternative)
  bindkey '^[[47;5u' undo

  # Ctrl+Shift+K - Kill line to clipboard
  bindkey '^[[75;6u' z::zle::kill-line-to-clipboard

  # Alt+. - Insert last argument
  bindkey '^[.' insert-last-word

  # ==============================================================================
  # SPECIAL FUNCTIONS
  # ==============================================================================
  # Ctrl+Space - Set mark (for visual selection)
  bindkey '^@' set-mark-command
  bindkey '^ ' set-mark-command

  # Ctrl+X Ctrl+E - Edit command line in editor
  bindkey '^X^E' edit-command-line

  # Ctrl+X Ctrl+U - Undo
  bindkey '^X^U' undo

  # ==============================================================================
  # ZSH NAVIGATION TOOLS (if available)
  # ==============================================================================
  # autoload -Uz znt-history-widget znt-cd-widget znt-kill-widget 2>/dev/null || true

  # local -A znt_bindings=(
  #   znt-history-widget '^R'      # Ctrl+R - History search
  #   znt-cd-widget      '^G'      # Ctrl+G - Directory navigation
  #   znt-kill-widget    '^Q'      # Ctrl+Q - Process kill menu
  # )
  #
  # local widget key
  # for widget key in "${(@kv)znt_bindings}"; do
  #   if (( ${+widgets[$widget]} )); then
  #     bindkey "$key" "$widget"
  #     z::log::debug "Bound znt widget '$widget' to '$key'"
  #   elif (( ${+functions[$widget]} )); then
  #     zle -N "$widget"
  #     bindkey "$key" "$widget"
  #     z::log::debug "Registered and bound znt widget '$widget' to '$key'"
  #   fi
  # done

  # ==============================================================================
  # FZF INTEGRATION (if available)
  # ==============================================================================
  # if (( ${+commands[fzf]} )); then
  #   # Ctrl+T - File finder
  #   if (( ${+widgets[fzf-file-widget]} )); then
  #     bindkey '^T' fzf-file-widget
  #     z::log::debug "Bound fzf-file-widget to ^T"
  #   fi
  #
  #   # Alt+C - Directory finder
  #   if (( ${+widgets[fzf-cd-widget]} )); then
  #     bindkey '^[c' fzf-cd-widget
  #     z::log::debug "Bound fzf-cd-widget to Alt+C"
  #   fi
  # fi

  z::log::info "Keybindings initialized successfully (CSI u enabled)."
}

# ==============================================================================
# AUTO-INITIALIZE
# ==============================================================================
if z::probe::func "__z::mod::keybindings::init"; then
  __z::mod::keybindings::init
fi
