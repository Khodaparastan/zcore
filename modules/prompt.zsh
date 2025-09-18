#!/usr/bin/env zsh
#
# Prompt Configuration Module
# Sets up the shell prompt, preferring Starship but with robust fallbacks.
#

# ==============================================================================
# PRIVATE HELPERS
# ==============================================================================

###
# Generates a git status string for use in prompts.
###
z::mod::prompt::_git_info()
{
  emulate -L zsh
  # Check if we're in a git repo. `git rev-parse` is the fastest way.
  command git rev-parse --is-inside-work-tree &> /dev/null \
    || return

  local branch git_status status_color
  branch=$(
    command git symbolic-ref --short HEAD 2> /dev/null \
      || command git rev-parse --short HEAD 2> /dev/null
  )
  git_status=$(command git status --porcelain=v1 2> /dev/null)

  if [[ -n "$git_status" ]]; then
    status_color='%F{yellow}' # Dirty repo
  else
    status_color='%F{green}' # Clean repo
  fi

  printf " %s(%s)%f" "$status_color" "$branch"
}

###
# Tries to initialize the Starship prompt.
###
z::mod::prompt::_setup_starship()
{
  emulate -L zsh
  if ! z::cmd::exists "starship"; then
    return 1
  fi

  z::log::debug "Attempting to initialize Starship prompt..."
  z::exec::eval "$(starship init zsh)" 10 true
}

###
# Sets up a robust, custom fallback prompt if Starship is not used.
###
z::mod::prompt::_setup_fallback()
{
  emulate -L zsh
  setopt PROMPT_SUBST

  # Colors for readability
  local C_CYAN='%F{cyan}'
  local C_BLUE='%F{blue}'
  local C_RESET='%f'
  local C_RED='%F{red}'
  local C_GREEN='%F{green}'

  local prompt_char='❯'
  # Use a different character and color for root
  if ((EUID == 0)); then
    prompt_char='#'
    C_CYAN='%F{red}'
  fi

  PS1="${C_CYAN}%n@%m${C_RESET}:${C_BLUE}%~${C_RESET}\$(z::mod::prompt::_git_info) ${C_GREEN}${prompt_char}${C_RESET} "
  RPS1="%(?..${C_RED}✗ %?${C_RESET} )" # Show exit code on error
  PS2="${C_GREEN}❯${C_RESET} "

  # --- Set Terminal Title ---
  # Use add-zsh-hook for safety if available, otherwise append to array
  autoload -Uz add-zsh-hook 2> /dev/null
  _zcore_update_title()
  {
    print -Pn '\e]0;%n@%m:%~\a'
  }
  if z::func::exists "add-zsh-hook"; then
    add-zsh-hook precmd _zcore_update_title
  elif [[ -z ${(M)precmd_functions:#_zcore_update_title} ]]; then
    precmd_functions+=_zcore_update_title
  fi

  z::log::debug "Configured custom fallback prompt."
  return 0
}

# ==============================================================================
# MAIN INITIALIZATION
# ==============================================================================
z::mod::prompt::init()
{
  emulate -L zsh
  z::runtime::check_interrupted \
    || return $?
  z::log::info "Initializing shell prompt..."

  if z::mod::prompt::_setup_starship; then
    z::log::info "Prompt initialized with Starship."
  else
    z::log::info "Starship not found or failed, using custom fallback prompt."
    z::mod::prompt::_setup_fallback
  fi
}

if z::func::exists "z::mod::prompt::init"; then
  z::mod::prompt::init
fi
