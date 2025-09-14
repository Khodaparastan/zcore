#!/usr/bin/env zsh
#
# Prompt Configuration Module
# Handles prompt setup with starship and fallback configurations
#

# ==============================================================================
# PROMPT SETUP
# ==============================================================================

###
# Sets up the shell prompt with starship or fallback options
###
_setup_prompt() {
    emulate -L zsh

    z::log::debug "Setting up shell prompt..."

    # Try to initialize starship first
    if _setup_starship_prompt; then
        z::log::info "Prompt initialized with starship"
        return 0
    fi

    # Fall back to other prompt options
    if _setup_fallback_prompt; then
        z::log::info "Prompt initialized with fallback"
        return 0
    fi

    z::log::warn "All prompt setup methods failed, using basic prompt"
    _setup_basic_prompt
    return 0
}

###
# Initialize starship prompt safely
###
_setup_starship_prompt() {
    emulate -L zsh

    if ! command -v starship >/dev/null 2>&1; then
        z::log::debug "starship not found, skipping"
        return 1
    fi

    local starship_init_code
    if starship_init_code="$(starship init zsh 2>/dev/null)" && [[ -n "$starship_init_code" ]]; then
        if z::exec::eval "$starship_init_code" 30 true; then
            z::log::debug "Starship prompt initialized successfully"
            return 0
        else
            z::log::warn "Failed to initialize starship prompt"
            return 1
        fi
    else
        z::log::warn "Failed to get starship initialization code"
        return 1
    fi
}

###
# Setup fallback prompt options (oh-my-posh, powerlevel10k, etc.)
###
_setup_fallback_prompt() {
    emulate -L zsh

    # Try oh-my-posh
    if _setup_oh_my_posh; then
        return 0
    fi

    # Try powerlevel10k if available
    if _setup_powerlevel10k; then
        return 0
    fi

    # Try pure prompt
    if _setup_pure_prompt; then
        return 0
    fi

    return 1
}

###
# Initialize oh-my-posh if available
###
_setup_oh_my_posh() {
    emulate -L zsh

    if ! command -v oh-my-posh >/dev/null 2>&1; then
        z::log::debug "oh-my-posh not found, skipping"
        return 1
    fi

    local oh_my_posh_init_code
    if oh_my_posh_init_code="$(oh-my-posh init zsh 2>/dev/null)" && [[ -n "$oh_my_posh_init_code" ]]; then
        if z::exec::eval "$oh_my_posh_init_code" 30 true; then
            z::log::debug "oh-my-posh initialized successfully"
            return 0
        else
            z::log::warn "Failed to initialize oh-my-posh"
            return 1
        fi
    else
        z::log::warn "Failed to get oh-my-posh init code"
        return 1
    fi
}

###
# Initialize powerlevel10k if available
###
_setup_powerlevel10k() {
    emulate -L zsh

    local -a p10k_paths=(
        "${HOME}/.p10k.zsh"
        "${ZDOTDIR:-$HOME}/.p10k.zsh"
        "/usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme"
        "/opt/homebrew/share/powerlevel10k/powerlevel10k.zsh-theme"
    )

    local p10k_path
    for p10k_path in "${p10k_paths[@]}"; do
        if [[ -f "$p10k_path" ]]; then
            if z::path::source "$p10k_path"; then
                z::log::debug "Powerlevel10k loaded from: $p10k_path"

                # Load p10k config if available
                local p10k_config="${ZDOTDIR:-$HOME}/.p10k.zsh"
                if [[ -f "$p10k_config" ]]; then
                    z::path::source "$p10k_config"
                fi

                return 0
            else
                z::log::warn "Failed to load powerlevel10k from: $p10k_path"
            fi
        fi
    done

    z::log::debug "powerlevel10k not found, skipping"
    return 1
}

###
# Initialize pure prompt if available
###
_setup_pure_prompt() {
    emulate -L zsh

    # Check if pure is available in fpath
    if (( ${+functions[prompt_pure_setup]} )); then
        autoload -U promptinit && promptinit
        prompt pure 2>/dev/null && {
            z::log::debug "Pure prompt initialized"
            return 0
        }
    fi

    z::log::debug "pure prompt not available, skipping"
    return 1
}

###
# Setup a comprehensive fallback prompt
###
_setup_enhanced_fallback_prompt() {
    emulate -L zsh

    # Enable prompt substitution
    setopt PROMPT_SUBST

    # Colors (if terminal supports them)
    if [[ -t 1 ]] && (( $(tput colors 2>/dev/null || echo 0) >= 8 )); then
        local reset='%f%b%k'
        local bold='%B'
        local red='%F{red}'
        local green='%F{green}'
        local yellow='%F{yellow}'
        local blue='%F{blue}'
        local magenta='%F{magenta}'
        local cyan='%F{cyan}'
        local white='%F{white}'
    else
        local reset='' bold='' red='' green='' yellow='' blue='' magenta='' cyan='' white=''
    fi

    # Build prompt components
    local user_part="${green}%n${reset}"
    local host_part="${blue}%m${reset}"
    local dir_part="${cyan}%~${reset}"
    local prompt_char="${bold}%#${reset}"
    local time_part="${yellow}%D{%H:%M:%S}${reset}"

    # Git status function (if git is available)
    if command -v git >/dev/null 2>&1; then
        _prompt_git_status() {
            local git_status git_branch
            git_status="$(git status --porcelain 2>/dev/null)" || return
            git_branch="$(git branch --show-current 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)" || return

            local status_color="${green}"
            if [[ -n "$git_status" ]]; then
                status_color="${red}"
            fi

            echo " ${status_color}(${git_branch})${reset}"
        }

        local git_part='$(_prompt_git_status)'
    else
        local git_part=''
    fi

    # Exit code indicator
    local exit_code_part="${red}%(?..(%?%) )${reset}"

    # Assemble the prompt
    export PS1="${time_part} ${exit_code_part}${user_part}@${host_part}:${dir_part}${git_part} ${prompt_char} "
    export PS2="${yellow}> ${reset}"
    export PS3="${yellow}?# ${reset}"
    export PS4="${magenta}+ ${reset}"

    z::log::debug "Enhanced fallback prompt configured"
    return 0
}

###
# Setup basic fallback prompt
###
_setup_basic_prompt() {
    emulate -L zsh

    # Try enhanced fallback first
    if _setup_enhanced_fallback_prompt; then
        return 0
    fi

    # Absolute fallback - minimal prompt
    export PS1='%n@%m:%~%# '
    export PS2='> '
    export PS3='?# '
    export PS4='+ '

    z::log::debug "Basic fallback prompt configured"
    return 0
}

###
# Configure prompt-related shell options
###
_configure_prompt_options() {
    emulate -L zsh

    # Enable prompt substitution for dynamic prompts
    setopt PROMPT_SUBST

    # Enable prompt parameter expansion, command substitution, and arithmetic expansion
    setopt PROMPT_PERCENT

    # Don't print a carriage return just before printing a prompt
    setopt NO_PROMPT_CR

    # Try to correct spelling of commands
    setopt CORRECT

    # Don't correct arguments
    unsetopt CORRECT_ALL

    z::log::debug "Prompt options configured"
}

###
# Setup prompt theme configuration if using manual themes
###
_configure_prompt_theme() {
    emulate -L zsh

    # This function can be used to set up custom prompt themes
    # or load theme configurations

    # Example: Load custom theme files
    local theme_dir="${ZDOTDIR:-$HOME/.config/zsh}/themes"
    if [[ -d "$theme_dir" ]]; then
        local theme_file="${theme_dir}/current.zsh"
        if [[ -f "$theme_file" ]]; then
            z::path::source "$theme_file" && z::log::debug "Custom prompt theme loaded"
        fi
    fi
}

# Initialize prompt when module is loaded
_configure_prompt_options

# Export main function
typeset -f _setup_prompt >/dev/null 2>&1 || {
    z::log::error "Failed to define prompt setup function"
    return 1
}

# Auto-initialize prompt when module is loaded
# _setup_prompt

z::log::debug "Prompt module loaded"
