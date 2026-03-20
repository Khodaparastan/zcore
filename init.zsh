#!/usr/bin/env zsh
if [[ -n "${_zcore_init_loaded:-}" ]]; then return 0; fi
setopt PROMPT_SUBST promptpercent
umask 022
zstyle ":plugin:zconvey" greeting "none"
typeset -gx ZCORE_LIBDIR="${ZDOTDIR}"
typeset -gx ZCORE_MODDIR="${ZDOTDIR}/modules"
typeset -gx ZCORE_LOGDIR="${ZDOTDIR}/logs"

z::interactive::_init_log() {
    emulate -L zsh
    setopt localoptions typeset_silent
    z::progress::disable
    __z::log::init_colors
    z::log::set_file "${ZCORE_LOGDIR}/init.log"
    z::log::set_file_level debug
    z::log::set_format "text"
    z::log::set_level "error"
    z::log::set_rotation 1
    z::log::set_max_size $((10 * 1024 * 1024)) # 10MB
    z::log::set_max_files 5
    z::log::enable_buffering 50
    z::log::info "Zsh initialization started" \
        zsh_version "$ZSH_VERSION" \
        zdotdir "$ZDOTDIR" \
        shell_pid "$$"
    z::log::enable_performance_mode
    z::log::enable_buffering 1000
    return 0
}
z::interactive::load_mods() {
    emulate -L zsh
    setopt localoptions typeset_silent

    local -ar modules=(
        "setpath"
        "environment"
        "ziplug"
        "completions"
        "ls-enhancements"
        "python"
        "clipboard"
        "external-tool-integrations"
        "prompt"
        "keybindings"
        "aliases"
        "zoxide"
    )

    local -i loaded_count=0 processed_count=0
    local -i total_modules=${#modules[@]}
    local module full_path

    z::log::info "Loading ${total_modules} configuration modules..."

    for module in "${modules[@]}"; do
        full_path="${ZCORE_MODDIR}/${module}.zsh"

        if [[ ! -f $full_path ]]; then
            z::log::warn "Module file not found: ${module}.zsh"
            ((processed_count++))
            z::progress::show "$processed_count" "$total_modules" "modules"
            continue
        fi

        if z::file::source --global "$full_path"; then
            ((loaded_count++))
            z::log::debug "Module loaded: ${module}.zsh"
        else
            z::log::warn "Failed to load module: ${module}.zsh"
        fi
        ((processed_count++))
        z::progress::show "$processed_count" "$total_modules" "modules"

    done

    z::log::info "Successfully loaded ${loaded_count}/${total_modules} modules."
    return 0
}
z::interactive::load_libs() {
    emulate -L zsh
    setopt localoptions typeset_silent
    source "$ZDOTDIR/zlog.zsh"
    source "$ZDOTDIR/z.zsh"
    source "$ZDOTDIR/zbus.zsh"
    return 0
}
z::interactive::init() {
    emulate -L zsh
    setopt localoptions typeset_silent
    zmodload zsh/datetime
    zmodload zsh/nearcolor
    zmodload zsh/mathfunc
    zmodload zsh/parameter
    z::interactive::load_libs
    z::interactive::_init_log
    z::interactive::load_mods
    return 0
}

z::interactive::cleanup() {
    emulate -L zsh
    setopt localoptions typeset_silent
    unset -f -- z::interactive::init z::interactive::load_mods z::interactive::_init_log z::interactive::cleanup
}

if [[ -o interactive ]]; then
    z::interactive::init || {
        print -r -- "Zsh initialization failed"
        z::interactive::cleanup
        return 1
    }
    z::interactive::cleanup
    z::file::source --global "${ZCORE_MODDIR}/options.zsh" || z::log::warn "Failed to source options module"
    z::log::flush
    z::log::disable_performance_mode
fi

return 0
