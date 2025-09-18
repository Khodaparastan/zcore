#!/usr/bin/env zsh
#
# Path Construction Module
# Builds and de-duplicates the PATH and FPATH environment variables.
#

# ==============================================================================
# MAIN INITIALIZATION
# ==============================================================================
z::mod::path_setup::init()
{
  emulate -L zsh
  z::runtime::check_interrupted \
    || return $?
  z::log::info "Building PATH and FPATH..."

  # Use typeset -U to automatically handle uniqueness while preserving order.
  typeset -gU path fpath

  # --- PATH Candidates (in order of precedence) ---
  local -a path_candidates=(
    # User-specific bins
    "$HOME/.local/bin"
    "$HOME/bin"
    # Language toolchains
    "${GOBIN:-$HOME/go/bin}"
    "${CARGO_HOME:-$HOME/.cargo}/bin"
    "${NPM_CONFIG_PREFIX:-$HOME/.npm-global}/bin"
    "${BUN_INSTALL:-$HOME/.bun}/bin"
    # Homebrew (Apple Silicon and Intel/Linux)
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
    "${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/bin}"
    "${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/sbin}"
    # System paths
    "/usr/local/bin"
    "/usr/bin"
    "/bin"
    "/usr/local/sbin"
    "/usr/sbin"
    "/sbin"
  )

  # --- FPATH Candidates (for Zsh functions/completions) ---
  local zsh_version="${ZSH_VERSION%.*}"
  local -a fpath_candidates=(
    # Custom local functions
    "${ZDOTDIR:-$HOME/.config/zsh}/functions"
    # Homebrew
    "${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/share/zsh/site-functions}"
    "/opt/homebrew/share/zsh/site-functions"
    # System paths
    "/usr/local/share/zsh/site-functions"
    "/usr/share/zsh/site-functions"
    "/usr/share/zsh/$zsh_version/functions"
  )

  # Prepend candidates to existing path arrays. `typeset -U` handles de-duplication.
  path=($path_candidates $path)
  fpath=($fpath_candidates $fpath)

  z::log::debug "PATH built with ${#path[@]} unique directories."
  z::log::debug "FPATH built with ${#fpath[@]} unique directories."
  z::log::info "PATH and FPATH built successfully."
}

if z::func::exists "z::mod::path_setup::init"; then
  z::mod::path_setup::init
fi
