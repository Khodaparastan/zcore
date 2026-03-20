#!/usr/bin/env zsh
#
# Path Construction Module
# Builds PATH and FPATH using framework utilities.
#

# ==============================================================================
# PRIVATE HELPERS
# ==============================================================================

###
# Adds a directory to FPATH if it exists (no framework function for this yet)
###
__z::mod::path_setup::fpath_add()
{
  emulate -L zsh
  local dir="$1"


  # Check existence
  z::probe::path "$dir" || return 1

  # Check if already in fpath
  if (( ${fpath[(Ie)$dir]} )); then
    z::log::debug "Directory already in FPATH: $dir"
    return 0
  fi

  # Add to beginning of fpath
  fpath=("$dir" $fpath)
  z::log::debug "Added to FPATH: $dir"
  return 0
}

# ==============================================================================
# MAIN INITIALIZATION
# ==============================================================================

__z::mod::path_setup::init()
{
  emulate -L zsh
  z::log::info "Building PATH and FPATH..."

  # Make fpath unique (PATH is handled by z::env::path_add)
  typeset -gU fpath

  # --- PATH Construction (using framework function) ---
  # Add in reverse order of priority (last = highest priority)
  # System paths (lowest priority)


  # Homebrew (varies by platform)
  if (( $IS_LINUX )); then
    z::log::silent z::env::path_add "/sbin" prepend
    z::log::silent z::env::path_add "/usr/sbin" prepend
    z::log::silent z::log::silent z::env::path_add "/usr/local/sbin" prepend
    z::log::silent z::env::path_add "/bin" prepend
    z::log::silent z::env::path_add "/usr/bin" prepend
    z::log::silent z::env::path_add "/usr/local/bin" prepend
    z::log::silent z::env::path_add "/home/linuxbrew/.linuxbrew/sbin" prepend
    z::log::silent z::env::path_add "/home/linuxbrew/.linuxbrew/bin" prepend
    z::log::silent z::env::path_add "/snap/bin" prepend
  fi
  # elif (( $IS_MACOS )); then
  # z::env::path_add "/usr/local/opt/brew/bin" prepend
  # z::env::path_add "/opt/homebrew/sbin" prepend
  z::log::silent z::env::path_add "/opt/homebrew/bin" prepend
  z::log::silent z::exec::from_hook brew shellenv

  # z::env::path_add "${HOMEBREW_PREFIX}/sbin" prepend
  # z::env::path_add "${HOMEBREW_PREFIX}/bin" prepend

  # Additional development tools
  # z::env::path_add "$HOME/.rye/shims" prepend
  z::log::silent z::env::path_add "$HOME/.poetry/bin" prepend
  z::log::silent z::env::path_add "${PDTM:-$HOME/.pdtm/go}/bin" prepend
  z::log::silent z::env::path_add "${LMSTUDIO:-$HOME/.lmstudio}/bin" prepend

  # Language toolchains
  # z::env::path_add "$HOME/.yarn/bin" prepend
  # z::env::path_add "${DENO_INSTALL:-$HOME/.deno}/bin" prepend
  z::log::silent z::env::path_add "${BUN_INSTALL:-$HOME/.bun}/bin" prepend
  # z::env::path_add "${PNPM_HOME:-$HOME/.local/share/pnpm}" prepend
  z::log::silent z::env::path_add "${NPM_CONFIG_PREFIX:-$HOME/.npm-global}/bin" prepend
  z::log::silent z::env::path_add "${RUSTUP_HOME:-$HOME/.rustup}/bin" prepend
  z::log::silent z::env::path_add "${CARGO_HOME:-$HOME/.cargo}/bin" prepend
  z::log::silent z::env::path_add "${GOBIN:-${GOPATH:-$HOME/go}/bin}" prepend

  # Version managers (check these before language toolchains)
  # z::env::path_add "${ASDF_DATA_DIR:-$HOME/.asdf}/shims" prepend
  z::log::silent z::env::path_add "${MISE_DATA_DIR:-$HOME/.local/share/mise}/shims" prepend
  # z::env::path_add "$HOME/.nodenv/shims" prepend
  # z::env::path_add "$HOME/.rbenv/shims" prepend
  # z::env::path_add "$HOME/.pyenv/shims" prepend

  # User-specific bins (highest priority)
  z::log::silent z::env::path_add "$HOME/bin" prepend
  z::log::silent z::env::path_add "$HOME/.local/bin" prepend

  # RedTeaming Tolls
  z::log::silent z::env::path_add "/opt/metasploit-framework/bin" prepend

  # --- FPATH Construction (manual, no framework function yet) ---
  local -a fpath_candidates=(
    # Additional sources
    "${ASDF_DIR:-$HOME/.asdf}/completions"

    # System completions
    "/usr/share/zsh/vendor-completions"
    "/usr/share/zsh/$ZSH_VERSION/functions"
    "/usr/share/zsh/site-functions"

    # Homebrew completions
    "${HOMEBREW_PREFIX}/share/zsh/site-functions"

    # User-specific (highest priority)
    "${XDG_DATA_HOME:-$HOME/.local/share}/zsh/completions"
    "${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions"
  )

  # Add FPATH entries (in reverse order for proper precedence)
  local dir
  for dir in "${fpath_candidates[@]}"; do
    z::log::silent __z::mod::path_setup::fpath_add "$dir"
  done

  z::log::debug "PATH built with ${#path} unique directories"
  z::log::debug "FPATH built with ${#fpath} unique directories"
  z::log::info "PATH and FPATH built successfully"
}

if z::probe::func "__z::mod::path_setup::init"; then
  __z::mod::path_setup::init
fi
