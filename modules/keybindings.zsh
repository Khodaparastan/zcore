# keybindings.zsh

_setup_keybindings() {
    emulate -L zsh

    bindkey -v
    typeset -gxi KEYTIMEOUT=${KEYTIMEOUT:-1}

    # Basic emacs-like helpers even in vi-insert
    bindkey '^A' beginning-of-line
    bindkey '^E' end-of-line
    bindkey '^K' kill-line
    bindkey '^U' kill-whole-line
    bindkey '^W' backward-kill-word
    bindkey '^?' backward-delete-char
    bindkey '^H' backward-delete-char
    bindkey '^[^?' backward-kill-word
    bindkey '^[d' kill-word

    # Delete key
    bindkey '^[[3~' delete-char

    # Word navigation
    bindkey '^[[1;5C' forward-word
    bindkey '^[[1;5D' backward-word
    bindkey '^[f' forward-word
    bindkey '^[b' backward-word

    # Completion
    bindkey '^I' expand-or-complete
    bindkey '^[[Z' reverse-menu-complete

    # Vi-mode history navigation
    bindkey -M vicmd 'k' up-line-or-search
    bindkey -M vicmd 'j' down-line-or-search
    bindkey -M vicmd 'gg' beginning-of-buffer-or-history
    bindkey -M vicmd 'G' end-of-buffer-or-history
    bindkey -M vicmd '/' history-incremental-search-forward
    bindkey -M vicmd '?' history-incremental-search-backward

    bindkey -M viins '^A' beginning-of-line
    bindkey -M viins '^E' end-of-line
    bindkey -M viins '^U' kill-whole-line
    bindkey -M viins '^W' backward-kill-word
    bindkey -M viins '^P' up-line-or-search
    bindkey -M viins '^N' down-line-or-search

    # Conditionally autoload and bind znt widgets (from zsh-navigation-tools)
    autoload -Uz znt-history-widget znt-cd-widget znt-kill-widget znt-env-widget znt-aliases-widget 2>/dev/null || true

    if whence -w znt-history-widget >/dev/null 2>&1; then
        zle -N znt-history-widget
        bindkey '^R' znt-history-widget
    fi
    if whence -w znt-cd-widget >/dev/null 2>&1; then
        zle -N znt-cd-widget
        bindkey '^W' znt-cd-widget
    fi
    if whence -w znt-kill-widget >/dev/null 2>&1; then
        zle -N znt-kill-widget
        bindkey '^Q' znt-kill-widget
    fi
    if whence -w znt-env-widget >/dev/null 2>&1; then
        zle -N znt-env-widget
        # Only set if available to avoid conflicting with end-of-line
        bindkey '^[e' znt-env-widget # Alt+e to avoid clobbering ^E
    fi
    if whence -w znt-aliases-widget >/dev/null 2>&1; then
        zle -N znt-aliases-widget
        bindkey '^V' znt-aliases-widget
    fi
}
