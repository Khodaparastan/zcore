#!/usr/bin/env zsh
#
# Path Construction Module
# Builds PATH and FPATH using framework utilities.
#

# ==============================================================================
# PRIVATE HELPERS
# ==============================================================================

###
# Adds a directory to FPATH if it exists and isn't already present.
###
__z::mod::path_setup::fpath_add() {
  emulate -L zsh
  local dir="$1"

  z::probe::path "$dir" || return 1

  if ((${fpath[(Ie)$dir]})); then
    z::log::debug "Directory already in FPATH: $dir"
    return 0
  fi

  fpath=("$dir" $fpath)
  z::log::debug "Added to FPATH: $dir"
  return 0
}

# ==============================================================================
# MAIN INITIALIZATION
# ==============================================================================

__z::mod::path_setup::init() {
  emulate -L zsh
  z::log::info "Building PATH and FPATH..."

  # Ensure uniqueness on both path & fpath.
  typeset -gU path fpath

  # ── System base paths (lowest priority via prepend ordering) ────────────
  local -a system_paths
  if ((IS_LINUX)); then
    system_paths=(
      /snap/bin
      /home/linuxbrew/.linuxbrew/bin /home/linuxbrew/.linuxbrew/sbin
      /usr/local/bin /usr/bin /bin
      /usr/local/sbin /usr/sbin /sbin
    )
  elif ((IS_MACOS)); then
    system_paths=(
      /usr/local/bin /usr/bin /bin
      /usr/local/sbin /usr/sbin /sbin
      /opt/homebrew/sbin /opt/homebrew/bin
    )
  fi

  local p
  for p in "${system_paths[@]}"; do
    z::log::silent z::env::path_add "$p" prepend
  done

  # Let brew populate HOMEBREW_PREFIX / MANPATH / INFOPATH on macOS.
  ((IS_MACOS)) && z::log::silent z::exec::from_hook brew shellenv

  # ── Developer toolchains (higher priority) ──────────────────────────────
  local -a dev_paths=(
    "$HOME/.poetry/bin"
    "${PDTM:-$HOME/.pdtm/go}/bin"
    "${LMSTUDIO:-$HOME/.lmstudio}/bin"
    "${BUN_INSTALL:-$HOME/.bun}/bin"
    "${NPM_CONFIG_PREFIX:-$HOME/.npm-global}/bin"
    "${RUSTUP_HOME:-$HOME/.rustup}/bin"
    "${CARGO_HOME:-$HOME/.cargo}/bin"
    "${GOBIN:-${GOPATH:-$HOME/go}/bin}"
    "${MISE_DATA_DIR:-$HOME/.local/share/mise}/shims"
    "$HOME/.config/composer/vendor/bin"
    /opt/metasploit-framework/bin
    "$HOME/bin"
    "$HOME/.local/bin"
    "$HOME/.luarocks/bin"
  )
  for p in "${dev_paths[@]}"; do
    z::log::silent z::env::path_add "$p" prepend
  done

  # ── FPATH ───────────────────────────────────────────────────────────────
  local -a fpath_candidates=(
    "${ASDF_DIR:-$HOME/.asdf}/completions"
    /usr/share/zsh/vendor-completions
    "/usr/share/zsh/$ZSH_VERSION/functions"
    /usr/share/zsh/site-functions
    "${XDG_DATA_HOME:-$HOME/.local/share}/zsh/completions"
    "${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions"
  )
  [[ -n "${HOMEBREW_PREFIX:-}" ]] &&
    fpath_candidates+=("${HOMEBREW_PREFIX}/share/zsh/site-functions")

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
