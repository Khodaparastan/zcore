_build_path() {
  typeset -gU path fpath

  local -a _path_candidates=(
    # --- User space ---------------------------------------------------------
    "$HOME/.local/bin"
    "$HOME/bin"
    "${NPM_CONFIG_PREFIX:-$HOME/.npm-global}/bin"
    "${CARGO_HOME:-$HOME/.cargo}/bin"
    "${BUN_INSTALL:-$HOME/.bun}/bin"
    "${GOBIN:-$HOME/go/bin}"

    # --- Homebrew (Apple-Silicon + legacy) ----------------------------------
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
    "/opt/homebrew/opt/coreutils/libexec/gnubin"
    "/opt/homebrew/opt/rustup/bin"
    "${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/bin}"
    "${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/sbin}"
    "${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/opt/coreutils/libexec/gnubin}"

    # --- System defaults ----------------------------------------------------
    "/usr/local/bin" "/usr/bin" "/bin"
    "/usr/local/sbin" "/usr/sbin" "/sbin"
  )

  local -a new_path=()
  local -A seen_path=()
  local dir

  for dir in "${_path_candidates[@]}" "${path[@]}"; do
    [[ -n "$dir" && -d "$dir" && -z "${seen_path[$dir]-}" ]] || continue
    new_path+=("$dir")
    seen_path[$dir]=1
  done
  path=("${new_path[@]}") # scalar $PATH auto-updates

  local zver="${ZSH_VERSION%.*}" # → "5.9" from "5.9.0"
  local -a _fpath_candidates=(
    "${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/share/zsh/site-functions}"
    "${XDG_DATA_HOME:-$HOME/.local/share}/zsh/completions"
    "/opt/homebrew/share/zsh/site-functions"
    "/usr/local/share/zsh/site-functions"
    "/usr/share/zsh/site-functions"
    "/usr/share/zsh/$zver/functions"
  )

  local -a new_fpath=()
  local -A seen_fpath=()

  for dir in "${_fpath_candidates[@]}" "${fpath[@]}"; do
    [[ -n "$dir" && -d "$dir" && -r "$dir" && -z "${seen_fpath[$dir]-}" ]] || continue
    new_fpath+=("$dir")
    seen_fpath[$dir]=1
  done
  fpath=("${new_fpath[@]}")
}
