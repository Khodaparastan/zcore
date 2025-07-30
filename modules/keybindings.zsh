_setup_keybindings() {
  bindkey -v
  typeset -gxi KEYTIMEOUT=1

  bindkey '^A' beginning-of-line
  bindkey '^E' end-of-line
  bindkey '^K' kill-line
  bindkey '^U' kill-whole-line
  bindkey '^W' backward-kill-word

  bindkey '^?' backward-delete-char
  bindkey '^H' backward-delete-char
  bindkey '^[[3~' delete-char
  bindkey '\e^?' backward-kill-word
  bindkey '\ed' kill-word

  bindkey '^[[1;5C' forward-word
  bindkey '^[[1;5D' backward-word
  bindkey '\ef' forward-word
  bindkey '\eb' backward-word

  bindkey '^I' expand-or-complete
  bindkey '^[[Z' reverse-menu-complete

  bindkey -M vicmd 'k' up-line-or-search
  bindkey -M vicmd 'j' down-line-or-search
  bindkey -M vicmd 'gg' beginning-of-buffer-or-history
  bindkey -M vicmd 'G' end-of-buffer-or-history
  bindkey -M vicmd '/' history-incremental-search-backward
  bindkey -M vicmd '?' history-incremental-search-forward

  bindkey -M viins '^A' beginning-of-line
  bindkey -M viins '^E' end-of-line
  bindkey -M viins '^U' kill-whole-line
  bindkey -M viins '^W' backward-kill-word
  bindkey -M viins '^R' znt-history-widget
  bindkey -M viins '^P' up-line-or-search
  bindkey -M viins '^N' down-line-or-search

  autoload znt-history-widget
  zle -N znt-history-widget
  bindkey "^R" znt-history-widget
  zle -N znt-cd-widget
  bindkey "^W" znt-cd-widget
  zle -N znt-kill-widget
  bindkey "^Q" znt-kill-widget
  zle -N znt-env-widget
  bindkey "^E" znt-env-widget
  zle -N znt-aliases-widget
  bindkey "^V" znt-aliases-widget
}
