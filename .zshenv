typeset -gx XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
typeset -gx XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
typeset -gx XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
typeset -gx XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
typeset -gx ZDOTDIR="${ZDOTDIR:-${XDG_CONFIG_HOME:-$HOME/.config}/zsh}"
typeset -gx ZCORE_LIBDIR="${ZDOTDIR}"
typeset -gx ZCORE_MODDIR="${ZDOTDIR}/modules"
zstyle ":plugin:zconvey" greeting "none"
typeset -gx ZCORE_BOOTSTRAP_QUIET=true
typeset -gx EDITOR=nvim
