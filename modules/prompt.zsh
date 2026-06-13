#!/usr/bin/env zsh
#
# Prompt Configuration Module
# Prefers Starship; falls back to a robust custom prompt.
#

# ==============================================================================
# PRIVATE HELPERS
# ==============================================================================

###
# Generate a git status string for the fallback prompt.
###
__z::mod::prompt::git_info() {
  emulate -L zsh
  command git rev-parse --is-inside-work-tree &>/dev/null || return

  local branch git_status status_color
  branch=$(command git symbolic-ref --short HEAD 2>/dev/null \
        || command git rev-parse  --short HEAD 2>/dev/null)
  git_status=$(command git status --porcelain=v1 2>/dev/null)

  if [[ -n "$git_status" ]]; then
    status_color='%F{yellow}'
  else
    status_color='%F{green}'
  fi
  printf " %s(%s)%f" "$status_color" "$branch"
}

###
# Try to initialize Starship.  Output cached on disk to avoid `starship init`
# subshell on every shell start.
###
__z::mod::prompt::setup_starship() {
  emulate -L zsh
  z::probe::cmd "starship" || return 1

  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/starship-init.zsh"
  if [[ ! -s "$cache" || "$(command -v starship)" -nt "$cache" ]]; then
    command mkdir -p -- "${cache:h}" 2>/dev/null
    starship init zsh > "$cache" 2>/dev/null || return 1
  fi
  z::file::source --global "$cache"
}

###
# Configure a robust, custom fallback prompt.
###
__z::mod::prompt::setup_fallback() {
  emulate -L zsh
  setopt PROMPT_SUBST

  local C_CYAN='%F{cyan}' C_BLUE='%F{blue}' C_RESET='%f'
  local C_RED='%F{red}'   C_GREEN='%F{green}'
  local prompt_char='❯'

  if (( EUID == 0 )); then
    prompt_char='#'
    C_CYAN='%F{red}'
  fi

  PS1="${C_CYAN}%n@%m${C_RESET}:${C_BLUE}%~${C_RESET}\$(__z::mod::prompt::git_info) ${C_GREEN}${prompt_char}${C_RESET} "
  RPS1="%(?..${C_RED}✗ %?${C_RESET} )"
  PS2="${C_GREEN}❯${C_RESET} "

  autoload -Uz add-zsh-hook 2>/dev/null
  _z_update_title() { print -Pn '\e]0;%n@%m:%~\a'; }

  if z::probe::func "add-zsh-hook"; then
    add-zsh-hook -D precmd _z_update_title 2>/dev/null
    add-zsh-hook    precmd _z_update_title
  elif [[ -z ${(M)precmd_functions:#_z_update_title} ]]; then
    precmd_functions+=_z_update_title
  fi

  z::log::debug "Configured custom fallback prompt."
  return 0
}

# ==============================================================================
# MAIN INITIALIZATION
# ==============================================================================

__z::mod::prompt::init() {
  emulate -L zsh

  z::log::info "Initializing shell prompt..."

  if __z::mod::prompt::setup_starship; then
    z::log::info "Prompt initialized with Starship."
  else
    z::log::info "Starship not found or failed, using custom fallback prompt."
    __z::mod::prompt::setup_fallback
  fi
}

if z::probe::func "__z::mod::prompt::init"; then
  __z::mod::prompt::init
fi
